import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'fare_estimate_screen.dart';

/// R-07 — Destination Search.
class DestinationSearchScreen extends StatelessWidget {
  const DestinationSearchScreen({super.key});

  static const List<_PlaceRow> _saved = [
    _PlaceRow(Icons.home, 'Home', 'N.O.K Complex, Benue'),
    _PlaceRow(Icons.work, 'Office', 'Secretariat, Makurdi'),
  ];

  static const List<_PlaceRow> _recent = [
    _PlaceRow(Icons.history, 'Benue State University', 'Main Campus Road, Makurdi'),
    _PlaceRow(Icons.history, 'Tito Gate', 'High Level, Makurdi'),
    _PlaceRow(Icons.history, 'Aper Aku Stadium', 'Police Barracks Road'),
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
            const AppBackButton(),
            const SizedBox(height: 8),
            Text('Destination Search',
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.my_location, color: AppColors.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('📍 Current Location - Wurukum',
                        style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Where to?',
                hintStyle: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.outlineVariant),
                prefixIcon: const Icon(Icons.search, color: AppColors.outline),
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Saved Places',
                    style: theme.textTheme.titleLarge),
                TextButton(onPressed: () {}, child: const Text('VIEW ALL')),
              ],
            ),
            ...[
              for (final p in _saved)
                _placeTile(p, theme, context),
            ],
            const SizedBox(height: 8),
            Text('Recent Destinations',
                style: theme.textTheme.titleLarge),
            ...[
              for (final p in _recent)
                _placeTile(p, theme, context),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.explore, color: AppColors.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Explore Local Rides',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: AppColors.onPrimaryContainer)),
                        const SizedBox(height: 2),
                        Text('12 drivers nearby in Makurdi',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.onPrimaryContainer)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeTile(_PlaceRow p, ThemeData theme, BuildContext context) {
    return ListTile(
      leading: Icon(p.icon, color: AppColors.primary),
      title: Text(p.title),
      subtitle: Text(p.subtitle,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: AppColors.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right),
      contentPadding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FareEstimateScreen()),
      ),
    );
  }
}

class _PlaceRow {
  const _PlaceRow(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}
