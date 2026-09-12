import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import 'session_controller.dart';

/// Manages real-time WebSocket connection for the rider using Socket.IO.
///
/// Handles:
///  - Listening for ride acceptance (`ride:accepted`)
///  - Listening for ride status updates (`ride:status:update`)
///  - Exchanging in-ride chat messages (`ride:chat:send`, `ride:chat:receive`)
class RiderSocketService {
  RiderSocketService._();

  static final RiderSocketService instance = RiderSocketService._();

  io.Socket? _socket;
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _rideAcceptedController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _statusUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _chatMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;

  /// Stream of ride acceptance events when a driver accepts a request.
  Stream<Map<String, dynamic>> get onRideAccepted =>
      _rideAcceptedController.stream;

  /// Stream of ride status transitions (e.g. arrived, started, completed).
  Stream<Map<String, dynamic>> get onRideStatusUpdated =>
      _statusUpdateController.stream;

  /// Stream of real-time in-ride chat messages from the assigned driver.
  Stream<Map<String, dynamic>> get onChatMessage =>
      _chatMessageController.stream;

  /// Connects to the backend Socket.IO server with the rider's JWT token.
  void connect() {
    if (_socket != null && _isConnected) return;

    final token = SessionController.instance.accessToken;
    debugPrint('[RiderSocket] Connecting to ${ApiConfig.baseUrl}...');

    try {
      _socket = io.io(
        ApiConfig.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setAuth({'token': token ?? ''})
            .setExtraHeaders({
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            })
            .enableReconnection()
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(10000)
            .setReconnectionAttempts(10)
            .enableForceNew()
            .build(),
      );

      _socket!.onConnect((_) {
        _isConnected = true;
        debugPrint('[RiderSocket] Connected. Socket ID: ${_socket?.id}');
      });

      _socket!.onDisconnect((reason) {
        _isConnected = false;
        debugPrint('[RiderSocket] Disconnected: $reason');
      });

      _socket!.onConnectError((err) {
        debugPrint('[RiderSocket] Connection error: $err');
      });

      _socket!.onReconnect((attempt) {
        debugPrint('[RiderSocket] Reconnected after $attempt attempt(s)');
      });

      _socket!.onError((err) {
        debugPrint('[RiderSocket] Error: $err');
      });

      // Listen for driver acceptance
      _socket!.on('ride:accepted', (data) {
        debugPrint('[RiderSocket] Received ride:accepted: $data');
        if (data is Map) {
          _rideAcceptedController.add(Map<String, dynamic>.from(data));
        }
      });

      // Listen for ride status updates
      _socket!.on('ride:status:update', (data) {
        debugPrint('[RiderSocket] Received ride:status:update: $data');
        if (data is Map) {
          _statusUpdateController.add(Map<String, dynamic>.from(data));
        }
      });

      // Listen for in-ride chat messages
      _socket!.on('ride:chat:receive', (data) {
        debugPrint('[RiderSocket] Received ride:chat:receive: $data');
        if (data is Map) {
          _chatMessageController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.connect();
    } catch (e) {
      debugPrint('[RiderSocket] Exception initializing socket: $e');
    }
  }

  /// Joins a specific ride room (e.g. `ride:{rideId}`) to receive targeted updates and chat.
  void joinRideRoom(String rideId) {
    if (_socket == null || !_isConnected) return;
    debugPrint('[RiderSocket] Joining room ride:$rideId');
    _socket!.emit('ride:join', {'rideId': rideId});
  }

  /// Sends an in-ride chat message to the driver.
  void sendChatMessage({
    required String rideId,
    required String message,
    String sender = 'rider',
  }) {
    if (_socket == null || !_isConnected) {
      debugPrint('[RiderSocket] Cannot send message — socket not connected.');
      return;
    }

    final payload = {
      'rideId': rideId,
      'message': message,
      'sender': sender,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    debugPrint('[RiderSocket] Emitting ride:chat:send: $payload');
    _socket!.emit('ride:chat:send', payload);
  }

  /// Disconnects and cleans up socket resources.
  void disconnect() {
    try {
      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
        _socket = null;
      }
    } catch (e) {
      debugPrint('[RiderSocket] Error on disconnect: $e');
    }
    _isConnected = false;
    debugPrint('[RiderSocket] Disconnected.');
  }
}
