import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'payment_methods_screen.dart';
import 'transaction_history_screen.dart';

/// R-15 — Wallet Dashboard.
class WalletDashboardScreen extends StatelessWidget {
  const WalletDashboardScreen({super.key});

  static const List<_Action> _actions = [
    _Action(Icons.add_circle, 'Add Funds'),
    _Action(Icons.swap_horiz, 'Transfer'),
    _Action(Icons.card_giftcard, 'Gift Card'),
  ];

  static const List<_Activity> _activity = [
    _Activity(Icons.local_taxi, 'Ride to Wurukum', 'Oct 24, 2023 • 08:45 AM',
        '-₦1,200.00', true),
    _Activity(Icons.account_balance_wallet, 'Wallet Top-up',
        'Oct 23, 2023 • 02:15 PM', '+₦5,000.00', true),
    _Activity(Icons.local_taxi, 'Ride to High Level', 'Oct 22, 2023 • 11:30 AM',
        '-₦1,850.00', true),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiderScaffold(
      currentIndex: 2,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.menu, color: AppColors.onSurface)),
                const SizedBox(width: 8),
                Text('Wallet', style: theme.textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Balance',
                      style: TextStyle(color: AppColors.onPrimary)),
                  const SizedBox(height: 6),
                  const Text('₦12,500.00',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onPrimary)),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, size: 14,
                            color: AppColors.onPrimary),
                        SizedBox(width: 6),
                        Text('Active Account',
                            style: TextStyle(color: AppColors.onPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                for (final a in _actions)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: a == _actions.last ? 0 : 12),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(a.icon, color: AppColors.primary),
                          ),
                          const SizedBox(height: 6),
                          Text(a.label,
                              style: theme.textTheme.labelMedium,
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Payment Methods',
                    style: theme.textTheme.titleLarge),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const PaymentMethodsScreen()),
                  ),
                  child: const Text('Manage All'),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border.all(color: AppColors.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mastercard',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('•••• •••• •••• 8842',
                            style: TextStyle(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('PRIMARY',
                        style: TextStyle(color: AppColors.onPrimaryContainer)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Activity',
                    style: theme.textTheme.titleLarge),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const TransactionHistoryScreen()),
                  ),
                  child: const Text('View Full Transaction History'),
                ),
              ],
            ),
            ...[
              for (final act in _activity)
                ListTile(
                  leading: Icon(act.icon, color: AppColors.primary),
                  title: Text(act.title),
                  subtitle: Text(act.sub, style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.onSurfaceVariant)),
                  trailing: Text(act.amount,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: act.credit
                            ? AppColors.primary
                            : AppColors.onSurface,
                      )),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _Activity {
  const _Activity(this.icon, this.title, this.sub, this.amount, this.credit);
  final IconData icon;
  final String title;
  final String sub;
  final String amount;
  final bool credit;
}
