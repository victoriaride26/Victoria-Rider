import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../ride/presentation/screens/destination_search_screen.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// R-06 — Home: greeting, destination search entry, saved places, recent rides.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const List<_SavedPlace> _savedPlaces = [
    _SavedPlace(Icons.home, 'Home', 'High-Level, Makurdi'),
    _SavedPlace(Icons.work, 'Work', 'Federal Secretariat'),
  ];

  static const List<_RecentRide> _recentRides = [
    _RecentRide('Modern Market Makurdi', 'South-Bank, Makurdi'),
    _RecentRide('Apir Toll Gate', 'Otukpo Road'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiderScaffold(
      currentIndex: 0,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.menu, color: AppColors.onSurface),
                ),
                const Spacer(),
                const Icon(Icons.shield_outlined,
                    color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 8),
            Text('Hello, Victoria',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Where are we going today?',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 20),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const DestinationSearchScreen()),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  border: Border.all(color: AppColors.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: AppColors.primary),
                    SizedBox(width: 12),
                    Text('Where to?',
                        style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                for (final p in _savedPlaces)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                          right: p == _savedPlaces.first ? 12 : 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(p.icon, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.label,
                                    style: theme.textTheme.labelLarge),
                                const SizedBox(height: 2),
                                Text(p.subtitle,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color: AppColors.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Rides', style: theme.textTheme.titleLarge),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...[
              for (final r in _recentRides)
                ListTile(
                  leading: const Icon(Icons.history, color: AppColors.primary),
                  title: Text(r.title),
                  subtitle: Text(r.subtitle,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant)),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedPlace {
  const _SavedPlace(this.icon, this.label, this.subtitle);
  final IconData icon;
  final String label;
  final String subtitle;
}

class _RecentRide {
  const _RecentRide(this.title, this.subtitle);
  final String title;
  final String subtitle;
}
