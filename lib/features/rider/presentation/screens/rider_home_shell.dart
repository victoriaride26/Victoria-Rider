import 'package:flutter/material.dart';

import '../../../../core/services/location_service.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../payments/presentation/screens/wallet_dashboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../ride/presentation/screens/ride_history_screen.dart';
import '../widgets/rider_bottom_nav.dart';
import '../widgets/rider_drawer.dart';
import 'location_permission_screen.dart';

/// Persistent rider shell holding the four primary tabs.
class RiderHomeShell extends StatefulWidget {
  const RiderHomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<RiderHomeShell> createState() => _RiderHomeShellState();
}

class _RiderHomeShellState extends State<RiderHomeShell>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _locationService = LocationService();

  late int _index;

  /// Tracks whether the location gate has been satisfied this session.
  /// Prevents showing the gate again on every hot-reload / tab switch.
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    // Show the gate after the first frame so the Navigator is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService.dispose();
    super.dispose();
  }

  /// Re-check when the user returns from background (e.g., from Settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_locationGranted) {
      _ensureLocation();
    }
  }

  /// Checks location permission status. If not granted, pushes the full-screen
  /// [LocationPermissionScreen]. Waits for it to pop (with `true` = granted)
  /// before marking [_locationGranted] and allowing the shell to render normally.
  Future<void> _ensureLocation() async {
    if (_locationGranted || !mounted) return;

    try {
      final status = await _locationService.checkPermissionStatus();
      if (!mounted) return;

      if (status == LocationPermissionStatus.granted) {
        setState(() => _locationGranted = true);
        return;
      }

      // Push the blocking gate. It pops itself with `true` once granted.
      final granted = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const LocationPermissionScreen(),
          // Prevent back-swipe dismissal — the gate must be resolved.
          fullscreenDialog: true,
        ),
      );

      if (mounted && granted == true) {
        setState(() => _locationGranted = true);
      }
    } catch (e) {
      debugPrint('RiderHomeShell _ensureLocation error: $e');
    }
  }

  void _setTab(int i) {
    if (_index != i) {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        onNavigateToTab: _setTab,
      ),
      const RideHistoryScreen(),
      const WalletDashboardScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: RiderDrawer(onSelectTab: _setTab),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: RiderBottomNav(
        currentIndex: _index,
        onTap: _setTab,
      ),
    );
  }
}
