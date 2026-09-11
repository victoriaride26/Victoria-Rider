import 'package:flutter/material.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../payments/data/rider_wallet_repository.dart';
import '../../../ride/presentation/screens/destination_search_screen.dart';

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
  const HomeScreen({
    super.key,
    this.onOpenDrawer,
    this.onNavigateToTab,
  });

  /// Triggers opening the persistent drawer on the home shell.
  final VoidCallback? onOpenDrawer;

  /// Requests tab navigation on the home shell.
  final ValueChanged<int>? onNavigateToTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  List<WalletTransaction> _recentActivity = [];
  final _locationService = LocationService();
  CurrentLocation? _currentLocation;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardData();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _currentLocation == null) {
      _loadCurrentLocation();
    }
  }

  Future<void> _loadCurrentLocation() async {
    if (!mounted) return;
    setState(() => _locationLoading = true);
    final loc = await _locationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _currentLocation = loc;
        _locationLoading = false;
      });
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      final txns = await RiderWalletRepository.instance.getTransactions();
      if (mounted) {
        setState(() => _recentActivity = txns);
      }
    } catch (_) {}
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const List<_SavedPlace> _savedPlaces = [
    _SavedPlace(Icons.home_rounded, 'Home', 'High-Level, Makurdi'),
    _SavedPlace(Icons.work_rounded, 'Work', 'Federal Secretariat, Makurdi'),
    _SavedPlace(Icons.shopping_bag_outlined, 'Modern Market', 'South-Bank, Makurdi'),
  ];

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
          onRefresh: _loadDashboardData,
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
                      side: const BorderSide(color: AppColors.surfaceContainerHigh),
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
                        child: Icon(Icons.menu_rounded,
                            color: AppColors.onSurface, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Current City Pill
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        await _loadCurrentLocation();
                        if (!context.mounted) return;
                        if (_currentLocation != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'GPS location: ${_currentLocation!.shortLabel}'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.surfaceContainerHigh),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on,
                                color: AppColors.primary, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _locationLoading
                                  ? const SizedBox(
                                      height: 12,
                                      width: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            AppColors.primary),
                                      ),
                                    )
                                  : Text(
                                      _currentLocation?.shortLabel ??
                                          'Makurdi, Benue State',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: AppColors.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                            const Icon(Icons.keyboard_arrow_down,
                                size: 16, color: AppColors.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Safety Shield / Quick Profile Avatar
                  Material(
                    color: AppColors.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.surfaceContainerHigh),
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
                          '${_getGreeting()}, $displayName 👋',
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
                            top: Radius.circular(16)),
                        onTap: () async {
                          if (_currentLocation == null) {
                            await _loadCurrentLocation();
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
                                                      AppColors.primary),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Getting location…',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              color: AppColors.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        _currentLocation != null
                                            ? 'Pickup: ${_currentLocation!.shortLabel}'
                                            : 'Pickup: Tap to set location',
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
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
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.1),
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
                            bottom: Radius.circular(16)),
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
              Row(
                children: [
                  _QuickServiceCard(
                    icon: Icons.directions_car,
                    title: 'Daily Ride',
                    subtitle: 'Instant pickup',
                    highlight: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DestinationSearchScreen(
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
                        builder: (_) => DestinationSearchScreen(
                          currentLocation: _currentLocation,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _QuickServiceCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'Courier',
                    subtitle: 'Fast delivery',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Courier delivery service launching soon!'),
                        behavior: SnackBarBehavior.floating,
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
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DestinationSearchScreen(
                          currentLocation: _currentLocation,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Place',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                            color: AppColors.surfaceContainerHigh),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DestinationSearchScreen(
                              currentLocation: _currentLocation,
                            ),
                          ),
                        ),
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
                                      color: AppColors.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(place.icon,
                                        color: AppColors.primary, size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      place.label,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                place.subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 11,
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
                    child: const Text('View All',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (_recentActivity.isNotEmpty) ...[
                for (final tx in _recentActivity.take(3))
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
                                '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} • ${tx.status}',
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
                            const SizedBox(height: 2),
                            if (!tx.isCredit)
                              InkWell(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const DestinationSearchScreen(
                                    currentLocation: null),
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
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 24),
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
                        'Your completed trips and rides around Makurdi will appear here.',
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
                              horizontal: 18, vertical: 10),
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

class _SavedPlace {
  const _SavedPlace(this.icon, this.label, this.subtitle);
  final IconData icon;
  final String label;
  final String subtitle;
}
