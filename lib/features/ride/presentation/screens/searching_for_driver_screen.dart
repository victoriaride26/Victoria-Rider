import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/services/session_controller.dart';
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
  });

  /// The ride ID returned by the backend after creating the ride.
  final String? rideId;

  /// Whether to enable live Socket.IO connection and status polling.
  /// Defaults to true; set to false in isolated widget tests.
  final bool enableRealtime;

  @override
  State<SearchingForDriverScreen> createState() =>
      _SearchingForDriverScreenState();
}

class _SearchingForDriverScreenState extends State<SearchingForDriverScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  StreamSubscription<Map<String, dynamic>>? _acceptedSub;
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
      _socket.joinRideRoom(widget.rideId!);

      // 1. Socket event listener for instant push
      _acceptedSub = _socket.onRideAccepted.listen((data) {
        final incomingId = (data['rideId'] ?? data['id'])?.toString();
        if (incomingId == null || incomingId == widget.rideId) {
          _handleRideAccepted(data);
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
      final token = SessionController.instance.accessToken;
      final res = await http.get(
        Uri.parse(ApiConfig.rideStatus(widget.rideId!)),
        headers: {
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>?;
        final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
        final status = data?['status']?.toString().toUpperCase();
        if (status == 'ACCEPTED' ||
            status == 'ARRIVED' ||
            status == 'IN_PROGRESS') {
          _handleRideAccepted(data ?? {});
        }
      }
    } catch (_) {}
  }

  void _handleRideAccepted(Map<String, dynamic> data) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _pollTimer?.cancel();
    _acceptedSub?.cancel();

    final driver = data['driver'] is Map ? data['driver'] as Map : null;
    final vehicle =
        driver?['vehicle'] is Map ? driver!['vehicle'] as Map : null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DriverAssignedScreen(
          rideId: widget.rideId,
          driverName:
              driver?['name']?.toString() ?? data['driverName']?.toString(),
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
        ),
      ),
    );
  }

  Future<void> _cancelRide() async {
    _pollTimer?.cancel();
    _acceptedSub?.cancel();
    if (widget.rideId != null && widget.rideId!.isNotEmpty) {
      try {
        final token = SessionController.instance.accessToken;
        await http
            .post(
              Uri.parse(ApiConfig.rideCancel(widget.rideId!)),
              headers: {
                'Content-Type': 'application/json',
                if (token != null && token.isNotEmpty)
                  'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'reason': 'Cancelled by rider'}),
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _acceptedSub?.cancel();
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
                  child: const Icon(Icons.directions_car,
                      size: 48, color: AppColors.onPrimaryContainer),
                ),
                const SizedBox(height: 24),
                Text('Finding your Victoria driver nearby...',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Matching with the best route for your premium journey.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Live Search',
                          style: theme.textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Est. 2 mins',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: AppPrimaryButton(
            label: 'Cancel Request',
            onPressed: _cancelRide,
          ),
        ),
      ),
    );
  }
}
