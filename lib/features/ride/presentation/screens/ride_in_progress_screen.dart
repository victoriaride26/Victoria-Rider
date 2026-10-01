import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/config/mapbox_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/mapbox_geocoding_service.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/services/rider_chat_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/fare_parser.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/driver_avatar.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import '../widgets/in_ride_chat_sheet.dart';
import '../widgets/ride_payment_sheet.dart';
import 'trip_completed_screen.dart';

/// R-11 — Ride in Progress: active map tracking the vehicle towards destination.
///
/// Rider actions available during a trip:
///  • **End Trip Early** (two-step) — stopovers are now added at request time
///    (max 2, via plus button under destination) for upfront fare calculation.
///     1. POST /rides/{id}/early-dropoff { lat, lng, reason } → backend recalculates fare, notifies driver
///     2. Rider confirms new fare → POST /rides/{id}/early-dropoff/confirm → driver pulls over & completes
class RideInProgressScreen extends StatefulWidget {
  const RideInProgressScreen({
    super.key,
    this.rideId,
    this.driverName,
    this.driverPhone,
    this.vehicleModel,
    this.plateNumber,
    this.driverProfileImage,
    this.fareNgn,
    this.pickupLatLng,
    this.destinationLatLng,
    this.destinationLabel,
    this.paymentMethod,
    this.pickupAddress,
    this.dropoffAddress,
  });

  final String? rideId;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleModel;
  final String? plateNumber;
  final String? driverProfileImage;
  final double? fareNgn;
  final LatLng? pickupLatLng;
  final LatLng? destinationLatLng;
  final String? destinationLabel;
  final String? paymentMethod;
  final String? pickupAddress;
  final String? dropoffAddress;

  @override
  State<RideInProgressScreen> createState() => _RideInProgressScreenState();
}

