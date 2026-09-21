import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import '../../data/rider_wallet_repository.dart';

/// R-17 — Transaction History.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final RiderWalletRepository _walletRepo = RiderWalletRepository.instance;
  
  int _tab = 0;
  bool _isLoading = true;
  List<WalletTransaction> _transactions = [];

  static const List<String> _tabs = ['All', 'Rides', 'Funding', 'Refunds'];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final txns = await _walletRepo.getTransactions();
      if (mounted) {
        setState(() {
          _transactions = txns;
        });
      }
    } catch (_) {
      // Ignore errors or show snackbar
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatCurrency(double amount) {
    return '₦${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }
  
  List<WalletTransaction> get _filteredTransactions {
    return _transactions.where((t) {
      if (_tab == 1) { // Rides
        return !t.isCredit && !t.type.toUpperCase().contains('REFUND');
      } else if (_tab == 2) { // Funding
        return t.isCredit && !t.type.toUpperCase().contains('REFUND');
      } else if (_tab == 3) { // Refunds
        return t.type.toUpperCase().contains('REFUND');
      }
      return true; // All
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedTxns = _filteredTransactions;
    
    return RiderScaffold(
      currentIndex: 2,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadTransactions,
          child: ListView(
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
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
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (displayedTxns.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'No transactions found.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ...[
                  for (final t in displayedTxns)
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: t.isCredit
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : AppColors.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          t.isCredit
                              ? Icons.account_balance_wallet
                              : Icons.directions_car,
                          color: t.isCredit
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        t.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year} • ${t.createdAt.hour.toString().padLeft(2, '0')}:${t.createdAt.minute.toString().padLeft(2, '0')}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${t.isCredit ? '+' : '-'}${_formatCurrency(t.amountNgn)}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: t.isCredit
                                  ? AppColors.primary
                                  : AppColors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(t.status,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: t.status.toUpperCase() == 'PENDING'
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
      ),
    );
  }
}
