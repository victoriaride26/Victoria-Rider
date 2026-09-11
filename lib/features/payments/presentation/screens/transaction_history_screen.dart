import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// R-17 — Transaction History.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  int _tab = 0;

  static const List<String> _tabs = ['All', 'Rides', 'Funding', 'Refunds'];

  static const List<_Txn> _txns = [
    _Txn(Icons.directions_car, 'Ride to Modern Market',
        'Oct 24, 2023 • 02:45 PM', '-₦4,500.00', 'Completed'),
    _Txn(Icons.account_balance_wallet, 'Wallet Funding',
        'Oct 23, 2023 • 10:12 AM', '+₦25,000.00', 'Completed'),
    _Txn(Icons.commute, 'Executive Ride: Ikeja',
        'Oct 22, 2023 • 06:15 PM', '-₦8,200.00', 'Pending'),
    _Txn(Icons.replay, 'Refund: Trip #2940',
        'Oct 21, 2023 • 11:30 AM', '+₦1,200.00', 'Completed'),
    _Txn(Icons.local_taxi, 'Ride to Victoria Island',
        'Oct 15, 2023 • 08:00 AM', '-₦6,000.00', 'Completed'),
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
                const AppBackButton(),
                const SizedBox(width: 8),
                Text('Transactions', style: theme.textTheme.headlineMedium),
              ],
            ),
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
            Text('Recent Transactions',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ...[
              for (final t in _txns)
                ListTile(
                  leading: Icon(t.icon, color: AppColors.primary),
                  title: Text(t.title),
                  subtitle: Text(t.sub,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(t.amount,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: t.amount.startsWith('+')
                                ? AppColors.primary
                                : AppColors.onSurface,
                          )),
                      const SizedBox(height: 2),
                      Text(t.status,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.status == 'Pending'
                                ? AppColors.onSurfaceVariant
                                : AppColors.primary,
                          )),
                    ],
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Txn {
  const _Txn(this.icon, this.title, this.sub, this.amount, this.status);
  final IconData icon;
  final String title;
  final String sub;
  final String amount;
  final String status;
}
