import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
import '../../../../core/utils/wait_threshold_parser.dart';
import '../../../../core/widgets/driver_avatar.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import '../../data/support_contacts.dart';
import '../widgets/in_ride_chat_sheet.dart';
import '../widgets/support_contacts_sheet.dart';
import 'trip_completed_screen.dart';

/// R-11 — Ride in Progress: active map tracking the vehicle towards destination.
///
/// Rider actions available during a trip:
///  • **Request Early Drop** (two-step) — stopovers are now added at request time
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
    this.driverRating,
    this.initialWaitingForDriver = false,
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
  final double? driverRating;

  /// Crash/restart recovery: the backend already holds EARLY_DROPOFF_CONFIRMED
  /// (rider agreed the fare before the restart), so open directly in the
  /// "waiting for driver" state instead of requiring another tap. The live
  /// poll re-asserts this from the server either way.
  final bool initialWaitingForDriver;

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

  /// Free-wait window for a stop-over in seconds, taken from the backend
  /// payload. `null` until a payload supplies one — [_freeWaitSeconds] then
  /// falls back to a display-only default so the UI can still render.
  int? _stopoverWaitDuration;

  /// Free-wait window the UI displays and the elapsed timer compares against:
  /// the backend value when known, otherwise the display fallback.
  int get _freeWaitSeconds => (_stopoverWaitDuration ?? 0) > 0
      ? _stopoverWaitDuration!
      : WaitThresholdParser.fallbackSeconds;

  /// Reads the backend's free-wait window out of an event/status payload.
  /// Returns true when a usable value was found, so the caller can rebuild.
  bool _applyWaitThreshold(dynamic payload, {required bool allowEventKeys}) {
    final seconds =
        WaitThresholdParser.thresholdSeconds(payload, allowEventKeys: allowEventKeys) ??
            // Silent payload → the window the estimate published (arrival
            // dialog runs before `ride:stopover:timer:start` delivers its own).
            WaitThresholdParser.estimateSeconds;
    if (seconds == null || seconds == _stopoverWaitDuration) return false;
    _stopoverWaitDuration = seconds;
    return true;
  }

  bool _navigated = false;
  bool _terminating = false;
  late LatLng _destinationPoint;
  LatLng? _driverPoint;
  double? _driverHeading;
  int _etaMinutes = 8;

  String? _resolvedPickupAddress;
  String? _resolvedDropoffAddress;
  String? _activePaymentMethod;
  List<dynamic> _stops = [];

  // --- Early drop-off state (ordered single-dialog flow) ---
  // Tap → POST /early-dropoff → wait for the backend's recalculated fare →
  // ONE confirm dialog (fare-gated) → POST /confirm → wait for the driver to
  // pull over and POST /complete. A reject from either side (or a status
  // reversal to IN_PROGRESS) resumes the original trip on both apps.
  bool _earlyDropoffRequested = false;
  bool _waitingForDriver = false;
  bool _earlyFareDialogOpen = false;
  bool _serverSawEarlyDropoff = false;
  bool _fareShown = false;
  // Restart recovery: adopt a server-held REQUESTED once per screen session
  // so the fare dialog appears without requiring another tap. Suppressed
  // briefly after a user cancel so a stale poll can't resurrect the dialog.
  bool _earlyAutoAdopted = false;
  DateTime? _suppressAutoAdoptUntil;
  double? _confirmedEarlyFareNgn;
  Timer? _fareTimer;

  bool get _earlyDropoffActive => _earlyDropoffRequested || _waitingForDriver;

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

    if (widget.initialWaitingForDriver) {
      _earlyDropoffRequested = true;
      _waitingForDriver = true;
      _serverSawEarlyDropoff = true;
      _fareShown = true;
    }

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
          // Seed the free-wait window from the ride's own status payload so
          // the first arrival dialog is backend-driven, not a 180s guess.
          _applyWaitThreshold(data, allowEventKeys: false);
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
          } else if (status == 'EARLY_DROPOFF_CONFIRMED' ||
              status == 'EARLYDROPOFFCONFIRMED') {
            // Rider confirmed the fare (possibly on another device, or the
            // confirm POST raced this event): hold the waiting state for the
            // driver's End Trip — never navigate until the trip completes.
            _serverSawEarlyDropoff = true;
            if (!_waitingForDriver && !_terminating && mounted) {
              final fare = FareParser.finalFareNgn(data);
              setState(() {
                _waitingForDriver = true;
                _earlyDropoffRequested = true;
                if (fare != null && fare > 0) _confirmedEarlyFareNgn = fare;
              });
              _fareTimer?.cancel();
            }
            _updateLiveFare(data);
          } else {
            if (status != null &&
                (status == 'IN_PROGRESS' || status == 'INPROGRESS')) {
              if (_isEarlyRejectedMessage(data['message'])) {
                _resumeOriginalTrip(
                  data['message']?.toString() ??
                      'Early drop-off declined — continuing your trip.',
                );
              } else if (_serverSawEarlyDropoff &&
                  !_payloadHasEarlyFlags(data) &&
                  (_earlyDropoffRequested || _waitingForDriver)) {
                // Backend reversed the request back to a clean IN_PROGRESS
                // (driver rejected): resume the original trip on this app too.
                _resumeOriginalTrip(
                  'Early drop-off ended — continuing to your original destination.',
                );
              }
            }
            _updateLiveFare(data);
            // Backend may deliver the recalculated fare over the generic
            // ride:state channel (status EARLY_DROPOFF_REQUESTED) instead of
            // the dedicated early-dropoff socket event. Surface the single
            // fare-gated confirmation from here too so the rider is never
            // stuck waiting with no dialog.
            if (status != null &&
                status.contains('EARLY') &&
                status.contains('REQUEST')) {
              _serverSawEarlyDropoff = true;
              _maybeShowEarlyDropoffFare(data);
            }
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
        _maybeShowEarlyDropoffFare(data);
      });

      // 5. Stopover wait timer (backend: arrive -> confirmation_requested -> rider confirm -> timer:start -> timer:completed)
      _stopoverTimerSub = _socket.onStopoverTimer.listen((data) {
        if (!mounted || _navigated) return;
        final incomingId = (data['rideId'] ?? data['id'] ?? data['ride']?['id'])?.toString();
        if (incomingId != null && incomingId.isNotEmpty && incomingId != widget.rideId) return;
        final rawType = (data['type'] ?? data['event'] ?? data['status'] ?? '').toString().toLowerCase();
        // The threshold must be read BEFORE the handler runs — otherwise the
        // arrival dialog/snackbar would still show the previous value. Generic
        // wait keys are only trusted here, not on `timer:completed`, where
        // they mean elapsed time rather than the free-wait window.
        final allowEventKeys = !rawType.contains('completed');
        if (_applyWaitThreshold(data, allowEventKeys: allowEventKeys) &&
            mounted) {
          setState(() {});
        }
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
      } else if (status == 'EARLY_DROPOFF_CONFIRMED' ||
          status == 'EARLYDROPOFFCONFIRMED') {
        // Confirmed fare: hold the waiting state for the driver's End Trip.
        _serverSawEarlyDropoff = true;
        if (!_waitingForDriver && !_terminating && mounted) {
          final fare = FareParser.finalFareNgn(data ?? {});
          setState(() {
            _waitingForDriver = true;
            _earlyDropoffRequested = true;
            if (fare != null && fare > 0) _confirmedEarlyFareNgn = fare;
          });
          _fareTimer?.cancel();
        }
        _updateLiveFare(data);
      } else if (mounted) {
        // Ride-level payloads only carry explicitly threshold-named keys —
        // `waitingTimeSeconds` here is elapsed time, not the free window.
        _applyWaitThreshold(data, allowEventKeys: false);
        setState(() {
          _stops = data?['stops'] ?? data?['stopovers'] ?? _stops;
        });

        if (status == 'IN_PROGRESS' || status == 'INPROGRESS') {
          if (_isEarlyRejectedMessage(data?['message'])) {
            _resumeOriginalTrip(
              data?['message']?.toString() ??
                  'Early drop-off declined — continuing your trip.',
            );
          } else if (_serverSawEarlyDropoff &&
              !_payloadHasEarlyFlags(data ?? {}) &&
              (_earlyDropoffRequested || _waitingForDriver)) {
            _resumeOriginalTrip(
              'Early drop-off ended — continuing to your original destination.',
            );
          }
        }
        _updateLiveFare(data);
        // Polling fallback: if the fare-recalculation socket was missed, the
        // status endpoint still carries EARLY_DROPOFF_REQUESTED + the new fare.
        if (status != null &&
            status.contains('EARLY') &&
            status.contains('REQUEST')) {
          _serverSawEarlyDropoff = true;
          if (!_earlyDropoffRequested &&
              !_waitingForDriver &&
              !_earlyAutoAdopted &&
              (_suppressAutoAdoptUntil == null ||
                  DateTime.now().isAfter(_suppressAutoAdoptUntil!))) {
            // Crash/restart with a live server-side request: adopt it once
            // so the fare dialog appears without another tap.
            _earlyAutoAdopted = true;
            _earlyDropoffRequested = true;
            if (mounted) setState(() {});
          }
          _maybeShowEarlyDropoffFare(data ?? {});
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────
  // Stopover wait timer handlers (backend: arrive -> confirmation_requested -> confirm -> timer:start -> timer:completed)
  // ─────────────────────────────────────────────────────────────────

  /// Backend stop indexes are waypoint indexes (pickup = 0, first stop-over =
  /// 1, …), so the first stop-over reports `index == 1`. Normalizing keeps the
  /// rider dialog saying "Stop 1 / Stop 2" — the same numbers the driver taps.
  int _stopDisplayNumber(int index) => index >= 1 ? index : index + 1;

  /// Resolves the real address of a stop-over so the arrival dialog can say
  /// "Stop 2: High Level Makurdi" instead of a placeholder. Prefers the socket
  /// payload (its `stop` object carries `address` / `location.address`), then
  /// the `stops` array shipped with the event, then this screen's own stop list
  /// (matched by waypoint index, falling back to list position).
  String _stopAddress(Map<String, dynamic> data, int stopIndex) {
    String text(dynamic value) => value == null ? '' : value.toString().trim();
    bool usable(String value) => value.isNotEmpty && value.toLowerCase() != 'the stop';

    for (final key in const ['address', 'stopAddress', 'stopAddressLine', 'streetAddress']) {
      final value = text(data[key]);
      if (usable(value)) return value;
    }

    String? fromStopObject(dynamic stop) {
      if (stop is! Map) return usable(text(stop)) ? text(stop) : null;
      for (final field in const ['address', 'stopAddress', 'formattedAddress', 'name']) {
        final value = text(stop[field]);
        if (usable(value)) return value;
      }
      final location = stop['location'] ?? stop['stopLocation'];
      if (location is Map) {
        final value = text(location['address'] ?? location['name']);
        if (usable(value)) return value;
      }
      return null;
    }

    for (final key in const ['stop', 'stopover', 'stopOver', 'location', 'stopLocation', 'waypoint']) {
      final value = fromStopObject(data[key]);
      if (value != null) return value;
    }

    final sources = <dynamic>[
      if (data['stops'] is List) data['stops'],
      _stops,
    ];
    for (final source in sources) {
      if (source is! List) continue;
      Map<String, dynamic>? byIndex;
      Map<String, dynamic>? byPosition;
      for (var position = 0; position < source.length; position++) {
        final entry = source[position];
        if (entry is! Map) continue;
        final raw = entry['index'] ?? entry['stopIndex'];
        final parsed = raw is int ? raw : int.tryParse('${raw ?? ''}');
        if (parsed == stopIndex) byIndex = Map<String, dynamic>.from(entry);
        if (position == _stopDisplayNumber(stopIndex) - 1) {
          byPosition = Map<String, dynamic>.from(entry);
        }
      }
      for (final stop in [byIndex, byPosition]) {
        if (stop == null) continue;
        final value = fromStopObject(stop);
        if (value != null) return value;
      }
    }
    return '';
  }

  Future<void> _handleStopoverConfirmationRequested(Map<String, dynamic> data) async {
    if (!mounted || _navigated) return;
    final rideId = (data['rideId'] ?? data['id'] ?? widget.rideId)?.toString() ?? widget.rideId ?? '';
    final idxRaw = data['index'] ?? data['stopIndex'] ?? 0;
    final stopIndex = idxRaw is int ? idxRaw : int.tryParse(idxRaw.toString()) ?? 0;
    final address = _stopAddress(data, stopIndex);
    final waitThreshold = _freeWaitSeconds;
    final waitLabel = WaitThresholdParser.label(waitThreshold);
    final arrivedLine = address.isEmpty
        ? 'Your driver has arrived at Stop ${_stopDisplayNumber(stopIndex)}. Please confirm to start the $waitLabel free wait.'
        : 'Your driver has arrived at Stop ${_stopDisplayNumber(stopIndex)}: $address. Please confirm to start the $waitLabel free wait.';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Driver Arrived at Stop'),
        content: Text(arrivedLine),
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
    if (!mounted) return;
    if (confirmed != true) {
      // "Not Yet" → tell the backend so the driver's stop goes back to pending
      // and they can press Arrive again at the real spot.
      await _rejectStopArrival(rideId, stopIndex);
      return;
    }
    try {
      await ApiClient.instance.post(ApiConfig.rideStopConfirm(rideId, stopIndex));
      if (!mounted) return;
      final waitThreshold = _freeWaitSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stop confirmed — ${WaitThresholdParser.label(waitThreshold)} timer started.'), backgroundColor: AppColors.primary),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to confirm stop.'), backgroundColor: AppColors.error));
    }
  }

  /// "Not Yet" → POST /rides/{id}/stops/{index}/reject. The backend reverts the
  /// waypoint to `pending` and broadcasts `ride:stopover:arrival_rejected` so
  /// the driver's "Arrive" button becomes available again.
  Future<void> _rejectStopArrival(String rideId, int stopIndex) async {
    try {
      await ApiClient.instance.post(ApiConfig.rideStopReject(rideId, stopIndex));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We've let your driver know you're not ready yet."),
          backgroundColor: AppColors.primary,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not notify your driver. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
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
    // The backend stamps `startTime` on `ride:stopover:timer:start` (the
    // moment the Rider confirmed the arrival) — prefer it over local clock,
    // then fall back to older `arrivedAt` payloads.
    final startRaw = data['startTime'] ??
        data['start_time'] ??
        data['arrivedAt'] ??
        data['arrived_at'];
    if (startRaw is String) {
      final parsed = DateTime.tryParse(startRaw);
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
    final waitThreshold = _freeWaitSeconds;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Wait timer started — ${WaitThresholdParser.shortLabel(waitThreshold)} free.'), backgroundColor: AppColors.primary),
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
    final waitThreshold = _freeWaitSeconds;
    final overSeconds =
        waitingSeconds > waitThreshold ? waitingSeconds - waitThreshold : 0;
    final msg = overSeconds == 0
        ? 'Stop completed within the ${WaitThresholdParser.label(waitThreshold)} free wait.'
        : 'Stop completed — $waitingSeconds sec total, ${WaitThresholdParser.shortLabel(overSeconds)} over free time. Extra charge: ₦${extraCharge.toStringAsFixed(0)}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: overSeconds == 0 ? AppColors.primary : AppColors.error));
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
  // Request Early Drop — ordered single-dialog flow
  // 1. Tap → POST /rides/{id}/early-dropoff (no pre-dialog; the button shows
  //    a "Getting updated fare…" state while the backend recalculates).
  // 2. ONE fare-gated dialog (only once the recalculated fare has arrived via
  //    REST, socket or polling) → Confirm posts /early-dropoff/confirm and the
  //    rider waits for the driver to pull over; Cancel posts /reject and the
  //    trip resumes. The driver is actionable once the rider has confirmed.
  // ─────────────────────────────────────────────────────────────────

  Future<void> _requestEarlyDropoff() async {
    if (widget.rideId == null ||
        _earlyDropoffRequested ||
        _waitingForDriver) {
      return;
    }

    setState(() {
      _earlyDropoffRequested = true;
      _fareShown = false;
    });
    _fareTimer?.cancel();
    _fareTimer = Timer(const Duration(seconds: 25), _onFareTimeout);

    try {
      final dropoff = await _currentDropoffPoint();
      final res = await ApiClient.instance.post(
        ApiConfig.rideEarlyDropoff(widget.rideId!),
        body: {
          'latitude': dropoff.latitude,
          'longitude': dropoff.longitude,
          'reason': 'Rider requested early drop-off',
        },
      );
      if (!mounted) return;
      // 2xx means the backend recorded the request, even if this payload
      // carries no fare yet (it arrives via socket/polling next).
      _serverSawEarlyDropoff = true;
      if (res != null) {
        _maybeShowEarlyDropoffFare(
          res is Map<String, dynamic> ? res : <String, dynamic>{},
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Re-entering an already-requested flow (e.g. after a restart): the
      // server holds REQUESTED state, so wait for its fare via polling
      // instead of erroring out.
      if (e.toString().toLowerCase().contains('already')) {
        _serverSawEarlyDropoff = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Resuming your early drop-off request…'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
        return;
      }
      _fareTimer?.cancel();
      setState(() {
        _earlyDropoffRequested = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not request early drop-off: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// No recalculated fare arrived within budget: stand the request down so
  /// the rider is never stuck on a dead "Getting updated fare…" state.
  Future<void> _onFareTimeout() async {
    if (!mounted ||
        _navigated ||
        _waitingForDriver ||
        _fareShown ||
        !_earlyDropoffRequested) {
      return;
    }
    try {
      await ApiClient.instance.post(
        ApiConfig.rideEarlyDropoffReject(widget.rideId!),
      );
    } catch (_) {}
    _resetEarlyDropoffState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No updated fare received — please try again.'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  /// Rider backs out while waiting for the driver: withdraw the request so
  /// both apps return to the IN_PROGRESS status quo.
  Future<void> _cancelEarlyDropoff() async {
    if (!_earlyDropoffRequested && !_waitingForDriver) return;
    _suppressAutoAdoptUntil = DateTime.now().add(const Duration(seconds: 15));
    try {
      await ApiClient.instance.post(
        ApiConfig.rideEarlyDropoffReject(widget.rideId!),
      );
    } catch (_) {
      // Best-effort — the reversal detector below also resumes the trip when
      // the backend flips the status back to IN_PROGRESS.
    }
    _resumeOriginalTrip('Early drop-off cancelled — continuing your trip.');
  }

  /// Early drop-off point: the live vehicle position (the rider is in the car),
  /// then the device GPS, then the original pickup as a last resort.
  Future<LatLng> _currentDropoffPoint() async {
    final driver = _driverPoint;
    if (driver != null) return driver;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {}
    return widget.pickupLatLng ??
        widget.destinationLatLng ??
        const LatLng(7.7337, 8.5211);
  }

  Future<void> _handleSupportAction(String endpoint, String title) async {
    if (!mounted || _navigated) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        // _doSupportFetch owns its loading dialog and dismisses it exactly once.
        unawaited(_doSupportFetch(endpoint, title, dialogCtx));
        return const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Future<void> _doSupportFetch(String endpoint, String title, BuildContext dialogCtx) async {
    // Dismiss the loading dialog exactly once. Popping a second time (the old
    // success-path + catch-path pops) removed whatever route sat on top of the
    // dialog — i.e. the Trip-in-Progress screen itself — making Emergency and
    // Customer Care silently destroy the trip screen.
    var dialogDismissed = false;
    void dismissDialog() {
      if (dialogDismissed) return;
      dialogDismissed = true;
      if (dialogCtx.mounted) {
        try {
          Navigator.of(dialogCtx).pop();
        } catch (_) {
          // Dialog already gone — never pop again.
        }
      }
    }

    try {
      final res = await ApiClient.instance.get(endpoint);
      dismissDialog();
      if (!mounted) return;
      // Both endpoints return `data: [ … ]` — a list, not a single object.
      _showSupportModal(title, parseSupportContacts(res));
    } catch (e) {
      dismissDialog();
      if (!mounted) return;
      _showSupportModal(
        title,
        const [],
        errorMessage: 'Could not load $title contacts right now. Please try again.',
      );
    }
  }

  /// Every outcome — contacts, empty state or fetch error — is a modal, as
  /// required for the Emergency / Customer Care buttons.
  void _showSupportModal(
    String title,
    List<SupportContact> contacts, {
    String? errorMessage,
  }) {
    if (!mounted || _navigated) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SupportContactsSheet(
        title: title,
        contacts: contacts,
        errorMessage: errorMessage,
      ),
    );
  }


  /// Single entry-point for the fare confirmation dialog.
  ///
  /// The recalculated fare can arrive over three channels — the dedicated
  /// early-dropoff socket, the generic `ride:state` socket, the POST
  /// `/early-dropoff` REST response, or the status polling fallback. All of
  /// them funnel through here so the rider sees exactly one dialog and is
  /// never stuck on "ENDING TRIP" with no confirmation.
  /// True when the backend signals the early drop-off request was refused
  /// (driver tapped Continue Driving / reject, or the rider withdrew it).
  bool _isEarlyRejectedMessage(dynamic message) {
    if (message == null) return false;
    final text = message.toString().toLowerCase();
    return text.contains('reject') && text.contains('drop') ||
        text.contains('declin') && text.contains('drop') ||
        text.contains('rejected early drop-off');
  }

  /// True when a status payload still carries early drop-off state, so a bare
  /// IN_PROGRESS can be told apart from a reject-driven reversal.
  bool _payloadHasEarlyFlags(Map<String, dynamic> data) {
    final status =
        (data['status'] ?? data['state'])?.toString().toUpperCase() ?? '';
    if (status.contains('EARLY')) return true;
    for (final key in const [
      'earlyDropoff',
      'early_dropoff',
      'earlyDropoffLocation',
      'earlyDropoffRequested',
      'earlyDropoffConfirmed',
    ]) {
      if (data.containsKey(key)) return true;
    }
    return false;
  }

  /// Back to the IN_PROGRESS status quo on this app: dismisses any fare
  /// dialog, clears the early drop-off flags and tells the rider the trip
  /// continues to the original destination.
  void _resumeOriginalTrip(String message) {
    if (!mounted || _navigated) return;
    if (!_earlyDropoffRequested && !_waitingForDriver) return;
    _dismissFareDialog();
    _resetEarlyDropoffState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _resetEarlyDropoffState() {
    _fareTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _earlyDropoffRequested = false;
      _waitingForDriver = false;
      _serverSawEarlyDropoff = false;
      _fareShown = false;
    });
  }

  /// Pops the fare dialog from the outside (reject/reversal path). Guarded by
  /// [_earlyFareDialogOpen] so a settled dialog never pops the trip screen.
  void _dismissFareDialog() {
    if (!_earlyFareDialogOpen || !mounted) return;
    try {
      Navigator.of(context).pop();
    } catch (_) {}
  }

  void _maybeShowEarlyDropoffFare(Map<String, dynamic> data) {
    if (!mounted ||
        _navigated ||
        _terminating ||
        _waitingForDriver ||
        _earlyFareDialogOpen ||
        !_earlyDropoffRequested) {
      return;
    }
    final incomingId = (data['rideId'] ?? data['id'])?.toString();
    if (incomingId != null && incomingId != widget.rideId) return;
    final rawFare = data['newFare'] ??
        data['earlyDropoffFare'] ??
        data['estimatedFare'] ??
        data['fare'] ??
        data['amount'] ??
        FareParser.finalFareNgn(data);
    final newFareNgn = FareParser.scalarNgn(rawFare);
    // Fare-gated: the single confirmation dialog only becomes visible once
    // the backend's recalculated fare has actually arrived. Bare REQUESTED
    // acks just keep the "Getting updated fare…" state (bounded by the fare
    // timer) instead of popping a fare-less dialog.
    if (newFareNgn == null || newFareNgn <= 0) {
      _updateLiveFare(data);
      return;
    }
    _fareShown = true;
    _fareTimer?.cancel();
    if (mounted) setState(() {});
    unawaited(_showEarlyDropoffFareConfirmation(newFareNgn, data));
  }

  /// THE single early drop-off dialog: only shown with the recalculated fare
  /// in hand. Confirm posts /early-dropoff/confirm and the rider waits for
  /// the driver to pull over (navigation happens on trip completion, so a
  /// later reject can still reverse both apps to IN_PROGRESS).
  Future<void> _showEarlyDropoffFareConfirmation(
    double? newFareNgn,
    Map<String, dynamic> payload,
  ) async {
    if (!mounted || _navigated || _earlyFareDialogOpen) return;
    _earlyFareDialogOpen = true;

    final fareStr = newFareNgn != null && newFareNgn > 0
        ? '₦${newFareNgn.toStringAsFixed(0)}'
        : 'Recalculated fare';

    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('End Trip Early?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Drop off at your current location for the recalculated fare below. '
                'Your driver will be asked to pull over safely.',
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
                'Confirming notifies your driver — they pull over and end the trip.',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep Riding'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm Drop-off'),
            ),
          ],
        ),
      );
    } finally {
      _earlyFareDialogOpen = false;
    }

    if (confirmed != true || !mounted || _navigated) {
      // Explicit "Keep Riding": withdraw the request and resume the original
      // trip. A null result means the dialog was dismissed externally by a
      // reject/reversal, which already reset the state — do nothing.
      if (confirmed == false &&
          mounted &&
          !_navigated &&
          !_waitingForDriver &&
          _earlyDropoffRequested) {
        _suppressAutoAdoptUntil =
            DateTime.now().add(const Duration(seconds: 15));
        try {
          await ApiClient.instance.post(
            ApiConfig.rideEarlyDropoffReject(widget.rideId!),
          );
        } catch (_) {}
        _resetEarlyDropoffState();
      }
      return;
    }

    // Rider accepted the recalculated fare: confirm, then wait for the
    // driver to pull over and end the trip (no navigation yet — a reject
    // must still be able to reverse both apps to IN_PROGRESS).
    try {
      await ApiClient.instance.post(
        ApiConfig.rideEarlyDropoffConfirm(widget.rideId!),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not confirm early drop-off: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted || _navigated) return;
    _serverSawEarlyDropoff = true;
    if (newFareNgn != null && newFareNgn > 0) {
      _confirmedEarlyFareNgn = newFareNgn;
      _liveFareNgn = newFareNgn;
    }
    setState(() {
      _waitingForDriver = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Waiting for your driver to pull over…'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // Trip termination handler
  // ─────────────────────────────────────────────────────────────────
  Future<void> _handleRideTerminated(
    Map<String, dynamic> data, {
    bool isPaymentPendingEvent = false,
    double? newFareNgn,
  }) async {
    if (_terminating || _navigated || !mounted) return;
    _terminating = true;

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
      } else {
        // Termination payloads often carry no fare at all. Ask the backend once
        // so the receipt shows the same final bill as the driver's summary,
        // instead of falling back to the pre-request estimate.
        final refreshed = await _fetchFinalFare();
        if (refreshed != null && refreshed > 0) {
          fare = refreshed;
        } else if (_confirmedEarlyFareNgn != null &&
            _confirmedEarlyFareNgn! > 0) {
          // The recalculated fare the rider agreed to — the checkout figure
          // when the completion payload carries no settled amount.
          fare = _confirmedEarlyFareNgn!;
        } else if (_liveFareNgn != null && _liveFareNgn! > 0) {
          fare = _liveFareNgn!;
        }
      }
    }

    _navigateToSummary(fare: fare, isPaymentConfirmed: isPaymentConfirmed);
  }

  /// Final fare straight from the backend (settled → estimate), so the receipt
  /// never falls back to the value captured when the ride was requested.
  Future<double?> _fetchFinalFare() async {
    final id = widget.rideId;
    if (id == null || id.isEmpty) return null;
    try {
      final res = await ApiClient.instance.get(ApiConfig.rideStatus(id));
      return FareParser.finalFareNgn(res);
    } catch (_) {
      return null;
    }
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

    // Required order: End Trip -> Trip Completed -> Payment -> Rate Driver
    // -> Dashboard. Payment is owned by TripCompletedScreen (Pay button when
    // pending), so always land on the receipt first — never show the payment
    // sheet on top of the in-progress screen.
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
          isPaymentConfirmed: isPaymentConfirmed,
          driverRating: widget.driverRating,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _callDriver() async {
    final phone = widget.driverPhone;
    if (phone != null && phone.isNotEmpty) {
      final uri = Uri.parse('tel:$phone');
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        }
      } catch (_) {
        // Fall through to the dialog below.
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Contact Driver'),
        content: Text(
          phone != null && phone.isNotEmpty
              ? 'Driver phone: $phone'
              : 'Driver phone number is not available. Please use in-ride chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          if (phone != null && phone.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                launchUrl(Uri.parse('tel:$phone')).catchError((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open the dialer.')),
                    );
                  }
                  return false;
                });
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
    _fareTimer?.cancel();
    _statusSub?.cancel();
    _paymentPendingSub?.cancel();
    _locationSub?.cancel();
    _earlyDropoffFareSub?.cancel();
    _stopoverTimerSub?.cancel();
    _fareUpdatedSub?.cancel();
    _stopoverUiTimer?.cancel();
    super.dispose();
  }

  /// Bottom-sheet early drop-off button across the three flow states: idle →
  /// request, awaiting fare → disabled spinner, driver-wait → cancel request.
  Widget _buildEarlyDropoffButton() {
    if (_waitingForDriver) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _cancelEarlyDropoff,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel Early Drop Request'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: AppColors.error),
            foregroundColor: AppColors.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
    final awaitingFare = _earlyDropoffRequested && !_fareShown;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _earlyDropoffRequested ? null : _requestEarlyDropoff,
        icon: awaitingFare
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
          awaitingFare ? 'Getting Updated Fare…' : 'Request Early Drop',
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
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
            // No back button while a trip is in progress: the route stays on
            // top of the stack (PopScope below blocks system back too), so the
            // only way out is ending the trip or cancelling with confirmation.
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Trip in progress',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
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
                                color: _earlyDropoffActive
                                    ? AppColors.error.withValues(alpha: 0.12)
                                    : AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _waitingForDriver
                                    ? 'WAITING FOR DRIVER'
                                    : _earlyDropoffRequested
                                        ? 'ENDING TRIP'
                                        : 'EN ROUTE',
                                style: TextStyle(
                                  color: _earlyDropoffActive
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
                                final unread = RiderChatService.instance
                                    .unreadFor(widget.rideId);
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
                                final rawIndex = s['index'] ?? s['stopIndex'] ?? (i + 1);
                                final stopNumber = _stopDisplayNumber(rawIndex is int ? rawIndex : int.tryParse(rawIndex.toString()) ?? (i + 1));
                                final status = (s['status'] ?? '').toString().toUpperCase();
                                final address = loc['address']?.toString() ?? 'Stop $stopNumber';
                                final completed = s['completed'] == true || status == 'COMPLETED';
                                final arrived = status == 'ARRIVED';
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
                                              'Stop $stopNumber',
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
                              final waitThreshold = _freeWaitSeconds;
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
                                            _stopoverElapsedSeconds > waitThreshold ? 'Extra wait charge applies' : 'Free wait — ${WaitThresholdParser.shortLabel(waitThreshold)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _stopoverElapsedSeconds > waitThreshold ? AppColors.error : AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${(_stopoverElapsedSeconds ~/ 60).toString().padLeft(1, '0')}:${(_stopoverElapsedSeconds % 60).toString().padLeft(2, '0')} elapsed${_stopoverElapsedSeconds > waitThreshold ? ' — ${WaitThresholdParser.shortLabel(_stopoverElapsedSeconds - waitThreshold)} over' : ''}',
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
                              _buildEarlyDropoffButton(),
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


