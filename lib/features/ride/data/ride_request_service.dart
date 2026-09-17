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

  // Local fare constants (fallback only)

  /// Base fare in Naira used when the backend estimate is unavailable.
  static const double _baseFareNgn = 500;

  /// Per-km rate in Naira used when the backend estimate is unavailable.
  static const double _perKmNgn = 150;

  // Enum normalisers

  /// Returns a local fare multiplier for a given vehicle type (display only).
  static double vehicleMultiplier(String vehicleType) =>
      switch (vehicleType.toLowerCase()) {
        'premium' => 1.5,
        'bike' => 0.5,
        _ => 1.0,
      };

  /// Maps any vehicle-type string to the backend enum: STANDARD, PREMIUM, BIKE.
  static String normalizeVehicleType(String vehicleType) =>
      switch (vehicleType.toLowerCase()) {
        'premium' || 'comfort' => 'PREMIUM',
        'bike' => 'BIKE',
        _ => 'STANDARD',
      };

  /// Maps any payment-method string to the backend enum: CASH, CARD, TRANSFER, WALLET.
  static String normalizePaymentMethod(String paymentMethod) =>
      switch (paymentMethod.toLowerCase()) {
        'wallet' => 'WALLET',
        'card' => 'CARD',
        'transfer' => 'TRANSFER',
        _ => 'CASH',
      };

  // estimate

  /// Fetches a [RideEstimate] for the given pickup to destination pair.
  ///
  /// 1. Calls POST /api/v1/rides/estimate with required flat coordinates.
  /// 2. If that succeeds and the response contains a fare, use it.
  /// 3. Otherwise falls back to a local Directions API / straight-line calc.
  Future<RideEstimate> estimate({
    required LatLng pickup,
    required String pickupLabel,
    required LatLng destination,
    required String destinationLabel,
    String vehicleType = 'standard',
  }) async {
    // 1 - Backend estimate
    try {
      final response = await ApiClient.instance.post(
        ApiConfig.rideEstimate,
        body: {
          'pickupLatitude': pickup.latitude,
          'pickupLongitude': pickup.longitude,
          'dropoffLatitude': destination.latitude,
          'dropoffLongitude': destination.longitude,
          'vehicleType': normalizeVehicleType(vehicleType),
        },
      );

      if (response is Map<String, dynamic>) {
        final data = response['data'] as Map<String, dynamic>? ?? response;
        final fareRaw = data['estimatedFare'] ?? data['fare'];
        if (fareRaw is num) {
          final fare = fareRaw.toDouble();
          final distanceRaw =
              data['estimatedDistance'] ?? data['distanceKm'] ?? data['distance'];
          final durationRaw =
              data['estimatedDuration'] ?? data['durationMinutes'] ?? data['duration'];
          final distance = distanceRaw is num
              ? distanceRaw.toDouble()
              : const Distance().as(LengthUnit.Meter, pickup, destination) / 1000;
          final duration = durationRaw is num
              ? durationRaw.toInt()
              : ((distance / 30) * 60).ceil();

          debugPrint(
            '[RideRequestService] Backend estimate: fare=NGN$fare dist=${distance.toStringAsFixed(1)} km dur=$duration min',
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
    } catch (e) {
      debugPrint('[RideRequestService] Backend estimate failed: $e. Falling back to local calculation.');
    }

    // 2 - Local fallback
    return _estimateLocally(
      pickup: pickup,
      pickupLabel: pickupLabel,
      destination: destination,
      destinationLabel: destinationLabel,
      vehicleType: vehicleType,
    );
  }

  Future<RideEstimate> _estimateLocally({
    required LatLng pickup,
    required String pickupLabel,
    required LatLng destination,
    required String destinationLabel,
    required String vehicleType,
  }) async {
    final route = await _directions.getRoute(
      origin: pickup,
      destination: destination,
    );

    final double distanceMeters;
    final int durationMinutes;

    if (route != null) {
      distanceMeters = route.distanceMeters;
      durationMinutes = (route.durationSeconds / 60).ceil();
    } else {
      // Straight-line fallback (~30 km/h average speed).
      distanceMeters = const Distance().as(LengthUnit.Meter, pickup, destination);
      durationMinutes = ((distanceMeters / 1000) / 30 * 60).ceil();
    }

    final distanceKm = distanceMeters / 1000;
    final multiplier = vehicleMultiplier(vehicleType);
    final fareNgn = ((_baseFareNgn + distanceKm * _perKmNgn) * multiplier)
        .clamp(_baseFareNgn * multiplier, double.infinity);

    debugPrint('[RideRequestService] Local estimate: fare=NGN$fareNgn dist=${distanceKm.toStringAsFixed(1)} km dur=$durationMinutes min');

    return RideEstimate(
      pickupLabel: pickupLabel,
      destinationLabel: destinationLabel,
      pickupLatLng: pickup,
      destinationLatLng: destination,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      fareNgn: fareNgn,
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
    final backendVehicle = normalizeVehicleType(vehicleType);
    final backendPayment = normalizePaymentMethod(paymentMethod);

    debugPrint('[RideRequestService] Requesting ride: vehicle=$backendVehicle payment=$backendPayment pickup=${estimate.pickupLabel} drop=${estimate.destinationLabel}');

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
        rideId = data['rideId']?.toString() ??
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
      if (e.data != null)   debugPrint('  Data    : ${e.data}');
      debugPrint('══════════════════════════════════════════════');
      rethrow;
    } catch (e) {
      debugPrint('[RideRequestService] Unexpected ride request error: $e');
      rethrow;
    }
  }
}