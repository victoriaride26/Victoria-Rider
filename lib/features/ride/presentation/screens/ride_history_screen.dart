import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/fare_parser.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../rider/presentation/widgets/rider_scaffold.dart';
import 'destination_search_screen.dart';
import 'ride_in_progress_screen.dart';
import 'trip_completed_screen.dart';

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

  String? _errorMessage;

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiClient.instance.get(
        ApiConfig.rideHistory(page: _page, limit: 10),
      );
      if (!mounted) return;

      // Live API shape (verified with ternator556@gmail.com & terfabinda@gmail.com):
      // {success:true, data:[{id,...}], meta:{total, page, limit, totalPages}}
      // Also handle legacy/alternative shapes for robustness.
      if (res is Map<String, dynamic> && res['success'] == false) {
        final msg = res['message']?.toString() ?? 'Failed to load ride history';
        throw ApiException(msg, statusCode: res['statusCode'] as int?);
      }

      // ApiClient returns the decoded body directly (Map or List), not a Dio Response.
      // Ride extraction is shared with the dashboard via parseList so both
      // surfaces understand the same backend envelopes.
      Map<String, dynamic>? meta;
      if (res is Map<String, dynamic>) {
        final responseMap = res;
        final dataField = responseMap['data'];
        if (dataField is List) {
          meta = responseMap['meta'] as Map<String, dynamic>?;
          meta ??= responseMap['pagination'] as Map<String, dynamic>?;
        } else if (dataField is Map<String, dynamic>) {
          meta = (dataField['meta'] ??
                  dataField['pagination'] ??
                  responseMap['meta'] ??
                  responseMap['pagination']) as Map<String, dynamic>?;
        } else {
          meta = (responseMap['meta'] ?? responseMap['pagination']) as Map<String, dynamic>?;
        }
        meta ??= responseMap['pagination'] as Map<String, dynamic>?;
        meta ??= (responseMap['data'] is Map<String, dynamic>
            ? (responseMap['data'] as Map<String, dynamic>)['meta'] as Map<String, dynamic>?
            : null);
        meta ??= (responseMap['data'] is Map<String, dynamic>
            ? (responseMap['data'] as Map<String, dynamic>)['pagination'] as Map<String, dynamic>?
            : null);
      }

      final rawMaps = RideHistoryItem.parseList(res);
      final parsed = RideHistoryItem.parseAll(res);
      if (parsed.isNotEmpty) {
          setState(() {
            _rides.addAll(parsed);
            _page++;
            // Robust totalPages handling: supports meta {totalPages, total_pages, pages, total, limit}
            final metaPages = (meta?['totalPages'] ?? meta?['total_pages'] ?? meta?['pages']) as num?;
            final metaTotal = (meta?['total'] ?? meta?['totalItems'] ?? meta?['count']) as num?;
            final metaLimit = (meta?['limit'] ?? meta?['perPage'] ?? meta?['pageSize']) as num?;
            if (metaPages != null) {
              _totalPages = metaPages.toInt();
              _hasMore = _page <= _totalPages;
            } else if (metaTotal != null && metaLimit != null && metaLimit > 0) {
              _totalPages = (metaTotal / metaLimit).ceil();
              _hasMore = _page <= _totalPages;
            } else {
              // If backend doesn't send meta, assume more if we got full page (10)
              _hasMore = parsed.length >= 10;
              if (!_hasMore) _totalPages = _page - 1;
            }
          });
        } else {
          debugPrint('[RideHistory] parsed empty despite rawList len ${rawMaps.length} res=$res');
          setState(() => _hasMore = false);
        }
    } catch (e) {
      debugPrint('[RideHistory] _loadMore error: $e');
      if (mounted) {
        setState(() {
          _hasMore = false;
          if (e is ApiException) {
            _errorMessage = e.message;
          } else {
            _errorMessage = 'Failed to load rides. Pull to retry.';
          }
        });
      }
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

  /// Opens a history row according to the ride's status:
  ///  • IN_PROGRESS (or any live state) → the Trip in Progress screen, which
  ///    re-loads the ride and shows the current locations
  ///  • PAYMENT_PENDING → the payment screen
  ///  • EARLY_DROPOFF_* → the completed-trip screen (rider's terminal state
  ///    for an early drop-off — never strand the user on the trip screen)
  ///  • COMPLETED / CANCELLED → trip details in a modal
  void _openRide(RideHistoryItem item) {
    final status = item.status.toUpperCase();

    if (status.contains('PAYMENT') || status.contains('EARLY')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TripCompletedScreen(
            rideId: item.id,
            fareNgn: item.displayFareNgn,
            pickupAddress: item.pickupAddress,
            dropoffAddress: item.dropoffAddress,
            isPaymentConfirmed: false,
            driverRating: item.driverRating,
          ),
        ),
      );
      return;
    }

    final isLive = status.contains('IN_PROGRESS') ||
        status.contains('INPROGRESS') ||
        status.contains('STARTED') ||
        status.contains('ARRIVED') ||
        status.contains('ACCEPTED') ||
        status.contains('REQUEST') ||
        status.contains('STOP');
    if (isLive && item.id.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RideInProgressScreen(
            rideId: item.id,
            fareNgn: item.displayFareNgn,
            pickupAddress: item.pickupAddress,
            dropoffAddress: item.dropoffAddress,
            destinationLabel: item.dropoffAddress,
          ),
        ),
      );
      return;
    }

    _showTripDetails(item);
  }

  /// COMPLETED / CANCELLED — and anything without a live screen — open as a
  /// details modal instead of navigating away from the history list.
  void _showTripDetails(RideHistoryItem item) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final created = item.createdAt;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Details',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _detailRow(theme, 'Status', item.status),
                _detailRow(
                  theme,
                  'Date',
                  '${created.day}/${created.month}/${created.year} • '
                  '${created.hour.toString().padLeft(2, '0')}:'
                  '${created.minute.toString().padLeft(2, '0')}',
                ),
                _detailRow(
                  theme,
                  'Pickup',
                  item.pickupAddress.isNotEmpty ? item.pickupAddress : '—',
                ),
                _detailRow(
                  theme,
                  'Drop-off',
                  item.dropoffAddress.isNotEmpty ? item.dropoffAddress : '—',
                ),
                _detailRow(theme, 'Fare', _formatCurrency(item.displayFareNgn)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openRide(r),
                    child: Container(
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
                  ),
              ] else if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
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
                          color: AppColors.errorContainer,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.error_outline,
                          size: 36,
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _errorMessage!.contains('Driver profile not found') ? 'Driver profile not found' : 'Failed to load rides',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _errorMessage!.contains('Driver profile not found')
                            ? 'Please complete your driver onboarding to view trip history.'
                            : _errorMessage!,
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
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          setState(() {
                            _errorMessage = null;
                            _hasMore = true;
                          });
                          _loadMore();
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
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
                            ? AppConstants.rideHistoryEmpty
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
  final double? driverRating;

  const RideHistoryItem({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.fareNgn,
    this.settledFareNgn,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.driverRating,
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

    // Parse kobo → Naira with the driver app's canonical parser so history
    // matches exactly what the driver app displays for the same ride.
    final fare = FareParser.estimatedFareNgn(j) ?? 0.0;
    final settled = FareParser.settledFareNgn(j);

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
      driverRating: (j['driver']?['rating'] ?? j['driverRating']) is num
          ? (j['driver']?['rating'] ?? j['driverRating']).toDouble()
          : null,
    );
  }

  double get displayFareNgn => settledFareNgn ?? fareNgn;

  /// Extracts the raw ride maps from any known backend envelope:
  /// `{data:[...]}`, `{data:{rides/items/history/trips/data/results}}`,
  /// a bare list, or top-level `{rides/items/history/trips/results}`.
  /// Shared with the dashboard's Recent Activity so both surfaces parse
  /// identically (shape drift here is what left the dashboard empty).
  static List<Map<String, dynamic>> parseList(dynamic res) {
    List<dynamic>? rawList;
    if (res is Map<String, dynamic>) {
      final dataField = res['data'];
      if (dataField is List) {
        rawList = dataField;
      } else if (dataField is Map<String, dynamic>) {
        rawList = (dataField['rides'] ??
                dataField['items'] ??
                dataField['history'] ??
                dataField['trips'] ??
                dataField['data'] ??
                dataField['results']) as List?;
      } else {
        rawList = (res['rides'] ??
                res['items'] ??
                res['history'] ??
                res['trips'] ??
                res['results']) as List?;
      }
    } else if (res is List) {
      rawList = res;
    }
    if (rawList == null) return const [];
    return [
      for (final e in rawList)
        if (e is Map<String, dynamic>)
          e
        else if (e is Map)
          Map<String, dynamic>.from(e),
    ];
  }

  /// Parses every ride in [res], skipping unparseable rows individually so
  /// one bad record never empties the whole list.
  static List<RideHistoryItem> parseAll(dynamic res) {
    final parsed = <RideHistoryItem>[];
    for (final map in parseList(res)) {
      try {
        parsed.add(RideHistoryItem.fromJson(map));
      } catch (err) {
        debugPrint('[RideHistory] parse skip: $err');
      }
    }
    return parsed;
  }
}
