import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Full-screen, non-dismissible location permission gate.
///
/// Shown by [RiderHomeShell] the first time the app is opened (and any time
/// the user returns from Settings without granting the permission).
///
/// Three states are handled with context-aware copy and actions:
///  - **Service disabled** → "Open Location Settings"
///  - **Denied forever**   → "Open App Settings"
///  - **Not yet asked / denied this session** → "Allow Location"
///
/// The screen keeps retrying automatically when the app is resumed from
/// the background (e.g., after the user toggles the system setting).
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen>
    with WidgetsBindingObserver {
  final _locationService = LocationService();

  LocationPermissionStatus? _status;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService.dispose();
    super.dispose();
  }

  /// Re-check whenever the app is resumed — the user may have just toggled
  /// GPS or granted the permission in the system Settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);

    final status = await _locationService.checkPermissionStatus();

    if (!mounted) return;

    if (status == LocationPermissionStatus.granted) {
      // Permission confirmed — pop back to the shell so it can load GPS.
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _status = status;
      _checking = false;
    });
  }

  Future<void> _onPrimaryTap() async {
    final status = _status;
    if (status == null) return;

    try {
      if (status == LocationPermissionStatus.serviceDisabled) {
        await Geolocator.openLocationSettings();
        // _check() fires automatically on resume via didChangeAppLifecycleState.
      } else if (status == LocationPermissionStatus.deniedForever) {
        await Geolocator.openAppSettings();
        // _check() fires automatically on resume.
      } else {
        // denied — can request directly.
        setState(() => _checking = true);
        final permission = await Geolocator.requestPermission();
        if (!mounted) return;
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _checking = false;
            _status = permission == LocationPermission.deniedForever
                ? LocationPermissionStatus.deniedForever
                : LocationPermissionStatus.denied;
          });
        }
      }
    } catch (e) {
      debugPrint('LocationPermissionScreen error: $e');
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    final bool isServiceOff =
        status == LocationPermissionStatus.serviceDisabled;
    final bool isForever =
        status == LocationPermissionStatus.deniedForever;

    final title = isServiceOff
        ? 'Turn On Location Services'
        : 'Allow Location Access';

    final body = isServiceOff
        ? "Your device's location services are switched off.\n\nVT Rides needs GPS to show your position on the map, find nearby drivers, and give you accurate pickup coordinates."
        : isForever
            ? "Location access was permanently denied.\n\nPlease open App Settings, go to Permissions, and allow Location so VT Rides can find you on the map."
            : "VT Rides needs your location to:\n\n\u2022 Show you on the map so drivers can find you\n\u2022 Give accurate pickup coordinates\n\u2022 Provide real distance and fare estimates\n\nYour location is only used while the app is open.";

    final primaryLabel = isServiceOff
        ? 'Open Location Settings'
        : isForever
            ? 'Open App Settings'
            : 'Allow Location';

    final primaryIcon = (isServiceOff || isForever)
        ? Icons.settings_outlined
        : Icons.location_on_outlined;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _checking && status == null
              // Initial load state — show a centred spinner.
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                )
              : Column(
                  children: [
                    const Spacer(flex: 2),

                    // ── Illustration ──────────────────────────────────────
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ring
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.2),
                                width: 2,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.location_on_rounded,
                            size: 52,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Headline ──────────────────────────────────────────
                    Text(
                      title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 14),

                    // ── Body copy ─────────────────────────────────────────
                    Text(
                      body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(flex: 3),

                    // ── Privacy note ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your location is never shared with third parties '
                              'and is only active while the app is in use.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Primary CTA ───────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _checking ? null : _onPrimaryTap,
                        icon: _checking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Icon(primaryIcon, size: 20),
                        label: Text(
                          primaryLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                  ],
                ),
        ),
      ),
    );
  }
}
