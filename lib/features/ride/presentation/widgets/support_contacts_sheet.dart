import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/support_contacts.dart';

/// Modal listing the contacts behind the trip-in-progress **Emergency** and
/// **Customer Care** buttons (`GET /users/support/emergency`,
/// `GET /users/support/customer-service`). Every outcome — contacts, empty
/// state or a fetch error — renders here so the rider always gets a modal.
class SupportContactsSheet extends StatelessWidget {
  const SupportContactsSheet({
    super.key,
    required this.title,
    required this.contacts,
    this.errorMessage,
  });

  final String title;
  final List<SupportContact> contacts;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (contacts.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'No $title contacts are available right now. Please try again.',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ] else
                  for (final contact in contacts) ...[
                    if (contact.hasName) ...[
                      const SizedBox(height: 12),
                      Text(
                        contact.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (contact.location != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              contact.location!,
                              style: const TextStyle(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (contact.phone != null)
                      _ContactRow(
                        icon: Icons.phone,
                        iconColor: AppColors.primary,
                        iconBackground: AppColors.primaryContainer,
                        label: contact.phone!,
                        subtitle: 'Call',
                        onTap: () => _openTel(context, contact.phone!),
                      ),
                    if (contact.whatsappNumber != null)
                      _ContactRow(
                        icon: Icons.chat,
                        iconColor: Colors.white,
                        iconBackground: Colors.green,
                        label: contact.whatsappNumber!,
                        subtitle: 'WhatsApp',
                        onTap: () => _openWhatsApp(
                          context,
                          contact.whatsappNumber!,
                        ),
                      ),
                  ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTel(BuildContext context, String phone) async {
    // No `canLaunchUrl` gate: on Android 11+ it returns false unless the
    // manifest declares <queries> for the scheme, which silently did nothing.
    final url = Uri.parse('tel:${Uri.encodeComponent(phone)}');
    try {
      await launchUrl(url);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer.')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(BuildContext context, String whatsapp) async {
    final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    // Try the WhatsApp app deep link first, then the wa.me web link.
    final appUrl = Uri.parse('whatsapp://send?phone=$digits');
    final webUrl = Uri.parse('https://wa.me/$digits');
    try {
      if (await launchUrl(appUrl, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    try {
      if (await launchUrl(webUrl, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: iconBackground,
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
