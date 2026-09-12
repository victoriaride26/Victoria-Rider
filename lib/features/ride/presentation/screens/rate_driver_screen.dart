import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_back_button.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../../rider/presentation/screens/rider_home_shell.dart';

/// R-13 — Rate Your Driver.
class RateDriverScreen extends StatefulWidget {
  const RateDriverScreen({
    super.key,
    this.rideId,
    this.driverName,
  });

  final String? rideId;
  final String? driverName;

  @override
  State<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends State<RateDriverScreen> {
  int _rating = 0;
  int? _tip;

  static const List<int> _tips = [200, 500, 1000];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = (widget.driverName ?? 'Terwase').split(' ').first;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Victoria'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.help_outline, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.primaryContainer,
                child: Icon(Icons.person, size: 36,
                    color: AppColors.onPrimaryContainer),
              ),
              const SizedBox(height: 16),
              Text('How was your ride with $firstName?',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Your feedback helps us maintain executive standards.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: AppColors.onSurfaceVariant),
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
                child: Text('Add a Tip',
                    style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final t in _tips)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: t == _tips.last ? 0 : 12),
                        child: ChoiceChip(
                          label: Text('₦$t'),
                          selected: _tip == t,
                          onSelected: (_) => setState(
                              () => _tip = _tip == t ? null : t),
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
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add a comment?',
                  hintStyle: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.outlineVariant),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const Spacer(),
              AppPrimaryButton(
                label: 'Submit Rating',
                icon: Icons.send,
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(
                      builder: (_) => const RiderHomeShell(initialIndex: 1)),
                  (route) => false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
