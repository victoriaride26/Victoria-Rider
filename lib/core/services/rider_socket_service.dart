import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../network/api_client.dart';
import '../utils/fare_parser.dart';
import '../../features/notifications/data/notification_service.dart';
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

  /// Typing indicator events (`ride:typing` / `chat:typing`).
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _paymentPendingController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Backend emits updated fare after rider POST /rides/{id}/early-dropoff.
  /// Payload: { rideId, newFare, estimatedFare, latitude, longitude, reason, … }
  final StreamController<Map<String, dynamic>> _earlyDropoffFareController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Backend/driver acknowledges a mid-trip stop addition.
  final StreamController<Map<String, dynamic>> _stopAddedController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stopover wait timer events (confirmation_requested, confirmed, timer:start, timer:completed)
  final StreamController<Map<String, dynamic>> _stopoverTimerController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _fareUpdatedController =
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

  /// Stream of typing indicators for the active ride room.
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  /// Ride the app is currently tracking/joined to — used as the conversation
  /// key when a chat payload omits its `rideId`.
  String? get activeTrackingRideId => _activeTrackingRideId;

  /// Pushes a chat payload through the same stream as a real
  /// `ride:chat:receive` event, so tests can drive the chat pipeline
  /// without a server.
  @visibleForTesting
  void debugDispatchChatMessage(Map<String, dynamic> data) =>
      _chatMessageController.add(data);

  /// Pushes a typing payload through the same stream as a real
  /// `ride:typing` event.
  @visibleForTesting
  void debugDispatchTyping(Map<String, dynamic> data) =>
      _typingController.add(data);

  /// Stream of payment pending events (e.g. for card/transfer payment at trip end).
  Stream<Map<String, dynamic>> get onPaymentPending =>
      _paymentPendingController.stream;

  /// Stream of early drop-off fare recalculation events.
  /// Backend emits this after `POST /rides/{id}/early-dropoff` with the new fare.
  /// Rider should display fare and confirm via `POST /rides/{id}/early-dropoff/confirm`.
  Stream<Map<String, dynamic>> get onEarlyDropoffFareUpdate =>
      _earlyDropoffFareController.stream;

  /// Stream of stop-added acknowledgements from backend or driver.
  Stream<Map<String, dynamic>> get onStopAdded => _stopAddedController.stream;

  /// Stream of stopover wait timer events (confirmation_requested, confirmed, timer:start/completed)
  Stream<Map<String, dynamic>> get onStopoverTimer => _stopoverTimerController.stream;

  /// Stream of dedicated fare update events (ride:fare:updated)
  Stream<Map<String, dynamic>> get onFareUpdated => _fareUpdatedController.stream;

  /// Local notification for a finished trip.
  ///
  /// The backend broadcasts the same fact under several names
  /// (`ride:state {status: COMPLETED}`, `ride:completed`, `ride:ended`, …), so
  /// the notification id is derived from the ride: the tray posts exactly one
  /// "Trip Completed" per trip no matter how many of those fire.
  void _notifyTripCompleted(Map<String, dynamic> data) {
    final rideId = _rideIdOf(data);
    RiderNotificationService.instance.insert(
      RiderNotification(
        id: rideId.isEmpty
            ? 'trip_completed_${DateTime.now().millisecondsSinceEpoch}'
            : 'trip_completed_$rideId',
        type: RiderNotificationType.tripEnded,
        title: 'Trip Completed',
        body: 'Your ride has successfully completed.',
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Local notification for a verified payment.
  ///
  /// The canonical backend event is `payment:completed`
  /// `{ rideId, amountPaid, message }` — the exact event the driver app
  /// listens to. The rider used to listen only for `ride:payment_successful`,
  /// which nothing emits, so this notification never appeared.
  void _notifyPaymentSuccessful(dynamic data) {
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    final amount = FareParser.scalarNgn(map['amountPaid'] ?? map['amount']);
    final rideId = _rideIdOf(map);
    RiderNotificationService.instance.insert(
      RiderNotification(
        id: rideId.isEmpty
            ? 'payment_successful_${DateTime.now().millisecondsSinceEpoch}'
            : 'payment_successful_$rideId',
        type: RiderNotificationType.paymentSuccessful,
        title: 'Payment Successful',
        body: (amount != null && amount > 0)
            ? 'Payment of ₦${amount.toStringAsFixed(0)} was verified for your trip.'
            : 'Your payment was verified successfully.',
        createdAt: DateTime.now(),
      ),
    );
  }

  String _rideIdOf(Map<String, dynamic> data) {
    final ride = data['ride'];
    final id = data['rideId'] ??
        data['ride_id'] ??
        data['id'] ??
        (ride is Map ? (ride['id'] ?? ride['rideId']) : null);
    return (id ?? '').toString();
  }

  static bool _isCompletedStatus(dynamic status) {
    final value = (status ?? '').toString().toUpperCase();
    return value == 'COMPLETED' ||
        value == 'COMPLETE' ||
        value == 'ENDED' ||
        value == 'END';
  }

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
          // Canonical completion broadcast — must raise the tray notification.
          if (_isCompletedStatus(status)) _notifyTripCompleted(map);
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
      
      _socket!.on('ride:payment_successful', (data) {
        debugPrint('[RiderSocket] Received ride:payment_successful: $data');
        _notifyPaymentSuccessful(data);
      });

      // ── Canonical payment-verified events (same names the driver app
      //    listens to) ── without these the rider never got the tray entry. ──
      for (final event in const [
        'payment:completed',
        'payment:verified',
        'payment:success',
      ]) {
        _socket!.on(event, (data) {
          debugPrint('[RiderSocket] Received $event: $data');
          _notifyPaymentSuccessful(data);
        });
      }

      // ── 3. Ride status updates ──
      _socket!.on('ride:status:update', (data) {
        debugPrint('[RiderSocket] Received ride:status:update: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _statusUpdateController.add(map);
          _rideStateController.add(map);
          if (_isCompletedStatus(map['status'] ?? map['state'])) {
            _notifyTripCompleted(map);
          }
        }
      });

      _socket!.on('ride:state', (data) {
        debugPrint('[RiderSocket] Received ride:state: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _statusUpdateController.add(map);
          _rideStateController.add(map);
          if (_isCompletedStatus(map['status'] ?? map['state'])) {
            _notifyTripCompleted(map);
          }
        }
      });

      _socket!.on('ride:status', (data) {
        debugPrint('[RiderSocket] Received ride:status: $data');
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          _statusUpdateController.add(map);
          _rideStateController.add(map);
          if (_isCompletedStatus(map['status'] ?? map['state'])) {
            _notifyTripCompleted(map);
          }
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
          if (fallbackStatus == 'COMPLETED') {
            _notifyTripCompleted(map);
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

      // ── 3c. Early drop-off fare recalculation (backend → rider after POST /early-dropoff) ──
      void handleEarlyDropoffFare(dynamic data) {
        debugPrint('[RiderSocket] Received early-dropoff fare update: $data');
        if (data is Map) {
          _earlyDropoffFareController.add(Map<String, dynamic>.from(data));
        }
      }

      // Backend may emit any of these after recalculating the fare
      _socket!.on('ride:early_dropoff:requested', handleEarlyDropoffFare);
      _socket!.on('ride:early_dropoff:fare', handleEarlyDropoffFare);
      _socket!.on('ride:earlyDropoff:requested', handleEarlyDropoffFare);
      _socket!.on('ride:earlyDropoff', handleEarlyDropoffFare);

      // ── 3d. Stopover wait timer (confirmation_requested, confirmed, timer:start/completed) ──
      void handleStopoverTimer(dynamic data, String type) {
        debugPrint('[RiderSocket] Received stopover timer event: $data ($type)');
        if (data is Map) {
          final m = Map<String, dynamic>.from(data);
          m['type'] ??= type;
          _stopoverTimerController.add(m);
        } else if (data != null) {
          _stopoverTimerController.add({'data': data, 'type': type});
        }
      }

      _socket!.on('ride:stopover:confirmation_requested', (data) => handleStopoverTimer(data, 'confirmation_requested'));
      _socket!.on('ride:stopover:confirmed', (data) {
        handleStopoverTimer(data, 'confirmed');
        RiderNotificationService.instance.insert(RiderNotification(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: RiderNotificationType.stopOver,
          title: 'Stopover Arrived',
          body: 'You have arrived at the stopover.',
          createdAt: DateTime.now(),
        ));
      });
      _socket!.on('ride:stopover:timer:start', (data) => handleStopoverTimer(data, 'timer:start'));
      _socket!.on('ride:stopover:timer:completed', (data) => handleStopoverTimer(data, 'timer:completed'));
      _socket!.on('ride:stopover:completed', (data) => handleStopoverTimer(data, 'timer:completed'));

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
      _socket!.on('driver:location:update', handleLocationUpdate);
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
      _socket!.on('chat:receive', handleChatMessage);
      _socket!.on('ride:message', handleChatMessage);
      // Some builds relay the sender's own event name into the room.
      _socket!.on('ride:chat:send', handleChatMessage);
      _socket!.on('chat:send', handleChatMessage);

      // ── 5b. Typing indicator from the driver ──
      void handleTyping(dynamic data) {
        if (data is Map) {
          _typingController.add(Map<String, dynamic>.from(data));
        }
      }

      _socket!.on('ride:typing', handleTyping);
      _socket!.on('chat:typing', handleTyping);
      _socket!.on('ride:chat:typing', handleTyping);

      // ── 6. Fare Updates ──
      _socket!.on('ride:fare:updated', (data) {
        debugPrint('[RiderSocket] Received ride:fare:updated: $data');
        if (data is Map) {
          _fareUpdatedController.add(Map<String, dynamic>.from(data));
        }
      });

      _socket!.connect();
    } catch (e) {
      debugPrint('[RiderSocket] Exception initializing socket: $e');
    }
  }

  Timer? _riderEmitTimer;
  StreamSubscription<Position>? _riderPositionSub;
  Position? _lastRiderPosition;

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
    _startRiderLocationEmission();
  }

  /// Streams the rider's own GPS position to the active ride room, mirroring
  /// the driver's `driver:location:update` pattern: every ~5 m of movement
  /// plus a 5 s heartbeat that re-sends the last fix.
  void _startRiderLocationEmission() {
    _riderEmitTimer?.cancel();
    _riderPositionSub?.cancel();
    try {
      _riderPositionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (pos) {
          _lastRiderPosition = pos;
          _emitRiderLocation(pos);
        },
        onError: (_) {},
      );
    } catch (_) {
      // Geolocation unavailable (tests / restricted env) — the heartbeat
      // below still re-emits any last known fix.
    }
    _riderEmitTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final pos = _lastRiderPosition;
      if (pos != null) _emitRiderLocation(pos);
    });
  }

  void _stopRiderLocationEmission() {
    _riderEmitTimer?.cancel();
    _riderEmitTimer = null;
    _riderPositionSub?.cancel();
    _riderPositionSub = null;
    _lastRiderPosition = null;
  }

  void _emitRiderLocation(Position pos) {
    final socket = _socket;
    final rideId = _activeTrackingRideId;
    if (socket == null || !_isConnected || rideId == null || rideId.isEmpty) {
      return;
    }
    socket.emit('rider:location:update', {
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracy': pos.accuracy,
      'heading': pos.heading,
      'speed': pos.speed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'rideId': rideId,
    });
  }

  /// Alias for [subscribeToRideTracking]. Joins room for ride updates and chat.
  void joinRideRoom(String rideId) => subscribeToRideTracking(rideId);

  /// Leaves the tracking room when ride completes or is cancelled.
  void leaveRideRoom(String rideId) {
    if (_activeTrackingRideId == rideId) {
      _activeTrackingRideId = null;
      _stopRiderLocationEmission();
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

    try {
      ApiClient.instance.post(ApiConfig.rideChat(rideId), body: {
        'message': message,
        'sender': sender,
      }).catchError((e) => debugPrint('[RiderSocket] HTTP fallback failed: $e'));
    } catch (_) {}
  }

  /// Broadcasts a typing indicator for the active ride room.
  /// `typing: false` is sent when the rider clears the composer or sends.
  void emitTyping({
    required String rideId,
    required bool typing,
    String sender = 'rider',
  }) {
    if (_socket == null || !_isConnected || rideId.isEmpty) return;
    final payload = {
      'rideId': rideId,
      'sender': sender,
      'typing': typing,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _socket!.emit('ride:typing', payload);
    _socket!.emit('chat:typing', payload);
  }

  /// Disconnects and cleans up socket resources.
  void disconnect() {
    _activeTrackingRideId = null;
    _stopRiderLocationEmission();
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