class _RideInProgressScreenState extends State<RideInProgressScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  final MapController _mapController = MapController();

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _paymentPendingSub;
  StreamSubscription<DriverLocationUpdate>? _locationSub;
  /// Listens for the backend's fare recalculation after POST /early-dropoff.
  StreamSubscription<Map<String, dynamic>>? _earlyDropoffFareSub;
  StreamSubscription<Map<String, dynamic>>? _fareUpdatedSub;
  Timer? _pollTimer;

  double? _liveFareNgn;

  // Stopover wait timer (new backend: confirmation_requested -> confirm -> timer:start -> timer:completed)
  StreamSubscription<Map<String, dynamic>>? _stopoverTimerSub;
  bool _stopoverTimerActive = false;
  DateTime? _stopoverTimerStart;
  Timer? _stopoverUiTimer;
  int _stopoverElapsedSeconds = 0;
  int _stopoverWaitDuration = 180; // Defaults to 180s, updated via backend events

  bool _navigated = false;
  late LatLng _destinationPoint;
  LatLng? _driverPoint;
  double? _driverHeading;
  int _etaMinutes = 8;

  String? _resolvedPickupAddress;
  String? _resolvedDropoffAddress;
  String? _activePaymentMethod;
  List<dynamic> _stops = [];

  // --- Early drop-off state ---
  bool _earlyDropoffRequested = false;

  @override
  void initState() {
    super.initState();
    _liveFareNgn = widget.fareNgn;
    _destinationPoint = widget.destinationLatLng ?? MapboxConfig.modernMarket;

    _driverPoint =
        widget.pickupLatLng ??
        LatLng(
          _destinationPoint.latitude - 0.012,
          _destinationPoint.longitude - 0.008,
        );

    _activePaymentMethod = widget.paymentMethod;
    _resolvedPickupAddress = widget.pickupAddress;
    _resolvedDropoffAddress = widget.dropoffAddress ?? widget.destinationLabel;

    _resolveAddresses();
    _fetchInitialData();
    _initListeners();
  }

  Future<void> _fetchInitialData() async {
    if (widget.rideId != null) {
      try {
        final response = await ApiClient.instance.get(
          ApiConfig.rideStatus(widget.rideId!),
        );
        final decoded = response as Map<String, dynamic>?;
        final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
        if (data != null && mounted) {
          setState(() {
            _stops = data['stops'] ?? data['stopovers'] ?? [];
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _resolveAddresses() async {
    final geocoding = MapboxGeocodingService();
    final isPickupCoords =
        _resolvedPickupAddress != null &&
        RegExp(
          r'^-?\d+(\.\d+)?[\s,]+-?\d+(\.\d+)?$',
        ).hasMatch(_resolvedPickupAddress!.trim());

    if ((_resolvedPickupAddress == null ||
            _resolvedPickupAddress!.isEmpty ||
            isPickupCoords) &&
        widget.pickupLatLng != null) {
      try {
        final res = await geocoding.reverseGeocode(widget.pickupLatLng!);
        if (res != null && mounted) {
          setState(() {
            _resolvedPickupAddress = res.placeName.isNotEmpty
                ? res.placeName
                : res.shortName;
          });
        }
      } catch (_) {}
    }

    final isDropoffCoords =
        _resolvedDropoffAddress != null &&
        RegExp(
          r'^-?\d+(\.\d+)?[\s,]+-?\d+(\.\d+)?$',
        ).hasMatch(_resolvedDropoffAddress!.trim());

    if ((_resolvedDropoffAddress == null ||
            _resolvedDropoffAddress!.isEmpty ||
            isDropoffCoords) &&
        widget.destinationLatLng != null) {
      try {
        final res = await geocoding.reverseGeocode(widget.destinationLatLng!);
        if (res != null && mounted) {
          setState(() {
            _resolvedDropoffAddress = res.placeName.isNotEmpty
                ? res.placeName
                : res.shortName;
          });
        }
      } catch (_) {}
    }
  }

  void _initListeners() {
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      // 1. Subscribe to live tracking room
      _socket.subscribeToRideTracking(widget.rideId!);

      // 2. Stream real-time driver coordinates
      _locationSub = _socket.onDriverLocation.listen((update) {
        if (!mounted) return;
        if (update.rideId.isEmpty || update.rideId == widget.rideId) {
          setState(() {
            _driverPoint = update.latLng;
            if (update.heading != null) {
              _driverHeading = update.heading;
            }
            if (update.etaMinutes != null && update.etaMinutes! > 0) {
              _etaMinutes = update.etaMinutes!;
            } else {
              final distanceMeters = const Distance().as(
                LengthUnit.Meter,
                _driverPoint!,
                _destinationPoint,
              );
              _etaMinutes = ((distanceMeters / 1000) / 30 * 60).ceil().clamp(
                1,
                60,
              );
            }
          });
        }
      });

      // 3. Socket listener for trip termination and completion
      _statusSub = _socket.onRideStatusUpdated.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          final status = (data['status'] ?? data['state'])
              ?.toString()
              .toUpperCase();
          if (status == 'COMPLETED' ||
              status == 'COMPLETE' ||
              status == 'TERMINATED' ||
              status == 'CANCELLED' ||
              status == 'CANCELED' ||
              status == 'ENDED' ||
              status == 'PAYMENT_PENDING') {
            _handleRideTerminated(data);
          } else {
            _updateLiveFare(data);
          }
        }
      });

      _paymentPendingSub = _socket.onPaymentPending.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          _handleRideTerminated(data, isPaymentPendingEvent: true);
        }
      });

      // 4. Backend fare recalculation response after POST /early-dropoff
      // Backend emits ride:early_dropoff:requested with the new fare preview.
      _earlyDropoffFareSub = _socket.onEarlyDropoffFareUpdate.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId != null && incomingId != widget.rideId) return;
        if (!mounted || _navigated) return;
        // Parse new fare from payload (kobo or Naira) with the driver's parser
        final rawFare = data['newFare'] ??
            data['estimatedFare'] ??
            data['fare'] ??
            data['amount'];
        double? newFareNgn = FareParser.scalarNgn(rawFare);
        setState(() {});
        // Show the fare confirmation dialog
        _showEarlyDropoffFareConfirmation(newFareNgn, data);
      });

      // 5. Stopover wait timer (backend: arrive -> confirmation_requested -> rider confirm -> timer:start -> timer:completed)
      _stopoverTimerSub = _socket.onStopoverTimer.listen((data) {
        if (!mounted || _navigated) return;
        final incomingId = (data['rideId'] ?? data['id'] ?? data['ride']?['id'])?.toString();
        if (incomingId != null && incomingId.isNotEmpty && incomingId != widget.rideId) return;
        final rawType = (data['type'] ?? data['event'] ?? data['status'] ?? '').toString().toLowerCase();
        if (rawType.contains('confirmation_requested')) {
          _handleStopoverConfirmationRequested(data);
        } else if (rawType.contains('confirmed')) {
          _handleStopoverConfirmed(data);
        } else if (rawType.contains('timer:start') || rawType.contains('timer_start')) {
          _handleStopoverTimerStart(data);
        } else if (rawType.contains('timer:completed') || rawType.contains('timer_completed') || data.containsKey('waitingTimeSeconds') || data.containsKey('extraCharge')) {
          _handleStopoverTimerCompleted(data);
        } else if (data.containsKey('arrivedAt')) {
          _handleStopoverConfirmed(data);
        } else {
          _handleStopoverConfirmationRequested(data);
        }
        
        final wdRaw = data['waitingTimeSeconds'] ?? data['waitingTime'] ?? data['waitSeconds'];
        if (wdRaw is num) {
          setState(() { _stopoverWaitDuration = wdRaw.toInt(); });
        } else if (wdRaw is String) {
          final parsed = int.tryParse(wdRaw);
          if (parsed != null) setState(() { _stopoverWaitDuration = parsed; });
        }
      });

      // 6. Dedicated fare updates (e.g. wait time penalty added)
      _fareUpdatedSub = _socket.onFareUpdated.listen((data) {
        if (!mounted || _navigated) return;
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId != null && incomingId != widget.rideId) return;

        _updateLiveFare(data);
        
        final extraCharge = data['extraCharge'];
        if (extraCharge != null) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(
               content: Text('Wait time penalty added to your fare.'),
               backgroundColor: AppColors.error,
               duration: Duration(seconds: 3),
             ),
           );
        }
      });

      // 7. 4-second polling fallback
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _checkStatus();
      });
    }
  }

  void _updateLiveFare(dynamic payload) {
    final newFareNgn = FareParser.scalarNgn(payload);
    if (newFareNgn != null && newFareNgn != _liveFareNgn) {
      if (mounted) {
        setState(() {
          _liveFareNgn = newFareNgn;
        });
      }
    }
  }

  Future<void> _checkStatus() async {
    if (_navigated || widget.rideId == null) return;
    try {
      final response = await ApiClient.instance.get(
        ApiConfig.rideStatus(widget.rideId!),
      );
      final decoded = response as Map<String, dynamic>?;
      final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
      final status = (data?['status'] ?? data?['state'])
          ?.toString()
          .toUpperCase();
      if (status == 'COMPLETED' ||
          status == 'COMPLETE' ||
          status == 'TERMINATED' ||
          status == 'CANCELLED' ||
          status == 'CANCELED' ||
          status == 'ENDED' ||
          status == 'PAYMENT_PENDING') {
        _handleRideTerminated(data ?? {});
      } else if (mounted) {
        setState(() {
          _stops = data?['stops'] ?? data?['stopovers'] ?? _stops;
          
          final wdRaw = data?['waitingTimeSeconds'] ?? data?['waitingTime'] ?? data?['waitSeconds'];
          if (wdRaw is num) _stopoverWaitDuration = wdRaw.toInt();
          else if (wdRaw is String) _stopoverWaitDuration = int.tryParse(wdRaw) ?? _stopoverWaitDuration;
        });

        _updateLiveFare(data);
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────
  // Stopover wait timer handlers (backend: arrive -> confirmation_requested -> confirm -> timer:start -> timer:completed)
  // ─────────────────────────────────────────────────────────────────
  Future<void> _handleStopoverConfirmationRequested(Map<String, dynamic> data) async {
    if (!mounted || _navigated) return;
    final rideId = (data['rideId'] ?? data['id'] ?? widget.rideId)?.toString() ?? widget.rideId ?? '';
    final idxRaw = data['index'] ?? data['stopIndex'] ?? 0;
    final stopIndex = idxRaw is int ? idxRaw : int.tryParse(idxRaw.toString()) ?? 0;
    final address = (data['address'] ?? data['stopAddress'] ?? (data['location'] is Map ? (data['location'] as Map)['address'] : null) ?? 'the stop')?.toString() ?? 'the stop';
    final waitThreshold = _stopoverWaitDuration > 0 ? _stopoverWaitDuration : 180;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Driver Arrived at Stop'),
        content: Text('Your driver has arrived at Stop ${stopIndex + 1}: $address. Please confirm to start the ${(waitThreshold / 60).toInt()}-minute free wait.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not Yet')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Arrival'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiClient.instance.post(ApiConfig.rideStopConfirm(rideId, stopIndex));
      if (!mounted) return;
      final waitThreshold = _stopoverWaitDuration > 0 ? _stopoverWaitDuration : 180;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stop confirmed — ${(waitThreshold / 60).toInt()}-minute timer started.'), backgroundColor: AppColors.primary),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to confirm stop.'), backgroundColor: AppColors.error));
    }
  }

  void _handleStopoverConfirmed(Map<String, dynamic> data) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stop arrival confirmed.'), backgroundColor: AppColors.primary),
    );
  }

  void _handleStopoverTimerStart(Map<String, dynamic> data) {
    if (!mounted) return;
    _stopoverUiTimer?.cancel();
    _stopoverTimerStart = DateTime.now();
    // Try to use server arrivedAt if provided
    final arrivedAtRaw = data['arrivedAt'] ?? data['arrived_at'];
    if (arrivedAtRaw is String) {
      final parsed = DateTime.tryParse(arrivedAtRaw);
      if (parsed != null) _stopoverTimerStart = parsed;
    }
    setState(() {
      _stopoverTimerActive = true;
      _stopoverElapsedSeconds = 0;
    });
    _stopoverUiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_stopoverTimerActive || _stopoverTimerStart == null) return;
      final elapsed = DateTime.now().difference(_stopoverTimerStart!).inSeconds;
      if (mounted) setState(() => _stopoverElapsedSeconds = elapsed);
    });
    final waitThreshold = _stopoverWaitDuration > 0 ? _stopoverWaitDuration : 180;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Wait timer started — ${(waitThreshold / 60).toInt()} minutes free.'), backgroundColor: AppColors.primary),
    );
  }

  void _handleStopoverTimerCompleted(Map<String, dynamic> data) {
    _stopoverUiTimer?.cancel();
    final waitingRaw = data['waitingTimeSeconds'] ?? data['waitingDurationSeconds'] ?? 0;
    final extraRaw = data['extraCharge'] ?? data['waitingCharge'] ?? 0;
    int waitingSeconds = 0;
    if (waitingRaw is num) waitingSeconds = waitingRaw.toInt();
    if (waitingRaw is String) waitingSeconds = int.tryParse(waitingRaw) ?? 0;
    double extraCharge = 0;
    if (extraRaw is num) extraCharge = extraRaw >= 100 ? extraRaw / 100.0 : extraRaw.toDouble();
    if (mounted) {
      setState(() {
        _stopoverTimerActive = false;
        _stopoverElapsedSeconds = waitingSeconds;
      });
    }
    _stopoverUiTimer?.cancel();
    if (!mounted) return;
    final waitThreshold = _stopoverWaitDuration > 0 ? _stopoverWaitDuration : 180;
    final minutesOver = waitingSeconds > waitThreshold ? ((waitingSeconds - waitThreshold) / 60).ceil() : 0;
    final msg = waitingSeconds <= waitThreshold
        ? 'Stop completed within free time.'
        : 'Stop completed — $waitingSeconds sec total, $minutesOver min over free time. Extra charge: ₦${extraCharge.toStringAsFixed(0)}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: waitingSeconds > waitThreshold ? AppColors.error : AppColors.primary));
  }

  // ─────────────────────────────────────────────────────────────────
  // Back / Cancel (before the ride is ended by rider)
  // ─────────────────────────────────────────────────────────────────
  Future<void> _handleBack() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text('Are you sure you want to cancel your ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (cancel == true && mounted) {
      if (widget.rideId != null) {
        try {
          await ApiClient.instance.post(ApiConfig.rideCancel(widget.rideId!));
        } catch (_) {}
      }
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const RiderHomeShell()),
          (r) => false,
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // End Trip Early — two-step early drop-off flow
  // Step 1: POST /rides/{id}/early-dropoff { lat, lng, reason }
  // Step 2: Rider confirms fare → POST /rides/{id}/early-dropoff/confirm
  // ─────────────────────────────────────────────────────────────────
  
  Future<void> _requestEarlyDropoff() async {
    if (widget.rideId == null || _earlyDropoffRequested) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Trip?'),
        content: const Text('Are you sure you want to end this trip now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _earlyDropoffRequested = true;
    });

    try {
      await ApiClient.instance.post(ApiConfig.rideComplete(widget.rideId!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error));
        setState(() {
          _earlyDropoffRequested = false;
        });
      }
      return;
    }

    if (mounted) {
      _handleRideTerminated({
        'status': 'COMPLETED',
      });
    }
  }

  Future<void> _handleSupportAction(String endpoint, String title) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        _doSupportFetch(endpoint, title, dialogCtx);
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Future<void> _doSupportFetch(String endpoint, String title, BuildContext dialogCtx) async {
    try {
      final res = await ApiClient.instance.get(endpoint);
      if (dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop(); // Safely pop the dialog
      }
      
      if (res != null) {
        final data = res['data'] ?? res;
        final name = data['name']?.toString() ?? title;
        final location = data['location']?.toString();
        final phone = data['phone']?.toString();
        final whatsapp = data['whatsappNumber']?.toString() ?? data['whatsapp']?.toString();

        if (mounted) {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      if (location != null && location.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: AppColors.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(child: Text(location, style: const TextStyle(color: AppColors.onSurfaceVariant))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (phone != null && phone.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primaryContainer,
                            child: Icon(Icons.phone, color: AppColors.primary),
                          ),
                          title: const Text('Phone Number'),
                          subtitle: Text(phone, style: const TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () async {
                            final url = Uri.parse('tel:$phone');
                            if (await canLaunchUrl(url)) await launchUrl(url);
                          },
                        ),
                      if (whatsapp != null && whatsapp.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Icon(Icons.chat, color: Colors.white),
                          ),
                          title: const Text('WhatsApp'),
                          subtitle: Text(whatsapp, style: const TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () async {
                            final url = Uri.parse('https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}');
                            if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                          },
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      }
    } catch (e) {
      if (dialogCtx.mounted) {
        Navigator.of(dialogCtx).pop(); // Safely pop the dialog
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error contacting support: $e')));
      }
    }
  }


  /// Shows the fare confirmation dialog to the rider.
  /// Called either from the socket listener or from the REST response fallback.
  Future<void> _showEarlyDropoffFareConfirmation(
    double? newFareNgn,
    Map<String, dynamic> payload,
  ) async {
    if (!mounted || _navigated) return;

    final fareStr = newFareNgn != null && newFareNgn > 0
        ? '₦${newFareNgn.toStringAsFixed(0)}'
        : 'Recalculated fare';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Updated Fare'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your driver has been notified. The updated fare for your '
              'current drop-off point is:',
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                fareStr,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your driver will pull over safely when you confirm.',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm End Trip'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Step 2: POST /rides/{id}/early-dropoff/confirm
    try {
      await ApiClient.instance.post(
        ApiConfig.rideEarlyDropoffConfirm(widget.rideId!),
      );
    } catch (_) {
      // Best-effort — driver already notified at step 1
    }

    // Navigate to summary screen; driver will call /complete to lock billing
    if (mounted) {
      _handleRideTerminated(
        {
          ...payload,
          'status': 'EARLY_DROPOFF_CONFIRMED',
        },
        isEarlyDropoff: true,
        newFareNgn: newFareNgn,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Trip termination handler
  // ─────────────────────────────────────────────────────────────────
  Future<void> _handleRideTerminated(
    Map<String, dynamic> data, {
    bool isPaymentPendingEvent = false,
    bool isEarlyDropoff = false,
    double? newFareNgn,
  }) async {
    if (_navigated || !mounted) return;

    if (data['paymentMethod'] != null) {
      _activePaymentMethod = data['paymentMethod'].toString();
    }

    final method = (_activePaymentMethod ?? widget.paymentMethod ?? 'cash')
        .toUpperCase();
    final status = (data['status'] ?? data['state'])?.toString().toUpperCase();

    final bool isPaymentConfirmed =
        !isPaymentPendingEvent &&
        (status == 'COMPLETED' ||
            status == 'COMPLETE' ||
            method == 'CASH' ||
            method == 'WALLET');

    double fare = widget.fareNgn ?? 0.0;

    // Use explicitly provided fare first (from early-dropoff flow)
    if (newFareNgn != null && newFareNgn > 0) {
      fare = newFareNgn;
    } else {
      // Settled fare when the backend has one, otherwise the backend estimate —
      // the exact rule the driver app's trip summary uses.
      final backendFare = FareParser.finalFareNgn(data);
      if (backendFare != null && backendFare > 0) {
        fare = backendFare;
      }
    }

    _navigateToSummary(fare: fare, isPaymentConfirmed: isPaymentConfirmed);
  }

  void _navigateToSummary({
    required double fare,
    required bool isPaymentConfirmed,
  }) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _pollTimer?.cancel();
    _statusSub?.cancel();
    _paymentPendingSub?.cancel();
    _locationSub?.cancel();
    _earlyDropoffFareSub?.cancel();

    final activePaymentMethod = _activePaymentMethod ?? widget.paymentMethod;

    void pushReceipt(bool confirmed) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => TripCompletedScreen(
            rideId: widget.rideId,
            driverName: widget.driverName,
            fareNgn: fare,
            pickupAddress: _resolvedPickupAddress,
            dropoffAddress: _resolvedDropoffAddress,
            paymentMethod: activePaymentMethod,
            isPaymentConfirmed: confirmed,
          ),
        ),
        (route) => route.isFirst,
      );
    }

    if (!isPaymentConfirmed && (activePaymentMethod?.toUpperCase() != 'CASH')) {
      RidePaymentSheet.show(
        context,
        rideId: widget.rideId,
        fareNgn: fare,
        driverName: widget.driverName,
        paymentMethod: activePaymentMethod,
        onPaymentConfirmed: (confirmed) {
          pushReceipt(confirmed);
        },
      );
    } else {
      pushReceipt(isPaymentConfirmed);
    }
  }

  Future<void> _callDriver() async {
    final phone = widget.driverPhone;
    if (phone != null && phone.isNotEmpty) {
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contact Driver'),
        content: Text(
          phone != null && phone.isNotEmpty
              ? 'Driver phone: $phone'
              : 'Driver phone number is not available. Please use in-ride chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (phone != null && phone.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse('tel:$phone'));
              },
              child: const Text('Call Now'),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusSub?.cancel();
    _paymentPendingSub?.cancel();
    _locationSub?.cancel();
    _earlyDropoffFareSub?.cancel();
    _stopoverTimerSub?.cancel();
    _fareUpdatedSub?.cancel();
    _stopoverUiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.driverName ?? 'Driver';
    final carInfo =
        '${widget.vehicleModel ?? 'Vehicle'} • ${widget.plateNumber ?? 'Plate Info'}';
    final currentFare = _liveFareNgn ?? widget.fareNgn;
    final fareStr = currentFare != null
        ? '₦${currentFare.toStringAsFixed(0)}'
        : 'Calculating...';

    final isPaystackMethod =
        (_activePaymentMethod?.toUpperCase() == 'CARD' ||
        _activePaymentMethod?.toUpperCase() == 'TRANSFER' ||
        widget.paymentMethod?.toUpperCase() == 'CARD' ||
        widget.paymentMethod?.toUpperCase() == 'TRANSFER');

    final markers = <Marker>[
      Marker(
        point: _destinationPoint,
        width: 46,
        height: 46,
        child: const Icon(
          Icons.location_on,
          color: AppColors.primary,
          size: 42,
        ),
      ),
      if (_driverPoint != null)
        Marker(
          point: _driverPoint!,
          width: 50,
          height: 50,
          child: Transform.rotate(
            angle: (_driverHeading ?? 0) * (3.141592653589793 / 180),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_car,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ),
    ];

    final polylines = <Polyline>[
      if (_driverPoint != null)
        Polyline(
          points: [_driverPoint!, _destinationPoint],
          color: AppColors.primary,
          strokeWidth: 4,
          pattern: StrokePattern.dashed(segments: [8, 6]),
        ),
    ];

    final mapCenter = _driverPoint != null
        ? LatLng(
            (_driverPoint!.latitude + _destinationPoint.latitude) / 2,
            (_driverPoint!.longitude + _destinationPoint.longitude) / 2,
          )
        : _destinationPoint;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: MapboxMapView(
                mapController: _mapController,
                center: mapCenter,
                zoom: 14,
                showUserLocation: true,
                markers: markers,
                polylines: polylines,
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: AppBackButton(onPressed: _handleBack),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.50,
              minChildSize: 0.25,
              maxChildSize: 0.58,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag handle
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Header row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trip in Progress',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Estimated arrival: $_etaMinutes mins',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _earlyDropoffRequested
                                    ? AppColors.error.withValues(alpha: 0.12)
                                    : AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _earlyDropoffRequested
                                    ? 'ENDING TRIP'
                                    : 'EN ROUTE',
                                style: TextStyle(
                                  color: _earlyDropoffRequested
                                      ? AppColors.error
                                      : AppColors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Driver info row
                        Row(
                          children: [
                            DriverAvatar(
                              imageUrl: widget.driverProfileImage,
                              radius: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    carInfo,
                                    style: const TextStyle(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _callDriver,
                              icon: const Icon(Icons.call),
                              tooltip: 'Call Driver',
                            ),
                            ListenableBuilder(
                              listenable: RiderChatService.instance,
                              builder: (context, _) {
                                final unread = RiderChatService.instance.unreadCount;
                                return IconButton(
                                  onPressed: () {
                                    InRideChatSheet.show(
                                      context,
                                      rideId: widget.rideId ?? 'active_ride',
                                      driverName: name,
                                    );
                                  },
                                  icon: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.chat_bubble_outline),
                                      if (unread > 0)
                                        Positioned(
                                          right: -4,
                                          top: -4,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                            child: Text(
                                              '$unread',
                                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  tooltip: 'Message Driver',
                                );
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 16),

                        // Route Locations (Pickup -> Stops -> Destination)
                        Row(
                          children: [
                            const Icon(
                              Icons.my_location,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pickup',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _resolvedPickupAddress ??
                                        widget.pickupAddress ??
                                        'Pickup Location',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_stops.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Column(
                              children: _stops.asMap().entries.map((entry) {
                                final s = entry.value;
                                final i = entry.key;
                                final loc = s['location'] ?? s;
                                final address = loc['address']?.toString() ?? 'Stop ${i + 1}';
                                final completed = s['completed'] == true || s['status'] == 'completed';
                                final arrived = s['status'] == 'arrived';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        completed ? Icons.check_circle : (arrived ? Icons.pause_circle : Icons.radio_button_unchecked),
                                        color: completed ? Colors.green : (arrived ? Colors.orange : AppColors.primary),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Stop ${i + 1}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.onSurfaceVariant,
                                              ),
                                            ),
                                            Text(
                                              address,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Destination',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _resolvedDropoffAddress ??
                                        widget.destinationLabel ??
                                        'Destination',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Stopover timer — shows when driver has arrived and rider confirmed
                        if (_stopoverTimerActive || _stopoverElapsedSeconds > 0) ...[
                          Builder(
                            builder: (context) {
                              final waitThreshold = _stopoverWaitDuration > 0 ? _stopoverWaitDuration : 180;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _stopoverElapsedSeconds > waitThreshold ? AppColors.error.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _stopoverElapsedSeconds > waitThreshold ? AppColors.error.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _stopoverElapsedSeconds > waitThreshold ? Icons.timer_off_outlined : Icons.timer_outlined,
                                      size: 18,
                                      color: _stopoverElapsedSeconds > waitThreshold ? AppColors.error : AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _stopoverElapsedSeconds > waitThreshold ? 'Extra wait charge applies' : 'Free wait — ${(waitThreshold / 60).toInt()} min',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _stopoverElapsedSeconds > waitThreshold ? AppColors.error : AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${(_stopoverElapsedSeconds ~/ 60).toString().padLeft(1, '0')}:${(_stopoverElapsedSeconds % 60).toString().padLeft(2, '0')} elapsed${_stopoverElapsedSeconds > waitThreshold ? ' — ${((_stopoverElapsedSeconds - waitThreshold) / 60).ceil()} min over' : ''}',
                                            style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_stopoverTimerActive)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                      ),
                                  ],
                                ),
                              );
                            }
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Fare row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Estimated Fare',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isPaystackMethod
                                        ? 'Paystack'
                                        : 'Cash/Wallet',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              fareStr,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Action buttons — End Trip only (Add Stop removed; stopovers now at request time max 2 for fare calc)
                        SafeArea(
                          top: false,
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _earlyDropoffRequested ? null : _requestEarlyDropoff,
                                  icon: _earlyDropoffRequested
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.flag_outlined, size: 18),
                                  label: Text(
                                    _earlyDropoffRequested ? 'Ending…' : 'End Trip',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _handleSupportAction(ApiConfig.supportEmergency, 'Emergency'),
                                      icon: const Icon(Icons.emergency, color: AppColors.error, size: 18),
                                      label: const Text('Emergency', style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        side: const BorderSide(color: AppColors.error),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _handleSupportAction(ApiConfig.supportCustomerService, 'Customer Care'),
                                      icon: const Icon(Icons.support_agent, color: AppColors.primary, size: 18),
                                      label: const Text('Customer Care', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        side: const BorderSide(color: AppColors.primary),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


