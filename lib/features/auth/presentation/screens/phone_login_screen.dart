import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/auth_repository.dart';
import 'otp_verification_screen.dart';

/// R-03 — Phone Login: collect the rider's phone number.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key, this.onboardingToken});

  /// Optional onboarding token carried from social login when phone verification is needed.
  final String? onboardingToken;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _countryCode = TextEditingController(text: '+234');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _countryCode.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final raw = _phone.text.trim();
    final code = _countryCode.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Please enter your phone number');
      return;
    }
    final pureDigits = raw.replaceAll(RegExp(r'\D'), '');
    if (pureDigits.length < 7) {
      setState(() => _error = 'Please enter a valid phone number');
      return;
    }
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Normalize to E.164 without '+' (e.g. 2348012345678).
      final phone = AuthRepository.normalizePhone(raw, countryCode: code);
      await AuthRepository.instance.sendPhoneOtp(
        phone,
        onboardingToken: widget.onboardingToken,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OtpVerificationScreen(
            phone: phone,
            countryCode: code,
            onboardingToken: widget.onboardingToken,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isServerError
            ? 'Server is temporarily busy. Please tap to try again.'
            : e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Victoria'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.help_outline, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter your phone number',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                "Ready for an executive ride? Let's start with your number.",
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _countryCode,
                      readOnly: true,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      onTap: () {},
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        suffixIcon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Phone number',
                        hintStyle: theme.textTheme.bodyLarge
                            ?.copyWith(color: AppColors.outlineVariant),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "We'll send you a 6-digit code to verify your number. "
                      'Carrier charges may apply.',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              AppPrimaryButton(
                label: 'Send OTP',
                icon: Icons.arrow_forward,
                loading: _loading,
                onPressed: _sendOtp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
