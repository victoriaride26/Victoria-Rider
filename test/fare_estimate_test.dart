import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:vtrides/core/models/geocoding_result.dart';
import 'package:vtrides/core/network/api_client.dart';
import 'package:vtrides/features/ride/data/ride_request_service.dart';

void main() {
  group('Backend-Only Fare Estimation & Enforcement', () {
    test('Normalizes vehicle types to backend enums', () {
      expect(RideRequestService.normalizeVehicleType('standard'), 'STANDARD');
      expect(RideRequestService.normalizeVehicleType('comfort'), 'PREMIUM');
      expect(RideRequestService.normalizeVehicleType('premium'), 'PREMIUM');
      expect(RideRequestService.normalizeVehicleType('bike'), 'BIKE');
      expect(RideRequestService.normalizeVehicleType('motorcycle'), 'STANDARD');
    });

    test('Parses backend-calculated fare when backend returns valid estimate', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/estimate')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'fare': {
                  'estimatedFare': 125000, // 125000 kobo = 1250 NGN
                },
                'route': {
                  'estimatedDistanceKm': 4.2,
                  'estimatedDurationMinutes': 12,
                },
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      addTearDown(service.dispose);

      final estimate = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Wurukum Roundabout',
        destination: const LatLng(7.7123, 8.5112),
        destinationLabel: 'Modern Market',
        vehicleType: 'standard',
      );

      expect(estimate.fareNgn, 1250.0);
      expect(estimate.distanceKm, 4.2);
      expect(estimate.durationMinutes, 12);
    });

    test('ABORTS with exception when backend calculation fails or fare is missing', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/estimate')) {
          // Backend response without fare calculation
          return http.Response(
            jsonEncode({
              'success': false,
              'message': 'Unable to calculate fare route',
            }),
            400,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      addTearDown(service.dispose);

      expect(
        () => service.estimate(
          pickup: const LatLng(7.7322, 8.5245),
          pickupLabel: 'Point A',
          destination: const LatLng(7.7123, 8.5112),
          destinationLabel: 'Point B',
          vehicleType: 'standard',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('ABORTS with exception when backend returns fare <= 0', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/estimate')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'fare': {'estimatedFare': 0},
                'route': {'distanceKm': 2.0, 'durationMinutes': 5},
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      addTearDown(service.dispose);

      expect(
        () => service.estimate(
          pickup: const LatLng(7.7322, 8.5245),
          pickupLabel: 'Point A',
          destination: const LatLng(7.7123, 8.5112),
          destinationLabel: 'Point B',
          vehicleType: 'standard',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Adds the per-stop fee when the backend estimate ignores stops', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/estimate')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // The stops ARE sent — the backend just doesn't price them.
          expect((body['stops'] as List).length, 2);
          expect((body['stopovers'] as List).length, 2);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'fare': {'estimatedFare': 125000},
                'route': {
                  'estimatedDistanceKm': 4.2,
                  'estimatedDurationMinutes': 12,
                },
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      addTearDown(service.dispose);

      final estimate = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Wurukum Roundabout',
        destination: const LatLng(7.7123, 8.5112),
        destinationLabel: 'Modern Market',
        vehicleType: 'standard',
        stops: const [
          GeocodingResult(
            placeName: 'Stop One, Makurdi',
            shortName: 'Stop One',
            location: LatLng(7.72, 8.51),
          ),
          GeocodingResult(
            placeName: 'Stop Two, Makurdi',
            shortName: 'Stop Two',
            location: LatLng(7.71, 8.50),
          ),
        ],
      );

      // Base ₦1,250 + 2 stops × ₦200 — matches what /rides/request creates.
      expect(estimate.fareNgn, 1650.0);
    });

    test('Trusts the backend number as-is once it prices stops itself', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/estimate')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'fare': {
                  'estimatedFare': 165000,
                  'appliedPerStopFeeKoba': 20000,
                },
                'route': {
                  'estimatedDistanceKm': 4.2,
                  'estimatedDurationMinutes': 12,
                },
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      addTearDown(service.dispose);

      final estimate = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Wurukum Roundabout',
        destination: const LatLng(7.7123, 8.5112),
        destinationLabel: 'Modern Market',
        vehicleType: 'standard',
        stops: const [
          GeocodingResult(
            placeName: 'Stop One, Makurdi',
            shortName: 'Stop One',
            location: LatLng(7.72, 8.51),
          ),
        ],
      );

      expect(estimate.fareNgn, 1650.0);
    });

    test('No stop fee is added when the rider picked no stops', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/estimate')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'fare': {'estimatedFare': 125000},
                'route': {
                  'estimatedDistanceKm': 4.2,
                  'estimatedDurationMinutes': 12,
                },
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      addTearDown(service.dispose);

      final estimate = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Wurukum Roundabout',
        destination: const LatLng(7.7123, 8.5112),
        destinationLabel: 'Modern Market',
        vehicleType: 'standard',
      );

      expect(estimate.fareNgn, 1250.0);
    });
  });
}
