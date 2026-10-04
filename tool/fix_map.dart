import 'dart:io';

void main() {
  final paths = [
    'c:/flutter_projects/victoria_rides_driver/lib/core/widgets/mapbox_map_view.dart',
    'c:/flutter_projects/victoria_rides/lib/core/widgets/mapbox_map_view.dart'
  ];

  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    
    var content = file.readAsStringSync();
    
    // Add _isFollowing property
    if (!content.contains('bool _isFollowing = false;')) {
      content = content.replaceFirst(
        '  bool _mapboxFailed = false;\n  int _mapboxFailCount = 0;',
        '  bool _mapboxFailed = false;\n  int _mapboxFailCount = 0;\n  bool _isFollowing = false;'
      );
    }

    // Initialize _isFollowing and add mapEventStream listener
    if (!content.contains('_isFollowing = widget.followUser;')) {
      content = content.replaceFirst(
        '  void initState() {\n    super.initState();',
        '''  void initState() {
    super.initState();
    _isFollowing = widget.followUser;
    _mapController.mapEventStream.listen((event) {
      if (event.source == MapEventSource.dragStart || event.source == MapEventSource.onDrag || event.source == MapEventSource.scrollWheel) {
        if (_isFollowing && mounted) {
          setState(() => _isFollowing = false);
        }
      }
    });'''
      );
    }

    // Add _getOffsetCenter method
    if (!content.contains('LatLng _getOffsetCenter(')) {
      content = content.replaceFirst(
        '  void _handlePosition(Position position) {',
        '''  LatLng _getOffsetCenter(LatLng center, double zoom) {
    // Shift center UP on the screen by offsetting latitude DOWN.
    // At zoom 14, 0.005 degrees latitude is roughly 1/4 of the screen.
    final latOffset = 0.005 * (14.0 / (zoom > 0 ? zoom : 14.0));
    return LatLng(center.latitude - latOffset, center.longitude);
  }

  void _handlePosition(Position position) {'''
      );
    }

    // Replace if (widget.followUser) with if (_isFollowing) and apply offset
    if (content.contains('if (widget.followUser) {\n      _mapController.move(latLng, widget.zoom);\n    }')) {
      content = content.replaceFirst(
        'if (widget.followUser) {\n      _mapController.move(latLng, widget.zoom);\n    }',
        '''if (_isFollowing) {
      try {
        final currentZoom = _mapController.camera.zoom;
        _mapController.move(_getOffsetCenter(latLng, currentZoom), currentZoom);
      } catch (_) {
        _mapController.move(_getOffsetCenter(latLng, widget.zoom), widget.zoom);
      }
    }'''
      );
    }

    // Replace initialCenter with offset
    if (content.contains('initialCenter: widget.center,')) {
      content = content.replaceFirst(
        'initialCenter: widget.center,',
        'initialCenter: _getOffsetCenter(widget.center, widget.zoom),'
      );
    }

    // Add Recenter button
    if (!content.contains('// Recenter button')) {
      content = content.replaceFirst(
        '        if (_locationDenied)',
        '''        if (!_isFollowing && widget.followUser)
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: AppColors.surface,
              onPressed: () {
                setState(() => _isFollowing = true);
                if (_userPosition != null) {
                  try {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(_getOffsetCenter(_userPosition!, currentZoom), currentZoom);
                  } catch (_) {
                    _mapController.move(_getOffsetCenter(_userPosition!, widget.zoom), widget.zoom);
                  }
                }
              },
              child: const Icon(Icons.my_location, color: AppColors.primary),
            ),
          ),
        if (_locationDenied)'''
      );
    }

    file.writeAsStringSync(content);
    print('Updated \$path');
  }
}
