import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import 'session_controller.dart';

/// Real-time driver GPS coordinate update streamed over WebSockets.
class DriverLocationUpdate {
  const DriverLocationUpdate({
    required this.rideId,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speed,
    this.etaMinutes,
    this.timestamp,
  });

  final String rideId;
  final double latitude;
  final double longitude;
  final double? heading;
  final double? speed;
  final int? etaMinutes;
  final DateTime? timestamp;

  LatLng get latLng => LatLng(latitude, longitude);

  factory DriverLocationUpdate.fromMap(
    Map<String, dynamic> map, {
    String? defaultRideId,
  }) {
    final rideId =
        (map['rideId'] ?? map['id'] ?? defaultRideId ?? '').toString();

    double lat = 0.0;
    double lng = 0.0;

    if (map['latitude'] is num) {
      lat = (map['latitude'] as num).toDouble();
    } else if (map['lat'] is num) {
      lat = (map['lat'] as num).toDouble();
    }

    if (map['longitude'] is num) {
      lng = (map['longitude'] as num).toDouble();
    } else if (map['lng'] is num) {
      lng = (map['lng'] as num).toDouble();
    }

    if (lat == 0.0 && lng == 0.0) {
      final loc = map['location'] ?? map['coords'] ?? map['position'];
      if (loc is Map) {
        lat = (loc['latitude'] ?? loc['lat'] ?? 0.0).toDouble();
        lng = (loc['longitude'] ?? loc['lng'] ?? 0.0).toDouble();
      } else if (map['coordinates'] is List &&
          (map['coordinates'] as List).length >= 2) {
        lng = ((map['coordinates'] as List)[0] as num).toDouble();
        lat = ((map['coordinates'] as List)[1] as num).toDouble();
      }
    }

    final heading = (map['heading'] ?? map['bearing']) is num
        ? ((map['heading'] ?? map['bearing']) as num).toDouble()
        : null;

    final speed =
        map['speed'] is num ? (map['speed'] as num).toDouble() : null;

    final etaMinutes = (map['etaMinutes'] ?? map['eta']) is num
        ? ((map['etaMinutes'] ?? map['eta']) as num).toInt()
        : null;

    return DriverLocationUpdate(
      rideId: rideId,
      latitude: lat,
      longitude: lng,
      heading: heading,
      speed: speed,
      etaMinutes: etaMinutes,
      timestamp: DateTime.now(),
    );
  }
}

/// Manages real-time WebSocket connection for the rider using Socket.IO.
///
/// Handles:
///  - Listening for ride state transitions (`ride:state`, `ride:accepted`, `ride:status:update`)
///  - Subscribing to live ride tracking rooms and streaming driver GPS coordinates
///  - Exchanging in-ride chat messages (`ride:chat:send`, `ride:chat:receive`)
class RiderSocketService {
  RiderSocketService._();

  static final RiderSocketService instance = RiderSocketService._();

  io.Socket? _socket;
  bool _isConnected = false;
  String? _activeTrackingRideId;

  final StreamController<Map<String, dynamic>> _rideAcceptedController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _rideStateController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _statusUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<DriverLocationUpdate> _driverLocationController =
      StreamController<DriverLocationUpdate>.broadcast();

  final StreamController<Map<String, dynamic>> _chatMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _paymentPendingController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;

  /// Stream of ride acceptance / match events when a driver accepts a request.
  Stream<Map<String, dynamic>> get onRideAccepted =>
      _rideAcceptedController.stream;

  /// Stream of all ride state events from the backend (`ride:state`).
  Stream<Map<String, dynamic>> get onRideState => _rideStateController.stream;

  /// Stream of ride status transitions (e.g. ARRIVED, IN_PROGRESS, COMPLETED).
  Stream<Map<String, dynamic>> get onRideStatusUpdated =>
      _statusUpdateController.stream;

  /// Stream of real-time driver GPS coordinate updates from WebSockets.
  Stream<DriverLocationUpdate> get onDriverLocation =>
      _driverLocationController.stream;

  /// Stream of real-time in-ride chat messages from the assigned driver.
  Stream<Map<String, dynamic>> get onChatMessage =>
      _chatMessageController.stream;

  /// Stream of payment pending events (e.g. for card/transfer payment at trip end).
  Stream<Map<String, dynamic>> get onPaymentPending =>
      _paymentPendingController.stream;

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
            .setAuth({
              'token': (token != null && token != 'null' && token != 'undefined')
                  ? token
                  : ''
            })
            .setExtraHeaders({
              if (token != null &&
                  token.isNotEmpty &&
                  token != 'null' &&
                  token != 'undefined')
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
        if (_activeTrackingRideId != null) {
          subscribeToRideTracking(_activeTrackingRideId!);
        }
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
        if (_activeTrackingRideId != null) {
          subscribeToRideTracking(_activeTrackingRideId!);
        }
      });

      _socket!.onError((err) {
        debugPrint('[RiderSocket] Error: $err');
      });

      // ── 1. Backend ride:state (MATCHED, ARRIVED, IN_PROGRESS, etc.) ──
      _socket!.on('ride:state', (data) {
        debugPrint('[RiderSocket] Received ride:state: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _rideStateController.add(map);

          final status = (map['status'] ?? map['state'])?.toString().toUpperCase();
          if (status == 'MATCHED' || status == 'ACCEPTED') {
            _rideAcceptedController.add(map);
          } else if (status != null && status.isNotEmpty) {
            _statusUpdateController.add(map);
          }
        }
      });

