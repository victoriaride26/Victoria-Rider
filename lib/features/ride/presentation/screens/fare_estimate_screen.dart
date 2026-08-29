import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import 'searching_for_driver_screen.dart';

/// R-08 — Fare Estimate & Ride Confirmation.
class FareEstimateScreen extends StatelessWidget {
  const FareEstimateScreen({super.key});

  static const List<_PayMethod> _methods = [
    _PayMethod(Icons.credit_card, 'Card', true),
    _PayMethod(Icons.payments_outlined, 'Cash', false),
    _PayMethod(Icons.account_balance_wallet, 'Wallet', false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Fare Estimate'),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _routeRow(Icons.trip_origin, 'Wurukum Market',
                        theme.textTheme.titleLarge!),
                    const Divider(height: 24, color: AppColors.outlineVariant),
                    _routeRow(Icons.location_on, 'Modern Market',
                        theme.textTheme.titleLarge!),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('₦1,500',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: AppColors.primary)),
                  const Spacer(),
                  const Text('4.2 km',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Text('•', style: TextStyle(color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  const Text('8 mins',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 24),
              Text('Payment Method',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              ...[
                for (final m in _methods)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: m.selected
                          ? AppColors.primaryContainer
                          : AppColors.surfaceContainerLowest,
                      border: Border.all(
                        color: m.selected
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(m.icon, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Text(m.label, style: theme.textTheme.titleLarge),
                        const Spacer(),
                        if (m.selected)
                          const Icon(Icons.check_circle,
                              color: AppColors.primary),
                      ],
                    ),
                  ),
              ],
              const Spacer(),
              AppPrimaryButton(
                label: 'Confirm Ride',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const SearchingForDriverScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeRow(IconData icon, String label, TextStyle style) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Text(label, style: style),
      ],
    );
  }
}

class _PayMethod {
  const _PayMethod(this.icon, this.label, this.selected);
  final IconData icon;
  final String label;
  final bool selected;
}
