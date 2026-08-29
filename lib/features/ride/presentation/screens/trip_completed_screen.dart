import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import 'rate_driver_screen.dart';

/// R-12 — Trip Completed (Payment).
class TripCompletedScreen extends StatelessWidget {
  const TripCompletedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Victoria'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.help_outline, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.check_circle,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Trip Completed!',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'We hope you had a pleasant executive ride experience '
                'through the city.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _row('PICKUP', 'Wurukum', theme),
                    _row('DROP-OFF', 'Modern Market', theme),
                    const Divider(height: 16, color: AppColors.outlineVariant),
                    _row('Distance', '4.2 km', theme),
                    _row('Duration', '14 mins', theme),
                    const Divider(height: 16, color: AppColors.outlineVariant),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL FARE',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                        Text('₦1,500',
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.credit_card, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Paid via Card  **** 89',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text('Adeola Johnson',
                                  style: TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Row(
                          children: const [
                            Icon(Icons.star, color: Colors.amber, size: 16),
                            SizedBox(width: 4),
                            Text('4.9 • Executive Class'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(onPressed: () {}, icon: const Icon(Icons.chat_bubble_outline)),
              const SizedBox(height: 8),
              AppPrimaryButton(
                label: 'Confirm Payment',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RateDriverScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: AppColors.onSurfaceVariant)),
          Text(value, style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}
