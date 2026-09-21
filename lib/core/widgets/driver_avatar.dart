import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/image_url_helper.dart';

/// A robust, elegantly styled avatar for displaying driver profile photos.
///
/// Features:
/// - Normalizes relative and local URLs to full backend URLs.
/// - Shows driver's initial letter as a gradient fallback when no photo is available.
/// - Shows a subtle loading spinner while the image is being downloaded.
/// - Gracefully falls back to a person icon on error if [driverName] is also null.
class DriverAvatar extends StatelessWidget {
  const DriverAvatar({
    super.key,
    required this.imageUrl,
    this.driverName,
    this.radius = 26,
  });

  final String? imageUrl;

  /// Optional driver name used to show the first initial when [imageUrl] is absent.
  final String? driverName;
  final double radius;

  String? get _initial {
    final name = (driverName ?? '').trim();
    if (name.isEmpty) return null;
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = ImageUrlHelper.normalize(imageUrl);
    final size = radius * 2;
    final initial = _initial;

    Widget fallback;
    if (initial != null) {
      // Gradient initial-letter avatar
      fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    } else {
      fallback = Container(
        width: size,
        height: size,
        color: AppColors.primaryContainer,
        child: Icon(
          Icons.person,
          size: radius * 1.15,
          color: AppColors.onPrimaryContainer,
        ),
      );
    }

    if (normalized == null || normalized.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: fallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          normalized,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: size,
              height: size,
              color: AppColors.primaryContainer,
              alignment: Alignment.center,
              child: SizedBox(
                width: radius * 0.7,
                height: radius * 0.7,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
