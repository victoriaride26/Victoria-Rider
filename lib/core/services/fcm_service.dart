import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../../features/notifications/data/notification_service.dart';
import 'notification_tray_service.dart';
import 'session_controller.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('[FCM] Background message: ${message.messageId}');
}

/// Manages Firebase Cloud Messaging lifecycle for push notifications.
class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  bool _initialized = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  /// Initializes Firebase and registers message handlers.
  Future<void> init() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      _initialized = true;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // Request push notification permissions (iOS & Android 13+)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('[FCM] Notification permissions granted.');
      }

      // Display pushes while the app is in the foreground (iOS) — without
      // this iOS drops foreground messages, so trip-completed / payment
      // pushes never reach the rider until they background the app.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Fetch FCM Device Token
      _fcmToken = await messaging.getToken();
      if (_fcmToken != null) {
        debugPrint('[FCM] Device Token: $_fcmToken');
        unawaited(registerTokenWithBackend(_fcmToken!));
      }

      // Listen for token rotations
      messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        unawaited(registerTokenWithBackend(token));
      });

      // Foreground message listener — curate to RiderNotificationService + tray
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM] Foreground notification: ${message.notification?.title}');
        final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Victoria Rides';
        final body = message.notification?.body ?? message.data['body']?.toString() ?? message.data['message']?.toString() ?? '';
        // Curate to SharedPreferences-backed service so Notifications screen shows history
        final typeStr = (message.data['type']?.toString() ?? '').toLowerCase();
        final notifType = switch (typeStr) {
          'ride' || 'ride_request' => RiderNotificationType.ride,
          'trip_in_progress' || 'trip_started' || 'in_progress' || 'started' => RiderNotificationType.tripInProgress,
          'stopover' || 'stop_over' || 'stop' || 'stop_added' => RiderNotificationType.stopOver,
          'payment' || 'wallet' || 'payout' => RiderNotificationType.payment,
          'payment_successful' || 'payment_success' || 'payment_completed' => RiderNotificationType.paymentSuccessful,
          'trip_ended' || 'trip_completed' || 'completed' || 'ended' => RiderNotificationType.tripEnded,
          'promo' || 'promotion' => RiderNotificationType.promo,
          _ => RiderNotificationType.system,
        };
        RiderNotificationService.instance.insert(
          RiderNotification(
            id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: notifType,
            title: title,
            body: body,
            createdAt: DateTime.now(),
            data: message.data,
          ),
        );
        NotificationTrayService.instance.show(
          title: title,
          body: body,
        );
      });

      // Background tap — also curate
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Victoria Rides';
        final body = message.notification?.body ?? message.data['body']?.toString() ?? '';
        RiderNotificationService.instance.insert(
          RiderNotification(
            id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: RiderNotificationType.system,
            title: title,
            body: body,
            createdAt: DateTime.now(),
            data: message.data,
          ),
        );
      });

      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final title = initialMessage.notification?.title ?? initialMessage.data['title']?.toString() ?? 'Victoria Rides';
        final body = initialMessage.notification?.body ?? initialMessage.data['body']?.toString() ?? '';
        RiderNotificationService.instance.insert(
          RiderNotification(
            id: initialMessage.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: RiderNotificationType.system,
            title: title,
            body: body,
            createdAt: DateTime.now(),
            data: initialMessage.data,
          ),
        );
      }
    } catch (e) {
      debugPrint('[FCM] Firebase initialization skipped: $e');
    }
  }

  /// Sends the device FCM token to the backend.
  Future<void> registerTokenWithBackend(String token) async {
    final authToken = SessionController.instance.accessToken;
    if (authToken == null ||
        authToken.isEmpty ||
        authToken == 'null' ||
        authToken == 'undefined') {
      return;
    }

    try {
      await http.post(
        Uri.parse('${ApiConfig.apiV1}/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'fcmToken': token}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[FCM] Token registered with backend successfully.');
    } catch (e) {
      debugPrint('[FCM] Token backend registration failed: $e');
    }
  }

  /// Synchronizes current FCM token with backend when user signs in.
  Future<void> syncToken() async {
    if (_fcmToken != null) {
      await registerTokenWithBackend(_fcmToken!);
    } else {
      try {
        _fcmToken = await FirebaseMessaging.instance.getToken();
        if (_fcmToken != null) {
          await registerTokenWithBackend(_fcmToken!);
        }
      } catch (_) {}
    }
  }
}
