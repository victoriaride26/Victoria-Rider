import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/directions_service.dart';

/// Summary returned after resolving the route between two points.
class RideEstimate {
  const RideEstimate({
    required this.pickupLabel,
    required this.destinationLabel,
    required this.pickupLatLng,
    required this.destinationLatLng,
    required this.distanceKm,
    required this.durationMinutes,
    required this.fareNgn,
  });

  final String pickupLabel;
  final String destinationLabel;
  final LatLng pickupLatLng;
  final LatLng destinationLatLng;
  final double distanceKm;
  final int durationMinutes;

  /// Estimated fare in Naira.
  final double fareNgn;

  /// Formatted fare string, e.g. "₦1,500".
  String get formattedFare =>
      '₦${fareNgn.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
}

/// Handles the rider-side ride request lifecycle:
///  1. [estimate] - call POST /api/v1/rides/estimate; falls back to local
///     Directions API / straight-line if the backend call fails.
///  2. [requestRide] - POST /api/v1/rides/request to create the ride.
///
/// All network calls go through [ApiClient.instance] so that:
///  - The correct Authorization: Bearer token header is always attached.
///  - Expired tokens are transparently refreshed before retrying (one rotation).
///  - Transport errors and non-2xx responses are surfaced as [ApiException].
class RideRequestService {
  RideRequestService({DirectionsService? directions})
    : _directions = directions ?? DirectionsService();

  final DirectionsService _directions;

  void dispose() {
    _directions.dispose();
  }

  // Local fare constants removed (backend only now)

  // Enum normalisers

  /// Maps any vehicle-type string to the backend enum: STANDARD, PREMIUM, BIKE.
  static String normalizeVehicleType(String vehicleType) =>
      switch (vehicleType.toLowerCase()) {
        'premium' || 'comfort' => 'PREMIUM',
        'bike' => 'BIKE',
        _ => 'STANDARD',
      };

  /// Maps any payment-method string to the backend enum: CASH, CARD, TRANSFER, WALLET.
  static String normalizePaymentMethod(String method) =>
      switch (method.toLowerCase()) {
        'card' => 'CARD',
        'transfer' => 'TRANSFER',
        'wallet' => 'WALLET',
        _ => 'CASH',
      };

  // estimate

  /// Fetches a [RideEstimate] for the given pickup to destination pair strictly
  /// from the backend calculation (POST /api/v1/rides/estimate).
  ///
  /// If the backend calculation cannot be obtained or fails, it ABORTS with an exception.
  /// Does NOT fall back to client-side formula or hardcoded defaults.
  Future<RideEstimate> estimate({
    required LatLng pickup,
    required String pickupLabel,
    required LatLng destination,
    required String destinationLabel,
    String vehicleType = 'standard',
  }) async {
    // 1 - Backend estimate
    final response = await ApiClient.instance.post(
      ApiConfig.rideEstimate,
      body: {
        'pickupLatitude': pickup.latitude,
        'pickupLongitude': pickup.longitude,
        'dropoffLatitude': destination.latitude,
        'dropoffLongitude': destination.longitude,
        'pickupLocation': {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'address': pickupLabel,
        },
        'dropoffLocation': {
          'lat': destination.latitude,
          'lng': destination.longitude,
          'address': destinationLabel,
        },
        'vehicleType': normalizeVehicleType(vehicleType),
      },
    );

    if (response is Map<String, dynamic>) {
      final data = response['data'] as Map<String, dynamic>? ?? response;

      // 1. Parse Fare strictly from backend
      double? fare;
      final fareObj = data['fare'];
      if (fareObj is Map) {
        final estRaw =
            fareObj['estimatedFare'] ??
            fareObj['finalFare'] ??
            fareObj['amount'];
        if (estRaw != null) {
          final parsed = double.tryParse(
            estRaw.toString().replaceAll(RegExp(r'[^\d.]'), ''),
          );
          if (parsed != null) fare = parsed > 10000 ? parsed / 100 : parsed;
        }
      } else if (data['estimatedFare'] != null || fareObj != null) {
        final raw = data['estimatedFare'] ?? fareObj;
        if (raw is num) {
          fare = raw.toDouble() > 10000 ? raw.toDouble() / 100 : raw.toDouble();
        } else {
          final parsed = double.tryParse(
            raw.toString().replaceAll(RegExp(r'[^\d.]'), ''),
          );
          if (parsed != null) fare = parsed > 10000 ? parsed / 100 : parsed;
        }
      }

      if (fare != null && fare > 0) {
        // 2. Parse Route (Distance & Duration)
        double? distance;
        int? duration;

        final routeObj = data['route'];
        if (routeObj is Map) {
          final distRaw =
              routeObj['estimatedDistanceKm'] ?? routeObj['distanceKm'];
          if (distRaw is num) distance = distRaw.toDouble();

          final durRaw =
              routeObj['estimatedDurationMinutes'] ??
              routeObj['durationMinutes'];
          if (durRaw is num) duration = durRaw.toInt();
        }

        // Fallbacks if not inside 'route'
        if (distance == null) {
          final rootDist =
              data['estimatedDistance'] ??
              data['distanceKm'] ??
              data['distance'];
          if (rootDist is num) distance = rootDist.toDouble();
        }
        if (duration == null) {
          final rootDur =
              data['estimatedDuration'] ??
              data['durationMinutes'] ??
              data['duration'];
          if (rootDur is num) duration = rootDur.toInt();
        }

        distance ??=
            const Distance().as(LengthUnit.Meter, pickup, destination) / 1000;
        duration ??= ((distance / 30) * 60).ceil();

        debugPrint(
          '[RideRequestService] Backend estimate verified: fare=NGN$fare dist=${distance.toStringAsFixed(1)} km dur=$duration min',
        );

        return RideEstimate(
          pickupLabel: pickupLabel,
          destinationLabel: destinationLabel,
          pickupLatLng: pickup,
          destinationLatLng: destination,
          distanceKm: distance,
          durationMinutes: duration,
          fareNgn: fare,
        );
      }
    }

    // Must be obtained from VT Rides, otherwise ABORT
    throw Exception(
      'Estimated fare could not be obtained from VT Rides. Ride request aborted.',
    );
  }

