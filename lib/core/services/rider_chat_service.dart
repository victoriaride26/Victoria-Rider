import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rider_socket_service.dart';

/// A single chat bubble. Scoped to the ride it belongs to so switching rides
/// never mixes threads.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.time,
    this.rideId = '',
    this.read = false,
  });

  final String id;
  final String text;
  final bool isMe;
  final DateTime time;

  /// Ride this message belongs to ('' when the backend omitted it).
  final String rideId;

  /// False for incoming messages that have not been opened yet — drives the
  /// unread badge on the chat icons.
  bool read;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isMe': isMe,
        'time': time.toIso8601String(),
        'rideId': rideId,
        'read': read,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        isMe: json['isMe'] == true,
        time: DateTime.tryParse(json['time']?.toString() ?? '') ??
            DateTime.now(),
        rideId: (json['rideId'] ?? '').toString(),
        read: json['read'] == true,
      );
}

/// Rider-side chat store: sends over Socket.IO, receives the normalised
/// payload, keeps a per-ride unread count and persists everything to
/// SharedPreferences so threads survive navigation and app restarts.
class RiderChatService extends ChangeNotifier {
  RiderChatService._() {
    _loadFuture ??= _hydrate();
    _chatSub = RiderSocketService.instance.onChatMessage.listen(handleIncoming);
    _typingSub = RiderSocketService.instance.onTyping.listen(handleTyping);
  }

  static final RiderChatService instance = RiderChatService._();

  static const _prefsKey = 'vr_rider_chat_messages';
  static const int _maxStored = 400;
  static const Duration _typingEmitInterval = Duration(seconds: 2);
  static const Duration _peerTypingTimeout = Duration(seconds: 4);

  final List<ChatMessage> _messages = [];
  final Map<String, bool> _peerTyping = {};
  final Map<String, Timer> _peerTypingTimers = {};
  final Map<String, DateTime> _lastTypingEmit = {};

  /// Ride whose chat sheet is currently open (incoming ones land as read).
  String? _openRideId;

  StreamSubscription<Map<String, dynamic>>? _chatSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  Future<void>? _loadFuture;

  /// Eagerly starts the service (hydration + socket subscription) so a
  /// message arriving before any chat screen opens is never dropped.
  Future<void> ensureStarted() => _loadFuture ??= _hydrate();

