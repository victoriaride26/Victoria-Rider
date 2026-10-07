import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:vtrides/core/services/benue_gazetteer.dart';
import 'package:vtrides/core/services/geoapify_geocoding_service.dart';
import 'package:vtrides/core/services/mapbox_geocoding_service.dart';
import 'package:vtrides/core/services/place_search_service.dart';
import 'package:vtrides/features/ride/presentation/screens/ride_history_screen.dart';

BenueGazetteer _gazetteer() => BenueGazetteer([
      GazetteerEntry(
        name: 'Judges Quarters',
        aliases: const [
          "Judge's Quarters",
          'Judges Crescent',
          'Judge Crescent',
          'Judges Quarters Gboko Rd',
        ],
        locality: 'Makurdi',
        category: 'district',
        lat: 7.7237,
        lng: 8.5601,
      ),
      GazetteerEntry(
        name: 'High Level',
        aliases: const ['Highlevel'],
        locality: 'Makurdi',
        category: 'district',
        lat: 7.74,
        lng: 8.517,
      ),
    ]);

String _mapboxBody(List<Map<String, dynamic>> features) => jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final f in features)
          {
            'place_name': f['name'],
            'center': [f['lng'], f['lat']],
          },
      ],
    });

String _geoapifyBody(List<Map<String, dynamic>> results) => jsonEncode({
      'results': [
        for (final r in results)
          {
            'formatted': r['name'],
            'name': r['short'],
            'lat': r['lat'],
            'lon': r['lng'],
          },
      ],
    });

