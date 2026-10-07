import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/models/saved_place.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/benue_gazetteer.dart';
import '../../../../core/services/location_service.dart';
import '../../../payments/data/rider_wallet_repository.dart';
import '../../../../core/services/places_storage_service.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../ride/presentation/screens/daily_ride_screen.dart';
import '../../../ride/presentation/screens/destination_search_screen.dart';
import '../../../ride/presentation/screens/reserve_ride_screen.dart';
import '../../../ride/presentation/screens/ride_history_screen.dart';
import '../../../ride/presentation/widgets/ride_request_sheet.dart';
import '../../../notifications/data/notification_service.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';

/// R-06 — Redesigned Rider Dashboard.
///
/// Features:
/// - Hamburger drawer trigger & quick location pill
/// - Time-aware personalized greeting
/// - Hero "Where to?" booking search card
/// - Quick service category shortcuts (Daily Ride, Reserve, Courier, Wallet)
/// - Wallet balance preview card with instant top-up action
/// - Saved places quick-tap cards (Home, Work, Market)
/// - Recent ride history cards with "Book Again" action
/// - Victoria Shield safety & security highlight
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenDrawer, this.onNavigateToTab});

  /// Triggers opening the persistent drawer on the home shell.
  final VoidCallback? onOpenDrawer;

  /// Requests tab navigation on the home shell.
  final ValueChanged<int>? onNavigateToTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// One row in the dashboard's Recent Activity: either a ride or a wallet
/// top-up, newest first.
class _DashboardActivity {
  const _DashboardActivity({
    required this.title,
    required this.subtitle,
    required this.amountNgn,
    required this.isCredit,
    required this.isRide,
    required this.createdAt,
  });

  final String title;
  final String subtitle;
  final double amountNgn;
  final bool isCredit;
  final bool isRide;
  final DateTime createdAt;
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<_DashboardActivity> _recentActivity = [];
  final _locationService = LocationService();
  CurrentLocation? _currentLocation;
  bool _locationLoading = true;

  List<SavedPlace> _savedPlaces = [];

