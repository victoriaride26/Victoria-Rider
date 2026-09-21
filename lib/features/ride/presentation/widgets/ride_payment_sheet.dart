import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_primary_button.dart';

enum _PaymentChannel { card, transfer }

enum _PaymentStep { select, awaitingPayment, verifying, success }

/// Modal bottom sheet for ride payment via Paystack (Card & Bank Transfer).
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
      enableDrag: true,
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

class _RidePaymentSheetState extends State<RidePaymentSheet>
    with WidgetsBindingObserver {
  _PaymentStep _step = _PaymentStep.select;
  late _PaymentChannel _selectedChannel;
  bool _loading = false;
  String? _errorMessage;
  String? _currentReference;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final m = (widget.paymentMethod ?? 'CARD').toUpperCase();
    _selectedChannel =
        m.contains('TRANSFER') ? _PaymentChannel.transfer : _PaymentChannel.card;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the rider returns from Paystack web checkout, auto-verify payment.
    if (state == AppLifecycleState.resumed &&
        _step == _PaymentStep.awaitingPayment &&
        _currentReference != null) {
      _verifyPayment();
    }
  }

  String get _formattedFare {
    return '₦${widget.fareNgn.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  Future<void> _initiatePayment() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
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
          final uri = Uri.parse(authUrl);
          bool launched = false;
          try {
            launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
          } catch (_) {
            launched = false;
          }
          if (!launched) {
            launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          if (!mounted) return;
          setState(() {
            _loading = false;
            _step = _PaymentStep.awaitingPayment;
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
        _errorMessage =
            'Could not launch payment: ${e.toString().replaceAll("Exception: ", "")}';
      });
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
      // 1. Notify backend to verify payment and record it on the ride
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
          _step = _PaymentStep.awaitingPayment;
          _errorMessage = data['data']?['gateway_response']?.toString() ??
              'Payment not verified yet. Please complete payment on Paystack or check again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _PaymentStep.awaitingPayment;
        _errorMessage =
            'Could not verify payment yet. If you completed payment, please click "Check Again".';
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
              _PaymentStep.awaitingPayment => _buildAwaitingStep(theme),
              _PaymentStep.verifying => _buildVerifyingStep(theme),
              _PaymentStep.success => _buildSuccessStep(theme),
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
            child: const Icon(
              Icons.open_in_browser_rounded,
              color: AppColors.primary,
              size: 32,
            ),
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
          'We opened the secure Paystack checkout for $_formattedFare. Complete your payment there, then tap below to confirm.',
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
          icon: Icons.check_circle_outline,
          onPressed: _verifyPayment,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            setState(() {
              _step = _PaymentStep.select;
              _errorMessage = null;
            });
          },
          child: const Text('Change Option or Retry'),
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
