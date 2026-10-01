import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// Placeholder for Help & Support.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

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
                  Text('Help & Support', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.support_agent, size: 48, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('How can we help you?', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Our support team is available 24/7. Browse FAQs or contact us directly.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _HelpTile(icon: Icons.help_outline, title: 'FAQs', subtitle: 'Common questions about rides, payments & safety', onTap: () {}),
                  _HelpTile(icon: Icons.chat_bubble_outline, title: 'Live Chat', subtitle: 'Chat with our support team', onTap: () {}),
                  _HelpTile(icon: Icons.email_outlined, title: 'Email Support', subtitle: 'support@victoriarides.com', onTap: () {}),
                  _HelpTile(icon: Icons.call_outlined, title: 'Call Us', subtitle: '+234 800 VICTORIA', onTap: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outlineVariant)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.outline),
        onTap: onTap,
      ),
    );
  }
}
