import 'package:flutter/material.dart';

import '../../features/rider/presentation/screens/rider_home_shell.dart';
import '../theme/app_theme.dart';

/// Back navigation button used in transactional screens.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ??
          () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              final rootNav = Navigator.of(context, rootNavigator: true);
              if (rootNav.canPop()) {
                rootNav.pop();
              } else {
                final riderShell = RiderShellScope.maybeOf(context);
                if (riderShell != null) {
                  riderShell.selectTab(0);
                } else {
                  nav.maybePop();
                }
              }
            }
          },
      icon: const Icon(Icons.arrow_back, color: AppColors.primary),
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}