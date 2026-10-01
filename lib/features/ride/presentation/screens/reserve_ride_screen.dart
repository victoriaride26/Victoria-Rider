import 'package:flutter/material.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'destination_search_screen.dart';

/// Reserve Ride flow - Schedule a trip for later (date + time picking).
class ReserveRideScreen extends StatefulWidget {
  const ReserveRideScreen({super.key, this.currentLocation});

  final CurrentLocation? currentLocation;

  @override
  State<ReserveRideScreen> createState() => _ReserveRideScreenState();
}

class _ReserveRideScreenState extends State<ReserveRideScreen> {
  CurrentLocation? _pickup;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _pickup = widget.currentLocation;
    // Default to tomorrow 9:00 AM
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _selectedDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary)), child: child!),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary)), child: child!),
    );
    if (picked != null && mounted) setState(() => _selectedTime = picked);
  }

  Future<void> _chooseDestination() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select date and time first'), behavior: SnackBarBehavior.floating));
      return;
    }
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

  String get _dateLabel {
    if (_selectedDate == null) return 'Select date';
    return '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
  }

  String get _timeLabel {
    if (_selectedTime == null) return 'Select time';
    final hour = _selectedTime!.hourOfPeriod == 0 ? 12 : _selectedTime!.hourOfPeriod;
    final period = _selectedTime!.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')} $period';
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
                  Text('Reserve Ride', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withValues(alpha: 0.2))),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.event_available, color: AppColors.onPrimary)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Schedule for Later', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)), Text('Reserve a driver for your future trip', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant))])),
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
                  const SizedBox(height: 20),
                  Text('Schedule', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.surfaceContainerHigh)),
                            child: Row(children: [const Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 18), const SizedBox(width: 10), Expanded(child: Text(_dateLabel, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))), const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.onSurfaceVariant)]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _pickTime,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.surfaceContainerHigh)),
                            child: Row(children: [const Icon(Icons.access_time, color: AppColors.primary, size: 18), const SizedBox(width: 10), Expanded(child: Text(_timeLabel, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))), const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.onSurfaceVariant)]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.outlineVariant)),
                    child: Row(children: [const Icon(Icons.info_outline, size: 18, color: AppColors.primary), const SizedBox(width: 10), Expanded(child: Text('Reserve lets you schedule ahead. Your driver will be assigned closer to $_timeLabel on $_dateLabel.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)))]),
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
