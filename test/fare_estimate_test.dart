import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vtrides/features/ride/data/ride_request_service.dart';

void main() {
  group('Fare Estimation Calculation & Multipliers', () {
    test('Vehicle multipliers match backend rules', () {
      expect(RideRequestService.vehicleMultiplier('standard'), 1.0);
      expect(RideRequestService.vehicleMultiplier('comfort'), 1.5);
      expect(RideRequestService.vehicleMultiplier('premium'), 1.5);
      expect(RideRequestService.vehicleMultiplier('xl'), 1.5);
      expect(RideRequestService.vehicleMultiplier('bike'), 0.5);
      expect(RideRequestService.vehicleMultiplier('motorcycle'), 0.5);
    });

    test('Local fallback calculates 500 NGN base + 150 NGN/km with multipliers', () async {
      final service = RideRequestService();
      addTearDown(service.dispose);

      // 0 distance fallback (clamp to base fare * multiplier)
      final zeroEstStandard = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Point A',
        destination: const LatLng(7.7322, 8.5245),
        destinationLabel: 'Point A',
        vehicleType: 'standard',
      );
      expect(zeroEstStandard.fareNgn, 500.0);

      final zeroEstPremium = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Point A',
        destination: const LatLng(7.7322, 8.5245),
        destinationLabel: 'Point A',
        vehicleType: 'premium',
      );
      expect(zeroEstPremium.fareNgn, 750.0); // 500 * 1.5

      final zeroEstBike = await service.estimate(
        pickup: const LatLng(7.7322, 8.5245),
        pickupLabel: 'Point A',
        destination: const LatLng(7.7322, 8.5245),
        destinationLabel: 'Point A',
        vehicleType: 'bike',
      );
      expect(zeroEstBike.fareNgn, 250.0); // 500 * 0.5
    });
  });
}
