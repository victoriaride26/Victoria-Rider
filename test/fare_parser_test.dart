import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/core/utils/fare_parser.dart';

void main() {
  group('FareParser mirrors the driver app Ride.fromJson fare rules', () {
    test('toKobo scales Naira values in (0, 10000) and passes kobo through', () {
      expect(FareParser.toKobo(1500), 150000);
      expect(FareParser.toKobo(4170), 417000);
      expect(FareParser.toKobo(417000), 417000);
      expect(FareParser.toKobo('₦1,500'), 150000);
      expect(FareParser.toKobo('junk'), 0);
      expect(FareParser.toKobo(null), 0);
    });

    test('unwrap handles data/ride envelopes like the driver app', () {
      expect(
        FareParser.unwrap({
          'success': true,
          'data': {
            'ride': {'id': 'r1'},
          },
        })['id'],
        'r1',
      );
      expect(
        FareParser.unwrap({
          'ride': {'id': 'r2'},
        })['id'],
        'r2',
      );
      expect(
        FareParser.unwrap({
          'data': {'id': 'r3'},
        })['id'],
        'r3',
      );
      expect(FareParser.unwrap('not a map'), isEmpty);
    });

    test('estimated fare reads the nested fare object first', () {
      expect(
        FareParser.estimatedFareNgn({
          'data': {
            'fare': {
              'estimatedFare': 417000,
              'finalFare': 999000,
            },
          },
        }),
        4170.0,
      );
      expect(
        FareParser.estimatedFareNgn({
          'estimatedFare': 150000,
          'amount': 999,
        }),
        1500.0,
      );
      expect(FareParser.estimatedFareNgn({'route': {}}), isNull);
    });

    test('settled fare wins over the estimate (driver summary rule)', () {
      final payload = {
        'ride': {
          'estimatedFare': 417000,
          'ridePayment': {
            'finalAmount': 567000,
            'grossFare': 547000,
          },
        },
      };
      expect(FareParser.finalFareNgn(payload), 5670.0);

      expect(
        FareParser.finalFareNgn({
          'estimatedFare': 417000,
        }),
        4170.0,
      );

      expect(
        FareParser.finalFareNgn({
          'settledFare': 300000,
          'estimatedFare': 417000,
        }),
        3000.0,
      );

      expect(FareParser.finalFareNgn({'status': 'COMPLETED'}), isNull);
    });

    test('scalarNgn accepts numbers and numeric strings', () {
      expect(FareParser.scalarNgn(1500), 1500.0);
      expect(FareParser.scalarNgn('1500'), 1500.0);
      expect(FareParser.scalarNgn(417000), 4170.0);
      expect(FareParser.scalarNgn('junk'), isNull);
      expect(FareParser.scalarNgn(null), isNull);
    });
  });
}
