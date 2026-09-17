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
import '../../../../core/widgets/mapbox_map_view.dart';
import '../widgets/in_ride_chat_sheet.dart';
import 'ride_in_progress_screen.dart';

/// R-10 — Driver Assigned: active map tracking the driver en route to pickup.
class DriverAssignedScreen extends StatefulWidget {
  const DriverAssignedScreen({
    super.key,
    this.rideId,
    this.driverName,
    this.driverPhone,
    this.driverRating,
    this.vehicleModel,
    this.plateNumber,
    this.etaMinutes,
    this.pickupLatLng,
    this.destinationLatLng,
    this.pickupLabel,
    this.destinationLabel,
    this.fareNgn,
    this.initialDriverLocation,
  });

  final String? rideId;
  final String? driverName;
  final String? driverPhone;
  final double? driverRating;
  final String? vehicleModel;
  final String? plateNumber;
  final int? etaMinutes;
  final LatLng? pickupLatLng;
  final LatLng? destinationLatLng;
  final String? pickupLabel;
  final String? destinationLabel;
  final double? fareNgn;
  final LatLng? initialDriverLocation;

  @override
  State<DriverAssignedScreen> createState() => _DriverAssignedScreenState();
}

class _DriverAssignedScreenState extends State<DriverAssignedScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  final MapController _mapController = MapController();

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<DriverLocationUpdate>? _locationSub;
  Timer? _pollTimer;

  bool _driverArrived = false;
  bool _navigated = false;

  late LatLng _pickupPoint;
  LatLng? _driverPoint;
  double? _driverHeading;
  int _etaMinutes = 4;

  @override
  void initState() {
    super.initState();

    _pickupPoint = widget.pickupLatLng ?? MapboxConfig.wurukumMarket;
    _etaMinutes = widget.etaMinutes ?? 4;

    // Initial driver location fallback: slightly offset if not provided
    if (widget.initialDriverLocation != null) {
      _driverPoint = widget.initialDriverLocation;
    } else {
      _driverPoint = LatLng(
        _pickupPoint.latitude + 0.008,
        _pickupPoint.longitude + 0.006,
      );
    }

    _initRealtimeListeners();
  }

  void _initRealtimeListeners() {
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      // 1. Subscribe to the ride's live tracking room
      _socket.subscribeToRideTracking(widget.rideId!);

      // 2. Stream driver GPS coordinates via WebSockets
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
              // Recalculate approximate ETA based on distance
              final distanceMeters = const Distance()
                  .as(LengthUnit.Meter, _driverPoint!, _pickupPoint);
              _etaMinutes = ((distanceMeters / 1000) / 30 * 60).ceil().clamp(1, 45);
            }
          });
        }
      });

      // 3. Realtime socket status updates (ride:status:update / ride:state)
      _statusSub = _socket.onRideStatusUpdated.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          final status =
              (data['status'] ?? data['state'])?.toString().toUpperCase();
          _handleStatus(status);
        }
      });

      // 4. 4-second fallback polling
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
      _handleStatus(status);
    } catch (_) {}
  }

  void _handleStatus(String? status) {
    if (_navigated || !mounted || status == null) return;

    if (status == 'ARRIVED') {
      if (!_driverArrived) {
        setState(() => _driverArrived = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚗 Your Victoria driver has arrived at the pickup point!'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else if (status == 'IN_PROGRESS' ||
        status == 'STARTED' ||
        status == 'INPROGRESS') {
      _navigated = true;
      _pollTimer?.cancel();
      _statusSub?.cancel();
      _locationSub?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RideInProgressScreen(
            rideId: widget.rideId,
            driverName: widget.driverName,
            driverPhone: widget.driverPhone,
            vehicleModel: widget.vehicleModel,
            plateNumber: widget.plateNumber,
            pickupLatLng: _pickupPoint,
            destinationLatLng: widget.destinationLatLng,
            destinationLabel: widget.destinationLabel,
            fareNgn: widget.fareNgn,
          ),
        ),
      );
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
              : 'Driver phone number is not available directly. Please use in-ride chat.',
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
    final name = widget.driverName ?? 'Terwase O.';
    final rating = widget.driverRating != null
        ? '⭐ ${widget.driverRating!.toStringAsFixed(1)}'
        : '⭐ 4.8';
    final vehicle = widget.vehicleModel ?? 'Toyota Corolla • White';
    final plate = widget.plateNumber ?? 'ABC-123-XY';

    // Build markers for map: Rider Pickup Point + Live Moving Driver Car
    final markers = <Marker>[
      // 1. Pickup location marker
      Marker(
        point: _pickupPoint,
        width: 50,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.location_on,
              color: AppColors.primary,
              size: 38,
            ),
          ),
        ),
      ),
      // 2. Live moving driver vehicle marker
      if (_driverPoint != null)
        Marker(
          point: _driverPoint!,
          width: 52,
          height: 52,
          child: Transform.rotate(
            angle: (_driverHeading ?? 0) * (3.141592653589793 / 180),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_car,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
    ];

    // Build route polyline between driver and pickup
    final polylines = <Polyline>[
      if (_driverPoint != null)
        Polyline(
          points: [_driverPoint!, _pickupPoint],
          color: AppColors.primary,
          strokeWidth: 4,
          pattern: StrokePattern.dashed(segments: [8, 6]),
        ),
    ];

    // Compute center between driver and pickup
    final mapCenter = _driverPoint != null
        ? LatLng(
            (_driverPoint!.latitude + _pickupPoint.latitude) / 2,
            (_driverPoint!.longitude + _pickupPoint.longitude) / 2,
          )
        : _pickupPoint;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(_driverArrived ? 'Driver has arrived' : 'Driver en route'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (widget.rideId != null) {
                _socket.subscribeToRideTracking(widget.rideId!);
                _checkStatus();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Active Map with Live Moving Driver Marker ──
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                MapboxMapView(
                  mapController: _mapController,
                  center: mapCenter,
                  zoom: 14.5,
                  showUserLocation: true,
                  markers: markers,
                  polylines: polylines,
                ),
                // Floating status pill over the map
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _driverArrived
                          ? AppColors.primary
                          : Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _driverArrived
                              ? Icons.check_circle
                              : Icons.navigation_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _driverArrived
                                ? 'Driver waiting at pickup point'
                                : 'Driver is on the way • arriving in $_etaMinutes mins',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Driver Info & Action Controls Sheet ──
          Expanded(
            flex: 5,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pickup address confirmation
                    Row(
                      children: [
                        const Icon(Icons.my_location,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.pickupLabel ?? 'Pickup location confirmed',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Driver Profile Details
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.person,
                              color: AppColors.onPrimaryContainer, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(name,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified,
                                      color: AppColors.primary, size: 18),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('$rating  •  Verified Victoria Driver',
                                  style: const TextStyle(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(plate,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1)),
                              Text(vehicle,
                                  style: const TextStyle(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 12)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$_etaMinutes MINS',
                              style: const TextStyle(
                                color: AppColors.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Action buttons: Call Driver & Message Driver
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _callDriver,
                            icon: const Icon(Icons.call),
                            label: const Text('Call Driver'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              InRideChatSheet.show(
                                context,
                                rideId: widget.rideId ?? 'active_ride',
                                driverName: name,
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Message'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppPrimaryButton(
                      label: 'Full Trip Tracking',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RideInProgressScreen(
                            rideId: widget.rideId,
                            driverName: name,
                            driverPhone: widget.driverPhone,
                            vehicleModel: vehicle,
                            plateNumber: plate,
                            pickupLatLng: _pickupPoint,
                            destinationLatLng: widget.destinationLatLng,
                            destinationLabel: widget.destinationLabel,
                            fareNgn: widget.fareNgn,
                          ),
                        ),
                      ),
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
