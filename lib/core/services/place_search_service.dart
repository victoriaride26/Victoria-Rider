import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/geocoding_result.dart';
import 'benue_gazetteer.dart';
import 'geoapify_geocoding_service.dart';
import 'mapbox_geocoding_service.dart';

/// Orchestrates place search across the bundled Benue gazetteer and the two
/// online providers:
///
///  1. local gazetteer first (instant, offline, covers names providers miss),
///  2. the primary provider for the call site,
///  3. the other provider as fallback when the primary returns nothing,
///  4. one merged, de-duplicated list.
class PlaceSearchService {
  PlaceSearchService({
    MapboxGeocodingService? mapbox,
    GeoapifyGeocodingService? geoapify,
    Future<BenueGazetteer> Function()? loadGazetteer,
  })  : _mapbox = mapbox ?? MapboxGeocodingService(),
        _geoapify = geoapify ?? GeoapifyGeocodingService(),
        _loadGazetteer = loadGazetteer ?? BenueGazetteer.load;

  final MapboxGeocodingService _mapbox;
  final GeoapifyGeocodingService _geoapify;
  final Future<BenueGazetteer> Function() _loadGazetteer;

  static PlaceSearchService? _instance;

  static PlaceSearchService get instance =>
      _instance ??= PlaceSearchService();

  @visibleForTesting
  static set debugInstance(PlaceSearchService? service) => _instance = service;

  /// Two records closer than this are the same place.
  @visibleForTesting
  static const double dedupeRadiusM = 150;

  Future<List<GeocodingResult>> search(
    String query, {
    LatLng? proximity,
    int limit = 6,
    bool primaryIsMapbox = true,
  }) async {
    final q = query.trim();
    if (q.length < BenueGazetteer.minQueryLength) return const [];

    var local = const <GeocodingResult>[];
    var gazetteer = BenueGazetteer(const []);
    try {
      gazetteer = await _loadGazetteer();
      local = gazetteer.search(q, proximity: proximity, limit: limit);
    } catch (_) {
      // a broken gazetteer must never break search
    }

    // Strong local match (exact or prefix on a gazetteer name) answers the
    // query offline and instantly - no need to wait for provider round-trips.
    if (local.isNotEmpty &&
        gazetteer.bestScore(q) <= BenueGazetteer.strongMatchScore) {
      return local;
    }

    var remote = const <GeocodingResult>[];
    try {
      remote = primaryIsMapbox
          ? await _mapbox.search(q, proximity: proximity, limit: limit)
          : await _geoapify.search(q, proximity: proximity, limit: limit);
      if (remote.isEmpty) {
        remote = primaryIsMapbox
            ? await _geoapify.search(q, proximity: proximity, limit: limit)
            : await _mapbox.search(q, proximity: proximity, limit: limit);
      }
    } catch (_) {
      // both providers swallow their own errors; keep local results
    }

    return _merge(local, remote, proximity: proximity, limit: limit);
  }

  /// Reverse geocode, local-first: the bundled Benue gazetteer answers
  /// instantly and offline for fixes near a known place (exact name within
  /// [BenueGazetteer.exactMatchRadiusM], `Near <name>` within
  /// [BenueGazetteer.nearMatchRadiusM]); Mapbox then Geoapify cover the rest.
  Future<GeocodingResult?> reverseGeocode(LatLng point) async {
    try {
      final gazetteer = await _loadGazetteer();
      final local = gazetteer.reverse(point);
      if (local != null) return local;
    } catch (_) {
      // a broken gazetteer must never break reverse geocoding
    }
    try {
      final result = await _mapbox.reverseGeocode(point);
      if (result != null) return result;
    } catch (_) {}
    try {
      final result = await _geoapify.reverseGeocode(point);
      if (result != null) return result;
    } catch (_) {}
    return null;
  }

  /// Closes the underlying HTTP clients. Screens that construct their own
  /// service must call this; [instance] lives for the app's lifetime.
  void dispose() {
    _mapbox.dispose();
    _geoapify.dispose();
  }

  static List<GeocodingResult> _merge(
    List<GeocodingResult> local,
    List<GeocodingResult> remote, {
    LatLng? proximity,
    required int limit,
  }) {
    final merged = <GeocodingResult>[];
    for (final result in [...local, ...remote]) {
      if (merged.length >= limit) break;
      if (_isDuplicate(result, merged)) continue;
      merged.add(result);
    }
    return merged;
  }

  static bool _isDuplicate(GeocodingResult candidate, List<GeocodingResult> kept) {
    for (final other in kept) {
      if (_normalize(candidate.shortName) == _normalize(other.shortName) ||
          _normalize(candidate.placeName) == _normalize(other.placeName)) {
        return true;
      }
      final meters = const Distance()(candidate.location, other.location);
      if (meters <= dedupeRadiusM) return true;
    }
    return false;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}
