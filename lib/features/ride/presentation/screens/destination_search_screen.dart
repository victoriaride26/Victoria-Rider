import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/mapbox_geocoding_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import '../widgets/ride_request_sheet.dart';

/// Indicates which point of the trip is currently being searched.
enum SearchTarget { pickup, destination }

/// R-07 — Search screen with live Mapbox geocoding.
/// Supports searching both pickup locations and destinations.
class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({
    super.key,
    this.currentLocation,
    this.initialTarget = SearchTarget.destination,
    this.isSettingPickup = false,
  });

  /// The rider's current GPS location, used to bias Mapbox search results
  /// toward the user's vicinity and display the real pickup address.
  final CurrentLocation? currentLocation;

  /// Which field should initially be active when opening the screen.
  final SearchTarget initialTarget;

  /// If true, selecting a place sets/returns the pickup location to the caller
  /// instead of launching a ride request.
  final bool isSettingPickup;

  @override
  State<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final _geocoding = MapboxGeocodingService();
  final _locationService = LocationService();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  late SearchTarget _activeTarget;
  CurrentLocation? _currentPickup;

  List<GeocodingResult> _searchResults = [];
  bool _isSearching = false;
  bool _hasQuery = false;
  bool _fetchingGps = false;

  Timer? _debounce;

  static const _savedPlaces = [
    _StaticPlace(Icons.home, 'Home', 'N.O.K Complex, Benue'),
    _StaticPlace(Icons.work, 'Office', 'Secretariat, Makurdi'),
  ];

  static const _recentPlaces = [
    _StaticPlace(Icons.history, 'Benue State University',
        'Main Campus Road, Makurdi'),
    _StaticPlace(Icons.history, 'Tito Gate', 'High Level, Makurdi'),
    _StaticPlace(Icons.history, 'Aper Aku Stadium', 'Police Barracks Road'),
  ];

  @override
  void initState() {
    super.initState();
    _activeTarget =
        widget.isSettingPickup ? SearchTarget.pickup : widget.initialTarget;
    _currentPickup = widget.currentLocation;

    _searchController.addListener(_onSearchChanged);
    // Auto-focus after the frame is drawn for better UX.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _geocoding.dispose();
    _locationService.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() => _hasQuery = query.isNotEmpty);

    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 380), () async {
      final results = await _geocoding.search(
        query,
        proximity: _currentPickup?.position ?? widget.currentLocation?.position,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _hasQuery = false;
    });
  }

  void _switchToTarget(SearchTarget target) {
    if (_activeTarget == target) return;
    setState(() {
      _activeTarget = target;
      _searchController.clear();
      _searchResults = [];
      _hasQuery = false;
    });
    _focusNode.requestFocus();
  }

  Future<void> _useDeviceGps() async {
    setState(() => _fetchingGps = true);
    final loc = await _locationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _fetchingGps = false);

    if (loc != null) {
      if (widget.isSettingPickup) {
        Navigator.of(context).pop(loc);
      } else {
        setState(() {
          _currentPickup = loc;
          _activeTarget = SearchTarget.destination;
          _clearSearch();
        });
        _focusNode.requestFocus();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not acquire GPS position. Check permissions.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _selectResult(GeocodingResult result) {
    if (_activeTarget == SearchTarget.pickup) {
      final picked = CurrentLocation(
        position: result.location,
        label: result.placeName,
        shortLabel: result.shortName,
      );

      if (widget.isSettingPickup) {
        Navigator.of(context).pop(picked);
      } else {
        setState(() {
          _currentPickup = picked;
          _activeTarget = SearchTarget.destination;
          _clearSearch();
        });
        _focusNode.requestFocus();
      }
    } else {
      showRideRequestSheet(
        context,
        destination: result,
        currentLocation: _currentPickup ?? widget.currentLocation,
      );
    }
  }

  void _selectStaticPlace(_StaticPlace place) {
    final result = GeocodingResult(
      placeName: place.subtitle,
      shortName: place.title,
      location: const LatLng(7.7337, 8.5211), // Makurdi center
    );
    _selectResult(result);
  }

  String get _pickupLabel {
    final loc = _currentPickup ?? widget.currentLocation;
    if (loc != null) {
      return loc.shortLabel;
    }
    return 'Tap to set pickup';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPickupActive = _activeTarget == SearchTarget.pickup;

    return RiderScaffold(
      currentIndex: 0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 8),
                  Text(
                    widget.isSettingPickup
                        ? 'Set Pickup Location'
                        : isPickupActive
                            ? 'Select Pickup Spot'
                            : 'Where to?',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Route card ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.surfaceContainerHigh,
                  ),
                ),
                child: Column(
                  children: [
                    // Pickup row
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _switchToTarget(SearchTarget.pickup),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: isPickupActive
                                  ? TextField(
                                      controller: _searchController,
                                      focusNode: _focusNode,
                                      textInputAction: TextInputAction.search,
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Search pickup location…',
                                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                          color: AppColors.outlineVariant,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        suffixIcon: _hasQuery
                                            ? GestureDetector(
                                                onTap: _clearSearch,
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 18,
                                                  color: AppColors.onSurfaceVariant,
                                                ),
                                              )
                                            : null,
                                      ),
                                    )
                                  : Text(
                                      _pickupLabel,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: AppColors.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                            if (!isPickupActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Change',
                                  style: TextStyle(
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

                    if (!widget.isSettingPickup) ...[
                      // Connector line
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 2,
                            height: 14,
                            color: AppColors.surfaceContainerHighest,
                          ),
                        ),
                      ),

                      // Destination search field
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _switchToTarget(SearchTarget.destination),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                              const SizedBox(width: 12),
                              Expanded(
                                child: !isPickupActive
                                    ? TextField(
                                        controller: _searchController,
                                        focusNode: _focusNode,
                                        textInputAction: TextInputAction.search,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.onSurface,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Search destination…',
                                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                                            color: AppColors.outlineVariant,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          suffixIcon: _hasQuery
                                              ? GestureDetector(
                                                  onTap: _clearSearch,
                                                  child: const Icon(
                                                    Icons.close,
                                                    size: 18,
                                                    color: AppColors.onSurfaceVariant,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      )
                                    : Text(
                                        'Where to?',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                              ),
                              if (_isSearching && !isPickupActive)
                                const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primary),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Result list ──────────────────────────────────────────────────
            Expanded(
              child: _hasQuery
                  ? _buildSearchResults(theme)
                  : _buildStaticSuggestions(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_isSearching && _searchResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: AppColors.outline.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'No places found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different search term.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.surfaceContainerHigh),
      itemBuilder: (context, i) {
        final result = _searchResults[i];
        return _ResultTile(
          icon: _activeTarget == SearchTarget.pickup
              ? Icons.location_pin
              : Icons.location_on_outlined,
          title: result.shortName,
          subtitle: result.placeName,
          onTap: () => _selectResult(result),
        );
      },
    );
  }

  Widget _buildStaticSuggestions(ThemeData theme) {
    final isPickupActive = _activeTarget == SearchTarget.pickup;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // "Use Current GPS Location" quick button when editing pickup
        if (isPickupActive) ...[
          _ResultTile(
            icon: Icons.my_location_rounded,
            title: 'Use Device Current Location',
            subtitle: _fetchingGps
                ? 'Acquiring GPS position…'
                : 'Auto-detect pickup using phone GPS',
            trailing: _fetchingGps
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _fetchingGps ? () {} : _useDeviceGps,
          ),
          const Divider(height: 16, color: AppColors.surfaceContainerHigh),
        ],

        // Saved places
        _SectionHeader(title: 'Saved Places', theme: theme),
        const SizedBox(height: 4),
        ...List.generate(_savedPlaces.length, (i) {
          final p = _savedPlaces[i];
          return _ResultTile(
            icon: p.icon,
            title: p.title,
            subtitle: p.subtitle,
            onTap: () => _selectStaticPlace(p),
          );
        }),

        const SizedBox(height: 8),
        _SectionHeader(
            title: isPickupActive ? 'Popular Pickups' : 'Recent Destinations',
            theme: theme),
        const SizedBox(height: 4),
        ...List.generate(_recentPlaces.length, (i) {
          final p = _recentPlaces[i];
          return _ResultTile(
            icon: p.icon,
            title: p.title,
            subtitle: p.subtitle,
            onTap: () => _selectStaticPlace(p),
          );
        }),

        const SizedBox(height: 16),

        // Explore card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.explore,
                  color: AppColors.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Explore Local Rides',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.onPrimaryContainer,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Type above to search any location in Nigeria',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});
  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: AppColors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StaticPlace {
  const _StaticPlace(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}
