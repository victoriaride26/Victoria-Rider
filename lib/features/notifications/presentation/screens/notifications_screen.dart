import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import '../../data/notification_service.dart';

/// Rider Notification Center — curates all alerts via SharedPreferences.
class RiderNotificationsScreen extends StatefulWidget {
  const RiderNotificationsScreen({super.key});

  @override
  State<RiderNotificationsScreen> createState() => _RiderNotificationsScreenState();
}

class _RiderNotificationsScreenState extends State<RiderNotificationsScreen> {
  final RiderNotificationService _service = RiderNotificationService.instance;

  @override
  void initState() {
    super.initState();
    // Ensure curated history is loaded from SharedPreferences on first open
    _service.init();
  }

  IconData _icon(RiderNotificationType type) {
    switch (type) {
      case RiderNotificationType.ride:
        return Icons.local_taxi_outlined;
      case RiderNotificationType.tripInProgress:
        return Icons.directions_car_filled_outlined;
      case RiderNotificationType.stopOver:
        return Icons.add_location_alt_outlined;
      case RiderNotificationType.tripEnded:
        return Icons.flag_circle_outlined;
      case RiderNotificationType.payment:
        return Icons.payments_outlined;
      case RiderNotificationType.paymentSuccessful:
        return Icons.verified_outlined;
      case RiderNotificationType.promo:
        return Icons.card_giftcard_outlined;
      case RiderNotificationType.system:
        return Icons.info_outline;
    }
  }

  Color _iconColor(RiderNotificationType type) {
    switch (type) {
      case RiderNotificationType.ride:
        return AppColors.primary;
      case RiderNotificationType.tripInProgress:
        return const Color(0xFF0F6B3A);
      case RiderNotificationType.stopOver:
        return const Color(0xFF7C4D00);
      case RiderNotificationType.tripEnded:
        return const Color(0xFF1A4D8F);
      case RiderNotificationType.payment:
        return const Color(0xFF8A5A00);
      case RiderNotificationType.paymentSuccessful:
        return const Color(0xFF0A7D2E);
      case RiderNotificationType.promo:
        return const Color(0xFF005FAF);
      case RiderNotificationType.system:
        return AppColors.secondary;
    }
  }

  String _label(RiderNotificationType type) {
    switch (type) {
      case RiderNotificationType.ride:
        return 'Ride';
      case RiderNotificationType.tripInProgress:
        return 'Trip';
      case RiderNotificationType.stopOver:
        return 'Stopover';
      case RiderNotificationType.tripEnded:
        return 'Trip Ended';
      case RiderNotificationType.payment:
        return 'Payment';
      case RiderNotificationType.paymentSuccessful:
        return 'Paid';
      case RiderNotificationType.promo:
        return 'Promo';
      case RiderNotificationType.system:
        return 'System';
    }
  }

  String _timeLabel(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && now.day == time.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 2) return 'Yesterday';
    return '${time.day}/${time.month}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RiderScaffold(
      currentIndex: 0,
      body: SafeArea(
        child: Column(
          children: [
            // Header — curated notifications, Mark all read
            AnimatedBuilder(
              animation: _service,
              builder: (context, _) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      AppBackButton(
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          'Notifications',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                            fontSize: 17.6, // 22 * 0.8
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _service.items.isEmpty ? null : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear Notifications'),
                              content: const Text('Are you sure you want to clear all notifications?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: const Text('Clear All')),
                              ],
                            ),
                          );
                          if (confirm == true) _service.clear();
                        },
                        child: Text(
                          'Clear all',
                          style: TextStyle(fontSize: 12.5, color: _service.items.isEmpty ? AppColors.onSurfaceVariant : AppColors.error), // 14 * 0.8
                        ),
                      ),
                      TextButton(
                        onPressed: _service.unreadCount == 0 ? null : _service.markAllRead,
                        child: Text(
                          'Mark all read',
                          style: TextStyle(fontSize: 12.5), // 14 * 0.8
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _service,
                builder: (context, _) {
                  final items = _service.items;
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 58, color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)), // 72 * 0.8
                          const SizedBox(height: 13),
                          Text('No notifications yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                                fontSize: 14, // 16 * 0.8
                              )),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Ride updates, payments and promos will appear here. They are curated and saved on your device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 10.6, // 12 * 0.8
                                height: 1.35,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final color = _iconColor(item.type);
                      // Scaled down 20%: title 12.8, body 11.2, time 8.8
                      return Container(
                        decoration: BoxDecoration(
                          color: item.read ? AppColors.surfaceContainerLowest : color.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.25)),
                          boxShadow: item.read 
                              ? null 
                              : [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _service.markRead(item.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color.withValues(alpha: 0.18)),
                                  ),
                                  child: Icon(_icon(item.type), size: 16, color: color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.onSurface,
                                                fontSize: 14, // 16 * 0.8
                                                height: 1.2,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: item.read ? 0.08 : 0.14),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _label(item.type),
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.4,
                                                color: color,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(_timeLabel(item.createdAt),
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: AppColors.onSurfaceVariant,
                                                fontSize: 9.7, // 11 * 0.8
                                                fontWeight: FontWeight.w500,
                                              )),
                                          if (!item.read) ...[
                                            const SizedBox(width: 6),
                                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                                            const SizedBox(width: 4),
                                            Text('New',
                                                style: TextStyle(
                                                  fontSize: 9.7,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
                                                )),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        item.body,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                          fontSize: 12.5, // 14 * 0.8
                                          height: 1.35,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
