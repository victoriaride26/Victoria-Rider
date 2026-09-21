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
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/driver_avatar.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import '../widgets/in_ride_chat_sheet.dart';
import 'trip_completed_screen.dart';

/// R-11 — Ride in Progress: active map tracking the vehicle towards destination.
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
  Timer? _pollTimer;

  bool _navigated = false;
  late LatLng _destinationPoint;
  LatLng? _driverPoint;
  double? _driverHeading;
  int _etaMinutes = 8;

  String? _resolvedPickupAddress;
  String? _resolvedDropoffAddress;
  String? _activePaymentMethod;

  @override
  void initState() {
    super.initState();
    _destinationPoint = widget.destinationLatLng ?? MapboxConfig.modernMarket;

    // Start driver location at pickup or destination offset
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
    _initListeners();
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
          }
        }
      });

      _paymentPendingSub = _socket.onPaymentPending.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          _handleRideTerminated(data, isPaymentPendingEvent: true);
        }
      });

      // 4. 4-second polling fallback
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _checkStatus();
      });
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
      }
    } catch (_) {}
  }

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

  Future<void> _confirmEndTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Trip?'),
        content: const Text(
          'Are you sure you want to end this trip and proceed to payment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Back to Navigation'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, End Trip'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (widget.rideId != null) {
        try {
          await ApiClient.instance.post(ApiConfig.rideComplete(widget.rideId!));
        } catch (_) {}
      }
      _handleRideTerminated({});
    }
  }

  Future<void> _handleRideTerminated(
    Map<String, dynamic> data, {
    bool isPaymentPendingEvent = false,
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

    final fareRaw =
        data['grossFare'] ??
        data['fare'] ??
        data['finalFare'] ??
        data['totalFare'] ??
        data['amount'];

    double fare = widget.fareNgn ?? 0.0;
    if (fareRaw is num) {
      // Backend uses kobo in Paystack endpoints (100 kobo = 1 NGN).
      // If integer >= 100, convert kobo to NGN.
      if (fareRaw is int && fareRaw >= 100) {
        fare = fareRaw / 100.0;
      } else {
        fare = fareRaw.toDouble();
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

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => TripCompletedScreen(
          rideId: widget.rideId,
          driverName: widget.driverName,
          fareNgn: fare,
          pickupAddress: _resolvedPickupAddress,
          dropoffAddress: _resolvedDropoffAddress,
          paymentMethod: _activePaymentMethod ?? widget.paymentMethod,
          isPaymentConfirmed: isPaymentConfirmed,
        ),
      ),
      (route) => route.isFirst,
    );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.driverName ?? 'Driver';
    final carInfo =
        '${widget.vehicleModel ?? 'Vehicle'} • ${widget.plateNumber ?? 'Plate Info'}';
    final fareStr = widget.fareNgn != null
        ? '₦${widget.fareNgn!.toStringAsFixed(0)}'
        : 'Calculating...';

    final isPaystackMethod =
        (_activePaymentMethod?.toUpperCase() == 'CARD' ||
        _activePaymentMethod?.toUpperCase() == 'TRANSFER' ||
        widget.paymentMethod?.toUpperCase() == 'CARD' ||
        widget.paymentMethod?.toUpperCase() == 'TRANSFER');

    final markers = <Marker>[
      // Destination marker
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
      // Live moving driver vehicle marker
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
              initialChildSize: 0.48,
              minChildSize: 0.25,
              maxChildSize: 0.52,
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
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'EN ROUTE',
                                style: TextStyle(
                                  color: AppColors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                            IconButton(
                              onPressed: () {
                                InRideChatSheet.show(
                                  context,
                                  rideId: widget.rideId ?? 'active_ride',
                                  driverName: name,
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline),
                              tooltip: 'Message Driver',
                            ),
                          ],
                        ),
                        const Divider(height: 16),
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
                        const SizedBox(height: 12),
                        SafeArea(
                          top: false,
                          child: AppPrimaryButton(
                            label: 'End Trip',
                            onPressed: _confirmEndTrip,
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