  /// Guards overlapping pickup-fix requests (initial load + pill tap +
  /// pull-to-refresh): only the latest generation may write state.
  int _locationGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Warm the bundled gazetteer cache so the first pickup label resolves
    // instantly and offline instead of paying the asset parse on the GPS path.
    unawaited(BenueGazetteer.load());
    _loadDashboardData();
    _loadCurrentLocation();
    _loadSavedPlaces();
  }

  void _loadSavedPlaces() {
    setState(() {
      _savedPlaces = PlacesStorageService.instance.getSavedPlaces();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_currentLocation == null) _loadCurrentLocation();
      _loadSavedPlaces();
    }
  }

  /// Two-stage pickup fix for the dashboard:
  ///
  ///  1. Instant — OS last-known position labelled offline from the bundled
  ///     Benue gazetteer, so the pill shows a real Makurdi name on first
  ///     frame instead of a spinner.
  ///  2. Refine — fresh high-accuracy GPS fix, labelled local-first
  ///     (gazetteer → Mapbox → Geoapify → coordinates), replacing the instant
  ///     label when it lands.
  ///
  /// The old 2 s timeout fired before a cold GPS fix ever arrived, leaving the
  /// pill on its fallback text until the rider manually retried.
  Future<void> _loadCurrentLocation({bool refresh = false}) async {
    if (!mounted) return;
    final generation = ++_locationGeneration;
    bool stillCurrent() => mounted && generation == _locationGeneration;

    if (!refresh) {
      // Stage 1 — instant last-known fix (no GPS wait, no permission prompt).
      // Capped: on some devices / in widget tests the OS call can hang, and
      // the pill must never stay a spinner forever.
      try {
        final instant = await _locationService
            .getLastKnownLocation()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (instant != null && stillCurrent()) {
          setState(() {
            _currentLocation = instant;
            _locationLoading = false;
          });
        } else if (stillCurrent()) {
          setState(() => _locationLoading = true);
        }
      } catch (_) {
        if (stillCurrent()) setState(() => _locationLoading = true);
      }
    } else {
      if (stillCurrent()) setState(() => _locationLoading = true);
    }

    // Stage 2 — fresh GPS fix with a budget that actually covers a cold start
    // (15 s GPS) plus provider fallbacks on a gazetteer miss.
    try {
      final loc = await _locationService
          .getCurrentLocation()
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      if (!stillCurrent()) return;
      setState(() {
        if (loc != null) _currentLocation = loc;
        _locationLoading = false;
      });
    } catch (_) {
      if (stillCurrent()) setState(() => _locationLoading = false);
    }
  }

  /// Loads the top-5 Recent Activity from both feeds — latest rides plus
  /// wallet top-ups — newest first. Ride parsing is shared with the history
  /// tab (same envelopes); each feed fails independently so one bad endpoint
  /// never empties the widget.
  Future<void> _loadDashboardData() async {
    final activities = <_DashboardActivity>[];

    try {
      final res = await ApiClient.instance.get(
        '/api/v1/rides/history?page=1&limit=5',
      );
      for (final ride in RideHistoryItem.parseAll(res)) {
        activities.add(
          _DashboardActivity(
            title: ride.dropoffAddress.isNotEmpty
                ? ride.dropoffAddress
                : 'Trip',
            subtitle:
                '${ride.createdAt.day}/${ride.createdAt.month}/${ride.createdAt.year} • ${ride.status}',
            amountNgn: ride.displayFareNgn,
            isCredit: false,
            isRide: true,
            createdAt: ride.createdAt,
          ),
        );
      }
    } catch (e) {
      debugPrint('[HomeScreen] rides activity error: $e');
    }

    try {
      final txns = await RiderWalletRepository.instance.getTransactions();
      for (final tx in txns) {
        if (!tx.isCredit) continue;
        activities.add(
          _DashboardActivity(
            title: tx.title.isNotEmpty ? tx.title : 'Wallet Top-up',
            subtitle:
                '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} • ${tx.status}',
            amountNgn: tx.amountNgn,
            isCredit: true,
            isRide: false,
            createdAt: tx.createdAt,
          ),
        );
      }
    } catch (e) {
      debugPrint('[HomeScreen] funding activity error: $e');
    }

    if (!mounted) return;
    activities.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() => _recentActivity = activities.take(5).toList());
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = SessionController.instance.user;
    final firstName = (user?['firstName'] as String?)?.trim();
    final displayName = (firstName != null && firstName.isNotEmpty)
        ? firstName
        : 'Victoria';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await Future.wait([
              _loadDashboardData(),
              _loadCurrentLocation(refresh: true),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              // --- Top Bar: Drawer Trigger, Location Pill, Notification/Profile ---
              Row(
                children: [
                  // Hamburger Menu Button
                  Material(
                    color: AppColors.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: AppColors.surfaceContainerHigh,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (widget.onOpenDrawer != null) {
                          widget.onOpenDrawer!();
                        } else {
                          Scaffold.of(context).openDrawer();
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.menu_rounded,
                          color: AppColors.onSurface,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Current City Pill
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        await _loadCurrentLocation(refresh: true);
                        if (!context.mounted) return;
                        if (_currentLocation != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'GPS location: ${_currentLocation!.shortLabel}',
                              ),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.surfaceContainerHigh,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _locationLoading
                                  ? const SizedBox(
                                      height: 12,
                                      width: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.primary,
                                            ),
                                      ),
                                    )
                                  : Text(
                                      _currentLocation?.shortLabel ??
                                          'Makurdi, Benue State',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: AppColors.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Notifications bell — curated via SharedPreferences
                  ListenableBuilder(
                    listenable: RiderNotificationService.instance,
                    builder: (context, _) {
                      final unread = RiderNotificationService.instance.unreadCount;
                      return Material(
                        color: AppColors.surfaceContainerLowest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.surfaceContainerHigh),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RiderNotificationsScreen())),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(Icons.notifications_outlined, color: AppColors.primary, size: 22),
                              ),
                              if (unread > 0)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(10)),
                                    child: Text(unread > 9 ? '9+' : '$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Safety Shield / Quick Profile Avatar
                  Material(
                    color: AppColors.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(
                        color: AppColors.surfaceContainerHigh,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (widget.onNavigateToTab != null) {
                          widget.onNavigateToTab!(3); // Navigate to Profile tab
                        } else {
                          widget.onOpenDrawer?.call();
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'V',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // --- Personalized Greeting ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_getGreeting()}, $displayName',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Where would you like to travel today?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // --- Hero Destination Search Card ---
              Material(
                elevation: 2,
                shadowColor: Colors.black.withValues(alpha: 0.06),
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceContainerHigh),
                  ),
                  child: Column(
                    children: [
                      // Pickup row (tappable to refresh GPS or search custom pickup location)
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        onTap: () async {
                          if (_currentLocation == null) {
                            await _loadCurrentLocation(refresh: true);
                            if (_currentLocation != null) return;
                          }
                          if (!context.mounted) return;
                          final selected = await Navigator.of(context)
                              .push<CurrentLocation>(
                                MaterialPageRoute<CurrentLocation>(
                                  builder: (_) => DestinationSearchScreen(
                                    currentLocation: _currentLocation,
                                    initialTarget: SearchTarget.pickup,
                                    isSettingPickup: true,
                                  ),
                                ),
                              );
                          if (selected != null && mounted) {
                            setState(() => _currentLocation = selected);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _locationLoading
                                    ? Row(
                                        children: [
                                          const SizedBox(
                                            height: 12,
                                            width: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    AppColors.primary,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Getting location…',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: AppColors
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        _currentLocation != null
                                            ? 'Pickup: ${_currentLocation!.shortLabel}'
                                            : 'Pickup: Tap to set location',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: _currentLocation != null
                                                  ? AppColors.onSurface
                                                  : AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _currentLocation == null ? 'SET' : 'GPS',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Connector line and divider
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Container(
                                width: 2,
                                height: 12,
                                color: AppColors.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(width: 18),
                            const Expanded(
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.surfaceContainerHigh,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Destination row (tappable to start ride search)
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        onTap: () async {
                          final updatedPickup = await Navigator.of(context)
                              .push<CurrentLocation>(
                                MaterialPageRoute<CurrentLocation>(
                                  builder: (_) => DestinationSearchScreen(
                                    currentLocation: _currentLocation,
                                    initialTarget: SearchTarget.destination,
                                  ),
                                ),
                              );
                          if (updatedPickup != null && mounted) {
                            setState(() => _currentLocation = updatedPickup);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Text(
                                  'Where to?',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.search,
                                  color: AppColors.onPrimary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- Quick Action Services ---
              // Courier removed for now - Daily Ride + Reserve resized to fill row
              Row(
                children: [
                  _QuickServiceCard(
                    icon: Icons.directions_car,
                    title: 'Daily Ride',
                    subtitle: 'Instant pickup',
                    highlight: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DailyRideScreen(
                          currentLocation: _currentLocation,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _QuickServiceCard(
                    icon: Icons.event_available,
                    title: 'Reserve',
                    subtitle: 'Schedule trip',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReserveRideScreen(
                          currentLocation: _currentLocation,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // --- Saved Places Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Saved Places',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DestinationSearchScreen(
                            initialTarget: SearchTarget.destination,
                          ), // The search screen now has an "Add Saved Place" button
                        ),
                      );
                      _loadSavedPlaces();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Add Place',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _savedPlaces.length,
                  separatorBuilder: (context, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final place = _savedPlaces[i];
                    return Material(
                      color: AppColors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(
                          color: AppColors.surfaceContainerHigh,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          // Auto setup ride request: Pickup = Current Location, Dropoff = Saved Location
                          final destination = place.toGeocodingResult();
                          showRideRequestSheet(
                            context,
                            destination: destination,
                            currentLocation: _currentLocation,
                          );
                        },
                        child: Container(
                          width: 170,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      place.type.icon,
                                      color: AppColors.primary,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      place.type.label,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                place.shortName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // --- Recent Activity Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Activity',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (widget.onNavigateToTab != null) {
                        widget.onNavigateToTab!(1); // Ride history tab
                      }
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (_recentActivity.isNotEmpty) ...[
                for (final tx in _recentActivity)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceContainerHigh),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tx.isCredit
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            tx.isCredit
                                ? Icons.account_balance_wallet
                                : Icons.directions_car,
                            color: tx.isCredit
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tx.subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${tx.isCredit ? '+' : '-'}₦${tx.amountNgn.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: tx.isCredit
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                            ),
                            if (tx.isRide) ...[
                              const SizedBox(height: 2),
                              InkWell(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const DestinationSearchScreen(
                                          currentLocation: null,
                                        ),
                                  ),
                                ),
                                child: const Text(
                                  'Rebook',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.surfaceContainerHigh),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.directions_car_outlined,
                          size: 32,
                          color: AppColors.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No Recent Activity',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your completed trips and wallet top-ups around locations in Nigeria will appear here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DestinationSearchScreen(
                              currentLocation: _currentLocation,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('Book a Ride'),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // --- Victoria Shield Safety Banner ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: AppColors.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Victoria Shield™ Safety',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All trips monitored with 24/7 emergency support and verified captains.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickServiceCard extends StatelessWidget {
  const _QuickServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.highlight = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: highlight
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.surfaceContainerHigh,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: highlight
                        ? AppColors.primary
                        : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: highlight ? AppColors.onPrimary : AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
