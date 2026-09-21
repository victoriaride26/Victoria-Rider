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

      // ApiClient returns the decoded body directly (Map or List), not a Dio Response.
      // Handle all backend shapes: {data:[...],meta:{}} , {data:{rides:[...]}} , [...] , {rides:[...]}.
      Map<String, dynamic>? responseMap;
      List<dynamic>? rawList;
      Map<String, dynamic>? meta;

      if (res is Map<String, dynamic>) {
        responseMap = res;
        // Try top-level list wrappers
        final dataField = responseMap['data'];
        if (dataField is List) {
          rawList = dataField;
          meta = responseMap['meta'] as Map<String, dynamic>?;
        } else if (dataField is Map<String, dynamic>) {
          rawList = (dataField['rides'] ??
                  dataField['items'] ??
                  dataField['history'] ??
                  dataField['data']) as List?;
          meta = (dataField['meta'] ?? responseMap['meta']) as Map<String, dynamic>?;
          // If data is a map with pagination inside, also look there
          if (rawList == null && dataField['data'] is List) {
            rawList = dataField['data'] as List;
          }
        } else {
          // Fallback: check alternative top-level keys
          rawList = (responseMap['rides'] ??
                  responseMap['items'] ??
                  responseMap['history'] ??
                  responseMap['results']) as List?;
          meta = responseMap['meta'] as Map<String, dynamic>?;
        }
        // meta may also be under pagination / paging
        meta ??= responseMap['pagination'] as Map<String, dynamic>?;
        meta ??= (responseMap['data'] is Map<String, dynamic>
            ? (responseMap['data'] as Map<String, dynamic>)['meta'] as Map<String, dynamic>?
            : null);
      } else if (res is List) {
        rawList = res;
      }

      final data = rawList;
      if (data != null && data.isNotEmpty) {
        final parsed = <RideHistoryItem>[];
        for (final e in data) {
          if (e is Map<String, dynamic>) {
            try {
              parsed.add(RideHistoryItem.fromJson(e));
            } catch (_) {}
          } else if (e is Map) {
            try {
              parsed.add(RideHistoryItem.fromJson(Map<String, dynamic>.from(e)));
            } catch (_) {}
          }
        }
        if (parsed.isNotEmpty) {
          setState(() {
            _rides.addAll(parsed);
            _page++;
            // Robust totalPages handling: meta may be at top or nested, and may be missing (fallback to hasMore based on page size)
            final metaPages = (meta?['totalPages'] ?? meta?['total_pages'] ?? meta?['pages']) as num?;
            if (metaPages != null) {
              _totalPages = metaPages.toInt();
              _hasMore = _page <= _totalPages;
            } else {
              // If backend doesn't send meta, assume more if we got full page (10)
              _hasMore = parsed.length >= 10;
              if (!_hasMore) _totalPages = _page - 1;
            }
          });
        } else {
          setState(() => _hasMore = false);
        }
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      debugPrint('[RideHistory] _loadMore error: $e');
      if (mounted) setState(() => _hasMore = false);
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
    // Handle nested wrappers: {data:{ride:{}}} or {ride:{}}.
    Map<String, dynamic> j = json;
    if (j['data'] is Map<String, dynamic> && j['data']['ride'] is Map) {
      j = Map<String, dynamic>.from((j['data']['ride'] as Map));
    } else if (j['ride'] is Map) {
      j = Map<String, dynamic>.from(j['ride'] as Map);
    } else if (j['data'] is Map<String, dynamic> && j['data'].containsKey('status')) {
      j = Map<String, dynamic>.from(j['data'] as Map);
    }

    // Parse kobo to Naira — handle nested fare objects and flat fields
    final payment = j['ridePayment'] is Map ? j['ridePayment'] as Map : null;
    final fareObj = j['fare'];
    final rawFare = fareObj is Map
        ? (fareObj['finalAmount'] ?? fareObj['grossFare'] ?? fareObj['estimatedFare'] ?? fareObj['amount'] ?? fareObj['total'] ?? fareObj['fare'] ?? 0)
        : (j['fare'] ?? j['estimatedFare'] ?? j['estimated_fare'] ?? j['fareAmount'] ?? j['amount'] ?? 0);
    final fare = _parseKobo(rawFare) / 100;
    final settled = payment == null
        ? null
        : _parseKobo(payment['finalAmount'] ?? payment['grossFare'] ?? payment['amount']) / 100;

    // Address resolution with all known keys
    final pickupAddr = j['pickupAddress']?.toString() ??
        j['pickup_address']?.toString() ??
        (j['pickupLocation'] is Map ? (j['pickupLocation'] as Map)['address']?.toString() : null) ??
        (j['pickup'] is Map ? (j['pickup'] as Map)['address']?.toString() : null) ??
        j['origin']?.toString() ??
        '';
    final dropoffAddr = j['dropoffAddress']?.toString() ??
        j['dropoff_address']?.toString() ??
        (j['dropoffLocation'] is Map ? (j['dropoffLocation'] as Map)['address']?.toString() : null) ??
        (j['dropoff'] is Map ? (j['dropoff'] as Map)['address']?.toString() : null) ??
        j['destination']?.toString() ??
        '';

    // createdAt fallback: created_at, timestamp, date
    final createdStr = j['createdAt']?.toString() ?? j['created_at']?.toString() ?? j['timestamp']?.toString() ?? j['date']?.toString();
    return RideHistoryItem(
      id: (j['id'] ?? j['_id'] ?? j['rideId'] ?? '').toString(),
      status: j['status']?.toString() ?? 'UNKNOWN',
      createdAt: DateTime.tryParse(createdStr ?? '') ?? DateTime.now(),
      fareNgn: fare,
      settledFareNgn: settled,
      pickupAddress: pickupAddr.trim(),
      dropoffAddress: dropoffAddr.trim(),
    );
  }

  double get displayFareNgn => settledFareNgn ?? fareNgn;

  static double _parseKobo(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '') ?? '') ?? 0;
  }
}
