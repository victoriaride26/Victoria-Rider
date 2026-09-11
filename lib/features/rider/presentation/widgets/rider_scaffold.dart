import 'package:flutter/material.dart';

import 'rider_bottom_nav.dart';
import '../screens/rider_home_shell.dart';

/// Scaffold wrapper for rider screens.
///
/// By default [showBottomNav] is false because the primary shell
/// ([RiderHomeShell]) hosts the persistent bottom navigation bar. Set
/// [showBottomNav] to true only if displaying outside of the shell.
class RiderScaffold extends StatelessWidget {
  const RiderScaffold({
    super.key,
    this.currentIndex = 0,
    required this.body,
    this.appBar,
    this.drawer,
    this.floatingActionButton,
    this.showBottomNav = false,
  });

  final int currentIndex;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final bool showBottomNav;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      drawer: drawer,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: showBottomNav
          ? RiderBottomNav(
              currentIndex: currentIndex,
              onTap: (i) => Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => RiderHomeShell(initialIndex: i)),
              ),
            )
          : null,
    );
  }
}
