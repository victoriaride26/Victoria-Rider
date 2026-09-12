import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/config/mapbox_config.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import '../widgets/in_ride_chat_sheet.dart';
import 'ride_in_progress_screen.dart';

/// R-10 — Driver Assigned (en route to pickup).
class DriverAssignedScreen extends StatefulWidget {
  const DriverAssignedScreen({
    super.key,
    this.rideId,
    this.driverName,
    this.driverRating,
    this.vehicleModel,
    this.plateNumber,
    this.etaMinutes,
  });

  final String? rideId;
  final String? driverName;
  final double? driverRating;
  final String? vehicleModel;
  final String? plateNumber;
  final int? etaMinutes;

  @override
  State<DriverAssignedScreen> createState() => _DriverAssignedScreenState();
}

class _DriverAssignedScreenState extends State<DriverAssignedScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  Timer? _pollTimer;
  bool _driverArrived = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initListeners();
  }

  void _initListeners() {
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      _socket.joinRideRoom(widget.rideId!);

      // Realtime socket status updates
      _statusSub = _socket.onRideStatusUpdated.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          final status = (data['status'] ?? data['state'])?.toString().toUpperCase();
          _handleStatus(status);
        }
      });

      // 4-second fallback polling
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _checkStatus();
      });
    }
  }

  Future<void> _checkStatus() async {
    if (_navigated || widget.rideId == null) return;
    try {
      final token = SessionController.instance.accessToken;
      final res = await http.get(
        Uri.parse(ApiConfig.rideStatus(widget.rideId!)),
        headers: {
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>?;
        final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
        final status = data?['status']?.toString().toUpperCase();
        _handleStatus(status);
      }
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
    } else if (status == 'IN_PROGRESS' || status == 'STARTED' || status == 'INPROGRESS') {
      _navigated = true;
      _pollTimer?.cancel();
      _statusSub?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RideInProgressScreen(
            rideId: widget.rideId,
            driverName: widget.driverName,
            vehicleModel: widget.vehicleModel,
            plateNumber: widget.plateNumber,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _statusSub?.cancel();
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
    final eta = widget.etaMinutes ?? 4;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(_driverArrived ? 'Driver has arrived' : 'En route to pickup'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.more_vert, color: AppColors.onSurface),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MapboxMapView(
              center: MapboxConfig.wurukumMarket,
              zoom: 15,
              showUserLocation: true,
              markers: const [
                Marker(
                  point: MapboxConfig.wurukumMarket,
                  width: 44,
                  height: 44,
                  child: Icon(Icons.location_on,
                      color: AppColors.primary, size: 40),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _driverArrived ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _driverArrived ? Icons.check_circle : Icons.access_time,
                            color: _driverArrived ? AppColors.onPrimaryContainer : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _driverArrived ? 'Driver waiting at pickup point' : 'Driver arriving in $eta mins',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _driverArrived ? AppColors.onPrimaryContainer : AppColors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(Icons.my_location, color: AppColors.primary),
                        SizedBox(width: 12),
                        Text('Pickup Location Confirmed',
                            style: TextStyle(fontSize: 16)),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.person,
                              color: AppColors.onPrimaryContainer),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(name,
                                      style: theme.textTheme.titleLarge),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.verified,
                                      color: AppColors.primary, size: 18),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('$rating  •  Verified Driver',
                                  style: const TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(plate,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text(vehicle,
                        style: const TextStyle(color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(
                      'Arriving in a clean $vehicle. '
                      'Please confirm the plate number before boarding.',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.call),
                            label: const Text('Call Driver'),
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
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppPrimaryButton(
                      label: 'Track Driver',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RideInProgressScreen(
                            rideId: widget.rideId,
                            driverName: name,
                            vehicleModel: vehicle,
                            plateNumber: plate,
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
