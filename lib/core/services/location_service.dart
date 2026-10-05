import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'benue_gazetteer.dart';
import 'geoapify_geocoding_service.dart';
import 'mapbox_geocoding_service.dart';

/// Holds the rider's current position and its human-readable label.
class CurrentLocation {
  const CurrentLocation({
    required this.position,
    required this.label,
    required this.shortLabel,
  });

  final LatLng position;

  /// Full Mapbox-resolved address (or coordinate fallback).
  final String label;

  /// Short first-segment label for compact UI display.
  final String shortLabel;
}

/// Granular permission/service state returned by [LocationService.checkPermissionStatus].
enum LocationPermissionStatus {
  /// Location services (GPS/network) are turned off at the system level.
  serviceDisabled,

  /// User has permanently denied the permission — must go to Settings.
  deniedForever,

  /// User has denied the permission this session — can re-prompt.
  denied,

  /// Permission granted and service is on — ready to use.
  granted,
}

/// Provides a single-shot helper to fetch the device's GPS position and
/// resolve it to a readable address via Mapbox reverse geocoding.
///
/// Handles all permission negotiation internally so callers don't need to
/// deal with [LocationPermission] states themselves.
class LocationService {
  LocationService({MapboxGeocodingService? geocoding, GeoapifyGeocodingService? geoapify})
      : _geocoding = geocoding ?? MapboxGeocodingService(),
        _geoapify = geoapify ?? GeoapifyGeocodingService();

  final MapboxGeocodingService _geocoding;
  final GeoapifyGeocodingService _geoapify;

  void dispose() {
    _geocoding.dispose();
    _geoapify.dispose();
  }

  Future<LocationPermissionStatus> checkPermissionStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

      final permission = await Geolocator.checkPermission();
      switch (permission) {
        case LocationPermission.deniedForever:
          return LocationPermissionStatus.deniedForever;
        case LocationPermission.denied:
          return LocationPermissionStatus.denied;
        default:
          return LocationPermissionStatus.granted;
      }
    } catch (_) {
      return LocationPermissionStatus.denied;
    }
  }

  /// Fast, offline-friendly label for a GPS fix: bundled Benue gazetteer
  /// first (instant, covers the Makurdi names Mapbox/Geoapify miss), then the
  /// online providers, then a coordinate fallback. Never returns `null` for a
  /// valid fix — the dashboard pickup pill always has something to show.
  Future<CurrentLocation> labelPosition(LatLng latLng) async {
    try {
      final gazetteer = await BenueGazetteer.load();
      final local = gazetteer.reverse(latLng);
      if (local != null) {
        return CurrentLocation(
          position: latLng,
          label: local.placeName,
          shortLabel: local.shortName,
        );
      }
    } catch (_) {}
    try {
      var result = await _geocoding.reverseGeocode(latLng);
      result ??= await _geoapify.reverseGeocode(latLng);
      if (result != null) {
        return CurrentLocation(
          position: latLng,
          label: result.placeName,
          shortLabel: result.shortName,
        );
      }
    } catch (_) {}
    final coordLabel =
        '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
    return CurrentLocation(
      position: latLng,
      label: coordLabel,
      shortLabel: coordLabel,
    );
  }

  /// Instant pickup fix from the OS last-known position — no GPS wait, no
  /// permission prompt, gazetteer-labelled offline.
  ///
  /// Returns `null` when no last-known fix exists (fresh install / GPS never
  /// used). The dashboard shows this immediately, then refines it with
  /// [getCurrentLocation] in the background.
  Future<CurrentLocation?> getLastKnownLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      if (await Geolocator.checkPermission() == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return await labelPosition(LatLng(position.latitude, position.longitude));
    } catch (_) {
      return null;
    }
  }

  /// Returns the rider's current location with an address label.
  ///
  /// Returns `null` if permissions are denied or GPS is disabled.
  Future<CurrentLocation?> getCurrentLocation() async {
    try {
      // 1. Check if location services are enabled.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // 2. Check and request permission if necessary.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      // 3. Get current position.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final latLng = LatLng(position.latitude, position.longitude);

      // 4. Local-first label: bundled gazetteer (instant, Makurdi-aware),
      // then Mapbox, then Geoapify, then coordinates — never null for a fix.
      return await labelPosition(latLng);
    } catch (_) {
      return null;
    }
  }
}
