import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'geocoding_result.dart';

enum SavedPlaceType {
  home,
  work,
  office,
  hospital,
  church,
  market,
  mall,
  park,
  hotel,
  school,
  other
}

extension SavedPlaceTypeExtension on SavedPlaceType {
  String get label {
    switch (this) {
      case SavedPlaceType.home:
        return 'Home';
      case SavedPlaceType.work:
        return 'Work';
      case SavedPlaceType.office:
        return 'Office';
      case SavedPlaceType.hospital:
        return 'Hospital';
      case SavedPlaceType.church:
        return 'Church';
      case SavedPlaceType.market:
        return 'Market';
      case SavedPlaceType.mall:
        return 'Mall';
      case SavedPlaceType.park:
        return 'Park';
      case SavedPlaceType.hotel:
        return 'Hotel';
      case SavedPlaceType.school:
        return 'School';
      case SavedPlaceType.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case SavedPlaceType.home:
        return Icons.home_outlined;
      case SavedPlaceType.work:
      case SavedPlaceType.office:
        return Icons.work_outline;
      case SavedPlaceType.hospital:
        return Icons.local_hospital_outlined;
      case SavedPlaceType.church:
        return Icons.church_outlined;
      case SavedPlaceType.market:
        return Icons.store_mall_directory_outlined;
      case SavedPlaceType.mall:
        return Icons.local_mall_outlined;
      case SavedPlaceType.park:
        return Icons.park_outlined;
      case SavedPlaceType.hotel:
        return Icons.hotel_outlined;
      case SavedPlaceType.school:
        return Icons.school_outlined;
      case SavedPlaceType.other:
        return Icons.place_outlined;
    }
  }
}

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.type,
    required this.placeName,
    required this.shortName,
    required this.location,
  });

  final String id;
  final SavedPlaceType type;
  final String placeName;
  final String shortName;
  final LatLng location;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'placeName': placeName,
        'shortName': shortName,
        'lat': location.latitude,
        'lng': location.longitude,
      };

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id'] as String,
      type: SavedPlaceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SavedPlaceType.other,
      ),
      placeName: json['placeName'] as String,
      shortName: json['shortName'] as String,
      location: LatLng(json['lat'] as double, json['lng'] as double),
    );
  }

  GeocodingResult toGeocodingResult() {
    return GeocodingResult(
      placeName: placeName,
      shortName: shortName,
      location: location,
    );
  }
}