  /// Drops the in-memory cache and re-reads the persisted threads — used by
  /// tests to simulate an app restart.
  @visibleForTesting
  Future<void> reloadFromPrefs() {
    _messages.clear();
    _loadFuture = null;
    return _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() => _loadFuture ??= _hydrate();

  // ── reads ─────────────────────────────────────────────────────────

  /// Messages of one ride, oldest first.
  List<ChatMessage> messagesFor(String? rideId) {
    final id = _normalizeRideId(rideId);
    final list = _messages
        .where((m) => m.rideId == id || (id.isNotEmpty && m.rideId.isEmpty))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  /// Unread incoming count for a ride (all rides when [rideId] is empty).
  int unreadFor(String? rideId) {
    final id = _normalizeRideId(rideId);
    return _messages
        .where((m) =>
            !m.isMe &&
            !m.read &&
            (id.isEmpty || m.rideId == id || m.rideId.isEmpty))
        .length;
  }

  /// Total unread across every ride — used by generic message badges.
  int get totalUnread => unreadFor(null);

  bool isPeerTyping(String? rideId) =>
      _peerTyping[_normalizeRideId(rideId)] ?? false;

  static String _normalizeRideId(String? rideId) {
    final value = (rideId ?? '').trim();
    return value;
  }

  // ── writes ────────────────────────────────────────────────────────

  /// Opens a thread: subsequent messages for it land as read while the sheet
  /// is visible, and the badge is cleared.
  void openChat(String? rideId) {
    _openRideId = _normalizeRideId(rideId);
    markRead(_openRideId);
  }

  void closeChat() {
    stopTyping(_openRideId);
    _openRideId = null;
  }

  void markRead(String? rideId) {
    final id = _normalizeRideId(rideId);
    var changed = false;
    for (final m in _messages) {
      if (m.isMe || m.read) continue;
      if (id.isEmpty || m.rideId == id || m.rideId.isEmpty) {
        m.read = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _persist();
    }
  }

  void sendMessage(String? rideId, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final id = _normalizeRideId(rideId);
    _messages.add(ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      text: trimmed,
      isMe: true,
      time: DateTime.now(),
      rideId: id,
      read: true,
    ));
    _trim();
    stopTyping(rideId);
    notifyListeners();
    _persist();
    RiderSocketService.instance.sendChatMessage(
      rideId: id,
      message: trimmed,
      sender: 'rider',
    );
  }

  /// Merges history fetched from the backend — deduped by id or by
  /// (ride, text, time) so reopening a sheet never doubles the thread.
  void addHistory(String? rideId, List<ChatMessage> history) {
    final id = _normalizeRideId(rideId);
    var changed = false;
    for (final incoming in history) {
      final withRide = incoming.rideId.isEmpty
          ? ChatMessage(
              id: incoming.id,
              text: incoming.text,
              isMe: incoming.isMe,
              time: incoming.time,
              rideId: id,
              read: incoming.read,
            )
          : incoming;
      final duplicate = _messages.any((m) =>
          (withRide.id.isNotEmpty && m.id == withRide.id) ||
          (m.rideId == withRide.rideId &&
              m.text == withRide.text &&
              m.isMe == withRide.isMe &&
              m.time.difference(withRide.time).inSeconds.abs() < 5));
      if (duplicate) continue;
      _messages.add(withRide);
      changed = true;
    }
    if (changed) {
      _trim();
      _messages.sort((a, b) => a.time.compareTo(b.time));
      notifyListeners();
      _persist();
    }
  }

  // ── socket ingest ─────────────────────────────────────────────────

  /// Normalises a raw `ride:chat:receive`-style payload and stores it.
  /// Handles every key spelling the backend may use and de-duplicates the
  /// same event arriving under several aliases.
  void handleIncoming(dynamic payload) {
    if (payload is! Map) return;
    final text = _textOf(payload);
    if (text.isEmpty) return;

    final sender = _senderOf(payload);
    if (sender == 'rider') return; // our own echo

    final rideId = _rideIdOf(payload);
    final messageId = _idOf(payload);
    final at = _timeOf(payload);

    if (messageId != null &&
        messageId.isNotEmpty &&
        _messages.any((m) => m.id == messageId)) {
      return;
    }
    // Echo of something we just sent — the relay may arrive without a sender.
    if (_messages.any((m) =>
        m.isMe &&
        m.text == text &&
        DateTime.now().difference(m.time).inSeconds < 10)) {
      return;
    }
    // The same text from the driver within 2s → duplicate alias delivery.
    // Only used when the payload carried no id to compare against (distinct
    // ids always mean distinct messages).
    if (messageId == null &&
        _messages.any((m) =>
            !m.isMe &&
            m.rideId == rideId &&
            m.text == text &&
            at.difference(m.time).inSeconds.abs() < 2)) {
      return;
    }

    _messages.add(ChatMessage(
      id: (messageId != null && messageId.isNotEmpty)
          ? messageId
          : 'remote-${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      isMe: false,
      time: at,
      rideId: rideId,
      read: _openRideId == rideId && rideId.isNotEmpty,
    ));
    _trim();
    notifyListeners();
    _persist();
  }

  static String _textOf(Map payload) {
    final raw = payload['message'] ?? payload['text'] ?? payload['body'] ?? '';
    return raw.toString().trim();
  }

  static String _senderOf(Map payload) {
    final raw = payload['sender'] ??
        payload['senderType'] ??
        payload['role'] ??
        payload['from'] ??
        '';
    return raw.toString().trim().toLowerCase();
  }

  static String? _idOf(Map payload) {
    final raw = payload['id'] ?? payload['_id'] ?? payload['messageId'];
    final value = raw?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String _rideIdOf(Map payload) {
    final ride = payload['ride'];
    final rideId = payload['rideId'] ??
        payload['ride_id'] ??
        payload['rideID'] ??
        (ride is Map ? (ride['rideId'] ?? ride['id']) : null);
    if (rideId != null && rideId.toString().isNotEmpty) {
      return rideId.toString();
    }
    final partner = payload['partnerId'];
    if (partner != null && partner.toString().isNotEmpty) {
      return partner.toString();
    }
    return _openRideId ??
        RiderSocketService.instance.activeTrackingRideId ??
        '';
  }

  static DateTime _timeOf(Map payload) {
    final raw = payload['timestamp'] ?? payload['createdAt'] ?? payload['time'];
    if (raw is num) {
      // seconds vs milliseconds
      final value = raw.toInt();
      return value > 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(value)
          : DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }

  // ── typing indicator ──────────────────────────────────────────────

  void handleTyping(dynamic payload) {
    if (payload is! Map) return;
    if (_senderOf(payload) == 'rider') return;
    final rideId = _rideIdOf(payload);
    if (rideId.isEmpty) return;
    final raw = payload['typing'] ?? payload['isTyping'];
    final typing = raw == true || raw?.toString() == 'true';

    _peerTypingTimers[rideId]?.cancel();
    if (typing) {
      _peerTyping[rideId] = true;
      _peerTypingTimers[rideId] = Timer(_peerTypingTimeout, () {
        if (_peerTyping[rideId] != true) return;
        _peerTyping[rideId] = false;
        notifyListeners();
      });
    } else {
      _peerTyping[rideId] = false;
    }
    notifyListeners();
  }

  /// Called while the rider types — throttled to one socket event per
  /// [_typingEmitInterval].
  void noteTyping(String? rideId) {
    final id = _normalizeRideId(rideId);
    if (id.isEmpty) return;
    final now = DateTime.now();
    final last = _lastTypingEmit[id];
    if (last != null && now.difference(last) < _typingEmitInterval) return;
    _lastTypingEmit[id] = now;
    RiderSocketService.instance.emitTyping(rideId: id, typing: true);
  }

  void stopTyping(String? rideId) {
    final id = _normalizeRideId(rideId);
    if (id.isEmpty) return;
    _lastTypingEmit.remove(id);
    RiderSocketService.instance.emitTyping(rideId: id, typing: false);
  }

  // ── persistence ───────────────────────────────────────────────────

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            try {
              if (item is Map<String, dynamic>) {
                _messages.add(ChatMessage.fromJson(item));
              } else if (item is Map) {
                _messages.add(
                    ChatMessage.fromJson(Map<String, dynamic>.from(item)));
              }
            } catch (_) {}
          }
          _trim();
          _messages.sort((a, b) => a.time.compareTo(b.time));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RiderChatService load error: $e');
      // Let a later ensureStarted() retry instead of staying failed for the
      // session (saved threads would otherwise never hydrate).
      _loadFuture = null;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _messages.toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      if (toSave.length > _maxStored) {
        toSave.removeRange(0, toSave.length - _maxStored);
      }
      await prefs.setString(
          _prefsKey, jsonEncode(toSave.map((m) => m.toJson()).toList()));
    } catch (e) {
      if (kDebugMode) debugPrint('RiderChatService persist error: $e');
    }
  }

  void _trim() {
    if (_messages.length <= _maxStored) return;
    _messages.sort((a, b) => a.time.compareTo(b.time));
    _messages.removeRange(0, _messages.length - _maxStored);
  }

  void disposeService() {
    _chatSub?.cancel();
    _typingSub?.cancel();
    for (final timer in _peerTypingTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