      // ── 2. Direct match/acceptance listeners ──
      _socket!.on('ride:matched', (data) {
        debugPrint('[RiderSocket] Received ride:matched: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _rideAcceptedController.add(map);
          _rideStateController.add(map);
        }
      });

      _socket!.on('ride:accepted', (data) {
        debugPrint('[RiderSocket] Received ride:accepted: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _rideAcceptedController.add(map);
          _rideStateController.add(map);
        }
      });

      _socket!.on('ride:payment_pending', (data) {
        debugPrint('[RiderSocket] Received ride:payment_pending: $data');
        if (data is Map) {
          _paymentPendingController.add(Map<String, dynamic>.from(data));
        }
      });

      // ── 3. Ride status updates ──
      _socket!.on('ride:status:update', (data) {
        debugPrint('[RiderSocket] Received ride:status:update: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _statusUpdateController.add(map);
          _rideStateController.add(map);
        }
      });

      _socket!.on('ride:status', (data) {
        debugPrint('[RiderSocket] Received ride:status: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _statusUpdateController.add(map);
          _rideStateController.add(map);
        }
      });

      // ── 3b. Ride termination and completion listeners ──
      void handleTermination(dynamic data, String fallbackStatus) {
        debugPrint('[RiderSocket] Received termination event: $data ($fallbackStatus)');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          if (map['status'] == null && map['state'] == null) {
            map['status'] = fallbackStatus;
          }
          _statusUpdateController.add(map);
          _rideStateController.add(map);
        } else if (data != null) {
          final map = {'rideId': data.toString(), 'status': fallbackStatus};
          _statusUpdateController.add(map);
          _rideStateController.add(map);
        }
      }

      _socket!.on('ride:completed', (data) => handleTermination(data, 'COMPLETED'));
      _socket!.on('ride:complete', (data) => handleTermination(data, 'COMPLETED'));
      _socket!.on('ride:terminated', (data) => handleTermination(data, 'TERMINATED'));
      _socket!.on('ride:terminate', (data) => handleTermination(data, 'TERMINATED'));
      _socket!.on('ride:cancelled', (data) => handleTermination(data, 'CANCELLED'));
      _socket!.on('ride:canceled', (data) => handleTermination(data, 'CANCELLED'));
      _socket!.on('ride:ended', (data) => handleTermination(data, 'COMPLETED'));
      _socket!.on('ride:end', (data) => handleTermination(data, 'COMPLETED'));

      // ── 4. Driver GPS coordinate streaming ──
      void handleLocationUpdate(dynamic data) {
        if (data is Map) {
          final update = DriverLocationUpdate.fromMap(
            Map<String, dynamic>.from(data),
            defaultRideId: _activeTrackingRideId,
          );
          if (update.latitude != 0.0 && update.longitude != 0.0) {
            debugPrint(
              '[RiderSocket] Driver location streamed: '
              'lat=${update.latitude}, lng=${update.longitude}, '
              'bearing=${update.heading}, eta=${update.etaMinutes}m',
            );
            _driverLocationController.add(update);
          }
        }
      }

      _socket!.on('driver:location', handleLocationUpdate);
      _socket!.on('ride:driver:location', handleLocationUpdate);
      _socket!.on('driver:position', handleLocationUpdate);
      _socket!.on('location:update', handleLocationUpdate);
      _socket!.on('ride:location', handleLocationUpdate);
      _socket!.on('ride:tracking', handleLocationUpdate);

      // ── 5. In-ride chat messages ──
      void handleChatMessage(dynamic data) {
        debugPrint('[RiderSocket] Received chat message: $data');
        if (data is Map) {
          _chatMessageController.add(Map<String, dynamic>.from(data));
        }
      }

      _socket!.on('ride:chat:receive', handleChatMessage);
      _socket!.on('ride:chat:message', handleChatMessage);
      _socket!.on('chat:message', handleChatMessage);
      _socket!.on('ride:message', handleChatMessage);

      _socket!.connect();
    } catch (e) {
      debugPrint('[RiderSocket] Exception initializing socket: $e');
    }
  }

  /// Subscribes the rider app to the ride's live tracking room.
  /// The backend continuously streams the driver's GPS coordinates to this room.
  void subscribeToRideTracking(String rideId) {
    _activeTrackingRideId = rideId;
    if (_socket == null || !_isConnected) {
      connect();
      return;
    }

    debugPrint('[RiderSocket] Subscribing to live tracking room for ride: $rideId');
    _socket!.emit('ride:join', {'rideId': rideId});
    _socket!.emit('ride:track', {'rideId': rideId});
    _socket!.emit('track:ride', {'rideId': rideId});
    _socket!.emit('subscribe:tracking', {'rideId': rideId});
  }

  /// Alias for [subscribeToRideTracking]. Joins room for ride updates and chat.
  void joinRideRoom(String rideId) => subscribeToRideTracking(rideId);

  /// Leaves the tracking room when ride completes or is cancelled.
  void leaveRideRoom(String rideId) {
    if (_activeTrackingRideId == rideId) {
      _activeTrackingRideId = null;
    }
    if (_socket != null && _isConnected) {
      _socket!.emit('ride:leave', {'rideId': rideId});
    }
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
      'text': message,
      'sender': sender,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    debugPrint('[RiderSocket] Emitting ride:chat:send: $payload');
    _socket!.emit('ride:chat:send', payload);
    _socket!.emit('chat:send', payload);
  }

  /// Disconnects and cleans up socket resources.
  void disconnect() {
    _activeTrackingRideId = null;
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
