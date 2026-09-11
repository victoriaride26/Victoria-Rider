import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../data/auth_repository.dart';
import 'login_screen.dart';

/// R-05 — Create Account: name + email + password (step 2 of onboarding).
///
/// The phone number was already verified on the OTP step. Submitting here
/// calls `POST /auth/register` (role RIDER) and redirects the rider to the
/// login screen so they can sign in to their new account.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.phone});

  /// Verified phone number carried through from the OTP step.
  final String phone;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final AuthRepository _auth = AuthRepository.instance;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Register creates the rider account (role RIDER).
      // Redirect the rider to the login screen so they can sign in.
      await _auth.register(
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        phone: widget.phone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully! Please sign in to continue.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(initialEmail: _emailController.text.trim()),
        ),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Create your account'),
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create your account',
                            style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Phone verified. Finish setting up your rider account.',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        AppTextField(
                          label: 'First Name',
                          hintText: 'Victoria',
                          icon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          controller: _firstNameController,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your first name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: 'Last Name',
                          hintText: 'Rider',
                          icon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          controller: _lastNameController,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your last name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: 'Email Address',
                          hintText: 'you@example.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          controller: _emailController,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter your email address';
                            }
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          label: 'Password',
                          hintText: 'Create a strong password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          controller: _passwordController,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Create a password';
                            }
                            if (v.length < 6) {
                              return 'Use at least 6 characters';
                            }
                            if (!RegExp(r'[A-Z]').hasMatch(v) ||
                                !RegExp(r'[a-z]').hasMatch(v) ||
                                !RegExp(r'[0-9]').hasMatch(v) ||
                                !RegExp(r'[^A-Za-z0-9]').hasMatch(v)) {
                              return 'Include uppercase, lowercase, a number '
                                  'and a special character';
                            }
                            return null;
                          },
                          suffix: IconButton(
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
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
                          hintText: 'Re-enter your password',
                          icon: Icons.lock_outline,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          controller: _confirmPasswordController,
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
                                () => _obscureConfirm = !_obscureConfirm),
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'By creating an account, you agree to our Terms of '
                          'Service and Privacy Policy.',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: AppColors.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppPrimaryButton(
                  label: 'Create Account',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
