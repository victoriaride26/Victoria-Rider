import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import 'rate_driver_screen.dart';

/// R-12 — Trip Completed (Payment & Receipt).
class TripCompletedScreen extends StatelessWidget {
  const TripCompletedScreen({
    super.key,
    this.rideId,
    this.driverName,
    this.fareNgn,
  });

  final String? rideId;
  final String? driverName;
  final double? fareNgn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fareText = fareNgn != null
        ? '₦${fareNgn!.toStringAsFixed(0)}'
        : '₦1,500';
    final name = driverName ?? 'Adeola Johnson';

    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const RiderHomeShell(),
                ),
                (route) => false,
              );
            }
          },
        ),
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
                'with Victoria Travels.',
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
                    _row('PICKUP', 'Wurukum Market', theme),
                    _row('DROP-OFF', 'Modern Market', theme),
                    const Divider(height: 16, color: AppColors.outlineVariant),
                    _row('Status', 'Arrived Safely', theme),
                    const Divider(height: 16, color: AppColors.outlineVariant),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL FARE',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: AppColors.onSurfaceVariant)),
                        Text(fareText,
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.credit_card, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Payment Confirmed',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text('Driver: $name',
                                  style: const TextStyle(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Row(
                          children: const [
                            Icon(Icons.star, color: Colors.amber, size: 16),
                            SizedBox(width: 4),
                            Text('4.9 • Executive'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AppPrimaryButton(
                label: 'Rate Driver',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RateDriverScreen(
                      rideId: rideId,
                      driverName: driverName,
                    ),
                  ),
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
