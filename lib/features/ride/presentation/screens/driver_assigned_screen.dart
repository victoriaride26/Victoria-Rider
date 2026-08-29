import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../../core/config/mapbox_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/mapbox_map_view.dart';
import 'ride_in_progress_screen.dart';

/// R-10 — Driver Assigned (en route to pickup).
class DriverAssignedScreen extends StatelessWidget {
  const DriverAssignedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('En route to pickup'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.more_vert, color: AppColors.onSurface),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MapboxMapView(
              center: MapboxConfig.wurukumMarket,
              zoom: 15,
              showUserLocation: true,
              markers: const [
                Marker(
                  point: MapboxConfig.wurukumMarket,
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
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Driver arriving in 4 mins',
                            style: theme.textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(Icons.my_location, color: AppColors.primary),
                        SizedBox(width: 12),
                        Text('Wurukum Pickup',
                            style: TextStyle(fontSize: 16)),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.primaryContainer,
                          child: Icon(Icons.person,
                              color: AppColors.onPrimaryContainer),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Terwase O.',
                                      style: theme.textTheme.titleLarge),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.verified,
                                      color: AppColors.primary, size: 18),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text('⭐ 4.8  •  120 trips completed',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('ABC-123-XY',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    const Text('Toyota Corolla • White',
                        style: TextStyle(color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(
                      'Arriving in a clean White Corolla. '
                      'Please confirm the plate number before boarding.',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.call),
                            label: const Text('Call Driver'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Message'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppPrimaryButton(
                      label: 'Track Driver',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const RideInProgressScreen()),
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
