import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/image_url_helper.dart';

/// A robust, elegantly styled avatar for displaying driver profile photos.
///
/// Features:
/// - Normalizes relative and local URLs to full backend URLs.
/// - Gracefully falls back to a branded person icon on loading error or 404.
/// - Shows a subtle loading spinner while the image is being downloaded.
class DriverAvatar extends StatelessWidget {
  const DriverAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 26,
  });

  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final normalized = ImageUrlHelper.normalize(imageUrl);
    final size = radius * 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: AppColors.primaryContainer,
        child: (normalized != null && normalized.isNotEmpty)
            ? Image.network(
                normalized,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person,
                    size: radius * 1.15,
                    color: AppColors.onPrimaryContainer,
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: radius * 0.8,
                      height: radius * 0.8,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  );
                },
              )
            : Icon(
                Icons.person,
                size: radius * 1.15,
                color: AppColors.onPrimaryContainer,
              ),
      ),
    );
  }
}
