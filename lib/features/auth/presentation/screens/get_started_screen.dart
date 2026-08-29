import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'phone_login_screen.dart';

/// R-02 — Get Started: value proposition + entry into the auth flow.
class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});

  static const List<_Feature> _features = [
    _Feature(Icons.timer_outlined, 'Book in seconds',
        'One-tap ride requests anywhere, anytime.'),
    _Feature(Icons.verified_user_outlined, 'Safe drivers',
        'Thoroughly vetted and professional captains.'),
    _Feature(Icons.account_balance_wallet_outlined, 'Cashless payment',
        'Seamless digital transactions for every trip.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: AppColors.onPrimaryContainer, size: 36),
              ),
              const SizedBox(height: 24),
              Text('Welcome to Victoria', style: theme.textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                'Your premium urban commute, redefined with precision.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const Spacer(flex: 2),
              ...[
                for (final f in _features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(f.icon, color: AppColors.primary),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.title, style: theme.textTheme.titleLarge),
                              const SizedBox(height: 2),
                              Text(f.subtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PhoneLoginScreen()),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Get Started'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'By continuing, you agree to our Terms of Service',
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

class _Feature {
  const _Feature(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}
