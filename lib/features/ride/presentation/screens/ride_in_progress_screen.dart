import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/config/mapbox_config.dart';
import '../../../../core/network/api_client.dart';
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

  @override
  State<RideInProgressScreen> createState() => _RideInProgressScreenState();
}

class _RideInProgressScreenState extends State<RideInProgressScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  final MapController _mapController = MapController();

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<DriverLocationUpdate>? _locationSub;
  Timer? _pollTimer;

  bool _navigated = false;
  late LatLng _destinationPoint;
  LatLng? _driverPoint;
  double? _driverHeading;
  int _etaMinutes = 8;

  @override
  void initState() {
    super.initState();
    _destinationPoint =
        widget.destinationLatLng ?? MapboxConfig.modernMarket;

    // Start driver location at pickup or destination offset
    _driverPoint = widget.pickupLatLng ??
        LatLng(
          _destinationPoint.latitude - 0.012,
          _destinationPoint.longitude - 0.008,
        );

    _initListeners();
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
              final distanceMeters = const Distance()
                  .as(LengthUnit.Meter, _driverPoint!, _destinationPoint);
              _etaMinutes =
                  ((distanceMeters / 1000) / 30 * 60).ceil().clamp(1, 60);
            }
          });
        }
      });

      // 3. Socket listener for trip completion
      _statusSub = _socket.onRideStatusUpdated.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          final status =
              (data['status'] ?? data['state'])?.toString().toUpperCase();
          if (status == 'COMPLETED' || status == 'COMPLETE') {
            _handleCompleted(data);
          }
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
      final response = await ApiClient.instance
          .get(ApiConfig.rideStatus(widget.rideId!));
      final decoded = response as Map<String, dynamic>?;
      final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
      final status =
          (data?['status'] ?? data?['state'])?.toString().toUpperCase();
      if (status == 'COMPLETED' || status == 'COMPLETE') {
        _handleCompleted(data ?? {});
      }
    } catch (_) {}
  }

  void _handleCompleted(Map<String, dynamic> data) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _pollTimer?.cancel();
    _statusSub?.cancel();
    _locationSub?.cancel();

    final fare = (data['fare'] ??
            data['finalFare'] ??
            data['totalFare'] ??
            widget.fareNgn) is num
        ? ((data['fare'] ??
                data['finalFare'] ??
                data['totalFare'] ??
                widget.fareNgn) as num)
            .toDouble()
        : widget.fareNgn;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TripCompletedScreen(
          rideId: widget.rideId,
          driverName: widget.driverName,
          fareNgn: fare,
        ),
      ),
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

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
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
                    child: AppBackButton(
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute<void>(
                              builder: (_) => const RiderHomeShell(),
                            ),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Trip in Progress',
                                style: theme.textTheme.headlineMedium),
                            const SizedBox(height: 4),
                            Text('Estimated arrival: $_etaMinutes mins',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.primary)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('EN ROUTE',
                              style: TextStyle(
                                  color: AppColors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        DriverAvatar(
                          imageUrl: widget.driverProfileImage,
                          radius: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: theme.textTheme.titleMedium),
                              Text(carInfo,
                                  style: const TextStyle(
                                      color: AppColors.onSurfaceVariant)),
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
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Destination',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                              Text(
                                widget.destinationLabel ?? 'Destination',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield, color: AppColors.primary),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Trip Protected')),
                          TextButton(
                            onPressed: () {},
                            child: const Text('Emergency',
                                style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimated Fare',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                        Text(fareStr,
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppPrimaryButton(
                      label: 'End Trip / Payment',
                      onPressed: () => _handleCompleted({}),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
