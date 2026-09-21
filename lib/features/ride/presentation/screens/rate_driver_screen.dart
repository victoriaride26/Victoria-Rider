import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';

/// R-13 — Rate Your Driver.
class RateDriverScreen extends StatefulWidget {
  const RateDriverScreen({super.key, this.rideId, this.driverName});

  final String? rideId;
  final String? driverName;

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  final _commentController = TextEditingController();
  int _rating = 0;
  int? _tip;
  bool _isSubmitting = false;
  String? _errorMessage;

  static const List<int> _tips = [200, 500, 1000];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_rating == 0 || widget.rideId == null) {
      setState(() => _errorMessage = _rating == 0 ? 'Please select a star rating.' : 'Missing ride reference.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final comment = _commentController.text.trim();
      // Build comprehensive body covering all backend field variants
      final body = <String, dynamic>{
        'rating': _rating,
        'stars': _rating,
        'score': _rating,
        if (comment.isNotEmpty) ...{
          'comment': comment,
          'feedback': comment,
          'review': comment,
          'text': comment,
        },
        if (_tip != null) ...{
          'tipAmount': _tip,
          'tip': _tip,
          'tip_amount': _tip,
        },
      };

      // Primary endpoint per ApiConfig
      ApiException? lastError;
      final endpoints = [
        ApiConfig.rideRating(widget.rideId!),
        '${ApiConfig.apiV1}/rides/${widget.rideId}/ratings',
        '${ApiConfig.apiV1}/rides/${widget.rideId}/review',
        '${ApiConfig.apiV1}/rides/${widget.rideId}/rate',
      ];

      bool success = false;
      for (final endpoint in endpoints) {
        try {
          await ApiClient.instance.post(endpoint, body: body);
          success = true;
          debugPrint('[RateDriver] Rating saved via $endpoint rating=$_rating tip=$_tip');
          break;
        } on ApiException catch (e) {
          lastError = e;
          // If endpoint not found (404) try next; otherwise rethrow if validation error
          if (e.statusCode == 404 || e.message.toLowerCase().contains('not found')) {
            debugPrint('[RateDriver] Endpoint $endpoint 404, trying next');
            continue;
          }
          // For 400 validation, check if it's endpoint-specific; still try next if message hints at route
          if (e.statusCode == 400 && e.message.toLowerCase().contains('route')) {
            continue;
          }
          rethrow;
        }
      }

      if (!success && lastError != null) throw lastError;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! Your rating has been saved.'),
            backgroundColor: AppColors.primary,
          ),
        );
        _navigateToDashboard();
      }
    } on ApiException catch (e) {
      debugPrint('[RateDriver] ApiException: ${e.statusCode} ${e.message}');
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      debugPrint('[RateDriver] Unexpected: $e');
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not save your rating. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const RiderHomeShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = (widget.driverName ?? 'Terwase').split(' ').first;

    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: _navigateToDashboard),
        title: const Text('Victoria'),
        actions: [
          TextButton(
            onPressed: _navigateToDashboard,
            child: const Text(
              'Skip',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.primaryContainer,
                child: Icon(
                  Icons.person,
                  size: 36,
                  color: AppColors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'How was your ride with $firstName?',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your feedback helps us maintain executive standards.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setState(() => _rating = i),
                      icon: Icon(
                        i <= _rating ? Icons.star : Icons.star_border,
                        size: 36,
                        color: i <= _rating ? Colors.amber : AppColors.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Add a Tip', style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final t in _tips)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: t == _tips.last ? 0 : 12,
                        ),
                        child: ChoiceChip(
                          label: Text('₦$t'),
                          selected: _tip == t,
                          onSelected: (_) =>
                              setState(() => _tip = _tip == t ? null : t),
                          selectedColor: AppColors.primaryContainer,
                          labelStyle: TextStyle(
                            color: _tip == t
                                ? AppColors.onPrimaryContainer
                                : AppColors.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add a comment?',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.outlineVariant,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              AppPrimaryButton(
                label: 'Submit Rating',
                icon: Icons.send,
                loading: _isSubmitting,
                onPressed: _rating > 0 ? _submitRating : null,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _navigateToDashboard,
                child: const Text('Skip Rating & Return to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