MockClient _client(String label, Map<String, String> responses,
    {required List<String> hits}) {
  return MockClient((request) async {
    hits.add('$label ${request.url.host}');
    for (final entry in responses.entries) {
      if (request.url.toString().contains(entry.key)) {
        return http.Response(entry.value, 200);
      }
    }
    return http.Response('{"features":[],"results":[]}', 200);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BenueGazetteer local search', () {
    test('matches approved aliases for Judges Quarters', () {
      final gaz = _gazetteer();
      for (final alias in const [
        'Judge Crescent',
        "Judge's Quarters",
        'Judges Crescent',
        'judges quarters gboko',
      ]) {
        final results = gaz.search(alias);
        expect(results, isNotEmpty, reason: 'alias "$alias" should match');
        expect(results.first.shortName, 'Judges Quarters');
      }
    });

    test('prefix beats substring and proximity breaks ties', () {
      final gaz = _gazetteer();
      final results = gaz.search('high');
      expect(results.first.shortName, 'High Level');
    });

    test('short queries return nothing', () {
      expect(_gazetteer().search('h'), isEmpty);
      expect(_gazetteer().search(''), isEmpty);
    });

    test('bundled asset loads and resolves Makurdi names providers miss',
        () async {
      final gaz = await BenueGazetteer.load();
      expect(gaz.entries, isNotEmpty,
          reason: 'assets/data/benue_gazetteer.json must be declared in pubspec');
      final judges = gaz.search('Judge Crescent');
      expect(judges, isNotEmpty);
      expect(judges.first.shortName.toLowerCase(), contains('judges quarters'));
      expect(gaz.search('High Level'), isNotEmpty);
      expect(gaz.search('North Bank'), isNotEmpty);
      BenueGazetteer.debugResetCache();
    });
  });

  group('PlaceSearchService', () {
    test('short query hits neither gazetteer nor providers', () async {
      final hits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: hits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {}, hits: hits),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      expect(await service.search('h'), isEmpty);
      expect(hits, isEmpty);
    });

    test('strong local match answers without any network call', () async {
      final geoHits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: geoHits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {}, hits: geoHits),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      final results = await service.search('judge crescent');
      expect(results, isNotEmpty);
      expect(results.first.shortName, 'Judges Quarters');
      expect(geoHits, isEmpty,
          reason: 'exact/prefix gazetteer hit must skip the providers');
    });

    test('substring-only local match still consults the providers', () async {
      final geoHits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: geoHits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {}, hits: geoHits),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      final results = await service.search('quarters');
      expect(results, isNotEmpty);
      expect(results.first.shortName, 'Judges Quarters');
      expect(geoHits.where((h) => h.startsWith('mapbox')), isNotEmpty,
          reason: 'weak local match must still query the primary provider');
    });

    test('primary provider hit skips the fallback provider', () async {
      final geoHits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {
            'api.mapbox.com': _mapboxBody([
              {'name': 'Wurukum Market, Makurdi', 'lat': 7.7322, 'lng': 8.5245},
            ]),
          }, hits: geoHits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {
            'api.geoapify.com': _geoapifyBody([
              {'name': 'Geoapify Result', 'short': 'Geo', 'lat': 7.7, 'lng': 8.5},
            ]),
          }, hits: geoHits),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      final results = await service.search('wurukum');
      expect(results.first.shortName, contains('Wurukum'));
      expect(geoHits.where((h) => h.startsWith('geoapify')), isEmpty);
    });

    test('empty primary falls back to the other provider', () async {
      final geoHits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: geoHits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {
            'api.geoapify.com': _geoapifyBody([
              {'name': 'Only On Geoapify', 'short': 'Only', 'lat': 7.71, 'lng': 8.53},
            ]),
          }, hits: geoHits),
        ),
        loadGazetteer: () async => BenueGazetteer(const []),
      );
      final results = await service.search('wurukum', primaryIsMapbox: true);
      expect(results.single.placeName, 'Only On Geoapify');
      expect(geoHits.where((h) => h.startsWith('geoapify')), isNotEmpty);
    });

    test('local and provider duplicates merge into one result', () async {
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {
            'api.mapbox.com': _mapboxBody([
              // same spot as the gazetteer's Judges Quarters
              {'name': 'Judges Quarters, Makurdi', 'lat': 7.7237, 'lng': 8.5601},
            ]),
          }, hits: <String>[]),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {}, hits: <String>[]),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      final results = await service.search('judges quarters');
      expect(results.where((r) => r.shortName.toLowerCase().contains('judges')), hasLength(1));
    });

    test('reverse geocode falls back from Mapbox to Geoapify', () async {
      final hits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: hits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {
            'api.geoapify.com': jsonEncode({
              'results': [
                {
                  'formatted': 'High Level, Makurdi, Nigeria',
                  'lat': 7.74,
                  'lon': 8.517,
                },
              ],
            }),
          }, hits: hits),
        ),
        loadGazetteer: () async => BenueGazetteer(const []),
      );
      final result = await service.reverseGeocode(LatLng(7.74, 8.517));
      expect(result, isNotNull);
      expect(result!.placeName, contains('High Level'));
      expect(hits.where((h) => h.startsWith('geoapify')), isNotEmpty);
    });
  });

  group('BenueGazetteer reverse (nearest)', () {
    test('fix on top of an entry returns its own name', () {
      final result = _gazetteer().reverse(LatLng(7.7237, 8.5601));
      expect(result, isNotNull);
      expect(result!.shortName, 'Judges Quarters');
      // The GPS fix itself is kept so the ride starts at the real position.
      expect(result.location.latitude, closeTo(7.7237, 1e-9));
    });

    test('fix a few streets away returns a Near label', () {
      // ~555 m north of Judges Quarters — inside the near radius.
      final result = _gazetteer().reverse(LatLng(7.7287, 8.5601));
      expect(result, isNotNull);
      expect(result!.shortName, 'Near Judges Quarters');
      expect(result.placeName, contains('Near Judges Quarters'));
    });

    test('fix far from every entry returns null for provider fallback', () {
      expect(_gazetteer().reverse(LatLng(9.0, 9.0)), isNull);
    });

    test('nearest reports the closest entry and its distance', () {
      final hit = _gazetteer().nearest(LatLng(7.74, 8.517));
      expect(hit, isNotNull);
      expect(hit!.entry.name, 'High Level');
      expect(hit.distanceMeters, closeTo(0, 1.0));
    });
  });

  group('PlaceSearchService reverseGeocode local-first', () {
    test('gazetteer hit answers without any network call', () async {
      final hits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: hits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {}, hits: hits),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      final result = await service.reverseGeocode(LatLng(7.7237, 8.5601));
      expect(result, isNotNull);
      expect(result!.shortName, 'Judges Quarters');
      expect(hits, isEmpty,
          reason: 'gazetteer reverse hit must skip the providers');
    });

    test('gazetteer miss still falls back to the providers', () async {
      final hits = <String>[];
      final service = PlaceSearchService(
        mapbox: MapboxGeocodingService(
          client: _client('mapbox', {}, hits: hits),
        ),
        geoapify: GeoapifyGeocodingService(
          client: _client('geoapify', {
            'api.geoapify.com': jsonEncode({
              'results': [
                {
                  'formatted': 'Remote Place, Nigeria',
                  'lat': 9.0,
                  'lon': 9.0,
                },
              ],
            }),
          }, hits: hits),
        ),
        loadGazetteer: () async => _gazetteer(),
      );
      final result = await service.reverseGeocode(LatLng(9.0, 9.0));
      expect(result, isNotNull);
      expect(result!.placeName, contains('Remote Place'));
    });
  });

  group('RideHistoryItem.parseList envelopes', () {
    Map<String, dynamic> ride() => {
          'id': 'r1',
          'status': 'COMPLETED',
          'createdAt': '2026-09-03T12:00:00.000Z',
          'estimatedFare': 250000,
          'dropoffAddress': 'High Level, Makurdi',
          'pickupAddress': 'Wurukum, Makurdi',
        };

    test('understands every known envelope', () {
      final envelopes = <dynamic>[
        {
          'success': true,
          'data': [ride()],
        },
        {
          'success': true,
          'data': {
            'rides': [ride()],
          },
        },
        {
          'success': true,
          'data': {
            'trips': [ride()],
          },
        },
        {
          'success': true,
          'data': {
            'results': [ride()],
          },
        },
        {
          'success': true,
          'data': {
            'data': [ride()],
          },
        },
        [ride()],
        {
          'rides': [ride()],
        },
        {
          'trips': [ride()],
        },
      ];
      for (final envelope in envelopes) {
        final parsed = RideHistoryItem.parseAll(envelope);
        expect(parsed, hasLength(1), reason: 'envelope: $envelope');
        expect(parsed.first.id, 'r1');
        expect(parsed.first.displayFareNgn, 2500.0);
      }
    });

    test('unknown shapes parse to empty, never throw', () {
      expect(RideHistoryItem.parseAll(null), isEmpty);
      expect(RideHistoryItem.parseAll({'success': true}), isEmpty);
      expect(
        RideHistoryItem.parseAll({
          'success': true,
          'data': {'unknown': []},
        }),
        isEmpty,
      );
    });
  });

  group('gazetteer asset contract', () {
    test('asset JSON has the schema the Dart loader expects', () async {
      final raw = await rootBundle.loadString(BenueGazetteer.assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['schema_version'], 1);
      expect(json['state'], 'Benue');
      final entries = json['entries'] as List<dynamic>;
      expect(entries.length, greaterThan(1000));
      for (final item in entries.take(25)) {
        final e = item as Map<String, dynamic>;
        expect(e['name'], isA<String>());
        expect(e['lat'], isA<num>());
        expect(e['lng'], isA<num>());
        expect(e['sources'], isA<List<dynamic>>());
        expect(e['licenses'], isA<List<dynamic>>());
      }
      expect(
        json['sources'],
        contains(predicate((s) => (s as Map)['name'] == 'overture')),
      );
      expect(
        (json['sources'] as List).map((s) => (s as Map)['license']),
        isNot(contains(contains('ODbL'))),
        reason: 'no OSM/ODbL data may enter the shared gazetteer',
      );
    });
  });
}
