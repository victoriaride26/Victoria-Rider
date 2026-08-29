import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// R-14 — Ride History.
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  int _tab = 0;

  static const List<String> _tabs = ['All', 'Completed', 'Cancelled'];

  static const List<_Ride> _rides = [
    _Ride('Oct 24, 10:30 AM', '₦1,500', 'Wurukum Roundabout',
        'Modern Market', 'Terwase O.', true),
    _Ride('Oct 22, 02:15 PM', '₦2,800', 'Benue State University',
        'North Bank', 'Agaba M.', true),
    _Ride('Oct 21, 08:45 AM', '₦0', 'High Level', 'Apir Road', '---', false),
    _Ride('Oct 19, 06:10 PM', '₦2,100', 'SRS Junction',
        'Tiers 1 Hotel', 'Umaru F.', true),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiderScaffold(
      currentIndex: 1,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const AppBackButton(),
            const SizedBox(height: 8),
            Text('Ride History', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  for (int i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _tab = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _tab == i
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _tabs[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _tab == i
                                  ? AppColors.onPrimary
                                  : AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...[
              for (final r in _rides)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    border: Border.all(color: AppColors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        r.completed ? Icons.directions_car : Icons.cancel_outlined,
                        color: r.completed
                            ? AppColors.primary
                            : AppColors.error,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.date,
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: AppColors.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Text('${r.from} → ${r.to}',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.person,
                                    size: 14, color: AppColors.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(r.driver,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: AppColors.onSurfaceVariant)),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: r.completed
                                        ? AppColors.primaryContainer
                                        : AppColors.errorContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    r.completed ? 'Completed' : 'Cancelled',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: r.completed
                                          ? AppColors.onPrimaryContainer
                                          : AppColors.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(r.fare,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ride {
  const _Ride(this.date, this.fare, this.from, this.to, this.driver, this.completed);
  final String date;
  final String fare;
  final String from;
  final String to;
  final String driver;
  final bool completed;
}
