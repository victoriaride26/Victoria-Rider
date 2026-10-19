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

    test('settled fare reads top-level finalFare/grossFare (PAYMENT_PENDING broadcasts)', () {
      // Backend now emits grossFare/finalFare/finalAmount at the top level of
      // ride:state PAYMENT_PENDING, ride:fare:updated, /rides/current and
      // /rides/:id/status — with no ridePayment object required.
      expect(
        FareParser.finalFareNgn({
          'status': 'PAYMENT_PENDING',
          'grossFare': 557000,
          'finalFare': 557000,
          'waitingCharge': 400000,
          'estimatedFare': 157000,
        }),
        5570.0,
      );
      expect(
        FareParser.finalFareNgn({'finalAmount': 557000}),
        5570.0,
      );
      expect(
        FareParser.finalFareNgn({
          'data': {'finalFare': 557000},
        }),
        5570.0,
      );
      // ridePayment still wins when both are present.
      expect(
        FareParser.finalFareNgn({
          'finalFare': 500000,
          'ridePayment': {'finalAmount': 557000},
        }),
        5570.0,
      );
    });

    test('waitingChargeKobo reads top-level, ridePayment and fare objects', () {
      expect(
        FareParser.waitingChargeKobo({
          'status': 'PAYMENT_PENDING',
          'finalFare': 557000,
          'waitingCharge': 400000,
        }),
        400000,
      );
      expect(
        FareParser.waitingChargeKobo({
          'ridePayment': {'waitingCharge': 400000},
        }),
        400000,
      );
      expect(
        FareParser.waitingChargeKobo({'extraCharge': 25000}),
        25000,
      );
      expect(FareParser.waitingChargeKobo({'status': 'COMPLETED'}), 0);
      expect(
        FareParser.waitingChargeNgn({'waitingCharge': 400000}),
        4000.0,
      );
    });

    test('scalarNgn resolves final amounts out of fare-update event maps', () {
      expect(
        FareParser.scalarNgn({
          'rideId': 'r1',
          'finalFare': 557000,
          'grossFare': 557000,
        }),
        5570.0,
      );
      expect(
        FareParser.scalarNgn({'estimatedFare': 157000}),
        1570.0,
      );
    });
  });
}
