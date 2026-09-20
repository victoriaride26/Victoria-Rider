import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// R-16 — Payment Methods.
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  static const List<_Method> _methods = [
    _Method(Icons.credit_card, 'Mastercard', '•••• 4242', 'Default',
        'Expires 12/26', true),
    _Method(Icons.credit_card, 'Visa', '•••• 8890', '', 'Expires 05/25', false),
    _Method(Icons.account_balance, 'GTBank - Amina O.',
        '•••• 1234', '', 'Checking', false),
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
            AppBackButton(
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const RiderHomeShell(initialIndex: 0),
                    ),
                    (route) => false,
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            Text('Payment Methods',
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user,
                      color: AppColors.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Secure Transactions',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: AppColors.onPrimaryContainer)),
                        const SizedBox(height: 2),
                        Text(
                          'Your payment data is encrypted and protected with '
                          'bank-grade security protocols.',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Saved Methods',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ...[
              for (final m in _methods)
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
                      Icon(m.icon, color: AppColors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.title,
                                style: theme.textTheme.titleLarge),
                            Text('${m.mask}  •  ${m.sub}',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (m.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Default',
                              style: TextStyle(color: AppColors.onPrimaryContainer)),
                        ),
                      TextButton(
                          onPressed: () {},
                          child: const Text('EDIT')),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Executive Rewards',
                            style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          'Link your corporate card to earn double points '
                          'on every ride.',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                      onPressed: () {},
                      child: const Text('LEARN MORE')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Add New Payment Method'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Method {
  const _Method(this.icon, this.title, this.mask, this.badge, this.sub,
      this.isDefault);
  final IconData icon;
  final String title;
  final String mask;
  final String badge;
  final String sub;
  final bool isDefault;
}
