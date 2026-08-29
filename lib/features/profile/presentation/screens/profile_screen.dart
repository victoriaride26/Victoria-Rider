import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';

/// Rider profile tab. Placeholder until the full profile flow is built.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RiderScaffold(
      currentIndex: 3,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primaryContainer,
              child: Icon(Icons.person, size: 40, color: AppColors.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(
              'Victoria Rider',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'victoria.rider@example.com',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
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
          ],
        ),
      ),
    );
  }
}
