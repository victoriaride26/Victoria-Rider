class RatingTierHelper {
  /// Maps a numeric rating (1-5) to its tier label:
  /// 5 -> Excellent, 4 -> Professional, 3 -> Best Driver, 2 -> Rookie, 1 -> Under Review.
  /// Uses rounding to the nearest integer (4.5+ => 5) so decimals like 4.86 resolve to Excellent.
  static String tierLabelFor(double? rating) {
    if (rating == null) return 'New Driver';
    final bucket = rating.clamp(0.0, 5.0).round().clamp(1, 5);
    switch (bucket) {
      case 5:
        return 'Excellent';
      case 4:
        return 'Professional';
      case 3:
        return 'Best Driver';
      case 2:
        return 'Rookie';
      case 1:
      default:
        return 'Under Review';
    }
  }
}
