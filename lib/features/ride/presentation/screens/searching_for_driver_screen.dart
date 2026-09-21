import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/rider_socket_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/image_url_helper.dart';
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
    this.paymentMethod,
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
  final String? paymentMethod;

  @override
  State<SearchingForDriverScreen> createState() =>
      _SearchingForDriverScreenState();
}

class _SearchingForDriverScreenState extends State<SearchingForDriverScreen> {
  final RiderSocketService _socket = RiderSocketService.instance;
  StreamSubscription<Map<String, dynamic>>? _acceptedSub;
  StreamSubscription<Map<String, dynamic>>? _stateSub;
  Timer? _pollTimer;
  Timer? _countdownTimer;

  static const int _maxSearchSeconds = 120;
  int _secondsRemaining = _maxSearchSeconds;
  bool _searchTimedOut = false;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    if (widget.fareNgn == null || widget.fareNgn! <= 0) {
      debugPrint(
        '[SearchingForDriverScreen] ABORT: Missing backend calculated fare.',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ride search aborted: Estimated fare must be obtained from VT Rides.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
          Navigator.of(context).pop();
        }
      });
      return;
    }
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
        final status = (data['status'] ?? data['state'])
            ?.toString()
            .toUpperCase();
        if (status == 'MATCHED' || status == 'ACCEPTED') {
          final incomingId = (data['rideId'] ?? data['id'])?.toString();
          if (incomingId == null || incomingId == widget.rideId) {
            _handleRideAccepted(data);
          }
        }
      });

      // 2. Periodic polling and countdown timer
      _startSearchTimers();
    }
  }

  void _startSearchTimers() {
    setState(() {
      _secondsRemaining = _maxSearchSeconds;
      _searchTimedOut = false;
    });

    _pollTimer?.cancel();
    _countdownTimer?.cancel();

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkRideStatus();
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _searchTimedOut = true;
          _pollTimer?.cancel();
          _countdownTimer?.cancel();
        }
      });
    });
  }

  Future<void> _checkRideStatus() async {
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
    _countdownTimer?.cancel();
    _acceptedSub?.cancel();
    _stateSub?.cancel();

    final driver = data['driver'] is Map ? data['driver'] as Map : null;
    final vehicle = driver?['vehicle'] is Map
        ? driver!['vehicle'] as Map
        : null;
    final driverUser = driver?['user'] is Map ? driver!['user'] as Map : null;

    final driverName =
        driver?['name']?.toString() ??
        driver?['fullName']?.toString() ??
        (driverUser?['firstName'] != null
            ? '${driverUser!['firstName']} ${driverUser['lastName'] ?? ''}'
                  .trim()
            : data['driverName']?.toString());

    final driverPhone =
        driver?['phone']?.toString() ??
        driver?['phoneNumber']?.toString() ??
        driverUser?['phone']?.toString() ??
        data['driverPhone']?.toString();

    LatLng? driverLocation;
    final loc =
        driver?['location'] ?? driver?['coords'] ?? data['driverLocation'];
    if (loc is Map) {
      final lat = (loc['latitude'] ?? loc['lat']) as num?;
      final lng = (loc['longitude'] ?? loc['lng']) as num?;
      if (lat != null && lng != null) {
        driverLocation = LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    final rawProfileImage =
        driver?['profilePhoto']?.toString() ??
        driver?['profilePhotoUrl']?.toString() ??
        driver?['avatar']?.toString() ??
        driver?['avatarUrl']?.toString() ??
        driver?['photoUrl']?.toString() ??
        driver?['profileImage']?.toString() ??
        driver?['photo']?.toString() ??
        driver?['imageUrl']?.toString() ??
        (driver?['profile'] is Map
            ? (driver!['profile']['profilePhoto']?.toString() ??
                  driver['profile']['avatar']?.toString() ??
                  driver['profile']['photoUrl']?.toString())
            : null) ??
        driverUser?['profilePhoto']?.toString() ??
        driverUser?['profilePhotoUrl']?.toString() ??
        driverUser?['avatar']?.toString() ??
        driverUser?['avatarUrl']?.toString() ??
        driverUser?['photoUrl']?.toString() ??
        driverUser?['profileImage']?.toString() ??
        driverUser?['photo']?.toString() ??
        driverUser?['imageUrl']?.toString() ??
        data['driverProfilePhoto']?.toString() ??
        data['driverProfilePhotoUrl']?.toString() ??
        data['driverAvatar']?.toString() ??
        data['driverAvatarUrl']?.toString() ??
        data['driverPhotoUrl']?.toString() ??
        data['driverProfileImage']?.toString() ??
        data['driverPhoto']?.toString();

    final driverProfileImage = ImageUrlHelper.normalize(rawProfileImage);

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
              ? [
                  vehicle['color']?.toString(),
                  vehicle['make']?.toString(),
                  vehicle['model']?.toString(),
                ].where((s) => s != null && s.trim().isNotEmpty).join(' ')
              : data['vehicleModel']?.toString(),
          plateNumber:
              vehicle?['plateNumber']?.toString() ??
              data['plateNumber']?.toString(),
          driverProfileImage: driverProfileImage,
          etaMinutes: (data['etaMinutes'] ?? driver?['etaMinutes']) is num
              ? (data['etaMinutes'] ?? driver?['etaMinutes']).toInt()
              : null,
          pickupLatLng: widget.pickupLatLng,
          destinationLatLng: widget.destinationLatLng,
          pickupLabel: widget.pickupLabel,
          destinationLabel: widget.destinationLabel,
          fareNgn: () {
            final f =
                data['fare'] ?? data['estimatedFare'] ?? data['finalFare'];
            if (f is num) return f > 10000 ? f.toDouble() / 100 : f.toDouble();
            if (f is Map) {
              final inner = f['estimatedFare'] ?? f['finalFare'] ?? f['amount'];
              if (inner is num)
                return inner > 10000
                    ? inner.toDouble() / 100
                    : inner.toDouble();
            }
            return widget.fareNgn;
          }(),
          initialDriverLocation: driverLocation,
          paymentMethod:
              widget.paymentMethod ?? data['paymentMethod']?.toString(),
        ),
      ),
    );
  }

  Future<void> _cancelRide() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
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
    _countdownTimer?.cancel();
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
                if (_searchTimedOut)
                  Column(
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.timer_off_outlined,
                          size: 40,
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Search Timed Out',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No drivers accepted the request in time. Would you like to try again?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      AppPrimaryButton(
                        label: 'Retry Search',
                        icon: Icons.refresh,
                        onPressed: _startSearchTimers,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _cancelRide,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel Request',
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: _secondsRemaining / _maxSearchSeconds,
                              color: AppColors.primary,
                              backgroundColor: AppColors.surfaceContainerHigh,
                              strokeWidth: 6,
                            ),
                          ),
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer.withValues(
                                alpha: 0.5,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${(_secondsRemaining ~/ 60)}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      AppPrimaryButton(
                        label: 'Cancel Request',
                        onPressed: _cancelRide,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
