import 'package:flutter/material.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'destination_search_screen.dart';

/// Daily Ride flow - Instant pickup, same as original ride request but dedicated.
/// This screen is the entry point for the "Daily Ride" quick action on the dashboard.
class DailyRideScreen extends StatefulWidget {
  const DailyRideScreen({super.key, this.currentLocation});

  final CurrentLocation? currentLocation;

  @override
  State<DailyRideScreen> createState() => _DailyRideScreenState();
}

class _DailyRideScreenState extends State<DailyRideScreen> {
  CurrentLocation? _pickup;

  @override
  void initState() {
    super.initState();
    _pickup = widget.currentLocation;
  }

  Future<void> _chooseDestination() async {
    final updatedPickup = await Navigator.of(context).push<CurrentLocation>(
      MaterialPageRoute<CurrentLocation>(
        builder: (_) => DestinationSearchScreen(
          currentLocation: _pickup ?? widget.currentLocation,
          initialTarget: SearchTarget.destination,
        ),
      ),
    );
    if (updatedPickup != null && mounted) {
      setState(() => _pickup = updatedPickup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickupLabel = _pickup?.shortLabel ?? 'Current Location (GPS)';

    return RiderScaffold(
      currentIndex: 0,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  AppBackButton(onPressed: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 8),
                  Text('Daily Ride', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.directions_car, color: AppColors.onPrimary)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Instant Pickup', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)), Text('Book now • Driver arrives in minutes', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant))])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Pickup', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.surfaceContainerHigh)),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location, color: AppColors.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(pickupLabel, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: const Text('GPS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Destination', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _chooseDestination,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: AppColors.primary),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Where to?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.onSurface))),
                          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.arrow_forward, color: AppColors.onPrimary, size: 18)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Daily Ride is our standard instant service. Confirm your pickup (current GPS) and choose a drop-off to get a fare estimate and request a driver.',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
