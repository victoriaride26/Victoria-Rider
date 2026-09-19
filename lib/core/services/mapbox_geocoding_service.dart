import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/mapbox_config.dart';
import '../models/geocoding_result.dart';

/// Thin client for the Mapbox Geocoding API (v5).
///
/// Supports:
///  - [search]         — forward geocoding (text → coordinates + place name)
///  - [reverseGeocode] — reverse geocoding (coordinates → place name)
///
/// ## Accuracy strategy
///
/// The client uses a **two-tier accuracy strategy** to deliver relevant,
/// localised results regardless of whether the user has GPS enabled:
///
/// ### GPS available (real [proximity] passed in)
/// - `proximity` = user's real coordinates → Mapbox ranks nearby results first.
/// - `bbox` = a **dynamic 40 km × 40 km window** computed around the user's
///   position so only results in their immediate city are returned.
///   A Lagos rider gets Lagos results; a Port Harcourt rider gets PH results.
///
/// ### No GPS (proximity is null)
/// - `proximity` = **Makurdi city centre** (7.7337°N, 8.5211°E) — the primary
///   service area — so typeahead still ranks local Makurdi places first.
/// - `bbox` = **Makurdi metropolitan area** (pre-defined constant) so no
///   out-of-area results leak in when the user hasn't yet granted GPS.
///
/// ### Always applied
/// - `fuzzyMatch=true` — tolerates the spelling variants common in Nigerian
///   place names (e.g. "Wadata" / "Wadatta", "Aper Aku" / "Aper Akuu").
/// - `types=poi,address,neighborhood,locality,place` — filters out coarse
///   country / state / district matches that add noise to a destination search.
/// - `country=ng` — Nigeria only, unless overridden by the caller.
class MapboxGeocodingService {
  MapboxGeocodingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places';

  // ── Makurdi fallback constants ───────────────────────────────────────────────

  /// City centre of Makurdi, Benue State — used when no real GPS is available.
  static const _makurdiCentreLng = 8.5211;
  static const _makurdiCentreLat = 7.7337;

  /// Pre-defined bbox that covers the Makurdi metropolitan area (~40 km across).
  /// Format: min_lng,min_lat,max_lng,max_lat
  static const _makurdiBbox = '8.40,7.62,8.70,7.90';

  // ── Dynamic bbox tuning ─────────────────────────────────────────────────────

  /// Half-width of the dynamic bounding box in degrees (~20 km at Nigerian
  /// latitudes). Produces a ~40 km × 40 km search window around the user.
  static const _bboxHalfDeg = 0.18;

  /// Result types that are meaningful for a ride destination search.
  static const _types = 'poi,address,neighborhood,locality,place';

  // ────────────────────────────────────────────────────────────────────────────

  /// Closes the underlying HTTP client.
  void dispose() => _client.close();

  /// Builds a bbox string centred on [lat]/[lng] with [half] degrees of margin.
  static String _dynamicBbox(double lat, double lng, {double half = _bboxHalfDeg}) {
    final minLng = (lng - half).clamp(-180.0, 180.0);
    final minLat = (lat - half).clamp(-90.0, 90.0);
    final maxLng = (lng + half).clamp(-180.0, 180.0);
    final maxLat = (lat + half).clamp(-90.0, 90.0);
    return '$minLng,$minLat,$maxLng,$maxLat';
  }

  /// Forward geocoding: converts a free-text [query] into a list of
  /// [GeocodingResult]s sorted by relevance.
  ///
  /// When [proximity] is provided (user's real GPS position) the results are
  /// biased toward that location and the bounding box is computed dynamically
  /// around it — so the app works accurately in any Nigerian city.
  ///
  /// When [proximity] is `null` the Makurdi fallback (centre + pre-defined bbox)
  /// is used automatically.
  Future<List<GeocodingResult>> search(
    String query, {
    LatLng? proximity,
    String country = 'ng',
    int limit = 5,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final String proximityStr;
      final String bbox;

      if (proximity != null) {
        // Real GPS → dynamic bbox centred on the user's actual position.
        proximityStr =
            '${proximity.longitude},${proximity.latitude}';
        bbox = _dynamicBbox(proximity.latitude, proximity.longitude);
      } else {
        // No GPS → anchor to Makurdi city centre (primary service area).
        proximityStr =
            '$_makurdiCentreLng,$_makurdiCentreLat';
        bbox = _makurdiBbox;
      }

      final params = <String, String>{
        'access_token': MapboxConfig.accessToken,
        'autocomplete': 'true',
        'fuzzyMatch': 'true',
        'country': country,
        'proximity': proximityStr,
        'bbox': bbox,
        'types': _types,
        'limit': '$limit',
        'language': 'en',
      };

      final uri = Uri.parse(
        '$_baseUrl/${Uri.encodeComponent(query)}.json',
      ).replace(queryParameters: params);

      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];
      return features.map((f) {
        final feature = f as Map<String, dynamic>;
        final placeName = (feature['place_name'] as String?) ?? '';
        final shortName = placeName.split(',').first.trim();
        final coords = (feature['center'] as List<dynamic>);
        return GeocodingResult(
          placeName: placeName,
          shortName: shortName,
          location: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
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
      final uri = Uri.parse(
        '$_baseUrl/${location.longitude},${location.latitude}.json',
      ).replace(queryParameters: {
        'access_token': MapboxConfig.accessToken,
        'types': _types,
        'limit': '1',
        'language': 'en',
      });

      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? [];
      if (features.isEmpty) return null;

      final feature = features.first as Map<String, dynamic>;
      final placeName = (feature['place_name'] as String?) ?? '';
      final shortName = placeName.split(',').first.trim();
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
