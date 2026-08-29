import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/mapbox_config.dart';

/// A single turn-by-turn maneuver from the Directions API.
class DirectionsStep {
  const DirectionsStep({
    required this.instruction,
    required this.maneuverLocation,
    required this.distanceMeters,
  });

  final String instruction;
  final LatLng maneuverLocation;
  final double distanceMeters;
}

/// Result of a Directions API route request.
class RouteResult {
  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
    required this.steps,
  });

  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;
  final List<DirectionsStep> steps;
}

/// Thin client for the Mapbox Directions API (v5).
///
/// Uses the same public token as the map tiles; returns road-following
/// geometry, real distance/duration, and turn-by-turn instructions.
class DirectionsService {
  DirectionsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Closes the underlying HTTP client to release socket resources.
  void dispose() => _client.close();

  static const _baseUrl =
      'https://api.mapbox.com/directions/v5/mapbox';

  /// Fetches a route from [origin] to [destination].
  ///
  /// [profile] is one of Mapbox's routing profiles, e.g. `walking` or
  /// `driving`. Returns `null` on any error or malformed response so callers
  /// can fall back to straight-line estimates.
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving',
  }) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/$profile/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}',
      ).replace(
        queryParameters: {
          'access_token': MapboxConfig.accessToken,
          'geometries': 'geojson',
          'overview': 'full',
          'steps': 'true',
          'alternatives': 'false',
        },
      );
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;

      final coordinates =
          ((route['geometry'] as Map<String, dynamic>)['coordinates']
              as List<dynamic>);
      final points = coordinates
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final steps = <DirectionsStep>[];
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null && legs.isNotEmpty) {
        for (final leg in legs) {
          for (final step in (leg['steps'] as List<dynamic>)) {
            final maneuver = step['maneuver'] as Map<String, dynamic>;
            final loc = maneuver['location'] as List<dynamic>;
            steps.add(
              DirectionsStep(
                instruction: maneuver['instruction'] as String,
                maneuverLocation:
                    LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
                distanceMeters: (step['distance'] as num).toDouble(),
              ),
            );
          }
        }
      }

      return RouteResult(
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
        points: points,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Picks the upcoming step whose maneuver is nearest ahead of [position].
/// Returns `null` when there are no steps.
DirectionsStep? activeStepFor(List<DirectionsStep> steps, LatLng position) {
  if (steps.isEmpty) return null;
  var best = steps.last;
  var bestDistance = double.infinity;
  for (final step in steps) {
    final d =
        const Distance().as(LengthUnit.Meter, position, step.maneuverLocation);
    if (d < bestDistance) {
      best = step;
      bestDistance = d;
    }
  }
  return best;
}