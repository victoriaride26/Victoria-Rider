import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/notification_tray_service.dart';

/// Rider-facing notification (ride updates, promos, wallet, system).
class RiderNotification {
  RiderNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.data,
  });

  final String id;
  final RiderNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  bool read;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
        if (data != null) 'data': data,
        'v': 1,
      };

  factory RiderNotification.fromJson(Map<String, dynamic> json) {
    final typeName = (json['type'] ?? 'system').toString();
    final type = RiderNotificationType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => RiderNotificationType.system,
    );
    return RiderNotification(
      id: (json['id'] ?? '').toString(),
      type: type,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      read: json['read'] == true,
      data: json['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['data'] as Map)
          : (json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : null),
    );
  }
}

enum RiderNotificationType {
  ride,
  tripInProgress,
  stopOver,
  payment,
  paymentSuccessful,
  tripEnded,
  promo,
  system,
}

/// Curated rider notification store — persists to SharedPreferences.
///
/// All rider alerts (FCM, ride state, wallet, promos) are inserted via
/// `insert()` and curated to `vr_rider_notifications`. The Notifications
/// screen reads from this store, so history survives restarts. Designed to
/// map to a future `GET /notifications` backend.
class RiderNotificationService extends ChangeNotifier {
  RiderNotificationService._() {
    _loadFromPrefs();
  }

  static final RiderNotificationService instance = RiderNotificationService._();

  static const _prefsKey = 'vr_rider_notifications';
  bool _initialized = false;
  final List<RiderNotification> _items = [];

  Future<void> init() => _loadFromPrefs();

  Future<void> _loadFromPrefs() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              try {
                _items.add(RiderNotification.fromJson(item));
              } catch (_) {}
            } else if (item is Map) {
              try {
                _items.add(RiderNotification.fromJson(Map<String, dynamic>.from(item)));
              } catch (_) {}
            }
          }
          if (_items.length > 100) {
            _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            _items.removeRange(100, _items.length);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RiderNotificationService load error: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (toSave.length > 100) toSave.removeRange(100, toSave.length);
      final encoded = jsonEncode(toSave.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, encoded);
    } catch (e) {
      if (kDebugMode) debugPrint('RiderNotificationService persist error: $e');
    }
  }

  List<RiderNotification> get items => List.unmodifiable(_items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  int get unreadCount => _items.where((n) => !n.read).length;

  void markRead(String id) {
    final match = _items.where((n) => n.id == id).toList();
    if (match.isEmpty || match.first.read) return;
    match.first.read = true;
    notifyListeners();
    _persist();
  }

  void markAllRead() {
    if (_items.every((n) => n.read)) return;
    for (final n in _items) {
      n.read = true;
    }
    notifyListeners();
    _persist();
  }

  void insert(RiderNotification notification) {
    if (_items.any((n) => n.id == notification.id)) return;
    
    _items.add(notification);
    if (_items.length > 100) {
      _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _items.removeRange(100, _items.length);
    }
    notifyListeners();
    _persist();
    NotificationTrayService.instance.show(
      title: notification.title,
      body: notification.body,
      payload: notification.id,
      type: switch (notification.type) {
        RiderNotificationType.ride => NotificationTypeTray.ride,
        RiderNotificationType.tripInProgress => NotificationTypeTray.ride,
        RiderNotificationType.stopOver => NotificationTypeTray.ride,
        RiderNotificationType.tripEnded => NotificationTypeTray.ride,
        RiderNotificationType.payment => NotificationTypeTray.payout,
        RiderNotificationType.paymentSuccessful => NotificationTypeTray.payout,
        RiderNotificationType.promo => NotificationTypeTray.general,
        RiderNotificationType.system => NotificationTypeTray.general,
      },
    );
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _persist();
  }
}
