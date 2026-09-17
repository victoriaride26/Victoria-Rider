import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/mapbox_geocoding_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/ride_request_service.dart';
import '../screens/searching_for_driver_screen.dart';

/// Shows the ride-request bottom sheet for a [destination].
///
/// Call this from [DestinationSearchScreen] when the user taps a result.
Future<void> showRideRequestSheet(
  BuildContext context, {
  required GeocodingResult destination,
  required CurrentLocation? currentLocation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RideRequestSheet(
      destination: destination,
      currentLocation: currentLocation,
    ),
  );
}

/// A premium, draggable bottom sheet that:
///  - Reverse-geocodes / uses the passed [currentLocation] as pickup.
///  - Calls the Directions API to compute real distance + duration + fare.
///  - Lets the user pick vehicle type and payment method.
///  - On confirm, POSTs the ride to the backend and navigates to the
///    searching-for-driver screen.
class RideRequestSheet extends StatefulWidget {
  const RideRequestSheet({
    super.key,
    required this.destination,
    required this.currentLocation,
  });

  final GeocodingResult destination;
  final CurrentLocation? currentLocation;

  @override
  State<RideRequestSheet> createState() => _RideRequestSheetState();
}

class _RideRequestSheetState extends State<RideRequestSheet>
    with SingleTickerProviderStateMixin {
  final _service = RideRequestService();
  final _locationService = LocationService();
  late final AnimationController _pulse;

  RideEstimate? _estimate;
  bool _loading = true;
  String? _error;

  /// Location resolved at confirm-time when the sheet was opened without one.
  CurrentLocation? _confirmedLocation;

  String _selectedVehicle = 'standard';
  String _selectedPayment = 'cash';
  bool _requesting = false;
  String? _requestError;

  static const _vehicles = [
    _VehicleOption('standard', Icons.directions_car, 'VT Standard',
        'Comfortable everyday ride'),
    _VehicleOption('premium', Icons.airline_seat_recline_extra, 'VT Premium',
        'Premium, quieter ride'),
    _VehicleOption('bike', Icons.two_wheeler, 'VT Bike',
        'Quick, affordable motorbike'),
  ];

  /// Payment channels available on the request screen.
  static const _payments = [
    _PayOption('cash', Icons.payments_outlined, 'Cash'),
    _PayOption('wallet', Icons.account_balance_wallet_outlined, 'Wallet'),
    _PayOption('card', Icons.credit_card_outlined, 'Card'),
    _PayOption('transfer', Icons.swap_horiz_rounded, 'Transfer'),
  ];

  /// Fare multipliers per vehicle tier (mirrors backend pricing rules).
  static const _fareMultipliers = {
    'standard': 1.0,
    'premium': 1.5,
    'bike': 0.5,
  };

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _loadEstimate();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _service.dispose();
    _locationService.dispose();
    super.dispose();
  }

  Future<void> _loadEstimate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pickup = widget.currentLocation;
      final pickupLatLng = pickup?.position ??
          const LatLng(7.7322, 8.5245); // Wurukum fallback
      final pickupLabel = pickup?.shortLabel ?? 'Current Location';

      final est = await _service.estimate(
        pickup: pickupLatLng,
        pickupLabel: pickupLabel,
        destination: widget.destination.location,
        destinationLabel: widget.destination.shortName,
        vehicleType: _selectedVehicle,
      );
      if (mounted) setState(() => _estimate = est);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load estimate.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_estimate == null || _requesting) return;

    // ── Option 3: location gate at confirm-time ──────────────────────────
    // If no location was passed into the sheet, try to acquire one now.
    // This is the only point in the app where location is mandatory.
    final effectiveLocation = widget.currentLocation ?? _confirmedLocation;
    if (effectiveLocation == null) {
      final status = await _locationService.checkPermissionStatus();
      if (status != LocationPermissionStatus.granted) {
        if (!mounted) return;
        await _showLocationGateSheet(status);
        return;
      }
      // Permission is granted but we don't yet have a fix — get it now.
      setState(() {
        _requesting = true;
        _requestError = null;
      });
      final fresh = await _locationService.getCurrentLocation();
      if (!mounted) return;
      if (fresh == null) {
        // Fall back gracefully to estimate's pickup point rather than stalling with invisible error
        final fallback = CurrentLocation(
          position: _estimate!.pickupLatLng,
          label: _estimate!.pickupLabel,
          shortLabel: _estimate!.pickupLabel,
        );
        setState(() {
          _confirmedLocation = fallback;
          _requesting = false;
        });
      } else {
        // Re-estimate with the freshly resolved pickup position.
        setState(() {
          _confirmedLocation = fresh;
          _requesting = false;
          _loading = true;
        });
        try {
          final est = await _service.estimate(
            pickup: fresh.position,
            pickupLabel: fresh.shortLabel,
            destination: widget.destination.location,
            destinationLabel: widget.destination.shortName,
            vehicleType: _selectedVehicle,
          );
          if (mounted) setState(() => _estimate = est);
        } catch (_) {
          // Keep the existing estimate if re-estimation fails.
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      }
      // Re-trigger confirm now that we have a location.
      await _confirm();
      return;
    }
    // ── End location gate ────────────────────────────────────────────────

    setState(() {
      _requesting = true;
      _requestError = null;
    });

    try {
      final rideId = await _service.requestRide(
        estimate: _estimate!,
        paymentMethod: _selectedPayment,
        vehicleType: _selectedVehicle,
      );

      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => SearchingForDriverScreen(
            rideId: rideId,
            pickupLatLng: _estimate?.pickupLatLng,
            destinationLatLng: _estimate?.destinationLatLng,
            pickupLabel: _estimate?.pickupLabel,
            destinationLabel: _estimate?.destinationLabel,
            fareNgn: _estimate?.fareNgn,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _requestError = e.message;
          _requesting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final rawMsg = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _requestError = rawMsg.isNotEmpty
              ? rawMsg
              : 'Failed to request ride. Please try again.';
          _requesting = false;
        });
      }
    } finally {
      if (mounted && _requesting) {
        setState(() => _requesting = false);
      }
    }
  }

  /// Shows a beautiful bottom-sheet explaining why location is needed,
  /// with context-aware action buttons based on the current [status].
  Future<void> _showLocationGateSheet(LocationPermissionStatus status) {
    final isServiceOff = status == LocationPermissionStatus.serviceDisabled;
    final isForever = status == LocationPermissionStatus.deniedForever;

    final title = isServiceOff
        ? 'Location Services Off'
        : 'Location Permission Needed';
    final body = isServiceOff
        ? 'Your device\'s location services are turned off. Please enable them in Settings so we can find your exact pickup point.'
        : isForever
            ? 'Location permission was permanently denied. Please open App Settings and grant location access so we can pick you up accurately.'
            : 'We need your location to place your pickup pin on the map. Without it your driver won\'t know where to find you.';
    final primaryLabel =
        (isServiceOff || isForever) ? 'Open Settings' : 'Allow Location';
    final primaryAction = isServiceOff
        ? () async {
            await Geolocator.openLocationSettings();
            if (mounted) Navigator.of(context).pop();
          }
        : isForever
            ? () async {
                await Geolocator.openAppSettings();
                if (mounted) Navigator.of(context).pop();
              }
            : () async {
                final permission = await Geolocator.requestPermission();
                if (mounted) Navigator.of(context).pop();
                // If the user just granted it, re-trigger confirm.
                if (permission == LocationPermission.always ||
                    permission == LocationPermission.whileInUse) {
                  await _confirm();
                }
              };

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            // Primary action
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: primaryAction,
                icon: Icon(
                  isServiceOff || isForever
                      ? Icons.settings_outlined
                      : Icons.location_on_outlined,
                  size: 20,
                ),
                label: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Secondary — dismiss
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceVariant,
                  side: const BorderSide(color: AppColors.surfaceContainerHigh),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Not Now',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _adjustedFare {
    final base = _estimate?.fareNgn ?? 0;
    return base * (_fareMultipliers[_selectedVehicle] ?? 1.0);
  }

  String get _formattedFare =>
      '₦${_adjustedFare.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Request a Ride',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Confirm your trip details below',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceContainerLow,
                          foregroundColor: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Route summary card ──────────────────────────────────
                  _RouteCard(
                    pickupLabel: widget.currentLocation?.shortLabel ??
                        'Current Location',
                    destinationLabel: widget.destination.shortName,
                  ),

                  const SizedBox(height: 12),

                  // ── Estimate row (distance / duration / fare) ───────────
                  if (_loading)
                    _EstimateLoading(pulse: _pulse)
                  else if (_error != null)
                    _EstimateError(onRetry: _loadEstimate)
                  else if (_estimate != null)
                    _EstimateBadges(
                      distanceKm: _estimate!.distanceKm,
                      durationMinutes: _estimate!.durationMinutes,
                      fare: _formattedFare,
                    ),

                  const SizedBox(height: 20),

                  // ── Vehicle type selector ───────────────────────────────
                  Text(
                    'Choose Vehicle',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(_vehicles.length, (i) {
                    final v = _vehicles[i];
                    final isSelected = _selectedVehicle == v.id;
                    final multiplier = _fareMultipliers[v.id] ?? 1.0;
                    final tierFare = (_estimate?.fareNgn ?? 0) * multiplier;
                    final tierLabel = _estimate != null
                        ? '₦${tierFare.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}'
                        : '—';

                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedVehicle = v.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.06)
                              : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.surfaceContainerHigh,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                v.icon,
                                size: 22,
                                color: isSelected
                                    ? AppColors.onPrimary
                                    : AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    v.name,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  Text(
                                    v.subtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              tierLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle,
                                  color: AppColors.primary, size: 18),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  // ── Payment method ──────────────────────────────────────
                  Text(
                    'Payment Method',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 2-column grid for payment options
                  Column(
                    children: [
                      for (int row = 0; row < 2; row++)
                        Padding(
                          padding: EdgeInsets.only(bottom: row == 0 ? 10 : 0),
                          child: Row(
                            children: List.generate(2, (col) {
                              final i = row * 2 + col;
                              final p = _payments[i];
                              final isSelected = _selectedPayment == p.id;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedPayment = p.id),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    margin: EdgeInsets.only(
                                        right: col == 0 ? 10 : 0),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                              .withValues(alpha: 0.08)
                                          : AppColors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.surfaceContainerHigh,
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          p.icon,
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.onSurfaceVariant,
                                          size: 24,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          p.label,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            color: isSelected
                                                ? AppColors.primary
                                                : AppColors.onSurfaceVariant,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Victoria Shield note ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Victoria Shield™ — your trip is monitored with 24/7 support.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Error Banner (Visible In-Sheet Feedback) ─────────────
                  if (_requestError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _requestError!,
                              style: const TextStyle(
                                color: AppColors.onErrorContainer,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: AppColors.onErrorContainer,
                            onPressed: () =>
                                setState(() => _requestError = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── CTA ─────────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed:
                          (_loading || _requesting || _estimate == null)
                              ? null
                              : _confirm,
                      child: _requesting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.directions_car, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _estimate != null
                                      ? 'Confirm Ride • $_formattedFare'
                                      : 'Confirm Ride',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.pickupLabel,
    required this.destinationLabel,
  });

  final String pickupLabel;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Column(
        children: [
          // Pickup
          Row(
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
                child: Text(
                  pickupLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'GPS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          // Connector
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: 16,
                color: AppColors.surfaceContainerHighest,
              ),
            ),
          ),
          // Destination
          Row(
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
                child: Text(
                  destinationLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EstimateBadges extends StatelessWidget {
  const _EstimateBadges({
    required this.distanceKm,
    required this.durationMinutes,
    required this.fare,
  });

  final double distanceKm;
  final int durationMinutes;
  final String fare;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Badge(
          icon: Icons.straighten,
          label: '${distanceKm.toStringAsFixed(1)} km',
        ),
        const SizedBox(width: 10),
        _Badge(
          icon: Icons.access_time,
          label: '$durationMinutes min',
        ),
        const Spacer(),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            fare,
            style: const TextStyle(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimateLoading extends StatelessWidget {
  const _EstimateLoading({required this.pulse});
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Row(
        children: [
          _ShimmerBox(width: 80, opacity: 0.4 + pulse.value * 0.6),
          const SizedBox(width: 10),
          _ShimmerBox(width: 70, opacity: 0.4 + pulse.value * 0.6),
          const Spacer(),
          _ShimmerBox(width: 90, height: 34, opacity: 0.4 + pulse.value * 0.6),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    this.height = 30,
    required this.opacity,
  });
  final double width;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _EstimateError extends StatelessWidget {
  const _EstimateError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Could not estimate fare.',
            style: TextStyle(color: AppColors.error, fontSize: 13),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _VehicleOption {
  const _VehicleOption(this.id, this.icon, this.name, this.subtitle);
  final String id;
  final IconData icon;
  final String name;
  final String subtitle;
}

class _PayOption {
  const _PayOption(this.id, this.icon, this.label);
  final String id;
  final IconData icon;
  final String label;
}
