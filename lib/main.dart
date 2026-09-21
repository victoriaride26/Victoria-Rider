import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/constants/app_constants.dart';
import 'core/services/background_location_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/notification_tray_service.dart';
import 'core/services/places_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the gitignored Mapbox token (see `.env.example`).
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Missing .env is fine — the map falls back to OpenStreetMap tiles.
  }

  // Notifications → system tray. Permission is requested here once;
  // if denied we continue — in-app list still works.
  try {
    await NotificationTrayService.instance.init();
  } catch (_) {
    // Tests / unsupported platforms — ignore.
  }

  // Push notifications (Firebase Cloud Messaging).
  try {
    unawaited(FcmService.instance.init());
  } catch (_) {
    // Tests / unsupported platforms — ignore.
  }

  // Warm up background location permission check without starting tracking.
  unawaited(BackgroundLocationService.instance.ensurePermission());

  await PlacesStorageService.instance.init();

  runApp(const VTRidesApp());
}

class VTRidesApp extends StatelessWidget {
  const VTRidesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
