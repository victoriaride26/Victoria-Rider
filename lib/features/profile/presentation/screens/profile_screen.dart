import 'package:flutter/material.dart';

import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// Rider profile tab.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = SessionController.instance.user;
    final firstName = user?['firstName'] as String? ?? 'Victoria';
    final lastName = user?['lastName'] as String? ?? 'Rider';
    final fullName = '$firstName $lastName'.trim();
    final email = user?['email'] as String? ??
        SessionController.instance.rememberedEmail ??
        'rider@victoriaride.com';
    final initials = (firstName.isNotEmpty ? firstName[0] : 'V') +
        (lastName.isNotEmpty ? lastName[0] : 'R');

    return RiderScaffold(
      currentIndex: 3,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Builder(
                  builder: (ctx) => IconButton(
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                    icon: const Icon(Icons.menu, color: AppColors.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Profile', style: theme.textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              fullName,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const ListTile(
              leading: Icon(Icons.history, color: AppColors.primary),
              title: Text('My Rides'),
              trailing: Icon(Icons.chevron_right),
            ),
            const ListTile(
              leading: Icon(Icons.card_giftcard, color: AppColors.primary),
              title: Text('Executive Rewards'),
              trailing: Icon(Icons.chevron_right),
            ),
            const ListTile(
              leading: Icon(Icons.support_agent, color: AppColors.primary),
              title: Text('Help & Support'),
              trailing: Icon(Icons.chevron_right),
            ),
            const ListTile(
              leading: Icon(Icons.settings, color: AppColors.primary),
              title: Text('Settings'),
              trailing: Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text(
                'Log Out',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => _confirmLogout(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text(
          'Are you sure you want to log out of your Victoria Rides account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );

      await AuthRepository.instance.logout();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}
