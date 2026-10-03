import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../models/geocoding_result.dart';

/// One location from the bundled Benue gazetteer (curated + GeoNames +
/// Wikidata + Overture Places). The gazetteer exists because OSM-derived
/// providers have no coverage for several Makurdi/Benue place names.
class GazetteerEntry {
  const GazetteerEntry({
    required this.name,
    required this.aliases,
    required this.locality,
    required this.category,
    required this.lat,
    required this.lng,
    this.verified = false,
  });

  factory GazetteerEntry.fromJson(Map<String, dynamic> json) => GazetteerEntry(
        name: json['name'] as String? ?? '',
        aliases: (json['aliases'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(),
        locality: json['locality'] as String? ?? '',
        category: json['category'] as String? ?? 'place',
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        verified: json['verified'] as bool? ?? false,
      );

  final String name;
  final List<String> aliases;
  final String locality;
  final String category;
  final double lat;
  final double lng;
  final bool verified;

  /// Display label, shaped like the provider results the UI already renders.
  String get placeName =>
      locality.isEmpty ? '$name, Benue, Nigeria' : '$name, $locality, Benue, Nigeria';

  GeocodingResult toGeocodingResult() => GeocodingResult(
        placeName: placeName,
        shortName: name,
        location: LatLng(lat, lng),
      );
}

/// Local-first place database covering Makurdi, Gboko, Otukpo, Katsina-Ala
/// and Vandeikya, bundled as an asset so search works offline and answers
/// names the online providers simply do not know.
class BenueGazetteer {
  BenueGazetteer(List<GazetteerEntry> entries)
      : entries = List.unmodifiable(entries);

  factory BenueGazetteer.fromJson(Map<String, dynamic> json) =>
      BenueGazetteer(
        (json['entries'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(GazetteerEntry.fromJson)
            .toList(),
      );

  /// Minimum characters before local matching starts.
  static const int minQueryLength = 2;

  static const String assetPath = 'assets/data/benue_gazetteer.json';

  static BenueGazetteer? _cache;

  /// Loads and caches the bundled gazetteer. Never throws — an unreadable
  /// asset degrades to an empty gazetteer so online search still works.
  static Future<BenueGazetteer> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = BenueGazetteer.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _cache = parsed;
      return parsed;
    } catch (error) {
      debugPrint('gazetteer load failed: $error');
      return BenueGazetteer(const []);
    }
  }

  @visibleForTesting
  static void debugResetCache() => _cache = null;

  final List<GazetteerEntry> entries;

  /// Instant offline search over names and aliases.
  ///
  /// Ranking: exact match, then prefix match, then substring match (queries
  /// of 3+ characters); ties broken by distance from [proximity].
  List<GeocodingResult> search(
    String query, {
    LatLng? proximity,
    int limit = 3,
  }) {
    final q = _normalize(query);
    if (q.length < minQueryLength || limit <= 0) return const [];

    final scored = <_Scored>[];
    for (final entry in entries) {
      final score = _score(entry, q);
      if (score < 0) continue;
      final distance = proximity == null
          ? 0.0
          : const Distance()(
              proximity,
              LatLng(entry.lat, entry.lng),
            );
      scored.add(_Scored(score, distance, entry.toGeocodingResult()));
    }
    scored.sort((a, b) {
      if (a.score != b.score) return a.score.compareTo(b.score);
      if (a.distance != b.distance) return a.distance.compareTo(b.distance);
      return 0;
    });
    return scored.take(limit).map((s) => s.result).toList();
  }

  static int _score(GazetteerEntry entry, String q) {
    var best = -1;
    for (final candidate in <String>[entry.name, ...entry.aliases]) {
      final c = _normalize(candidate);
      if (c.isEmpty) continue;
      int score;
      if (c == q) {
        score = 0;
      } else if (c.startsWith(q)) {
        score = 1;
      } else if (q.length >= 3 && c.contains(q)) {
        score = 2;
      } else {
        continue;
      }
      if (score < best || best < 0) best = score;
    }
    return best;
  }

  /// Best ranking for [query]: 0 exact, 1 prefix, 2 substring-only,
  /// [noMatchScore] when nothing matches.
  int bestScore(String query) {
    final q = _normalize(query);
    if (q.length < minQueryLength) return noMatchScore;
    var best = noMatchScore;
    for (final entry in entries) {
      final score = _score(entry, q);
      if (score >= 0 && score < best) best = score;
    }
    return best;
  }

  /// A local exact or prefix match is good enough to skip the network.
  static const int strongMatchScore = 1;

  /// Returned by [bestScore] when no entry matches at all.
  static const int noMatchScore = 99;

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}

class _Scored {
  const _Scored(this.score, this.distance, this.result);

  final int score;
  final double distance;
  final GeocodingResult result;
}
