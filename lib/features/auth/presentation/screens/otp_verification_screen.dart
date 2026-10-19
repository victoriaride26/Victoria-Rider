import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/auth_repository.dart';
import 'profile_setup_screen.dart';

/// R-04 — OTP Verification: 6-digit code entry.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.phone,
    this.countryCode = '+234',
    this.onboardingToken,
    this.devOtp,
  });

  /// The full phone number (country code + digits) submitted for verification.
  final String phone;

  /// Display prefix shown alongside the masked number.
  final String countryCode;

  /// Optional onboarding token carried through from social login.
  final String? onboardingToken;

  /// DEV-ONLY OTP echoed by the backend's send-otp response, captured on the
  /// previous screen and shown here so only ONE code is ever sent. Never set
  /// in release builds (the backend does not echo it there).
  final String? devOtp;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final SmartAuth _smartAuth = SmartAuth.instance;
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  Timer? _timer;
  int _seconds = 45;
  bool _loading = false;
  bool _sendingOtp = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Android SmsRetriever (via smart_auth): captures the incoming SMS
      // without any permission. The SMS must contain the app-hash (see
      // appSignature debug log) — coordinate the format with the backend team.
      _listenForSmsCode();
      unawaited(_logAppSignature());
      _showDevOtp(widget.devOtp);
    });
  }

  /// Logs the app-hash the backend must embed in the OTP SMS.
  Future<void> _logAppSignature() async {
    final res = await _smartAuth.getAppSignature();
    debugPrint(
      '[OTP] appSignature for SMS hash: '
      '${res.hasData ? res.requireData : res.error}',
    );
  }

  /// One-shot SMS Retriever listener (Android only; smart_auth is a
  /// no-op elsewhere). Fills the boxes when the SMS code is captured.
  Future<void> _listenForSmsCode() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final res = await _smartAuth.getSmsWithRetrieverApi();
    if (!mounted || !res.hasData) return;
    _applySmsCode(res.requireData.code);
  }

  /// Shows the server-echoed OTP in a snackbar for development/testing only.
  ///
  /// The backend returns `otp` in the send-otp response purely so the app can
  /// be tested during development; it must not appear in release builds.
  void _showDevOtp(String? otp) {
    if (!mounted || kReleaseMode || otp == null || otp.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('DEV OTP: $otp'),
          backgroundColor: AppColors.secondary,
          duration: const Duration(seconds: 8),
        ),
      );
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _seconds--;
        if (_seconds <= 0) t.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_smartAuth.removeSmsRetrieverApiListener());
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills all six boxes when the SMS code is captured (Android retriever).
  void _applySmsCode(String? code) {
    final digits = (code ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || !mounted) return;
    setState(() {
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      _error = null;
    });
    FocusScope.of(context).unfocus();
    if (digits.length >= 6) _verify();
  }

  String get _otp =>
      _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_loading) return;
    if (_otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code sent to your phone');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthRepository.instance.verifyPhoneOtp(
        phone: widget.phone,
        otp: _otp,
        onboardingToken: widget.onboardingToken,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
            builder: (_) => ProfileSetupScreen(phone: widget.phone)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isServerError
            ? 'Server is temporarily busy. Please tap to try again.'
            : e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _resend() async {
    if (_sendingOtp) return;
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    try {
      final otp = await AuthRepository.instance.sendPhoneOtp(
        widget.phone,
        onboardingToken: widget.onboardingToken,
      );
      if (!mounted) return;
      setState(() {
        _seconds = 45;
        _sendingOtp = false;
      });
      _showDevOtp(otp);
      _startTimer();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isServerError
            ? 'Server is temporarily busy. Please tap to try again.'
            : e.message;
        _sendingOtp = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _sendingOtp = false;
      });
    }
  }

  String get _maskedPhone {
    final digits = widget.phone.replaceAll(RegExp(r'\D'), '');
    final shown = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
    return '${widget.countryCode} ••• ••• $shown';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verify your number'),
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
              Text('Verify your number', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                "We've sent a 6-digit code to",
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(_maskedPhone,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (int i = 0; i < 6; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: TextField(
                          controller: _controllers[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(1),
                          ],
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: AppColors.surfaceContainerLowest,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppColors.outline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppColors.primary, width: 2),
                            ),
                          ),
                          onChanged: (v) {
                            if (v.isNotEmpty &&
                                i < _controllers.length - 1) {
                              FocusScope.of(context).nextFocus();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_seconds > 0)
                    Text(
                      'Resend code in 0:${_seconds.toString().padLeft(2, "0")}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.onSurfaceVariant),
                    )
                  else
                    TextButton(
                      onPressed: _sendingOtp ? null : _resend,
                      child: Text(_sendingOtp ? 'Sending…' : 'Resend code'),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.error),
                ),
              ],
              const Spacer(),
              AppPrimaryButton(
                label: 'Verify',
                icon: Icons.chevron_right,
                loading: _loading,
                onPressed: _verify,
              ),
              const SizedBox(height: 16),
              Text(
                'By continuing, you agree to our Terms of Service and Privacy Policy.',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
