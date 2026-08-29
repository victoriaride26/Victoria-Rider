import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Bottom navigation for the rider app: Home · Rides · Wallet · Profile.
class RiderBottomNav extends StatelessWidget {
  const RiderBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<NavItem> items = [
    NavItem(Icons.home_outlined, Icons.home, 'Home'),
    NavItem(Icons.directions_car_outlined, Icons.directions_car, 'Rides'),
    NavItem(Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet, 'Wallet'),
    NavItem(Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.onSurfaceVariant,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      items: [
        for (var i in items)
          BottomNavigationBarItem(
            icon: Icon(currentIndex == items.indexOf(i) ? i.active : i.idle),
            label: i.label,
          ),
      ],
    );
  }
}

class NavItem {
  const NavItem(this.idle, this.active, this.label);
  final IconData idle;
  final IconData active;
  final String label;
}
