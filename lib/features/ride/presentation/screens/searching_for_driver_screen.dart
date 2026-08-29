import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';

/// R-09 — Searching for Driver.
class SearchingForDriverScreen extends StatelessWidget {
  const SearchingForDriverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Searching for Driver'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car,
                    size: 56, color: AppColors.onPrimaryContainer),
              ),
              const SizedBox(height: 28),
              Text('Finding your Victoria driver nearby...',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Matching with the best route for your premium journey.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Text('Live Search',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(width: 12),
                    Text('Est. 2 mins',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              const Spacer(),
              AppPrimaryButton(
                label: 'Cancel Request',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
