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
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import '../widgets/in_ride_chat_sheet.dart';
import 'trip_completed_screen.dart';

/// R-11 — Ride in Progress.
class RideInProgressScreen extends StatefulWidget {
  const RideInProgressScreen({
    super.key,
    this.rideId,
    this.driverName,
    this.vehicleModel,
    this.plateNumber,
    this.fareNgn,
  });

  final String? rideId;
  final String? driverName;
  final String? vehicleModel;
  final String? plateNumber;
  final double? fareNgn;

  @override
  State<RideInProgressScreen> createState() => _RideInProgressScreenState();
}

class _RideInProgressScreenState extends State<RideInProgressScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  Timer? _pollTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initListeners();
  }

  void _initListeners() {
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      _socket.joinRideRoom(widget.rideId!);

      // Socket listener for trip completion
      _statusSub = _socket.onRideStatusUpdated.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          final status = (data['status'] ?? data['state'])?.toString().toUpperCase();
          if (status == 'COMPLETED' || status == 'COMPLETE') {
            _handleCompleted(data);
          }
        }
      });

      // 4-second polling fallback
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
        if (status == 'COMPLETED' || status == 'COMPLETE') {
          _handleCompleted(data ?? {});
        }
      }
    } catch (_) {}
  }

  void _handleCompleted(Map<String, dynamic> data) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _pollTimer?.cancel();
    _statusSub?.cancel();

    final fare = (data['fare'] ?? data['finalFare'] ?? data['totalFare'] ?? widget.fareNgn) is num
        ? ((data['fare'] ?? data['finalFare'] ?? data['totalFare'] ?? widget.fareNgn) as num).toDouble()
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
    final carInfo = '${widget.vehicleModel ?? 'Lexus ES 350'} • ${widget.plateNumber ?? 'ABC-123-XY'}';
    final fareStr = widget.fareNgn != null
        ? '₦${widget.fareNgn!.toStringAsFixed(0)}'
        : '₦3,450.00';

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MapboxMapView(
              center: MapboxConfig.modernMarket,
              zoom: 14,
              showUserLocation: true,
              markers: const [
                Marker(
                  point: MapboxConfig.modernMarket,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Trip in Progress',
                                style: theme.textTheme.headlineMedium),
                            const SizedBox(height: 4),
                            Text('Estimated arrival: 8 mins',
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
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.person,
                              color: AppColors.onPrimaryContainer),
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
                            onPressed: () {}, icon: const Icon(Icons.call)),
                        IconButton(
                            onPressed: () {
                              InRideChatSheet.show(
                                context,
                                rideId: widget.rideId ?? 'active_ride',
                                driverName: name,
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline)),
                      ],
                    ),
                    const Divider(height: 24),
                    const Row(
                      children: [
                        Icon(Icons.location_on, color: AppColors.primary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Destination',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                              Text('Modern Market',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
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
                          const Expanded(child: Text('Share Trip Status')),
                          TextButton(
                              onPressed: () {},
                              child: const Text('Emergency',
                                  style: TextStyle(color: AppColors.error))),
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
                      label: 'Trip Details',
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