  // requestRide

  /// POSTs a ride request to POST /api/v1/rides/request.
  ///
  /// Returns the new ride ID on success. Throws [ApiException] on any failure.
  ///
  /// Payload matches the OpenAPI spec exactly:
  ///  - pickupLocation  : { lat, lng, address }
  ///  - dropoffLocation : { lat, lng, address }
  ///  - vehicleType     : STANDARD, PREMIUM, or BIKE
  ///  - paymentMethod   : CASH, CARD, TRANSFER, or WALLET
  Future<String> requestRide({
    required RideEstimate estimate,
    required String paymentMethod,
    required String vehicleType,
  }) async {
    if (estimate.fareNgn <= 0) {
      throw Exception(
        'Cannot request ride: Estimated fare must be obtained from VT Rides, otherwise ABORT.',
      );
    }

    final backendVehicle = normalizeVehicleType(vehicleType);
    final backendPayment = normalizePaymentMethod(paymentMethod);

    debugPrint(
      '[RideRequestService] Requesting ride: vehicle=$backendVehicle payment=$backendPayment pickup=${estimate.pickupLabel} drop=${estimate.destinationLabel}',
    );

    try {
      final response = await ApiClient.instance.post(
        ApiConfig.rideRequest,
        body: {
          // Flat coordinate fields — required by the backend validator
          // (same pattern as the estimate endpoint).
          'pickupLatitude': estimate.pickupLatLng.latitude,
          'pickupLongitude': estimate.pickupLatLng.longitude,
          'dropoffLatitude': estimate.destinationLatLng.latitude,
          'dropoffLongitude': estimate.destinationLatLng.longitude,
          // Nested location objects for address metadata.
          'pickupLocation': {
            'lat': estimate.pickupLatLng.latitude,
            'lng': estimate.pickupLatLng.longitude,
            'address': estimate.pickupLabel,
          },
          'dropoffLocation': {
            'lat': estimate.destinationLatLng.latitude,
            'lng': estimate.destinationLatLng.longitude,
            'address': estimate.destinationLabel,
          },
          'vehicleType': backendVehicle,
          'paymentMethod': backendPayment,
        },
      );

      // Parse the ride ID — response schema is not fully documented in the
      // OpenAPI spec, so we probe the most common key patterns.
      String? rideId;
      if (response is Map<String, dynamic>) {
        final data = response['data'] as Map<String, dynamic>? ?? response;
        rideId =
            data['rideId']?.toString() ??
            data['id']?.toString() ??
            data['_id']?.toString();
      }

      debugPrint('[RideRequestService] Ride created. ID: $rideId');
      // Return the ID; an empty string means the server accepted the request
      // but did not return an ID — the socket event will carry it.
      return rideId ?? '';
    } on ApiException catch (e) {
      // Log all fields so the full server message is visible in the console.
      debugPrint('══════════════════════════════════════════════');
      debugPrint('[RideRequestService] Ride request FAILED');
      debugPrint('  Status  : ${e.statusCode}');
      debugPrint('  Message : ${e.message}');
      if (e.errors != null) debugPrint('  Errors  : ${e.errors}');
      if (e.data != null) debugPrint('  Data    : ${e.data}');
      debugPrint('══════════════════════════════════════════════');
      rethrow;
    } catch (e) {
      debugPrint('[RideRequestService] Unexpected ride request error: $e');
      rethrow;
    }
  }
}
