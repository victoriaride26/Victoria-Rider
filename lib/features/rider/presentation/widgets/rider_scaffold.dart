import 'package:flutter/material.dart';

import 'rider_bottom_nav.dart';
import '../screens/rider_home_shell.dart';

/// Scaffold wrapper that renders the rider bottom navigation bar.
///
/// Tapping a tab replaces the current route with the [RiderHomeShell] at
/// the chosen index, so the bottom nav behaves like a persistent shell.
class RiderScaffold extends StatelessWidget {
  const RiderScaffold({
    super.key,
    required this.currentIndex,
    required this.body,
    this.appBar,
    this.floatingActionButton,
  });

  final int currentIndex;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: RiderBottomNav(
        currentIndex: currentIndex,
        onTap: (i) => Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => RiderHomeShell(initialIndex: i)),
        ),
      ),
    );
  }
}
