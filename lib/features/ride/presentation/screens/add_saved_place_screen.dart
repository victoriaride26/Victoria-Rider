import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../core/models/geocoding_result.dart';
import '../../../../core/models/saved_place.dart';
import '../../../../core/services/geoapify_geocoding_service.dart';
import '../../../../core/services/places_storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';

class AddSavedPlaceScreen extends StatefulWidget {
  const AddSavedPlaceScreen({super.key});

  @override
  State<AddSavedPlaceScreen> createState() => _AddSavedPlaceScreenState();
}

class _AddSavedPlaceScreenState extends State<AddSavedPlaceScreen> {
  final _geoapifyGeocoding = GeoapifyGeocodingService();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  List<GeocodingResult> _searchResults = [];
  bool _isSearching = false;
  bool _hasQuery = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _geoapifyGeocoding.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() => _hasQuery = query.isNotEmpty);

    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounce = Timer(const Duration(milliseconds: 380), () async {
      final results = await _geoapifyGeocoding.search(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _hasQuery = false;
    });
  }

  void _onResultSelected(GeocodingResult result) {
    _focusNode.unfocus();
    _showSaveBottomSheet(result);
  }

  void _showSaveBottomSheet(GeocodingResult result) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SavePlaceBottomSheet(result: result),
    ).then((saved) {
      if (saved == true && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 8),
                  Text(
                    'Add Saved Place',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceContainerHigh),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.search, color: AppColors.onSurfaceVariant),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search for an address...',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.outlineVariant,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    if (_hasQuery)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: AppColors.onSurfaceVariant,
                        onPressed: _clearSearch,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else if (_searchResults.isEmpty && _hasQuery)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No results found',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surfaceContainerHigh),
                  itemBuilder: (context, i) {
                    final res = _searchResults[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                      title: Text(
                        res.shortName,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        res.placeName,
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _onResultSelected(res),
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

class _SavePlaceBottomSheet extends StatefulWidget {
  const _SavePlaceBottomSheet({required this.result});
  final GeocodingResult result;

  @override
  State<_SavePlaceBottomSheet> createState() => _SavePlaceBottomSheetState();
}

class _SavePlaceBottomSheetState extends State<_SavePlaceBottomSheet> {
  SavedPlaceType _selectedType = SavedPlaceType.home;
  bool _isLoading = false;

  Future<void> _save() async {
    setState(() => _isLoading = true);
    final place = SavedPlace(
      id: DateTime.now().toIso8601String(),
      type: _selectedType,
      placeName: widget.result.placeName,
      shortName: widget.result.shortName,
      location: widget.result.location,
    );
    await PlacesStorageService.instance.addSavedPlace(place);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save Place',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            widget.result.shortName,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            widget.result.placeName,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Text(
            'Choose a label',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SavedPlaceType.values.map((type) {
              final selected = _selectedType == type;
              return ChoiceChip(
                label: Text(type.label),
                selected: selected,
                onSelected: (val) {
                  if (val) setState(() => _selectedType = type);
                },
                avatar: Icon(
                  type.icon,
                  size: 18,
                  color: selected ? AppColors.onPrimary : AppColors.primary,
                ),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? AppColors.onPrimary : AppColors.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.outlineVariant,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isLoading ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Place'),
          ),
        ],
      ),
    );
  }
}
