import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_constants.dart';
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
      useRootNavigator: true,
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

enum _FundingStep { input, launching, paystackWebView, awaitingPayment, verifying, success, error }

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
  double? _creditedAmount;
  WebViewController? _webViewController;
  double? _pageProgress;
  bool _verificationStarted = false;

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
    // When the rider returns from external checkout (fallback) or webview, verify.
    if (state == AppLifecycleState.resumed &&
        (_step == _FundingStep.awaitingPayment || _step == _FundingStep.paystackWebView) &&
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
      _step = _FundingStep.launching;
    });

    try {
      final result = await _walletRepo.initiateFunding(amount);
      _fundedAmount = amount;
      _currentReference = result.reference;
      _verificationStarted = false;

      final authUrl = result.authorizationUrl;

      _setupWebViewController(authUrl);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _FundingStep.paystackWebView;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _FundingStep.input;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _FundingStep.input;
        _errorMessage = 'Could not initiate payment. Please try again.';
      });
    }
  }

  void _setupWebViewController(String authUrl) {
    try {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'PaystackChannel',
          onMessageReceived: (message) {
            if (message.message == 'success') {
              _verifyPayment();
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() => _pageProgress = progress / 100.0);
              }
            },
            onPageStarted: (String url) {
              debugPrint('[WalletPaystackWebView] Page started: $url');
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() => _pageProgress = null);
              }
              debugPrint('[WalletPaystackWebView] Page finished: $url');
              _injectSuccessObserver();
            },
            onNavigationRequest: (NavigationRequest request) {
              final url = request.url.toLowerCase();
              debugPrint('[WalletPaystackWebView] Navigation request: ${request.url}');
              if (url.contains('standard.paystack.co/close') ||
                  url.contains('callback') ||
                  url.contains('trxref=') ||
                  url.contains('reference=') ||
                  url.contains('status=success')) {
                _verifyPayment();
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('[WalletPaystackWebView] Resource Error: ${error.description}');
            },
          ),
        )
        ..loadRequest(Uri.parse(authUrl));
    } catch (e) {
      debugPrint('[WalletPaystackWebView] Exception setting up controller: $e');
    }
  }

  void _injectSuccessObserver() {
    _webViewController?.runJavaScript(r'''
      (function() {
        if (window._victoriaPaystackObserverInstalled) return;
        window._victoriaPaystackObserverInstalled = true;
        var timer = setInterval(function() {
          var body = document.body ? document.body.innerText.toLowerCase() : '';
          if (body.includes('payment successful') ||
              body.includes('transaction successful') ||
              body.includes('payment complete') ||
              document.querySelector('[data-status="success"]') !== null ||
              document.querySelector('.status-success') !== null) {
            clearInterval(timer);
            PaystackChannel.postMessage('success');
          }
        }, 300);
      })();
    ''');
  }

  Future<void> _verifyPayment() async {
    if (_verificationStarted) return;
    final ref = _currentReference;
    if (ref == null || ref.isEmpty) return;
    _verificationStarted = true;

    setState(() {
      _step = _FundingStep.verifying;
      _errorMessage = null;
    });

    try {
      final verified = await _walletRepo.verifyFunding(ref);
      if (verified) {
        final previousBal = widget.currentBalance ?? 0;
        // Fetch fresh balance
        double updatedBal = (_fundedAmount + previousBal);
        try {
          updatedBal = await _walletRepo.getBalance();
        } catch (_) {}

        if (!mounted) return;

        // Report what was actually credited (fresh delta), not the gross
        // checkout amount: backends that net off Paystack fees — or that
        // credit minor units inconsistently — otherwise show a success
        // message the header balance contradicts.
        final credited = updatedBal - previousBal;

        setState(() {
          _step = _FundingStep.success;
          _newBalance = updatedBal;
          _creditedAmount = credited > 0 ? credited : _fundedAmount;
        });

        widget.onFundingSuccess?.call(updatedBal);
      } else {
        if (!mounted) return;
        _verificationStarted = false;
        setState(() {
          _step = _FundingStep.paystackWebView;
          _errorMessage =
              'Payment has not been confirmed yet. Please complete it on Paystack or tap Verify.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      _verificationStarted = false;
      setState(() {
        _step = _FundingStep.paystackWebView;
        _errorMessage =
            'Could not verify payment yet. If you were debited, tap Verify in a moment.';
      });
    }
  }

  Future<void> _confirmCancelInAppGateway() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Payment?'),
        content: const Text(
          'Are you sure you want to exit the Paystack gateway? You can retry or switch amount.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Paying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Payment'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _step = _FundingStep.input;
        _webViewController = null;
        _pageProgress = null;
        _verificationStarted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isWebView = _step == _FundingStep.paystackWebView;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: isWebView ? screenHeight * 0.88 : null,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, isWebView ? 12 : 24 + bottomInset),
      child: isWebView
          ? _buildPaystackWebView(theme)
          : AnimatedSize(
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
                    _FundingStep.launching => _buildLaunchingStep(theme),
                    _FundingStep.paystackWebView => const SizedBox.shrink(),
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

  Widget _buildLaunchingStep(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        Text('Connecting to Paystack Gateway...', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Initializing secure wallet funding for ₦${_fundedAmount.toStringAsFixed(0)}.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPaystackWebView(ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.lock, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paystack Secure Gateway', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('₦${_fundedAmount.toStringAsFixed(0)} • In-App Checkout',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11.5)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.refresh, size: 20, color: AppColors.primary), tooltip: 'Check Status', onPressed: _verifyPayment),
            IconButton(icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant), tooltip: 'Cancel', onPressed: _confirmCancelInAppGateway),
          ],
        ),
        if (_pageProgress != null && _pageProgress! < 1.0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(value: _pageProgress, backgroundColor: AppColors.surfaceContainerHigh, color: AppColors.primary, minHeight: 2.5),
          )
        else
          const Divider(height: 12, color: AppColors.outlineVariant),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _webViewController != null ? _SafeWebView(controller: _webViewController!) : const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(onPressed: _confirmCancelInAppGateway, icon: const Icon(Icons.arrow_back, size: 14), label: const Text('Change Amount', style: TextStyle(fontSize: 12))),
              FilledButton.tonalIcon(onPressed: _verifyPayment, icon: const Icon(Icons.check, size: 14), label: const Text('I Have Paid', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.errorContainer.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(8)),
            child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 12.5, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _buildAwaitingStepLegacy(ThemeData theme) => _buildAwaitingStep(theme);

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
    String fmt(double v) =>
        '₦${v.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    final balanceText = _newBalance != null ? fmt(_newBalance!) : null;
    final creditedText =
        _creditedAmount != null ? fmt(_creditedAmount!) : null;

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
          creditedText != null
              ? AppConstants.walletCredited(creditedText)
              : AppConstants.walletFunded,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        if (creditedText != null &&
            (_creditedAmount! - _fundedAmount).abs() > 0.009) ...[
          const SizedBox(height: 6),
          Text(
            'Paid ₦${_fundedAmount.toStringAsFixed(2)} — the difference is the gateway deduction applied before credit.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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

class _SafeWebView extends StatelessWidget {
  const _SafeWebView({required this.controller});
  final WebViewController controller;
  @override
  Widget build(BuildContext context) {
    try {
      return WebViewWidget(controller: controller);
    } catch (_) {
      return const Center(
        child: Text('Paystack Secure Payment Gateway Active', style: TextStyle(color: AppColors.onSurfaceVariant)),
      );
    }
  }
}
