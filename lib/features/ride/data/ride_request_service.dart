import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/config/api_config.dart';
import '../../../core/services/directions_service.dart';
import '../../../core/services/session_controller.dart';

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
///  1. [estimate] — resolve route + compute fare locally via Directions API.
///  2. [requestRide] — POST to the backend to create the ride.
class RideRequestService {
  RideRequestService({
    DirectionsService? directions,
    http.Client? client,
  })  : _directions = directions ?? DirectionsService(),
        _http = client ?? http.Client();

  final DirectionsService _directions;
  final http.Client _http;

  void dispose() {
    _directions.dispose();
    _http.close();
  }

  /// Base fare in Naira.
  static const double _baseFareNgn = 500;

  /// Per-km rate in Naira.
  static const double _perKmNgn = 150;

  /// Returns multiplier for a given vehicle type.
  static double vehicleMultiplier(String vehicleType) => switch (vehicleType.toLowerCase()) {
        'premium' || 'comfort' || 'xl' => 1.5,
        'bike' || 'motorcycle' => 0.5,
        _ => 1.0,
      };

  /// Computes a [RideEstimate] for the given pickup → destination pair.
  ///
  /// First calls backend `POST /api/v1/rides/estimate`.
  /// Falls back to local Directions API / straight-line calculation if offline.
  Future<RideEstimate> estimate({
    required LatLng pickup,
    required String pickupLabel,
    required LatLng destination,
    required String destinationLabel,
    String vehicleType = 'standard',
  }) async {
    // 1. Attempt backend estimation first
    try {
      final token = SessionController.instance.accessToken;
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final body = jsonEncode({
        'pickupLocation': {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'address': pickupLabel,
        },
        'destinationLocation': {
          'lat': destination.latitude,
          'lng': destination.longitude,
          'address': destinationLabel,
        },
        'vehicleType': vehicleType,
      });

      final response = await _http
          .post(
            Uri.parse(ApiConfig.rideEstimate),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
        final data = decoded?['data'] as Map<String, dynamic>? ?? decoded;
        if (data != null && (data['estimatedFare'] != null || data['fare'] != null)) {
          final fare = ((data['estimatedFare'] ?? data['fare']) as num).toDouble();
          final distance = ((data['estimatedDistance'] ?? data['distanceKm'] ?? data['distance']) as num?)?.toDouble() ??
              const Distance().as(LengthUnit.Meter, pickup, destination) / 1000;
          final duration = ((data['estimatedDuration'] ?? data['durationMinutes'] ?? data['duration']) as num?)?.toInt() ??
              ((distance / 30) * 60).ceil();

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
    } catch (_) {
      // Fallback to local calculation
    }

    // 2. Local fallback calculation
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
      // Straight-line fallback.
      distanceMeters =
          const Distance().as(LengthUnit.Meter, pickup, destination);
      durationMinutes = ((distanceMeters / 1000) / 30 * 60).ceil(); // ~30 km/h
    }

    final distanceKm = distanceMeters / 1000;
    final multiplier = vehicleMultiplier(vehicleType);
    final fareNgn = ((_baseFareNgn + distanceKm * _perKmNgn) * multiplier).clamp(
      _baseFareNgn * multiplier,
      double.infinity,
    );

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

  /// POSTs a ride request to the backend.
  ///
  /// Returns the new ride ID on success, or `null` on failure.
  Future<String?> requestRide({
    required RideEstimate estimate,
    required String paymentMethod, // 'wallet' | 'cash' | 'card'
    required String vehicleType,   // 'standard' | 'comfort' | 'xl'
  }) async {
    try {
      final token = SessionController.instance.accessToken;
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final body = jsonEncode({
        'pickupLocation': {
          'lat': estimate.pickupLatLng.latitude,
          'lng': estimate.pickupLatLng.longitude,
          'address': estimate.pickupLabel,
        },
        'destinationLocation': {
          'lat': estimate.destinationLatLng.latitude,
          'lng': estimate.destinationLatLng.longitude,
          'address': estimate.destinationLabel,
        },
        'paymentMethod': paymentMethod,
        'vehicleType': vehicleType,
        'estimatedFare': estimate.fareNgn,
        'estimatedDistance': estimate.distanceKm,
        'estimatedDuration': estimate.durationMinutes,
      });

      final response = await _http
          .post(
            Uri.parse(ApiConfig.rideRequest),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final rideId = data?['data']?['rideId'] as String? ??
            data?['rideId'] as String?;
        return rideId ?? 'pending';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
