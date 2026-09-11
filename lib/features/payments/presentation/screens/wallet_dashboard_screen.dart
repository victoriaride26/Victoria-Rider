import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import '../../data/rider_wallet_repository.dart';
import '../widgets/fund_wallet_sheet.dart';
import 'payment_methods_screen.dart';
import 'transaction_history_screen.dart';

/// R-15 — Wallet Dashboard with Live Funding & Balance.
class WalletDashboardScreen extends StatefulWidget {
  const WalletDashboardScreen({super.key});

  @override
  State<WalletDashboardScreen> createState() => _WalletDashboardScreenState();
}

class _WalletDashboardScreenState extends State<WalletDashboardScreen> {
  final RiderWalletRepository _walletRepo = RiderWalletRepository.instance;

  double _balance = 12500.0;
  bool _loading = false;
  List<WalletTransaction> _transactions = [];

  static const List<_Action> _actions = [
    _Action(Icons.add_circle, 'Add Funds'),
    _Action(Icons.swap_horiz, 'Transfer'),
    _Action(Icons.card_giftcard, 'Gift Card'),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final bal = await _walletRepo.getBalance();
      if (mounted) setState(() => _balance = bal);
    } catch (_) {}

    try {
      final txns = await _walletRepo.getTransactions();
      if (mounted) setState(() => _transactions = txns);
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  void _openFundWalletSheet() {
    FundWalletSheet.show(
      context,
      currentBalance: _balance,
      onFundingSuccess: (newBalance) {
        setState(() => _balance = newBalance);
        _loadData();
      },
    );
  }

  String _formatCurrency(double amount) {
    return '₦${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RiderScaffold(
      currentIndex: 2,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              // Header
              Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      icon: const Icon(Icons.menu, color: AppColors.onSurface),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Wallet', style: theme.textTheme.headlineMedium),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Total Balance Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Balance',
                          style: TextStyle(color: AppColors.onPrimary),
                        ),
                        InkWell(
                          onTap: _openFundWalletSheet,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.onPrimary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add,
                                    size: 14, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Top Up',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatCurrency(_balance),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.onPrimary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified,
                              size: 14, color: AppColors.onPrimary),
                          SizedBox(width: 6),
                          Text('Active Account • Ready for Rides',
                              style: TextStyle(
                                  color: AppColors.onPrimary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons Row
              Row(
                children: [
                  for (final a in _actions)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: a == _actions.last ? 0 : 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            if (a.label == 'Add Funds') {
                              _openFundWalletSheet();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${a.label} coming soon!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: a.label == 'Add Funds'
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: a.label == 'Add Funds'
                                        ? AppColors.primary.withValues(alpha: 0.3)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Icon(
                                  a.icon,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                a.label,
                                style: theme.textTheme.labelMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Payment Methods Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Payment Methods',
                        style: theme.textTheme.titleLarge),
                  ),
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
                          Text('Mastercard / Visa (Paystack)',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text('Fast bank cards and transfer',
                              style: TextStyle(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('DEFAULT',
                          style:
                              TextStyle(color: AppColors.onPrimaryContainer)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Recent Activity Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Recent Activity',
                        style: theme.textTheme.titleLarge),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const TransactionHistoryScreen()),
                    ),
                    child: const Text('View All'),
                  ),
                ],
              ),

              // Transactions list: real or fallback
              if (_transactions.isNotEmpty) ...[
                for (final tx in _transactions.take(5))
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tx.isCredit
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        tx.isCredit
                            ? Icons.account_balance_wallet
                            : Icons.directions_car,
                        color: tx.isCredit
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      tx.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} • ${tx.status}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    trailing: Text(
                      '${tx.isCredit ? '+' : '-'}${_formatCurrency(tx.amountNgn)}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: tx.isCredit
                            ? AppColors.primary
                            : AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 28),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.surfaceContainerHigh),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          size: 32,
                          color: AppColors.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No Recent Transactions',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your completed ride payments and wallet top-ups will appear here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: _openFundWalletSheet,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Funds Now'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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
