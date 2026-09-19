import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:vtrides/core/network/api_client.dart';
import 'package:vtrides/core/services/location_service.dart';
import 'package:vtrides/core/models/geocoding_result.dart';

import 'package:vtrides/features/ride/data/ride_request_service.dart';
import 'package:vtrides/features/ride/presentation/widgets/ride_request_sheet.dart';

void main() {
  group('RideRequestService unit tests', () {
    test('requestRide formats payload matching backend OpenAPI spec', () async {
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/rides/request')) {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'success': true, 'data': {'rideId': 'ride_abc_123'}}),
            201,
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      const estimate = RideEstimate(
        pickupLabel: 'Wurukum Roundabout',
        destinationLabel: 'High Level Market',
        pickupLatLng: LatLng(7.7322, 8.5245),
        destinationLatLng: LatLng(7.7300, 8.5300),
        distanceKm: 2.5,
        durationMinutes: 6,
        fareNgn: 875.0,
      );

      final rideId = await service.requestRide(
        estimate: estimate,
        paymentMethod: 'cash',
        vehicleType: 'standard',
      );

      expect(rideId, 'ride_abc_123');
      expect(capturedBody, isNotNull);
      // Verify dropoffLocation is present (backend requirement)
      expect(capturedBody!['dropoffLocation'], isNotNull);
      expect(capturedBody!['dropoffLocation']['address'], 'High Level Market');
      // Verify uppercase enums
      expect(capturedBody!['vehicleType'], 'STANDARD');
      expect(capturedBody!['paymentMethod'], 'CASH');
    });

    test('requestRide maps comfort to PREMIUM and wallet to WALLET', () async {
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'success': true, 'rideId': 'ride_xyz_789'}),
          200,
        );
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      const estimate = RideEstimate(
        pickupLabel: 'Point A',
        destinationLabel: 'Point B',
        pickupLatLng: LatLng(7.7322, 8.5245),
        destinationLatLng: LatLng(7.7300, 8.5300),
        distanceKm: 3.0,
        durationMinutes: 8,
        fareNgn: 1200.0,
      );

      final rideId = await service.requestRide(
        estimate: estimate,
        paymentMethod: 'wallet',
        vehicleType: 'comfort',
      );

      expect(rideId, 'ride_xyz_789');
      expect(capturedBody!['vehicleType'], 'PREMIUM');
      expect(capturedBody!['paymentMethod'], 'WALLET');
    });

    test('requestRide throws ApiException with backend error message on failure', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'message': 'Insufficient wallet balance'}),
          400,
        );
      });

      ApiClient.setTestClient(mockClient);
      final service = RideRequestService();
      const estimate = RideEstimate(
        pickupLabel: 'Point A',
        destinationLabel: 'Point B',
        pickupLatLng: LatLng(7.7322, 8.5245),
        destinationLatLng: LatLng(7.7300, 8.5300),
        distanceKm: 3.0,
        durationMinutes: 8,
        fareNgn: 1200.0,
      );

      expect(
        () => service.requestRide(
          estimate: estimate,
          paymentMethod: 'wallet',
          vehicleType: 'standard',
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Insufficient wallet balance',
        )),
      );
    });
  });

  group('RideRequestSheet widget feedback tests', () {
    testWidgets('shows visible error banner in sheet when request fails', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showRideRequestSheet(
                    context,
                    destination: const GeocodingResult(
                      placeName: 'High Level, Makurdi',
                      shortName: 'High Level',
                      location: LatLng(7.7300, 8.5300),
                    ),
                    currentLocation: const CurrentLocation(
                      position: LatLng(7.7322, 8.5245),
                      label: 'Wurukum Roundabout, Makurdi',
                      shortLabel: 'Wurukum',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));

      final confirmBtn = find.textContaining('Confirm Ride');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      // Let the asynchronous request complete and error state update
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Sheet is STILL open (not popped into void)
      expect(find.byType(RideRequestSheet), findsOneWidget);

      // Visible error banner is rendered with feedback
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });
  });
}
