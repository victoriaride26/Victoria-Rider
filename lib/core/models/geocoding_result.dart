import 'package:latlong2/latlong.dart';

/// A single geocoding result.
class GeocodingResult {
  const GeocodingResult({
    required this.placeName,
    required this.shortName,
    required this.location,
  });

  /// Full formatted place name (e.g. "Wurukum Market, Makurdi, Benue, Nigeria").
  final String placeName;

  /// Short display name — the first segment before the first comma.
  final String shortName;

  /// Geographic coordinates.
  final LatLng location;
}
