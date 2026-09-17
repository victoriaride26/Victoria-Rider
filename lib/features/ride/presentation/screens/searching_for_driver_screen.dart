import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import 'driver_assigned_screen.dart';

/// R-09 — Searching for Driver.
class SearchingForDriverScreen extends StatefulWidget {
  const SearchingForDriverScreen({
    super.key,
    this.rideId,
    this.enableRealtime = true,
    this.pickupLatLng,
    this.destinationLatLng,
    this.pickupLabel,
    this.destinationLabel,
    this.fareNgn,
  });

  /// The ride ID returned by the backend after creating the ride.
  final String? rideId;

  /// Whether to enable live Socket.IO connection and status polling.
  /// Defaults to true; set to false in isolated widget tests.
  final bool enableRealtime;

  final LatLng? pickupLatLng;
  final LatLng? destinationLatLng;
  final String? pickupLabel;
  final String? destinationLabel;
  final double? fareNgn;

  @override
  State<SearchingForDriverScreen> createState() =>
      _SearchingForDriverScreenState();
}

class _SearchingForDriverScreenState extends State<SearchingForDriverScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  StreamSubscription<Map<String, dynamic>>? _acceptedSub;
  StreamSubscription<Map<String, dynamic>>? _stateSub;
  Timer? _pollTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableRealtime) {
      _initListeners();
    }
  }

  void _initListeners() {
    _socket.connect();
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      _socket.subscribeToRideTracking(widget.rideId!);

      // 1. Socket event listener for instant push (ride:state MATCHED or ride:accepted)
      _acceptedSub = _socket.onRideAccepted.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          _handleRideAccepted(data);
        }
      });

      _stateSub = _socket.onRideState.listen((data) {
        final status = (data['status'] ?? data['state'])?.toString().toUpperCase();
        if (status == 'MATCHED' || status == 'ACCEPTED') {
          final incomingId = (data['rideId'] ?? data['id'])?.toString();
          if (incomingId == null || incomingId == widget.rideId) {
            _handleRideAccepted(data);
          }
        }
      });

      // 2. Periodic polling fallback every 3 seconds
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _checkRideStatus();
      });
    }
  }

  Future<void> _checkRideStatus() async {
    if (_navigated || widget.rideId == null) return;
    try {
      final response = await ApiClient.instance
          .get(ApiConfig.rideStatus(widget.rideId!));
      final decoded = response as Map<String, dynamic>?;
      final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
      final status = (data?['status'] ?? data?['state'])?.toString().toUpperCase();
      if (status == 'MATCHED' ||
          status == 'ACCEPTED' ||
          status == 'ARRIVED' ||
          status == 'IN_PROGRESS') {
        _handleRideAccepted(data ?? {});
      }
    } catch (_) {}
  }

  void _handleRideAccepted(Map<String, dynamic> data) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _pollTimer?.cancel();
    _acceptedSub?.cancel();
    _stateSub?.cancel();

    final driver = data['driver'] is Map ? data['driver'] as Map : null;
    final vehicle =
        driver?['vehicle'] is Map ? driver!['vehicle'] as Map : null;
    final driverUser =
        driver?['user'] is Map ? driver!['user'] as Map : null;

    final driverName = driver?['name']?.toString() ??
        driver?['fullName']?.toString() ??
        (driverUser?['firstName'] != null
            ? '${driverUser!['firstName']} ${driverUser['lastName'] ?? ''}'.trim()
            : data['driverName']?.toString());

    final driverPhone = driver?['phone']?.toString() ??
        driver?['phoneNumber']?.toString() ??
        driverUser?['phone']?.toString() ??
        data['driverPhone']?.toString();

    LatLng? driverLocation;
    final loc = driver?['location'] ?? driver?['coords'] ?? data['driverLocation'];
    if (loc is Map) {
      final lat = (loc['latitude'] ?? loc['lat']) as num?;
      final lng = (loc['longitude'] ?? loc['lng']) as num?;
      if (lat != null && lng != null) {
        driverLocation = LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DriverAssignedScreen(
          rideId: widget.rideId,
          driverName: driverName,
          driverPhone: driverPhone,
          driverRating: (driver?['rating'] ?? data['driverRating']) is num
              ? (driver?['rating'] ?? data['driverRating']).toDouble()
              : null,
          vehicleModel: vehicle != null
              ? '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim()
              : data['vehicleModel']?.toString(),
          plateNumber: vehicle?['plateNumber']?.toString() ??
              data['plateNumber']?.toString(),
          etaMinutes: (data['etaMinutes'] ?? driver?['etaMinutes']) is num
              ? (data['etaMinutes'] ?? driver?['etaMinutes']).toInt()
              : null,
          pickupLatLng: widget.pickupLatLng,
          destinationLatLng: widget.destinationLatLng,
          pickupLabel: widget.pickupLabel,
          destinationLabel: widget.destinationLabel,
          fareNgn: widget.fareNgn,
          initialDriverLocation: driverLocation,
        ),
      ),
    );
  }

  Future<void> _cancelRide() async {
    _pollTimer?.cancel();
    _acceptedSub?.cancel();
    _stateSub?.cancel();
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      try {
        await ApiClient.instance.post(
          ApiConfig.rideCancel(widget.rideId!),
          body: {'reason': 'Cancelled by rider'},
        );
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _acceptedSub?.cancel();
    _stateSub?.cancel();
    if (widget.enableRealtime) {
      _socket.disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: _cancelRide),
        title: const Text('Searching for Driver'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Finding your Victoria driver nearby...',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Notifying the closest drivers within 10km. Please hold on.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                AppPrimaryButton(
                  label: 'Cancel Request',
                  onPressed: _cancelRide,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
