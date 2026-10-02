/// Reads the backend's stop-over free-wait window (the "3-minute free wait")
/// out of a socket payload or `GET /rides/{id}` status payload.
///
/// The value is never assumed: [thresholdSeconds] returns `null` until a
/// payload actually carries one, and callers keep a display-only fallback
/// (180s) for that case.
class WaitThresholdParser {
  const WaitThresholdParser._();

  /// Last-resort copy for when no payload ever supplied a threshold.
  static const int fallbackSeconds = 180;

  /// Session seed captured from `POST /rides/estimate` — historically the only
  /// place the backend published the free window. The arrival dialog fires
  /// *before* `ride:stopover:timer:start`, so this keeps that dialog's copy
  /// backend-driven instead of a blind 180s guess.
  static int? estimateSeconds;

  /// Remembers the free window from an estimate response. No-op when the
  /// response carries none, and it never overwrites a known value with null.
  static void seedFromEstimate(dynamic payload) {
    // Only explicitly named keys: an estimate has no *elapsed* wait to
    // confuse them with, but it may carry unrelated "waiting" estimates.
    final seconds = thresholdSeconds(payload, allowEventKeys: false);
    if (seconds != null) estimateSeconds = seconds;
  }

  /// Keys that explicitly name the free-wait window. Safe to read from any
  /// payload, including ride-status polling where "waiting time" means
  /// *elapsed*.
  static const List<String> explicitKeys = [
    'freeWaitSeconds',
    'free_wait_seconds',
    'freeWait',
    'waitThresholdSeconds',
    'waitThreshold',
    'wait_threshold_seconds',
    'waitTimeThreshold',
    'waitTimeThresholdSeconds',
    'graceSeconds',
    'gracePeriodSeconds',
    'stopFreeWaitSeconds',
    'stopoverFreeWaitSeconds',
  ];

  /// Keys whose value is expressed in **minutes** and must be scaled ×60.
  /// `waitingTimeFreeMinutes` ships on `ride:stopover:timer:start` — the exact
  /// moment the rider app begins counting down — and may also arrive on the
  /// ride-status payload, so it is trusted regardless of [allowEventKeys].
  static const List<String> minutesKeys = [
    'waitingTimeFreeMinutes',
    'waitingTimeFreeMinute',
    'freeWaitMinutes',
    'freeWaitTimeMinutes',
    'waitThresholdMinutes',
    'graceMinutes',
  ];

  /// Generic wait keys used inside stop-over timer events
  /// (`confirmation_requested` / `confirmed` / `timer:start`), where they
  /// carry the free-wait window. Same names mean *elapsed* time in ride
  /// polling and `timer:completed`, so those paths must pass
  /// `allowEventKeys: false`.
  static const List<String> eventKeys = [
    'waitingTimeSeconds',
    'waitingTime',
    'waitSeconds',
  ];

  /// Nested carriers of the threshold, e.g. `{ wait: {...} }` or `{ stop: {...} }`.
  static const List<String> _carriers = [
    'wait',
    'waitConfig',
    'waitTime',
    'waitThreshold',
    'freeWait',
    'config',
    'pricingSnapshot',
    'data',
    'payload',
    'result',
    'stop',
    'stopover',
    'stopOver',
  ];

  /// Stop-shaped carriers: their `waitingTimeSeconds` is elapsed time, so only
  /// the explicitly threshold-named keys are trusted inside them.
  static bool _isStopCarrier(String key) =>
      key == 'stop' || key == 'stopover' || key == 'stopOver';

  /// The free-wait window in seconds, or `null` when the payload has none.
  static int? thresholdSeconds(
    dynamic payload, {
    required bool allowEventKeys,
  }) {
    if (payload is! Map) return null;
    for (final key in explicitKeys) {
      final seconds = _positiveCount(payload[key]);
      if (seconds != null) return seconds;
    }
    // Minute-valued keys first: they are explicit "free wait" names, and a
    // `waitingTime` travelling beside them would mean elapsed time instead.
    for (final key in minutesKeys) {
      final minutes = _positiveCount(payload[key]);
      if (minutes != null) return minutes * 60;
    }
    if (allowEventKeys) {
      for (final key in eventKeys) {
        final seconds = _positiveCount(payload[key]);
        if (seconds != null) return seconds;
      }
    }
    for (final key in _carriers) {
      if (payload[key] is! Map) continue;
      final seconds = thresholdSeconds(
        payload[key],
        allowEventKeys: allowEventKeys && !_isStopCarrier(key),
      );
      if (seconds != null) return seconds;
    }
    return null;
  }

  /// Non-positive values are elapsed placeholders, not thresholds.
  static int? _positiveCount(dynamic raw) {
    if (raw is num) {
      final value = raw.toInt();
      return value > 0 ? value : null;
    }
    if (raw is String) {
      final value = int.tryParse(raw.trim());
      if (value != null && value > 0) return value;
    }
    return null;
  }

  /// "3-minute" / "1-minute" / "90-second" — for sentences such as
  /// "…start the 3-minute free wait".
  static String label(int seconds) => seconds % 60 == 0
      ? '${seconds ~/ 60}-minute'
      : '$seconds-second';

  /// "3 min" / "90 s" — for compact UI such as the live wait-timer pill.
  static String shortLabel(int seconds) =>
      seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s';
}
