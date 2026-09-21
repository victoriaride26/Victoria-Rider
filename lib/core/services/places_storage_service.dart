import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/geocoding_result.dart';
import '../models/saved_place.dart';

class PlacesStorageService {
  PlacesStorageService._();
  static final instance = PlacesStorageService._();

  static const String _savedPlacesKey = 'saved_places';
  static const String _recentDestinationsKey = 'recent_destinations';
  static const int _maxRecentDestinations = 5;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // --- Saved Places ---

  List<SavedPlace> getSavedPlaces() {
    if (_prefs == null) return [];
    final jsonList = _prefs!.getStringList(_savedPlacesKey) ?? [];
    return jsonList.map((str) => SavedPlace.fromJson(jsonDecode(str))).toList();
  }

  Future<void> addSavedPlace(SavedPlace place) async {
    await init();
    final places = getSavedPlaces();
    
    // Check if type already exists and remove it to replace (e.g. only 1 'Home')
    places.removeWhere((p) => p.type == place.type && p.type != SavedPlaceType.other);
    // Also remove exact same location
    places.removeWhere((p) => p.location.latitude == place.location.latitude && p.location.longitude == place.location.longitude);
    
    places.add(place);
    final jsonList = places.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs!.setStringList(_savedPlacesKey, jsonList);
  }

  Future<void> removeSavedPlace(String id) async {
    await init();
    final places = getSavedPlaces();
    places.removeWhere((p) => p.id == id);
    final jsonList = places.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs!.setStringList(_savedPlacesKey, jsonList);
  }

  // --- Recent Destinations ---

  List<GeocodingResult> getRecentDestinations() {
    if (_prefs == null) return [];
    final jsonList = _prefs!.getStringList(_recentDestinationsKey) ?? [];
    return jsonList.map((str) {
      final map = jsonDecode(str);
      return GeocodingResult(
        placeName: map['placeName'] as String,
        shortName: map['shortName'] as String,
        location: LatLng(map['lat'] as double, map['lng'] as double),
      );
    }).toList();
  }

  Future<void> addRecentDestination(GeocodingResult result) async {
    await init();
    final dests = getRecentDestinations();
    
    // Remove if it already exists (to bump it to the top)
    dests.removeWhere((d) => 
      d.location.latitude == result.location.latitude && 
      d.location.longitude == result.location.longitude
    );
    
    // Insert at beginning
    dests.insert(0, result);
    
    // Cap at max
    if (dests.length > _maxRecentDestinations) {
      dests.removeRange(_maxRecentDestinations, dests.length);
    }
    
    final jsonList = dests.map((d) => jsonEncode({
      'placeName': d.placeName,
      'shortName': d.shortName,
      'lat': d.location.latitude,
      'lng': d.location.longitude,
    })).toList();
    
    await _prefs!.setStringList(_recentDestinationsKey, jsonList);
  }
}
