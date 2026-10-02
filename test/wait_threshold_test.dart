import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/core/utils/wait_threshold_parser.dart';

void main() {
  group('WaitThresholdParser — backend free-wait window', () {
    test('reads an explicitly named threshold from a ride status payload', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        {'freeWaitSeconds': 240},
        allowEventKeys: false,
      );

      expect(seconds, 240);
    });

    test('reads the threshold from a stop-over event payload', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        {
          'type': 'confirmation_requested',
          'waitingTimeSeconds': 180,
        },
        allowEventKeys: true,
      );

      expect(seconds, 180);
    });

    test('ignores generic wait keys on ride polling / timer:completed', () {
      // Same name, but it means *elapsed* there — must not become the
      // threshold for the next stop's dialog.
      final seconds = WaitThresholdParser.thresholdSeconds(
        {'waitingTimeSeconds': 455},
        allowEventKeys: false,
      );

      expect(seconds, isNull);
    });

    test('explicit keys win over generic ones', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        {
          'freeWaitSeconds': 300,
          'waitingTimeSeconds': 180,
        },
        allowEventKeys: true,
      );

      expect(seconds, 300);
    });

    test('rejects zero, negative and empty values', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'freeWaitSeconds': 0},
          allowEventKeys: false,
        ),
        isNull,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'freeWaitSeconds': -60},
          allowEventKeys: false,
        ),
        isNull,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'freeWaitSeconds': ''},
          allowEventKeys: false,
        ),
        isNull,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'freeWaitSeconds': null},
          allowEventKeys: false,
        ),
        isNull,
      );
    });

    test('parses numeric strings', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'freeWaitSeconds': '240'},
          allowEventKeys: false,
        ),
        240,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'waitSeconds': ' 120 '},
          allowEventKeys: true,
        ),
        120,
      );
    });

    test('finds a threshold nested in a wait config object', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        {
          'type': 'confirmation_requested',
          'wait': {'freeWaitSeconds': 420},
        },
        allowEventKeys: true,
      );

      expect(seconds, 420);
    });

    test('never treats a stop object elapsed time as the threshold', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        {
          'type': 'confirmation_requested',
          'stop': {'waitingTimeSeconds': 45},
        },
        allowEventKeys: true,
      );

      expect(seconds, isNull);
    });

    test('does accept an explicit threshold carried on a stop object', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        {
          'stop': {'freeWaitSeconds': 45},
        },
        allowEventKeys: false,
      );

      expect(seconds, 45);
    });

    test('returns null for missing or non-map payloads', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          {'fare': 100},
          allowEventKeys: false,
        ),
        isNull,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(null, allowEventKeys: true),
        isNull,
      );
      expect(
        WaitThresholdParser.thresholdSeconds('180', allowEventKeys: true),
        isNull,
      );
    });
  });

  group('WaitThresholdParser — waitingTimeFreeMinutes on timer:start', () {
    // The backend ships the free window (in MINUTES) on
    // `ride:stopover:timer:start`, which is exactly when the countdown UI
    // starts, so the "3-minute free wait" copy no longer depends on the
    // earlier estimate call.
    const timerStartPayload = {
      'rideId': 'ride-123',
      'index': 1,
      'startTime': '2026-10-02T15:50:00.000Z',
      'waitingTimeFreeMinutes': 3,
      'waitingPricePerMinute': '5000',
    };

    test('reads the minutes and scales them to seconds', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          timerStartPayload,
          allowEventKeys: true,
        ),
        180,
      );
    });

    test('is trusted on ride polling too, where event keys are not', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          timerStartPayload,
          allowEventKeys: false,
        ),
        180,
      );
    });

    test('wins over an elapsed waitingTime travelling beside it', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          {...timerStartPayload, 'waitingTime': 12},
          allowEventKeys: true,
        ),
        180,
      );
    });

    test('never mistakes the per-minute price for the threshold', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          const {'waitingPricePerMinute': '5000'},
          allowEventKeys: true,
        ),
        isNull,
      );
    });

    test('accepts string minutes and rejects zero / malformed values', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          const {'waitingTimeFreeMinutes': '1'},
          allowEventKeys: true,
        ),
        60,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(
          const {'waitingTimeFreeMinutes': 0},
          allowEventKeys: true,
        ),
        isNull,
      );
      expect(
        WaitThresholdParser.thresholdSeconds(
          const {'waitingTimeFreeMinutes': '3.5'},
          allowEventKeys: true,
        ),
        isNull,
      );
    });

    test('is read through a nested carrier as well', () {
      expect(
        WaitThresholdParser.thresholdSeconds(
          const {
            'stopover': {'waitingTimeFreeMinutes': 5},
          },
          allowEventKeys: false,
        ),
        300,
      );
    });

    test('scales into the same copy the UI already renders', () {
      final seconds = WaitThresholdParser.thresholdSeconds(
        timerStartPayload,
        allowEventKeys: true,
      )!;

      expect(WaitThresholdParser.label(seconds), '3-minute');
      expect(WaitThresholdParser.shortLabel(seconds), '3 min');
    });

    test('estimate response seeds the session fallback for the dialog', () {
      // The arrival dialog runs before `timer:start`, so the window the
      // estimate published is what it must quote.
      WaitThresholdParser.seedFromEstimate(const {
        'data': {
          'estimatedFare': 2500,
          'waitingTimeFreeMinutes': 5,
        },
      });
      expect(WaitThresholdParser.estimateSeconds, 300);

      // A response without the window never wipes a known seed.
      WaitThresholdParser.seedFromEstimate(const {'data': {'estimatedFare': 2500}});
      expect(WaitThresholdParser.estimateSeconds, 300);

      // Generic "waiting" keys on an estimate are not thresholds.
      WaitThresholdParser.estimateSeconds = null;
      WaitThresholdParser.seedFromEstimate(const {'waitingTimeSeconds': 420});
      expect(WaitThresholdParser.estimateSeconds, isNull);
    });
  });

  group('WaitThresholdParser — copy helpers', () {
    test('labels whole minutes and odd seconds', () {
      expect(WaitThresholdParser.label(180), '3-minute');
      expect(WaitThresholdParser.label(60), '1-minute');
      expect(WaitThresholdParser.label(90), '90-second');
      expect(WaitThresholdParser.label(WaitThresholdParser.fallbackSeconds), '3-minute');
    });

    test('short labels stay compact', () {
      expect(WaitThresholdParser.shortLabel(180), '3 min');
      expect(WaitThresholdParser.shortLabel(90), '90 s');
    });
  });
}
