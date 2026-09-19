import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/geoapify_config.dart';
import '../models/geocoding_result.dart';

/// Client for the Geoapify Geocoding API.
///
/// Supports:
///  - [search]         — forward geocoding (text → coordinates + place name)
///  - [reverseGeocode] — reverse geocoding (coordinates → place name)
class GeoapifyGeocodingService {
  GeoapifyGeocodingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  // ── Makurdi fallback constants ───────────────────────────────────────────────

  /// City centre of Makurdi, Benue State — used when no real GPS is available.
  static const _makurdiCentreLng = 8.5211;
  static const _makurdiCentreLat = 7.7337;

  /// Closes the underlying HTTP client.
  void dispose() => _client.close();

  /// Forward geocoding: converts a free-text [query] into a list of
  /// [GeocodingResult]s sorted by relevance.
  Future<List<GeocodingResult>> search(
    String query, {
    LatLng? proximity,
    String country = 'ng',
    int limit = 5,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final lat = proximity?.latitude ?? _makurdiCentreLat;
      final lon = proximity?.longitude ?? _makurdiCentreLng;

      final params = <String, String>{
        'text': query,
        'apiKey': GeoapifyConfig.apiKey,
        'filter': 'countrycode:$country',
        'bias': 'proximity:$lon,$lat',
        'limit': '$limit',
        'format': 'json',
      };

      final uri = Uri.parse('https://api.geoapify.com/v1/geocode/search')
          .replace(queryParameters: params);

      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];

      return results.map((f) {
        final feature = f as Map<String, dynamic>;
        final placeName = (feature['formatted'] as String?) ?? '';
        final shortName = (feature['name'] as String?) ??
            placeName.split(',').first.trim();
        return GeocodingResult(
          placeName: placeName,
          shortName: shortName,
          location: LatLng(
            (feature['lat'] as num).toDouble(),
            (feature['lon'] as num).toDouble(),
          ),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Reverse geocoding: converts [location] coordinates into a human-readable
  /// address string. Returns `null` on failure.
  Future<GeocodingResult?> reverseGeocode(LatLng location) async {
    try {
      final params = <String, String>{
        'lat': location.latitude.toString(),
        'lon': location.longitude.toString(),
        'apiKey': GeoapifyConfig.apiKey,
        'limit': '1',
        'format': 'json',
      };

      final uri = Uri.parse('https://api.geoapify.com/v1/geocode/reverse')
          .replace(queryParameters: params);

      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;

      final feature = results.first as Map<String, dynamic>;
      final placeName = (feature['formatted'] as String?) ?? '';
      final shortName = (feature['name'] as String?) ??
          placeName.split(',').first.trim();
      
      return GeocodingResult(
        placeName: placeName,
        shortName: shortName,
        location: location,
      );
    } catch (_) {
      return null;
    }
  }
}
