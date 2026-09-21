import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'destination_search_screen.dart';

/// R-14 — Ride History with Dynamic Live Transactions & Empty States.
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final _scrollController = ScrollController();
  int _tab = 0;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  int _totalPages = 1;
  final List<RideHistoryItem> _rides = [];

  static const List<String> _tabs = ['All', 'Completed', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final res = await ApiClient.instance.get(
        '/api/v1/rides/history?page=$_page&limit=10',
      );
      if (!mounted) return;

      final response = res.data is Map<String, dynamic>
          ? res.data as Map<String, dynamic>
          : const <String, dynamic>{};
      final data = response['data'] as List?;
      final meta = response['meta'] as Map<String, dynamic>?;
      if (data != null && data.isNotEmpty) {
        setState(() {
          _rides.addAll(
            data
                .map((e) => RideHistoryItem.fromJson(e as Map<String, dynamic>))
                .toList(),
          );
          _page++;
          _totalPages = (meta?['totalPages'] as num?)?.toInt() ?? _totalPages;
          _hasMore = _page <= _totalPages;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (_) {
      // Ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<RideHistoryItem> get _filteredRides {
    return _rides.where((r) {
      if (_tab == 1) {
        return r.status.toUpperCase().contains('COMPLET');
      }
      if (_tab == 2) {
        return r.status.toUpperCase().contains('CANCEL');
      }
      return true;
    }).toList();
  }

  String _formatCurrency(double amount) {
    return '₦${amount.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedList = _filteredRides;

    return RiderScaffold(
      currentIndex: 1,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            _page = 1;
            _totalPages = 1;
            _hasMore = true;
            _rides.clear();
            await _loadMore();
          },
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              Row(
                children: [
                  const AppBackButton(),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Ride History', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 16),

              // Filter Tabs
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    for (int i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tab = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tab == i
                                  ? AppColors.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _tabs[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _tab == i
                                    ? AppColors.onPrimary
                                    : AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Ride items or Empty State
              if (displayedList.isNotEmpty) ...[
                for (final r in displayedList)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      border: Border.all(color: AppColors.surfaceContainerHigh),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.directions_car,
                            color: AppColors.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r.createdAt.day}/${r.createdAt.month}/${r.createdAt.year} • ${r.createdAt.hour.toString().padLeft(2, '0')}:${r.createdAt.minute.toString().padLeft(2, '0')}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                r.dropoffAddress.isNotEmpty
                                    ? r.dropoffAddress
                                    : 'Dropoff',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      r.status.toUpperCase().contains('FAIL') ||
                                          r.status.toUpperCase().contains(
                                            'CANCEL',
                                          )
                                      ? AppColors.errorContainer
                                      : AppColors.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  r.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        r.status.toUpperCase().contains(
                                              'FAIL',
                                            ) ||
                                            r.status.toUpperCase().contains(
                                              'CANCEL',
                                            )
                                        ? AppColors.onErrorContainer
                                        : AppColors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₦${_formatCurrency(r.displayFareNgn)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 36,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceContainerHigh),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.directions_car_outlined,
                          size: 36,
                          color: AppColors.outline,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _tab == 0
                            ? 'No Rides Found'
                            : 'No ${_tabs[_tab]} Rides',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _tab == 0
                            ? 'You have not taken any rides yet. Start your journey with Victoria Rides today!'
                            : 'You have no ${_tabs[_tab].toLowerCase()} rides in your history.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DestinationSearchScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text(
                          'Book a Ride Now',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_hasMore && _rides.isNotEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class RideHistoryItem {
  final String id;
  final String status;
  final DateTime createdAt;
  final double fareNgn;
  final double? settledFareNgn;
  final String pickupAddress;
  final String dropoffAddress;

  const RideHistoryItem({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.fareNgn,
    this.settledFareNgn,
    required this.pickupAddress,
    required this.dropoffAddress,
  });

  factory RideHistoryItem.fromJson(Map<String, dynamic> json) {
    // Parse kobo to Naira
    final payment = json['ridePayment'] is Map
        ? json['ridePayment'] as Map
        : null;
    final rawFare = json['fare'] ?? json['estimatedFare'] ?? 0;
    final fare = _parseKobo(rawFare) / 100;
    final settled = payment == null
        ? null
        : _parseKobo(payment['finalAmount'] ?? payment['grossFare']) / 100;

    return RideHistoryItem(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      fareNgn: fare,
      settledFareNgn: settled,
      pickupAddress:
          json['pickupAddress']?.toString() ??
          json['pickupLocation']?['address']?.toString() ??
          '',
      dropoffAddress:
          json['dropoffAddress']?.toString() ??
          json['dropoffLocation']?['address']?.toString() ??
          '',
    );
  }

  double get displayFareNgn => settledFareNgn ?? fareNgn;

  static double _parseKobo(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '') ?? '') ?? 0;
  }
}
