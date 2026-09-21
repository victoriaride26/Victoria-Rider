import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pay_with_paystack/pay_with_paystack.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import 'rate_driver_screen.dart';

/// R-12 — Trip Completed (Payment & Receipt).
class TripCompletedScreen extends StatefulWidget {
  const TripCompletedScreen({
    super.key,
    this.rideId,
    this.driverName,
    this.fareNgn,
    this.pickupAddress,
    this.dropoffAddress,
    this.paymentMethod,
    this.isPaymentConfirmed = true,
  });

  final String? rideId;
  final String? driverName;
  final double? fareNgn;
  final String? pickupAddress;
  final String? dropoffAddress;
  final String? paymentMethod;
  final bool isPaymentConfirmed;

  @override
  State<TripCompletedScreen> createState() => _TripCompletedScreenState();
}

class _TripCompletedScreenState extends State<TripCompletedScreen> {
  late bool _isPaymentConfirmed;
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _isPaymentConfirmed = widget.isPaymentConfirmed;
  }

  String _cleanAddress(String? address, String fallback) {
    if (address == null || address.trim().isEmpty) return fallback;
    final trimmed = address.trim();
    // If it's pure raw coordinates e.g. "7.7322, 8.5245" or "7.7322,8.5245"
    final isCoords = RegExp(r'^-?\d+(\.\d+)?[\s,]+-?\d+(\.\d+)?$').hasMatch(trimmed);
    if (isCoords) {
      return fallback;
    }
    return trimmed;
  }

  String get _paymentLabel {
    final m = (widget.paymentMethod ?? 'cash').toUpperCase();
    if (m == 'CARD') return 'Card (Paystack)';
    if (m == 'TRANSFER') return 'Bank Transfer';
    if (m == 'WALLET') return 'Wallet Balance';
    return 'Cash';
  }

  IconData get _paymentIcon {
    final m = (widget.paymentMethod ?? 'cash').toUpperCase();
    if (m == 'CARD') return Icons.credit_card;
    if (m == 'TRANSFER') return Icons.swap_horiz_rounded;
    if (m == 'WALLET') return Icons.account_balance_wallet_outlined;
    return Icons.payments_outlined;
  }

  Future<void> _payWithPaystack() async {
    if (_isProcessingPayment || !mounted) return;
    setState(() => _isProcessingPayment = true);

    final envKey =
        dotenv.env['PAYSTACK_SECRET_KEY'] ??
        dotenv.env['PAYSTACK_PUBLIC_KEY'] ??
        dotenv.env['PAYSTACK_KEY'];
    final key = (envKey != null && envKey.isNotEmpty)
        ? envKey
        : ApiConfig.paystackSecretKey;

    final email =
        SessionController.instance.user?['email'] ?? 'rider@victoriarides.com';
    final ref = PayWithPayStack().generateUuidV4();
    final amount = widget.fareNgn ?? 0.0;

    try {
      await PayWithPayStack().now(
        context: context,
        secretKey: key,
        customerEmail: email,
        reference: ref,
        currency: 'NGN',
        amount: amount,
        transactionCompleted: (paymentData) async {
          if (mounted) {
            setState(() {
              _isProcessingPayment = false;
              _isPaymentConfirmed = true;
            });
          }
          if (widget.rideId != null) {
            try {
              await ApiClient.instance.post(
                '${ApiConfig.apiV1}/rides/${widget.rideId}/verify-payment',
                body: {'reference': paymentData.reference ?? ref},
              );
            } catch (e) {
              debugPrint('Payment verify exception: $e');
            }
          }
        },
        transactionNotCompleted: (reason) {
          if (mounted) setState(() => _isProcessingPayment = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment not completed: $reason'),
                backgroundColor: Colors.orange.shade800,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _isProcessingPayment = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fareText = widget.fareNgn != null
        ? '₦${widget.fareNgn!.toStringAsFixed(0)}'
        : '—';
    final name = widget.driverName ?? 'Adeola Johnson';
    final cleanPickup = _cleanAddress(widget.pickupAddress, 'Wurukum Roundabout, Makurdi');
    final cleanDropoff = _cleanAddress(widget.dropoffAddress, 'High Level Market, Makurdi');

    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const RiderHomeShell(),
                ),
                (route) => false,
              );
            }
          },
        ),
        title: const Text('Victoria Rides'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.help_outline, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                size: 52,
                color: AppColors.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'Trip Completed!',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'We hope you had a pleasant executive ride experience with Victoria Travels.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Payment method badge (Trip ID removed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_paymentIcon, size: 13, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      _paymentLabel.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Receipt Container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Route Section (Pickup & Drop-off in full)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            const SizedBox(height: 4),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 2,
                              height: 38,
                              color: AppColors.outlineVariant,
                            ),
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PICKUP',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cleanPickup,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'DROP-OFF',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cleanDropoff,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.outlineVariant),
                    // Fare Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL FARE',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isPaymentConfirmed
                                  ? 'Payment Confirmed'
                                  : 'Payment Pending',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isPaymentConfirmed
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          fareText,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppColors.outlineVariant),
                    // Driver info
                    Row(
                      children: [
                        const Icon(Icons.person_pin, color: AppColors.primary, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Payment Method: $_paymentLabel',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: const [
                            Icon(Icons.star, color: Colors.amber, size: 16),
                            SizedBox(width: 4),
                            Text(
                              '4.9 • Executive',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action buttons
              if (!_isPaymentConfirmed) ...[
                AppPrimaryButton(
                  label: _isProcessingPayment
                      ? 'Processing Payment…'
                      : 'Pay $fareText via Paystack',
                  icon: Icons.credit_card,
                  loading: _isProcessingPayment,
                  onPressed: _isProcessingPayment ? null : _payWithPaystack,
                ),
                const SizedBox(height: 12),
              ],
              AppPrimaryButton(
                label: 'Rate Driver',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RateDriverScreen(
                      rideId: widget.rideId,
                      driverName: widget.driverName,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const RiderHomeShell(),
                    ),
                    (route) => false,
                  );
                },
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
