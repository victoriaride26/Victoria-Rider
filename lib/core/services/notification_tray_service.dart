import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// System tray notification service.
///
/// When `POST_NOTIFICATIONS` (Android 13+) / notification permission is
/// granted, app notifications are also posted to the OS alerts tray so the
/// driver sees ride requests, KYC updates etc. even outside the app.
///
/// Gracefully degrades in tests / when plugin not available.
class NotificationTrayService {
  NotificationTrayService._();

  static final NotificationTrayService instance = NotificationTrayService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;

  bool get isGranted => _permissionGranted;
  bool get isInitialized => _initialized;

  static const _channelId = 'victoria_rides_driver';
  static const _channelName = 'Victoria Rides Driver';
  static const _channelDesc = 'Ride requests, payouts and KYC updates';

  /// Initializes the plugin and checks/requests notification permission.
  ///
  /// Call once in `main()` before `runApp`. Safe to call multiple times.
  Future<void> init({bool requestPermission = true}) async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          // Deep-link handling can be added here (e.g. open ride request).
          if (kDebugMode) debugPrint('Notification tapped: ${details.payload}');
        },
      );

      // Create Android channel.
      if (Platform.isAndroid) {
        final androidPlugin =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );
      }

      _initialized = true;

      if (requestPermission) {
        await requestNotificationPermission();
      } else {
        _permissionGranted = await _checkPermission();
      }
    } catch (e) {
      // Plugin unavailable (tests, web) — degrade silently.
      if (kDebugMode) debugPrint('NotificationTrayService init failed: $e');
    }
  }

  /// Checks current notification permission without prompting.
  Future<bool> _checkPermission() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.notification.status;
        return status.isGranted;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Requests `POST_NOTIFICATIONS` / iOS notification permission.
  ///
  /// Returns true when granted. On Android <13 the permission is implicitly
  /// granted; on iOS the system dialog is shown once.
  Future<bool> requestNotificationPermission() async {
    try {
      if (Platform.isIOS) {
        final iosPlugin =
            _plugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        final granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        // Fallback to permission_handler for accurate status.
        final status = await Permission.notification.status;
        _permissionGranted = granted ?? status.isGranted;
        return _permissionGranted;
      }
      if (Platform.isAndroid) {
        // Direct plugin request handles Android 13+ correctly.
        final androidPlugin =
            _plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        if (granted != null) {
          _permissionGranted = granted;
          return granted;
        }
        // Fallback via permission_handler.
        final status = await Permission.notification.request();
        _permissionGranted = status.isGranted;
        return _permissionGranted;
      }
      _permissionGranted = await _checkPermission();
      return _permissionGranted;
    } catch (e) {
      if (kDebugMode) debugPrint('Notification permission request failed: $e');
      _permissionGranted = false;
      return false;
    }
  }

  /// Ensures tray permission is granted, requesting if needed.
  Future<bool> ensurePermission() async {
    if (!_initialized) await init();
    if (_permissionGranted) return true;
    return requestNotificationPermission();
  }

  /// Shows a heads-up system notification in the OS tray.
  ///
  /// No-op when not initialized or permission denied (still logs in debug).
  Future<void> show({
    required String title,
    required String body,
    String? payload,
    int? id,
    NotificationTypeTray type = NotificationTypeTray.general,
  }) async {
    if (!_initialized) {
      if (kDebugMode) debugPrint('Tray not initialized — dropping: $title');
      return;
    }
    if (!_permissionGranted) {
      final granted = await _checkPermission();
      if (!granted) {
        if (kDebugMode) debugPrint('Tray permission denied — dropping: $title');
        return;
      }
      _permissionGranted = true;
    }
    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body),
        category: type.androidCategory,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      final notifId = id ?? DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
      await _plugin.show(notifId, title, body, details, payload: payload);
    } catch (e) {
      if (kDebugMode) debugPrint('Show tray notification failed: $e');
    }
  }

  /// Convenience helpers for common driver events.
  Future<void> showRideRequest({
    required String riderName,
    String? pickup,
  }) =>
      show(
        title: 'New ride request — $riderName',
        body: pickup != null ? 'Pickup: $pickup' : 'Tap to view details',
        type: NotificationTypeTray.ride,
        payload: 'ride_request',
      );

  Future<void> showKycUpdate(String title, String body) => show(
        title: title,
        body: body,
        type: NotificationTypeTray.kyc,
        payload: 'kyc',
      );

  Future<void> showPayout(String body) => show(
        title: 'Payout update',
        body: body,
        type: NotificationTypeTray.payout,
        payload: 'payout',
      );

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

enum NotificationTypeTray { general, ride, payout, kyc }

extension on NotificationTypeTray {
  AndroidNotificationCategory? get androidCategory {
    switch (this) {
      case NotificationTypeTray.ride:
        return AndroidNotificationCategory.call;
      case NotificationTypeTray.kyc:
      case NotificationTypeTray.payout:
      case NotificationTypeTray.general:
        return null;
    }
  }
}
