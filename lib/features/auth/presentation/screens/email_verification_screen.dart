import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/auth_repository.dart';
import 'login_screen.dart';

/// R-05b — Email Verification: 6-digit code entry.
///
/// After `POST /auth/register` the backend emails a 6-digit OTP. The rider
/// enters it here; it is submitted to `POST /auth/verify-email`
/// `{email, otp}` — the same endpoint and shape the driver app uses.
/// Resends go through `POST /auth/email/send-otp` `{email}` on demand.
/// On success the rider continues to [LoginScreen] to sign in to the new
/// account (riders have no session until sign-in, unlike drivers).
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.email});

  /// Email address the verification OTP was sent to.
  final String email;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _seconds = 45;
  bool _loading = false;
  bool _sendingOtp = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
    // The email code goes out at registration, so nothing auto-sends here —
    // resends go through Resend code on demand (same as the driver app).
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

  String get _otp => _controllers.map((c) => c.text).join();

  String get _maskedEmail {
    final email = widget.email.trim();
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    final shown = name.length <= 2 ? '${name[0]}•••' : '${name.substring(0, 2)}•••';
    return '$shown@$domain';
  }

  void _onOtpChanged(int index, String value) {
    // Support pasting the full 6-digit code into any box.
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      _focusNodes[5].requestFocus();
      if (digits.length >= 6) _verify();
      return;
    }
    if (value.isNotEmpty && index < _controllers.length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verify() async {
    if (_loading) return;
    if (_otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code sent to your email');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthRepository.instance.verifyEmail(
        email: widget.email,
        otp: _otp,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Email verified! Please sign in to continue.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(initialEmail: widget.email.trim()),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.isServerError) {
          _error = 'Server is temporarily busy. Please try again.';
        } else {
          final expired = e.message.toLowerCase().contains('expired') ||
              e.message.toLowerCase().contains('invalid');
          _error = expired
              ? '${e.message} Tap Resend code to get a new one.'
              : e.message;
        }
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
    _startTimer();
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    try {
      await AuthRepository.instance.sendEmailOtp(widget.email);
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Verification code sent')),
        );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // The backend may not have rolled the resend endpoint out yet —
        // surface the failure gracefully and point at the code sent at
        // sign-up (same as the driver app).
        _error = e.statusCode == 404
            ? 'Resending is not available yet — the code was sent to your '
                'inbox at registration.'
            : e.isServerError
                ? 'Server is temporarily busy. Please try again.'
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

  void _continueToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(initialEmail: widget.email.trim()),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: _continueToLogin),
        title: const Text('Verify your email'),
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
              Text('Check your email',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                "We've sent a 6-digit code to",
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email.trim(),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                '($_maskedEmail)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
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
                          focusNode: _focusNodes[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
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
                          onChanged: (v) => _onOtpChanged(i, v),
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
                label: 'Verify Email',
                icon: Icons.chevron_right,
                loading: _loading,
                onPressed: _verify,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _continueToLogin,
                  child: const Text('Continue to login'),
                ),
              ),
              const SizedBox(height: 8),
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
