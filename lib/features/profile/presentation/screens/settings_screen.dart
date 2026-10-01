import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'help_support_screen.dart';
import 'legal_screen.dart';

/// Rider Settings - linked from Profile and Drawer.
/// Includes Preferences, Privacy & Security, Support, Legal and About.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showLanguageSelector(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 16),
            Text('Select Language', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Choose your preferred language', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 16),
            _LanguageOption(flag: '🇳🇬', title: 'English (Nigeria)', subtitle: 'Default • Fully supported', selected: true, onTap: () { Navigator.of(ctx).pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Language is already set to English (Nigeria)'))); }),
            _LanguageOption(flag: '🇫🇷', title: 'Français', subtitle: 'Coming soon', enabled: false, onTap: () { Navigator.of(ctx).pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('French support coming soon'))); }),
            _LanguageOption(flag: '🇳🇬', title: 'Hausa', subtitle: 'Coming soon', enabled: false, onTap: () { Navigator.of(ctx).pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hausa support coming soon'))); }),
            const SizedBox(height: 8),
            Text('More languages will be added based on community demand.', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiderScaffold(
      currentIndex: 3,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  AppBackButton(onPressed: () {
                    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                  }),
                  const SizedBox(width: 8),
                  Text('Settings', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Preferences', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _SettingsTile(icon: Icons.notifications_outlined, title: 'Notifications', subtitle: 'Ride updates, promos & safety alerts', trailing: Switch(value: true, onChanged: (_) {}, activeThumbColor: AppColors.primary)),
                  _SettingsTile(icon: Icons.language, title: 'Language', subtitle: 'English (Nigeria)', onTap: () => _showLanguageSelector(context)),
                  _SettingsTile(icon: Icons.dark_mode_outlined, title: 'Dark Mode', trailing: Switch(value: false, onChanged: (_) {}, activeThumbColor: AppColors.primary)),
                  const SizedBox(height: 24),
                  Text('Privacy & Security', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Privacy',
                    subtitle: 'Manage data & permissions',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Privacy settings coming soon'))),
                  ),
                  _SettingsTile(
                    icon: Icons.security_outlined,
                    title: 'Security',
                    subtitle: 'Biometrics, 2FA',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Security settings coming soon'))),
                  ),
                  _SettingsTile(
                    icon: Icons.delete_outline,
                    title: 'Delete Account',
                    subtitle: 'Permanently delete your account',
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Account?'),
                          content: const Text('This will permanently delete your Victoria Rides account and all associated data. This action cannot be undone.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deletion requires verification. Contact support@victoriarides.com')));
                              },
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    isDestructive: true,
                  ),
                  const SizedBox(height: 24),
                  Text('Support', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _SettingsTile(icon: Icons.support_agent, title: 'Help & Support', subtitle: 'FAQs, chat and contact us', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpSupportScreen()))),
                  const SizedBox(height: 24),
                  Text('Legal', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _SettingsTile(icon: Icons.gavel_outlined, title: 'Legal', subtitle: 'Privacy Policy • Terms & Conditions', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LegalScreen()))),
                  const SizedBox(height: 24),
                  Text('About', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outlineVariant)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Victoria Rides • v1.0.0', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Made with care in Makurdi, Benue State', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.isDestructive = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool isDestructive;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outlineVariant)),
      child: ListTile(
        leading: Icon(icon, color: isDestructive ? AppColors.error : AppColors.primary),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isDestructive ? AppColors.error : AppColors.onSurface)),
        subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)) : null,
        trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, size: 18, color: AppColors.outline) : null),
        onTap: onTap,
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({required this.flag, required this.title, required this.subtitle, this.selected = false, this.enabled = true, required this.onTap});
  final String flag;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.outlineVariant, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: enabled ? AppColors.onSurface : AppColors.onSurfaceVariant)),
                  Text(subtitle, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20) else const Icon(Icons.chevron_right, size: 18, color: AppColors.outlineVariant),
          ],
        ),
      ),
    );
  }
}
