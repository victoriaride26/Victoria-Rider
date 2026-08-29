import 'package:flutter/material.dart';

import '../../../home/presentation/screens/home_screen.dart';
import '../../../payments/presentation/screens/wallet_dashboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../ride/presentation/screens/ride_history_screen.dart';
import '../widgets/rider_bottom_nav.dart';

/// Persistent rider shell holding the four primary tabs.
class RiderHomeShell extends StatefulWidget {
  const RiderHomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<RiderHomeShell> createState() => _RiderHomeShellState();
}

class _RiderHomeShellState extends State<RiderHomeShell> {
  late int _index;

  static const List<Widget> _screens = [
    HomeScreen(),
    RideHistoryScreen(),
    WalletDashboardScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: RiderBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
