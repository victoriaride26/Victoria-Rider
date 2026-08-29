import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';

/// R-05 — Profile Setup: photo + name/email capture.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = TextEditingController();
    final lastName = TextEditingController();
    final email = TextEditingController();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Complete your profile'),
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
              Text('Complete your profile', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 24),
              Center(
                child: Stack(
                  children: [
                    const CircleAvatar(
                      radius: 46,
                      backgroundColor: AppColors.surfaceContainerLow,
                      child: Icon(Icons.person, size: 48,
                          color: AppColors.onSurfaceVariant),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_camera,
                            size: 18, color: AppColors.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text('ADD PHOTO',
                    style: TextStyle(
                        letterSpacing: 0.05,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'First Name',
                hintText: 'Victoria',
                icon: Icons.person_outline,
                controller: firstName,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Last Name',
                hintText: 'Rider',
                icon: Icons.person_outline,
                controller: lastName,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email Address',
                hintText: 'you@example.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                controller: email,
              ),
              const SizedBox(height: 16),
              Text(
                'By continuing, you agree that Victoria may contact you at the '
                'email provided. This helps us secure your account and send '
                'ride receipts.',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const Spacer(),
              AppPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                      builder: (_) => const RiderHomeShell(initialIndex: 0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
