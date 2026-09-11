import 'package:flutter/material.dart';

import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/screens/login_screen.dart';
import '../../../payments/presentation/screens/wallet_dashboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../ride/presentation/screens/destination_search_screen.dart';
import '../../../ride/presentation/screens/ride_history_screen.dart';

/// Premium Rider Navigation Drawer.
class RiderDrawer extends StatelessWidget {
  const RiderDrawer({super.key, this.onSelectTab});

  /// Optional callback to switch tabs on [RiderHomeShell].
  final ValueChanged<int>? onSelectTab;

  void _handleTabSelect(BuildContext context, int tabIndex) {
    Navigator.of(context).pop(); // Close drawer
    if (onSelectTab != null) {
      onSelectTab!(tabIndex);
    } else {
      // Fallback navigation if not in shell
      final screens = [
        null,
        const RideHistoryScreen(),
        const WalletDashboardScreen(),
        const ProfileScreen(),
      ];
      final target = screens[tabIndex];
      if (target != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => target),
        );
      }
    }
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

  void _showInfoDialog(BuildContext context, String title, String message) {
    Navigator.of(context).pop(); // Close drawer
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionController.instance.user;
    final firstName = user?['firstName'] as String? ?? 'Victoria';
    final lastName = user?['lastName'] as String? ?? 'Rider';
    final fullName = '$firstName $lastName'.trim();
    final email = user?['email'] as String? ??
        SessionController.instance.rememberedEmail ??
        'rider@victoriaride.com';
    final initials = (firstName.isNotEmpty ? firstName[0] : 'V') +
        (lastName.isNotEmpty ? lastName[0] : 'R');

    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            // User Header Card
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border(
                  bottom: BorderSide(color: AppColors.surfaceContainerHigh),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
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
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onPrimary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Rating & Status Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded,
                                size: 16, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text(
                              '4.9',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              '• Gold Rider',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                size: 14, color: AppColors.primaryContainer),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Drawer Items List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                children: [
                  _DrawerTile(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    title: 'Home',
                    onTap: () => _handleTabSelect(context, 0),
                  ),
                  _DrawerTile(
                    icon: Icons.directions_car_outlined,
                    activeIcon: Icons.directions_car,
                    title: 'My Rides',
                    badge: 'History',
                    onTap: () => _handleTabSelect(context, 1),
                  ),
                  _DrawerTile(
                    icon: Icons.account_balance_wallet_outlined,
                    activeIcon: Icons.account_balance_wallet,
                    title: 'Wallet & Payments',
                    onTap: () => _handleTabSelect(context, 2),
                  ),
                  _DrawerTile(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    title: 'My Profile',
                    onTap: () => _handleTabSelect(context, 3),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Divider(),
                  ),
                  _DrawerTile(
                    icon: Icons.bookmark_border,
                    title: 'Saved Places',
                    subtitle: 'Home, Work & Favorites',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DestinationSearchScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.card_giftcard_outlined,
                    title: 'Promotions & Discounts',
                    badge: 'NEW',
                    badgeColor: AppColors.primary,
                    onTap: () => _showInfoDialog(
                      context,
                      'Promotions & Discounts',
                      'Enjoy 20% off your next 3 rides using promo code VICTORIA20 at checkout!',
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.shield_outlined,
                    title: 'Victoria Shield Safety',
                    subtitle: '24/7 SOS & Trip Sharing',
                    onTap: () => _showInfoDialog(
                      context,
                      'Victoria Shield Safety',
                      'Victoria Rides ensures every trip is monitored with 24/7 safety assistance, emergency SOS contact sharing, and thoroughly vetted drivers.',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Divider(),
                  ),
                  _DrawerTile(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    onTap: () => _showInfoDialog(
                      context,
                      'Help & Support',
                      'Need help? Our customer support team is available 24/7. Contact us at support@victoriarides.com or via live chat.',
                    ),
                  ),
                  _DrawerTile(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: () => _showInfoDialog(
                      context,
                      'Settings',
                      'Manage notifications, privacy, language, and security preferences.',
                    ),
                  ),
                ],
              ),
            ),

            // Footer: Version & Logout
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.surfaceContainerHigh),
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    tileColor: AppColors.errorContainer.withValues(alpha: 0.35),
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
                  const SizedBox(height: 8),
                  Text(
                    'Victoria Rides • v1.0.0',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    this.activeIcon,
    required this.title,
    this.subtitle,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String title;
  final String? subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            )
          : null,
      trailing: badge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor ?? AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onPrimary,
                ),
              ),
            )
          : const Icon(Icons.chevron_right, size: 18, color: AppColors.outline),
      onTap: onTap,
    );
  }
}
