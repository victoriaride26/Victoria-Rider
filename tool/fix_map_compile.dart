import 'dart:io';

void main() {
  final path = 'c:/flutter_projects/victoria_rides/lib/core/widgets/mapbox_map_view.dart';
  final file = File(path);
  if (!file.existsSync()) return;
  
  var content = file.readAsStringSync();
  
  content = content.replaceAll('_mapController.camera', '_controller.camera');
  content = content.replaceAll('_mapController.move', '_controller.move');
  content = content.replaceAll('_mapController.mapEventStream', '_controller.mapEventStream');
  
  // Fix AppColors missing import
  if (content.contains('AppColors.') && !content.contains('app_colors.dart')) {
    content = content.replaceFirst(
      "import 'package:flutter/material.dart';",
      "import 'package:flutter/material.dart';\nimport '../theme/app_colors.dart';"
    );
  }
  
  // Fix constant value error around floating action button (const Icon -> AppColors is not const? actually const Icon(..., color: AppColors.primary) might be fine if AppColors.primary is const, but sometimes it isn't)
  content = content.replaceAll('const Icon(Icons.my_location, color: AppColors.primary)', 'Icon(Icons.my_location, color: AppColors.primary)');
  
  file.writeAsStringSync(content);
  print('Fixed mapbox_map_view.dart');
}
