import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/mapbox_config.dart';

/// Reusable Mapbox-backed map view built on [FlutterMap] raster tiles.
///
/// An OpenStreetMap tile layer sits underneath as a fallback: if Mapbox
/// tiles fail to load, the OSM layer shows through automatically. If Mapbox
/// keeps failing, the layer is dropped entirely so the fallback renders.
///
/// While tiles are pending or failing, a small status pill is shown so
/// network problems are visible instead of a silently blank map.
///
/// When [showUserLocation] is enabled the driver's live GPS position is
/// rendered as a blue dot; with [followUser] the camera continuously
/// re-centers on the driver and [onUserPosition] fires on every fix so
/// callers can show live distances/ETAs.
class MapboxMapView extends StatefulWidget {
  const MapboxMapView({
    super.key,
    required this.center,
    this.zoom = 14,
    this.markers = const [],
    this.polylines = const [],
    this.interactive = true,
    this.showAttribution = true,
    this.showUserLocation = false,
    this.followUser = false,
    this.onUserPosition,
    this.mapController,
  });

  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final bool interactive;
  final bool showAttribution;
  final bool showUserLocation;
  final bool followUser;
  final ValueChanged<LatLng>? onUserPosition;
  final MapController? mapController;

  @override
  State<MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<MapboxMapView> {
  static const _mapboxFailThreshold = 6;

  final MapController _internalMapController = MapController();
  MapController get _controller =>
      widget.mapController ?? _internalMapController;

  final Set<String> _errors = {};
  Timer? _loadingTimer;
  bool _showLoading = true;
  bool _mapboxFailed = false;
  int _mapboxFailCount = 0;

  LatLng? _userPosition;
  LatLng? _lastPosition;
  double? _userBearing;
  StreamSubscription<Position>? _positionSub;
  bool _locationDenied = false;
  bool _locationServiceOff = false;

  @override
  void initState() {
    super.initState();
    _loadingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showLoading = false);
    });
    if (widget.showUserLocation) {
      _initLocation();
    }
  }

  @override
  void didUpdateWidget(covariant MapboxMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.followUser &&
        (widget.center != oldWidget.center || widget.zoom != oldWidget.zoom)) {
      try {
        _controller.move(widget.center, widget.zoom);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  void _onMapboxTileError(Object error) {
    final message = error.toString();
    if (mounted) {
      setState(() {
        _errors.add(message);
        _mapboxFailCount++;
        if (_mapboxFailCount >= _mapboxFailThreshold) {
          _mapboxFailed = true;
        }
      });
    }
  }

Future<void> _initLocation() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _locationDenied = true);
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      setState(() => _locationServiceOff = true);
      return;
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) _handlePosition(lastKnown);

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      _handlePosition,
      onError: (_) {
        if (mounted) setState(() => _locationServiceOff = true);
      },
    );
  } catch (_) {
    // Geolocation may be unavailable (e.g. in widget tests or restricted
    // environments); degrade to a static map.
  }
}

  void _handlePosition(Position position) {
    if (!mounted) return;
    final latLng = LatLng(position.latitude, position.longitude);

    // Direction of travel: prefer the bearing derived from consecutive fixes
    // (it follows the road and is jitter-free), falling back to the device's
    // own heading for the first fix only.
    double? rawBearing;
    if (_lastPosition != null) {
      rawBearing = const Distance().bearing(_lastPosition!, latLng);
    } else if (position.heading > 0) {
      rawBearing = position.heading;
    }
    _lastPosition = latLng;
    if (rawBearing != null) {
      _userBearing = _smoothBearing(_userBearing, rawBearing);
    }

    setState(() => _userPosition = latLng);
    if (widget.followUser) {
      _controller.move(latLng, widget.zoom);
    }
    widget.onUserPosition?.call(latLng);
  }

  double _smoothBearing(double? previous, double next) {
    if (previous == null) return next;
    var delta = next - previous;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return previous + delta * 0.3;
  }

  Marker _buildUserMarker() {
    return Marker(
      point: _userPosition!,
      width: 46,
      height: 46,
      child: Transform.rotate(
        angle: (_userBearing ?? 0) * math.pi / 180,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Icon(
            Icons.navigation,
            size: 34,
            color: Color(0xFF1A73E8),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBanner(String message) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ng.com.victoriatravels.victoriarides',
            ),
            if (!_mapboxFailed)
              TileLayer(
                urlTemplate: MapboxConfig.styleUrl,
                userAgentPackageName: 'ng.com.victoriatravels.victoriarides',
                errorTileCallback: (tile, error, stackTrace) =>
                    _onMapboxTileError(error),
              ),
            if (widget.polylines.isNotEmpty)
              PolylineLayer(polylines: widget.polylines),
            if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
            if (_userPosition != null)
              MarkerLayer(markers: [_buildUserMarker()]),
            if (widget.showAttribution)
              const Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SimpleAttributionWidget(
                    source: Text(
                      'Mapbox © OpenStreetMap',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_locationDenied)
          _buildLocationBanner('Location permission denied — enable it to see your position')
        else if (_locationServiceOff)
          _buildLocationBanner('Location services off — turn on GPS to see your position')
        else if (_errors.isNotEmpty)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Map unavailable: ${_errors.first}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() {
                        _errors.clear();
                        _mapboxFailCount = 0;
                        _mapboxFailed = false;
                      }),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, size: 16, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_showLoading)
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  backgroundColor: Colors.black26,
                ),
              ),
            ),
          ),
      ],
    );
  }
}