import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/rider_wallet_repository.dart';

/// Modal bottom sheet for rider wallet funding via Paystack.
class FundWalletSheet extends StatefulWidget {
  const FundWalletSheet({
    super.key,
    this.currentBalance,
    this.onFundingSuccess,
  });

  final double? currentBalance;
  final ValueChanged<double>? onFundingSuccess;

  /// Helper static method to show the sheet easily from any screen.
  static Future<void> show(
    BuildContext context, {
    double? currentBalance,
    ValueChanged<double>? onFundingSuccess,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FundWalletSheet(
        currentBalance: currentBalance,
        onFundingSuccess: onFundingSuccess,
      ),
    );
  }

  @override
  State<FundWalletSheet> createState() => _FundWalletSheetState();
}

enum _FundingStep { input, awaitingPayment, verifying, success, error }

class _FundWalletSheetState extends State<FundWalletSheet>
    with WidgetsBindingObserver {
  final TextEditingController _amountController =
      TextEditingController(text: '2500');
  final RiderWalletRepository _walletRepo = RiderWalletRepository.instance;

  static const List<int> _quickAmounts = [1000, 2500, 5000, 10000, 20000];

  _FundingStep _step = _FundingStep.input;
  bool _loading = false;
  String? _errorMessage;
  String? _currentReference;
  double _fundedAmount = 0.0;
  double? _newBalance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the rider returns from the Paystack web checkout, automatically
    // attempt to verify the payment reference if we're waiting.
    if (state == AppLifecycleState.resumed &&
        _step == _FundingStep.awaitingPayment &&
        _currentReference != null) {
      _verifyPayment();
    }
  }

  double get _enteredAmount {
    final cleaned = _amountController.text.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  Future<void> _initiatePayment() async {
    final amount = _enteredAmount;
    if (amount < 100) {
      setState(() {
        _errorMessage = 'Minimum funding amount is ₦100';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await _walletRepo.initiateFunding(amount);
      _fundedAmount = amount;
      _currentReference = result.reference;

      final uri = Uri.parse(result.authorizationUrl);

      // Launch Paystack authorization URL
      bool launched = false;
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.inAppBrowserView,
        );
      } catch (_) {
        launched = false;
      }

      if (!launched) {
        // Fallback to external application (system browser)
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
        _step = _FundingStep.awaitingPayment;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not initiate payment. Please try again.';
      });
    }
  }

  Future<void> _verifyPayment() async {
    final ref = _currentReference;
    if (ref == null || ref.isEmpty) return;

    setState(() {
      _step = _FundingStep.verifying;
      _errorMessage = null;
    });

    try {
      final verified = await _walletRepo.verifyFunding(ref);
      if (verified) {
        // Fetch fresh balance
        double updatedBal = (_fundedAmount + (widget.currentBalance ?? 0));
        try {
          updatedBal = await _walletRepo.getBalance();
        } catch (_) {}

        if (!mounted) return;

        setState(() {
          _step = _FundingStep.success;
          _newBalance = updatedBal;
        });

        widget.onFundingSuccess?.call(updatedBal);
      } else {
        if (!mounted) return;
        setState(() {
          _step = _FundingStep.awaitingPayment;
          _errorMessage =
              'Payment has not been confirmed yet. Please complete it on Paystack or try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _FundingStep.awaitingPayment;
        _errorMessage =
            'Could not verify payment yet. If you were debited, click "Check Again" in a moment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Step Content
            switch (_step) {
              _FundingStep.input => _buildInputStep(theme),
              _FundingStep.awaitingPayment => _buildAwaitingStep(theme),
              _FundingStep.verifying => _buildVerifyingStep(theme),
              _FundingStep.success => _buildSuccessStep(theme),
              _FundingStep.error => _buildErrorStep(theme),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildInputStep(ThemeData theme) {
    final currentBal = widget.currentBalance;
    final currentBalFormatted = currentBal != null
        ? '₦${currentBal.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fund Your Wallet',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Instant top-up via Paystack',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            // Paystack security badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceContainerHigh),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                      size: 14, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'Paystack',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        if (currentBalFormatted != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.surfaceContainerHigh),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Current balance: ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  currentBalFormatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Amount Input Field
        Text(
          'Enter Amount (₦)',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
          ],
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          onChanged: (_) => setState(() => _errorMessage = null),
          decoration: InputDecoration(
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 16, right: 8),
              child: Text(
                '₦',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: '0.00',
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.surfaceContainerHigh),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Quick Amount Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amt in _quickAmounts)
              InkWell(
                onTap: () {
                  setState(() {
                    _amountController.text = amt.toString();
                    _errorMessage = null;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _enteredAmount == amt.toDouble()
                        ? AppColors.primary
                        : AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _enteredAmount == amt.toDouble()
                          ? AppColors.primary
                          : AppColors.surfaceContainerHigh,
                    ),
                  ),
                  child: Text(
                    '₦${amt.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _enteredAmount == amt.toDouble()
                          ? AppColors.onPrimary
                          : AppColors.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Pay Button
        AppPrimaryButton(
          label: 'Proceed to Payment (₦${_enteredAmount > 0 ? _enteredAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},') : '0'})',
          loading: _loading,
          onPressed: _enteredAmount > 0 ? _initiatePayment : null,
        ),
      ],
    );
  }

  Widget _buildAwaitingStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.open_in_browser_rounded,
                color: AppColors.primary, size: 32),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Complete Payment on Paystack',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We opened the secure Paystack checkout for ₦${_fundedAmount.toStringAsFixed(2)}. Complete your payment there, then tap below to confirm.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 24),
        AppPrimaryButton(
          label: 'I Have Completed Payment',
          onPressed: _verifyPayment,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            setState(() {
              _step = _FundingStep.input;
              _errorMessage = null;
            });
          },
          child: const Text('Change Amount or Cancel'),
        ),
      ],
    );
  }

  Widget _buildVerifyingStep(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 20),
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Verifying Payment...',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Checking with Paystack to credit your wallet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccessStep(ThemeData theme) {
    final balanceText = _newBalance != null
        ? '₦${_newBalance!.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.onPrimaryContainer, size: 44),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Wallet Funded Successfully!',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '₦${_fundedAmount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} has been added to your Victoria Rides wallet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        if (balanceText != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceContainerHigh),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'New Total Balance',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  balanceText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        AppPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildErrorStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Payment Unsuccessful',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'We could not complete your wallet funding.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppPrimaryButton(
          label: 'Try Again',
          onPressed: () {
            setState(() {
              _step = _FundingStep.input;
              _errorMessage = null;
            });
          },
        ),
      ],
    );
  }
}
