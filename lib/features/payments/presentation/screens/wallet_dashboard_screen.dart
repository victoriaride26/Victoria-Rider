import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
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
  List<RiderBankAccount> _bankAccounts = [];
  bool _withdrawLoading = false;

  static const List<_Action> _actions = [
    _Action(Icons.add_circle, 'Add Funds'),
    _Action(Icons.swap_horiz, 'Transfer'),
    _Action(Icons.card_giftcard, 'Gift Card'),
  ];

  RiderBankAccount? get _defaultAccount => _bankAccounts.where((b) => b.isDefault).isNotEmpty
      ? _bankAccounts.firstWhere((b) => b.isDefault)
      : (_bankAccounts.isNotEmpty ? _bankAccounts.first : null);

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

    try {
      final accounts = await _walletRepo.fetchBankAccounts();
      if (mounted) setState(() => _bankAccounts = accounts);
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

  Future<void> _withdraw() async {
    final account = _defaultAccount;
    if (account == null) {
      final added = await _showAddBankAccountSheet();
      if (added == true) await _loadData();
      return;
    }
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => _RiderWithdrawDialog(balance: _balance, account: account),
    );
    if (amount == null || !mounted) return;
    if (amount <= 0) {
      _showError('Enter a valid amount.');
      return;
    }
    if (amount > _balance) {
      _showError('Amount exceeds your available balance.');
      return;
    }
    setState(() => _withdrawLoading = true);
    try {
      final result = await _walletRepo.withdraw(amountNgn: amount, bankAccountId: account.id);
      if (!mounted) return;
      setState(() => _balance -= result.amountNgn);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('₦${result.amountNgn.toStringAsFixed(2)} payout requested to ${account.bankName}.')),
      );
      _loadData();
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('Withdrawal failed. Please try again.');
    } finally {
      if (mounted) setState(() => _withdrawLoading = false);
    }
  }

  Future<bool?> _showAddBankAccountSheet() {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RiderAddBankSheet(),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.onPrimary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified, size: 14, color: AppColors.onPrimary),
                              const SizedBox(width: 6),
                              Text(
                                _defaultAccount == null ? 'No payout account' : '${_defaultAccount!.bankName} ${ _defaultAccount!.accountMask}',
                                style: const TextStyle(color: AppColors.onPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
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
                    const SizedBox(height: 4),
                    Text(
                      _bankAccounts.isEmpty ? 'Add a bank account to withdraw' : 'Ready for withdrawals',
                      style: TextStyle(color: AppColors.onPrimary.withValues(alpha: 0.8), fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: FilledButton.icon(
                              onPressed: _openFundWalletSheet,
                              icon: const Icon(Icons.add_card_rounded, size: 18),
                              label: const Text('Fund', style: TextStyle(fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.onPrimary,
                                foregroundColor: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: FilledButton.icon(
                              onPressed: _withdrawLoading ? null : _withdraw,
                              icon: _withdrawLoading
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                                  : const Icon(Icons.arrow_upward_rounded, size: 18),
                              label: Text(_withdrawLoading ? '...' : 'Withdraw', style: const TextStyle(fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.onPrimary.withValues(alpha: 0.15),
                                foregroundColor: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Rider payout account card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      child: Icon(Icons.account_balance_outlined, size: 20, color: AppColors.onSurface),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _defaultAccount == null ? 'No payout account' : '${_defaultAccount!.bankName} ${_defaultAccount!.accountMask}',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.onSurface),
                          ),
                          Text(
                            _defaultAccount == null ? 'Tap Manage to add bank' : (_defaultAccount!.accountName.isNotEmpty ? _defaultAccount!.accountName : 'Default payout method'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final result = await _showAddBankAccountSheet();
                        if (result == true) _loadData();
                      },
                      child: Text(_bankAccounts.isEmpty ? 'Add' : 'Manage'),
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

class _RiderWithdrawDialog extends StatefulWidget {
  const _RiderWithdrawDialog({required this.balance, required this.account});
  final double balance;
  final RiderBankAccount account;
  @override
  State<_RiderWithdrawDialog> createState() => _RiderWithdrawDialogState();
}

class _RiderWithdrawDialogState extends State<_RiderWithdrawDialog> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Withdraw funds'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available: ₦${widget.balance.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('To ${widget.account.bankName} ${widget.account.accountMask}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(prefixText: '₦ ', hintText: 'Amount', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final cleaned = _controller.text.replaceAll(',', '').trim();
            final parsed = double.tryParse(cleaned);
            Navigator.of(context).pop(parsed);
          },
          child: const Text('Withdraw'),
        ),
      ],
    );
  }
}

const List<_RiderBank> _riderNigerianBanks = [
  _RiderBank(name: 'Test Bank (Sandbox / Paystack)', code: '001'),
  _RiderBank(name: 'Access Bank', code: '044'),
  _RiderBank(name: 'First Bank of Nigeria', code: '011'),
  _RiderBank(name: 'Guaranty Trust Bank', code: '058'),
  _RiderBank(name: 'United Bank for Africa', code: '033'),
  _RiderBank(name: 'Zenith Bank', code: '057'),
  _RiderBank(name: 'Ecobank Nigeria', code: '050'),
  _RiderBank(name: 'Fidelity Bank', code: '070'),
  _RiderBank(name: 'Union Bank of Nigeria', code: '032'),
  _RiderBank(name: 'Wema Bank', code: '035'),
  _RiderBank(name: 'Sterling Bank', code: '232'),
  _RiderBank(name: 'Polaris Bank', code: '076'),
  _RiderBank(name: 'Kuda Microfinance Bank', code: '50211'),
  _RiderBank(name: 'Moniepoint MFB', code: '50515'),
];

class _RiderBank {
  const _RiderBank({required this.name, required this.code});
  final String name;
  final String code;
}

class _RiderAddBankSheet extends StatefulWidget {
  const _RiderAddBankSheet();
  @override
  State<_RiderAddBankSheet> createState() => _RiderAddBankSheetState();
}

class _RiderAddBankSheetState extends State<_RiderAddBankSheet> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedBankCode;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _error = null; });
    try {
      final bankName = _riderNigerianBanks.firstWhere((b) => b.code == _selectedBankCode, orElse: () => _RiderBank(name: '', code: _selectedBankCode!)).name;
      await RiderWalletRepository.instance.addBankAccount(
        accountNumber: _numberController.text.trim(),
        bankCode: _selectedBankCode!,
        accountName: _nameController.text.trim(),
        bankName: bankName,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank account added.')));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save bank account.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            Text('Add payout account', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _numberController,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: const InputDecoration(labelText: 'Account number', hintText: '0123456789', border: OutlineInputBorder(), counterText: ''),
              validator: (v) => (v ?? '').trim().length != 10 ? 'Enter 10-digit account number' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedBankCode,
              hint: const Text('Select bank'),
              items: _riderNigerianBanks.map((b) => DropdownMenuItem(value: b.code, child: Text(b.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _selectedBankCode = v),
              decoration: const InputDecoration(labelText: 'Bank', border: OutlineInputBorder()),
              validator: (v) => v == null ? 'Please select a bank' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Account name', hintText: 'As on bank statement', border: OutlineInputBorder()),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Account name required' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
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
