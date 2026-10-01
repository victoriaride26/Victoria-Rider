/// Canonical fare parsing for the rider app.
///
/// This is a 1:1 mirror of the driver app's fare logic
/// (`victoria_rides_driver/lib/features/ride/data/ride.dart` → `Ride._kobo()`
/// and the `estimatedFareKoba` / `settledFareKoba` branches of
/// `Ride.fromJson()`), so both apps read the exact same number out of the
/// exact same backend payload.
///
/// Rules (do not diverge from the driver app):
///  * `toKobo` — a value in `(0, 10000)` is Naira and is scaled to kobo;
///    anything else is already kobo. Non-numeric junk is stripped first.
///  * `unwrap` — `{data:{ride:{…}}}` → `ride`, `{ride:{…}}` → `ride`,
///    `{data:{…}}` → `data`, otherwise the payload itself.
///  * estimated fare precedence — nested `fare` object wins and reads
///    `estimatedFare → finalFare → amount → total → fare`; flat payloads read
///    `estimatedFare → estimated_fare → fare → fareAmount → amount`.
///  * settled fare precedence — `ridePayment.finalAmount → ridePayment.grossFare`
///    → `settledFare`; `null` when the payload carries no settled amount.
class FareParser {
  FareParser._();

  /// Converts a raw fare value (Naira, kobo, or a numeric string such as
  /// `"₦1,500"`) into kobo using the driver app's `_kobo()` heuristic.
  static int toKobo(dynamic value) {
    double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
    }
    if (parsed == null) return 0;
    if (parsed > 0 && parsed < 10000) return (parsed * 100).round();
    return parsed.round();
  }

  /// Unwraps `{data:{ride:{…}}}` / `{ride:{…}}` / `{data:{…}}` envelopes the
  /// same way `Ride.fromJson()` does.
  static Map<String, dynamic> unwrap(dynamic payload) {
    if (payload is! Map) return const <String, dynamic>{};
    if (payload['data'] is Map && (payload['data'] as Map)['ride'] is Map) {
      return Map<String, dynamic>.from(
        (payload['data'] as Map)['ride'] as Map,
      );
    }
    if (payload['ride'] is Map) {
      return Map<String, dynamic>.from(payload['ride'] as Map);
    }
    if (payload['data'] is Map) {
      return Map<String, dynamic>.from(payload['data'] as Map);
    }
    return Map<String, dynamic>.from(payload);
  }

  /// Estimated fare in kobo (0 when the payload carries none).
  static int estimatedFareKobo(dynamic payload) {
    final json = unwrap(payload);
    final fareObj = json['fare'];
    if (fareObj is Map) {
      return toKobo(
        fareObj['estimatedFare'] ??
            fareObj['finalFare'] ??
            fareObj['amount'] ??
            fareObj['total'] ??
            fareObj['fare'],
      );
    }
    return toKobo(
      json['estimatedFare'] ??
          json['estimated_fare'] ??
          json['fare'] ??
          json['fareAmount'] ??
          json['amount'],
    );
  }

  /// Settled (final) fare in kobo, or `null` when none is present.
  static int? settledFareKobo(dynamic payload) {
    final json = unwrap(payload);
    final payment = json['ridePayment'];
    if (payment is Map) {
      return toKobo(payment['finalAmount'] ?? payment['grossFare']);
    }
    if (json['settledFare'] != null) return toKobo(json['settledFare']);
    return null;
  }

  /// Estimated fare in Naira; `null` when the payload carries no usable fare.
  static double? estimatedFareNgn(dynamic payload) {
    final kobo = estimatedFareKobo(payload);
    return kobo > 0 ? kobo / 100.0 : null;
  }

  /// Settled fare in Naira; `null` when the payload carries none.
  static double? settledFareNgn(dynamic payload) {
    final kobo = settledFareKobo(payload);
    return (kobo != null && kobo > 0) ? kobo / 100.0 : null;
  }

  /// The amount both apps show for a ride: settled fare when the backend has
  /// one, otherwise the backend-calculated estimate (driver trip summary rule).
  static double? finalFareNgn(dynamic payload) =>
      settledFareNgn(payload) ?? estimatedFareNgn(payload);

  /// Converts an already-extracted scalar fare (num or numeric string).
  static double? scalarNgn(dynamic raw) {
    if (raw is Map) return estimatedFareNgn(raw);
    final kobo = toKobo(raw);
    return kobo > 0 ? kobo / 100.0 : null;
  }
}
