import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_primary_button.dart';

enum _PaymentChannel { card, transfer }

enum _PaymentStep { select, launching, paystackWebView, verifying, success }

/// Modal bottom sheet for ride payment wrapped seamlessly inside the app
/// via Paystack (Card & Bank Transfer embedded WebView).
class RidePaymentSheet extends StatefulWidget {
  const RidePaymentSheet({
    super.key,
    required this.rideId,
    required this.fareNgn,
    required this.driverName,
    this.paymentMethod,
    required this.onPaymentConfirmed,
  });

  final String? rideId;
  final double fareNgn;
  final String? driverName;
  final String? paymentMethod;
  final ValueChanged<bool> onPaymentConfirmed;

  /// Helper static method to display the payment sheet easily.
  static Future<bool?> show(
    BuildContext context, {
    required String? rideId,
    required double fareNgn,
    required String? driverName,
    String? paymentMethod,
    required ValueChanged<bool> onPaymentConfirmed,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => RidePaymentSheet(
        rideId: rideId,
        fareNgn: fareNgn,
        driverName: driverName,
        paymentMethod: paymentMethod,
        onPaymentConfirmed: onPaymentConfirmed,
      ),
    );
  }

  @override
  State<RidePaymentSheet> createState() => _RidePaymentSheetState();
}

class _RidePaymentSheetState extends State<RidePaymentSheet> {
  _PaymentStep _step = _PaymentStep.select;
  late _PaymentChannel _selectedChannel;
  bool _loading = false;
  String? _errorMessage;
  String? _currentReference;
  WebViewController? _webViewController;
  double? _pageProgress;

  @override
  void initState() {
    super.initState();
    final m = (widget.paymentMethod ?? 'CARD').toUpperCase();
    _selectedChannel =
        m.contains('TRANSFER') ? _PaymentChannel.transfer : _PaymentChannel.card;
  }

