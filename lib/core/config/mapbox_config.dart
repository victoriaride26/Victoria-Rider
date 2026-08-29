import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';

/// Mapbox configuration for the Victoria Rides rider app.
class MapboxConfig {
  MapboxConfig._();

  /// Public (publishable) Mapbox access token, loaded from the gitignored
  /// `.env` file (`MAPBOX_TOKEN`). Falls back to an empty string so the
  /// map gracefully degrades to OpenStreetMap tiles when unset.
  static String get accessToken => dotenv.env['MAPBOX_TOKEN'] ?? '';

  /// Mapbox style used for the rider experience.
  static const String styleId = 'navigation-preview-day-v4';

  /// Raster tile URL template (Mapbox style API, works with the public token).
  static String get styleUrl =>
      'https://api.mapbox.com/styles/v1/mapbox/$styleId/tiles/256/{z}/{x}/{y}?access_token=$accessToken';

  /// Makurdi city center (Benue State, Nigeria).
  static const LatLng makurdiCenter = LatLng(7.7337, 8.5211);

  /// Wurukum Market (pickup).
  static const LatLng wurukumMarket = LatLng(7.7322, 8.5245);

  /// Modern Market, Makurdi (drop-off).
  static const LatLng modernMarket = LatLng(7.7261, 8.5180);

  /// Tarka Foundation, High Level (pickup for the navigate flow).
  static const LatLng tarkaFoundation = LatLng(7.7411, 8.5166);
}