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

  /// Minimum base fare in Naira.
  static const double _baseFareNgn = 300;

  /// Per-km rate in Naira.
  static const double _perKmNgn = 180;

  /// Computes a [RideEstimate] for the given pickup → destination pair.
  ///
  /// Falls back to straight-line distance if the Directions API is unavailable.
  Future<RideEstimate> estimate({
    required LatLng pickup,
    required String pickupLabel,
    required LatLng destination,
    required String destinationLabel,
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
      // Straight-line fallback.
      distanceMeters =
          const Distance().as(LengthUnit.Meter, pickup, destination);
      durationMinutes = ((distanceMeters / 1000) / 30 * 60).ceil(); // ~30 km/h
    }

    final distanceKm = distanceMeters / 1000;
    final fareNgn = (_baseFareNgn + distanceKm * _perKmNgn).clamp(
      _baseFareNgn,
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
            Uri.parse('${ApiConfig.apiV1}/rides/request'),
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
