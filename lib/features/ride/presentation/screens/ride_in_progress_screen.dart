import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../../core/config/mapbox_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import 'trip_completed_screen.dart';

/// R-11 — Ride in Progress.
class RideInProgressScreen extends StatelessWidget {
  const RideInProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MapboxMapView(
              center: MapboxConfig.modernMarket,
              zoom: 14,
              showUserLocation: true,
              followUser: true,
              polylines: [
                Polyline(
                  points: [
                    MapboxConfig.wurukumMarket,
                    MapboxConfig.modernMarket,
                  ],
                  color: AppColors.primary,
                  strokeWidth: 4,
                ),
              ],
              markers: const [
                Marker(
                  point: MapboxConfig.wurukumMarket,
                  width: 40,
                  height: 40,
                  child: Icon(Icons.circle,
                      color: AppColors.primary, size: 18),
                ),
                Marker(
                  point: MapboxConfig.modernMarket,
                  width: 44,
                  height: 44,
                  child: Icon(Icons.location_on,
                      color: AppColors.primary, size: 40),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estimated Arrival',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('Arriving in 12 mins',
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.person,
                              color: AppColors.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Johnathan',
                                  style: theme.textTheme.titleLarge),
                              const Text('Lexus ES 350 • ABC-123-XY',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        IconButton(
                            onPressed: () {}, icon: const Icon(Icons.call)),
                        IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.chat_bubble_outline)),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Destination',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                              Text('Modern Market',
                                  style: theme.textTheme.titleLarge),
                              const Text('Old Otukpo Rd, Makurdi',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield,
                              color: AppColors.primary),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Share Trip Status')),
                          TextButton(
                              onPressed: () {},
                              child: const Text('Cancel Ride',
                                  style: TextStyle(color: AppColors.error))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimated Fare',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                        Text('₦3,450.00',
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppPrimaryButton(
                      label: 'Trip Completed',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const TripCompletedScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
