import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../data/auth_repository.dart';
import 'login_screen.dart';

/// R-reset Set New Password (email OTP).
///
/// Submits the 6-digit code from `POST /auth/forgot-password` plus the
/// new password to `POST /auth/reset-password`
/// `{email, otp, newPassword}`.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  /// Email the reset code was sent to.
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final AuthRepository _auth = AuthRepository.instance;
  bool _loading = false;
  bool _resending = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : null,
        ),
      );
  }

  Future<void> _resendCode() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await _auth.forgotPassword(widget.email);
      if (!mounted) return;
      setState(() => _resending = false);
      _showMessage('Reset code sent to ${widget.email}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _resending = false);
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _resending = false);
      _showMessage('Something went wrong. Please try again.', isError: true);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _auth.resetPassword(
        email: widget.email,
        otp: _otpController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Password reset successfully. Please sign in.'),
          ),
        );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Something went wrong. Please try again.', isError: true);
    }
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Create a password';
    if (v.length < 6) return 'Use at least 6 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v) ||
        !RegExp(r'[a-z]').hasMatch(v) ||
        !RegExp(r'[0-9]').hasMatch(v) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(v)) {
      return 'Include uppercase, lowercase, a number and a special character';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Set New Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Check your email',
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'We sent a 6-digit code to ${widget.email}. Enter it below with your new password.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                AppTextField(
                  label: 'Reset Code',
                  controller: _otpController,
                  hintText: '6-digit code',
                  icon: Icons.sms_outlined,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final code = v?.trim() ?? '';
                    if (code.isEmpty) return 'Enter the 6-digit code';
                    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                      return 'Code must be 6 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'New Password',
                  controller: _passwordController,
                  hintText: 'Create a strong password',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  validator: _validatePassword,
                  suffix: IconButton(
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Confirm Password',
                  controller: _confirmController,
                  hintText: 'Re-enter your password',
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Confirm your password';
                    }
                    if (v != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                  suffix: IconButton(
                    onPressed: () => setState(
                      () => _obscureConfirm = !_obscureConfirm,
                    ),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                AppPrimaryButton(
                  label: 'Reset Password',
                  icon: Icons.check_circle,
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _resending ? null : _resendCode,
                    child: Text(_resending ? 'Sending…' : 'Resend code'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