  String get _formattedFare {
    return '₦${widget.fareNgn.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  Future<void> _initiatePayment() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _step = _PaymentStep.launching;
    });

    final envKey = dotenv.env['PAYSTACK_SECRET_KEY'] ??
        dotenv.env['PAYSTACK_PUBLIC_KEY'] ??
        dotenv.env['PAYSTACK_KEY'];
    final key = (envKey != null && envKey.isNotEmpty)
        ? envKey
        : ApiConfig.paystackSecretKey;

    final email = SessionController.instance.user?['email'] ??
        'rider@victoriarides.com';
    final ref =
        'VR_RIDE_${widget.rideId ?? DateTime.now().millisecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch}';
    final amountKobo = (widget.fareNgn * 100).round();

    _currentReference = ref;

    try {
      final response = await http.post(
        Uri.parse('https://api.paystack.co/transaction/initialize'),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'amount': amountKobo,
          'reference': ref,
          'currency': 'NGN',
          'channels': _selectedChannel == _PaymentChannel.transfer
              ? ['bank_transfer', 'card', 'ussd']
              : ['card', 'bank_transfer', 'ussd'],
          'metadata': {
            'rideId': widget.rideId,
            'driverName': widget.driverName,
            'channel': _selectedChannel.name,
          },
        }),
      );

      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['status'] == true) {
        final authUrl = data['data']?['authorization_url']?.toString();
        if (authUrl != null && authUrl.isNotEmpty) {
          _setupWebViewController(authUrl);
          if (!mounted) return;
          setState(() {
            _loading = false;
            _step = _PaymentStep.paystackWebView;
          });
          return;
        }
      }
      throw ApiException(
        data['message']?.toString() ?? 'Failed to initialize Paystack checkout',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _PaymentStep.select;
        _errorMessage =
            'Could not launch payment: ${e.toString().replaceAll("Exception: ", "")}';
      });
    }
  }

  void _setupWebViewController(String authUrl) {
    try {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() => _pageProgress = progress / 100.0);
              }
            },
            onPageStarted: (String url) {
              debugPrint('[PaystackWebView] Page started: $url');
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() => _pageProgress = null);
              }
              debugPrint('[PaystackWebView] Page finished: $url');
            },
            onNavigationRequest: (NavigationRequest request) {
              final url = request.url.toLowerCase();
              debugPrint('[PaystackWebView] Navigation request: ${request.url}');
              // Intercept Paystack completion, callback, or close URLs
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
              debugPrint('[PaystackWebView] Resource Error: ${error.description}');
            },
          ),
        )
        ..loadRequest(Uri.parse(authUrl));
    } catch (e) {
      debugPrint('[PaystackWebView] Exception setting up controller: $e');
    }
  }

  Future<void> _verifyPayment() async {
    final ref = _currentReference;
    if (ref == null || ref.isEmpty) return;

    setState(() {
      _step = _PaymentStep.verifying;
      _errorMessage = null;
    });

    try {
      // 1. Notify Victoria Rides backend to verify payment and record on ride
      if (widget.rideId != null) {
        try {
          await ApiClient.instance.post(
            '${ApiConfig.apiV1}/rides/${widget.rideId}/verify-payment',
            body: {'reference': ref},
          );
        } catch (e) {
          debugPrint('[RidePaymentSheet] Backend verify error: $e');
        }
      }

      // 2. Query Paystack status for double confirmation
      final envKey = dotenv.env['PAYSTACK_SECRET_KEY'] ??
          dotenv.env['PAYSTACK_PUBLIC_KEY'] ??
          dotenv.env['PAYSTACK_KEY'];
      final key = (envKey != null && envKey.isNotEmpty)
        ? envKey
        : ApiConfig.paystackSecretKey;

      final res = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$ref'),
        headers: {'Authorization': 'Bearer $key'},
      );

      final data = jsonDecode(res.body);
      final isSuccess = (data is Map &&
          data['status'] == true &&
          (data['data']?['status'] == 'success' ||
              data['data']?['gateway_response'] == 'Successful'));

      if (isSuccess || (widget.rideId != null && data['status'] == true)) {
        if (!mounted) return;
        setState(() {
          _step = _PaymentStep.success;
        });
        widget.onPaymentConfirmed(true);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        if (!mounted) return;
        setState(() {
          _step = _PaymentStep.select;
          _errorMessage = data['data']?['gateway_response']?.toString() ??
              'Payment not completed or verified yet. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _PaymentStep.select;
        _errorMessage =
            'Could not verify payment yet. If you completed payment, please check your network and try again.';
      });
    }
  }

  Future<void> _confirmCancelInAppGateway() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Payment?'),
        content: const Text(
          'Are you sure you want to exit the Paystack gateway? You can retry or switch payment methods.',
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
        _step = _PaymentStep.select;
        _webViewController = null;
        _pageProgress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWebView = _step == _PaymentStep.paystackWebView;
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: isWebView ? screenHeight * 0.88 : null,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        isWebView ? 12 : (24 + bottomInset),
      ),
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
                  const SizedBox(height: 12),

                  // Header with title and explicit Close (X) button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.payment_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ride Payment',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: AppColors.outlineVariant),
                  const SizedBox(height: 8),

                  // Step View
                  switch (_step) {
                    _PaymentStep.select => _buildSelectStep(theme),
                    _PaymentStep.launching => _buildLaunchingStep(theme),
                    _PaymentStep.verifying => _buildVerifyingStep(theme),
                    _PaymentStep.success => _buildSuccessStep(theme),
                    _PaymentStep.paystackWebView => const SizedBox.shrink(),
                  },
                ],
              ),
            ),
    );
  }

  Widget _buildSelectStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total Fare summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL FARE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _formattedFare,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (widget.driverName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Driver: ${widget.driverName}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Select Payment Option',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),

        // Channel selector: Card vs Transfer
        Row(
          children: [
            Expanded(
              child: _ChannelTile(
                icon: Icons.credit_card,
                title: 'Card',
                subtitle: 'Debit / Credit',
                isSelected: _selectedChannel == _PaymentChannel.card,
                onTap: () => setState(() => _selectedChannel = _PaymentChannel.card),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChannelTile(
                icon: Icons.account_balance,
                title: 'Transfer',
                subtitle: 'Bank Transfer',
                isSelected: _selectedChannel == _PaymentChannel.transfer,
                onTap: () => setState(() => _selectedChannel = _PaymentChannel.transfer),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Security badge
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Secured by Paystack • 256-bit encryption',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Proceed Button
        AppPrimaryButton(
          label: 'Pay $_formattedFare via Paystack',
          icon: _selectedChannel == _PaymentChannel.card
              ? Icons.credit_card
              : Icons.account_balance,
          loading: _loading,
          onPressed: _loading ? null : _initiatePayment,
        ),
      ],
    );
  }

  Widget _buildLaunchingStep(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
        const SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Connecting to Paystack Gateway...',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Initializing secure payment session for $_formattedFare.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPaystackWebView(ThemeData theme) {
    return Column(
      children: [
        // In-App Gateway Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paystack Secure Gateway',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$_formattedFare • In-App Checkout',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            // Verify / Refresh button
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: AppColors.primary),
              tooltip: 'Check Status',
              onPressed: _verifyPayment,
            ),
            // Close / Cancel button
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
              tooltip: 'Cancel',
              onPressed: _confirmCancelInAppGateway,
            ),
          ],
        ),
        if (_pageProgress != null && _pageProgress! < 1.0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(
              value: _pageProgress,
              backgroundColor: AppColors.surfaceContainerHigh,
              color: AppColors.primary,
              minHeight: 2.5,
            ),
          )
        else
          const Divider(height: 12, color: AppColors.outlineVariant),

        // Embedded In-App WebView
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _webViewController != null
                ? _SafeWebView(controller: _webViewController!)
                : const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
          ),
        ),

        // Safety footer
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _confirmCancelInAppGateway,
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('Change Method', style: TextStyle(fontSize: 12)),
              ),
              FilledButton.tonalIcon(
                onPressed: _verifyPayment,
                icon: const Icon(Icons.check, size: 14),
                label: const Text('I Have Paid', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerifyingStep(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 24),
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
          'Confirming your transaction with Victoria Rides server.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSuccessStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.onPrimaryContainer,
              size: 44,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Payment Confirmed!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '$_formattedFare has been received. Thank you for riding with Victoria Travels!',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
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
      // Graceful fallback for test runners or environments where native WebView platform is stubbed
      return const Center(
        child: Text(
          'Paystack Secure Payment Gateway Active',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
      );
    }
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppColors.primary : AppColors.onSurface,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.8)
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
