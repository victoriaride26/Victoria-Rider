import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// Legal hub for rider app — Privacy Policy, Terms, etc.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

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
              child: Row(children: [AppBackButton(onPressed: () => Navigator.of(context).maybePop()), const SizedBox(width: 8), Text('Legal', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary))]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
                    child: Row(children: [const Icon(Icons.gavel_outlined, color: AppColors.primary), const SizedBox(width: 12), Expanded(child: Text('Legal documents will be supplied. Sections below are ready.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant, height: 1.4)))]),
                  ),
                  const SizedBox(height: 16),
                  _LegalTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', subtitle: 'How we collect and protect your data', onTap: () => _open(context, 'Privacy Policy')),
                  _LegalTile(icon: Icons.description_outlined, title: 'Terms & Conditions', subtitle: AppConstants.termsSubtitle, onTap: () => _open(context, 'Terms & Conditions')),
                  _LegalTile(icon: Icons.receipt_long_outlined, title: 'Rider Terms', subtitle: 'Rights and responsibilities as a rider', onTap: () => _open(context, 'Rider Terms')),
                  _LegalTile(icon: Icons.security_outlined, title: 'Safety & Community Guidelines', subtitle: 'Safe and respectful rides', onTap: () => _open(context, 'Community Guidelines')),
                  _LegalTile(icon: Icons.cookie_outlined, title: 'Cookie Policy', onTap: () => _open(context, 'Cookie Policy')),
                  _LegalTile(icon: Icons.payments_outlined, title: 'Fare & Refund Policy', onTap: () => _open(context, 'Fare Policy')),
                  _LegalTile(icon: Icons.support_agent_outlined, title: 'Support & Disputes', onTap: () => _open(context, 'Support Policy')),
                  const SizedBox(height: 16),
                  Text('Last updated: —  Final copy will replace placeholders. Contact support@victoriarides.com', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, String title) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _LegalDetail(title: title)));
  }
}

class _LegalDetail extends StatelessWidget {
  const _LegalDetail({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RiderScaffold(
      currentIndex: 3,
      body: SafeArea(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Row(children: [AppBackButton(onPressed: () => Navigator.of(context).maybePop()), const SizedBox(width: 8), Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))])),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.description_outlined, size: 48, color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(AppConstants.legalPlaceholder, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant, height: 1.5)),
                  const SizedBox(height: 16),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.outlineVariant)), child: Text('Placeholder • Final legal copy will replace this.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant))),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  const _LegalTile({required this.icon, required this.title, this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outlineVariant)),
      child: ListTile(leading: Icon(icon, color: AppColors.primary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)) : null, trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.outline), onTap: onTap),
    );
  }
}
