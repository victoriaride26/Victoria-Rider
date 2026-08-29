import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

import '../config/api_config.dart';
import '../network/api_client.dart';

/// Background GPS tracking — keeps sending driver position even when the app
/// is minimized / screen off.
///
/// Android: uses `Geolocator.getPositionStream` with a foreground service
/// notification (`FOREGROUND_SERVICE_LOCATION`) so the OS does not kill the
/// stream. Requires `ACCESS_BACKGROUND_LOCATION` + `POST_NOTIFICATIONS`.
///
/// iOS: requires `UIBackgroundModes: location` + `NSLocationWhenInUseUsageDescription`
/// / `NSLocationAlwaysAndWhenInUseUsageDescription` (add to Info.plist).
///
/// Usage:
/// ```dart
/// await BackgroundLocationService.instance.start(); // when driver goes online
/// await BackgroundLocationService.instance.stop();  // when driver goes offline
/// ```
class BackgroundLocationService {
  BackgroundLocationService._();

  static final BackgroundLocationService instance =
      BackgroundLocationService._();

  StreamSubscription<Position>? _sub;
  Timer? _throttleTimer;
  Position? _lastSent;
  bool _running = false;

  bool get isRunning => _running;

  /// Last known position (if any).
  Position? get lastPosition => _lastSent;

  /// Checks / requests location permissions.
  ///
  /// - Handles `denied`, `deniedForever`, service disabled.
  /// - On Android, also requests `Permission.notification` for the foreground
  ///   service notification and `Permission.locationAlways` for background.
  Future<bool> ensurePermission() async {
    try {
      // Service enabled?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) debugPrint('Location services disabled');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (kDebugMode) debugPrint('Location permission denied: $permission');
        return false;
      }

      // For background on Android, we need "always" (background) permission.
      // Geolocator.requestPermission() only asks for whenInUse; escalate via
      // permission_handler if we only have whileInUse.
      if (permission == LocationPermission.whileInUse) {
        try {
          final status = await perm.Permission.locationAlways.status;
          if (!status.isGranted) {
            final req = await perm.Permission.locationAlways.request();
            if (kDebugMode) debugPrint('Background status: $req');
            // Even if not granted, we can still run foreground tracking
            // while app is visible; OS will pause when minimized.
          }
        } catch (_) {}
      }

      // Notification permission for foreground service notification channel.
      try {
        await perm.Permission.notification.request();
      } catch (_) {}

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('ensurePermission failed: $e');
      return false;
    }
  }

  /// Starts continuous location updates.
  ///
  /// - Throttles network posts to at most every 10 seconds / 10 meters.
  /// - Shows Android foreground notification "Victoria Rides — Tracking your location".
  /// - Safe to call multiple times (idempotent).
  Future<bool> start({
    Duration throttle = const Duration(seconds: 10),
    double minDistanceMeters = 10,
  }) async {
    if (_running) return true;

    final granted = await ensurePermission();
    if (!granted) return false;

    try {
      LocationSettings settings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Victoria Rides — Tracking your location',
            notificationText: 'Sharing live location so riders can find you',
            enableWakeLock: true,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        );
      }

      // Get immediate fix.
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: settings,
        );
        _handlePosition(pos, minDistanceMeters: minDistanceMeters);
      } catch (_) {}

      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) => _handlePosition(pos, minDistanceMeters: minDistanceMeters),
        onError: (e) {
          if (kDebugMode) debugPrint('BackgroundLocation error: $e');
        },
      );

      _running = true;
      if (kDebugMode) debugPrint('BackgroundLocationService started');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('start background tracking failed: $e');
      return false;
    }
  }

  void _handlePosition(Position pos,
      {required double minDistanceMeters}) {
    // Throttle: only send if moved enough or throttle timer elapsed.
    final now = DateTime.now();
    final last = _lastSent;
    bool shouldSend = false;
    if (last == null) {
      shouldSend = true;
    } else {
      final dist = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        pos.latitude,
        pos.longitude,
      );
      final elapsed = now.difference(_lastTime ?? now);
      if (dist >= minDistanceMeters || elapsed.inSeconds >= 10) {
        shouldSend = true;
      }
    }
    if (!shouldSend) return;

    _lastSent = pos;
    _lastTime = now;
    _throttleTimer?.cancel();
    // Post asynchronously — don't await in stream.
    unawaited(_postLocation(pos));
  }

  DateTime? _lastTime;

  Future<void> _postLocation(Position pos) async {
    try {
      await ApiClient.instance.post(
        ApiConfig.driverLocation,
        body: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
          'heading': pos.heading,
          'speed': pos.speed,
          'timestamp': pos.timestamp.toIso8601String(),
        },
      );
      if (kDebugMode) debugPrint('Posted location ${pos.latitude},${pos.longitude}');
    } catch (e) {
      if (kDebugMode) debugPrint('Post location failed: $e');
    }
  }

  /// Stops tracking and removes foreground notification.
  Future<void> stop() async {
    if (!_running && _sub == null) return;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _running = false;
    if (kDebugMode) debugPrint('BackgroundLocationService stopped');
  }

  /// Dispose for app shutdown.
  Future<void> dispose() => stop();
}
