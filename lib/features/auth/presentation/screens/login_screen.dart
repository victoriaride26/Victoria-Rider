import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/services/social_sign_in_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';
import '../../data/auth_repository.dart';
import 'phone_login_screen.dart';

/// R-06 — Rider Login: sign in after completing the profile form.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialEmail});

  /// Email entered on the profile setup screen, prefilled for the user.
  final String? initialEmail;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthRepository _auth = AuthRepository.instance;
  bool _obscurePassword = true;
  bool _loading = false;
  SocialProvider? _socialLoading;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    final session = SessionController.instance;
    _rememberMe = session.rememberMe;
    final rememberedEmail = session.rememberedEmail;
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    } else if (rememberedEmail != null && rememberedEmail.isNotEmpty) {
      _emailController.text = rememberedEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      SessionController.instance.rememberMe = _rememberMe;
      await _auth.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      await SessionController.instance.saveRememberPrefs(
        rememberMe: _rememberMe,
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      AppRouter.pushAndClearStack(context, const RiderHomeShell());
    } on ApiException catch (e) {
      setState(() => _loading = false);
      _showMessage(e.message, isError: true);
    } catch (_) {
      setState(() => _loading = false);
      _showMessage('Something went wrong. Please try again.', isError: true);
    }
  }

  Future<void> _socialSignIn(SocialProvider provider) async {
    if (_socialLoading != null) return;
    setState(() => _socialLoading = provider);
    try {
      final idToken = await SocialSignInService.getIdToken(provider);
      if (!mounted) return;
      if (idToken == null) {
        setState(() => _socialLoading = null);
        _showMessage(
          '${provider == SocialProvider.apple ? 'Apple' : 'Google'} sign-in '
          'is not available yet. Please use your email and password.',
        );
        return;
      }
      final result = await _auth.socialLogin(
        provider: provider,
        idToken: idToken,
      );
      if (!mounted) return;
      if (result.requiresPhoneVerification) {
        setState(() => _socialLoading = null);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PhoneLoginScreen(
              onboardingToken: result.onboardingToken,
            ),
          ),
        );
        return;
      }
      AppRouter.pushAndClearStack(context, const RiderHomeShell());
    } on ApiException catch (e) {
      setState(() => _socialLoading = null);
      _showMessage(e.message, isError: true);
    } catch (_) {
      setState(() => _socialLoading = null);
      _showMessage('Something went wrong. Please try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/icons/logo.png',
                          width: 64,
                          height: 64,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: AppColors.onBackground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to start riding',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppTextField(
                        label: 'Email or Phone Number',
                        controller: _emailController,
                        hintText: 'Enter your email or phone',
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Enter your email or phone number'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Password',
                        controller: _passwordController,
                        hintText: 'Enter your password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter your password' : null,
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (v) => setState(
                                      () => _rememberMe = v ?? true),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                const Text('Remember me'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AppPrimaryButton(
                        label: 'Login',
                        loading: _loading,
                        onPressed: _login,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Or continue with',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _socialLoading == null
                                  ? () => _socialSignIn(SocialProvider.google)
                                  : null,
                              icon: _socialLoading == SocialProvider.google
                                  ? const _ButtonSpinner()
                                  : const Image(
                                      image: AssetImage('assets/icons/google.png'),
                                      width: 20,
                                      height: 20,
                                    ),
                              label: const Text('Google'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _socialLoading == null
                                  ? () => _socialSignIn(SocialProvider.apple)
                                  : null,
                              icon: _socialLoading == SocialProvider.apple
                                  ? const _ButtonSpinner()
                                  : const Image(
                                      image: AssetImage(
                                          'assets/icons/apple-icon.png'),
                                      width: 20,
                                      height: 20,
                                    ),
                              label: const Text('Apple'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'By continuing, you agree to our Terms of Service '
                        'and Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}