import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
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
  });
}
