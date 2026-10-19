import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import 'legal_consent_screen.dart';
import 'login_screen.dart';
import 'phone_login_screen.dart';

/// One-time swipeable onboarding carousel for first-time riders, built from
/// the three value propositions. Skip leads to login; Get Started leads to
/// sign up. Completing or skipping persists a flag so it never shows again.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _seenKey = 'onboarding_seen';

  /// Whether the rider has already completed (or skipped) the carousel.
  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage(this.image, this.title, this.subtitle);

  final String image;
  final String title;
  final String subtitle;
}

const List<_OnboardingPage> _pages = [
  _OnboardingPage(
    'assets/images/onboarding/booking.png',
    'Book in seconds',
    'One-tap ride requests anywhere, anytime.',
  ),
  _OnboardingPage(
    'assets/images/onboarding/safe_drivers.png',
    'Safe drivers',
    'Thoroughly vetted and professional captains.',
  ),
  _OnboardingPage(
    'assets/images/onboarding/cashless.png',
    'Cashless payment',
    'Seamless digital transactions for every trip.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToNext() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen._seenKey, true);
  }

  /// Skip: straight to login (the login screen carries a Sign up option).
  Future<void> _skipToLogin() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  /// Get Started: sign up — via the consent gate when the legal documents
  /// have not been accepted yet.
  Future<void> _signUp() async {
    await _markSeen();
    final accepted = await LegalConsentScreen.hasAccepted();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => accepted
            ? const PhoneLoginScreen()
            : const LegalConsentScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Skip (hidden on the last page).
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: isLast
                    ? const SizedBox.shrink()
                    : TextButton(
                        onPressed: _skipToLogin,
                        child: const Text(
                          'Skip',
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      final page = _pageController.page ?? index.toDouble();
                      final delta =
                          (index - page).clamp(-1.0, 1.0).toDouble();
                      return Opacity(
                        opacity: (1 - delta.abs() * 0.6).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(delta * 40, 0),
                          child: child,
                        ),
                      );
                    },
                    child: _OnboardingPageView(data: _pages[index]),
                  );
                },
              ),
            ),
            // Page indicator dots.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        active ? AppColors.primary : AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            // Next / Get Started.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: isLast ? _signUp : _goToNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: isLast
                        ? const Row(
                            key: ValueKey('get-started'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Get Started'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 20),
                            ],
                          )
                        : const Row(
                            key: ValueKey('next'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Next'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 20),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.data});

  final _OnboardingPage data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/icons/t-logo.png',
            height: 96,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: Image.asset(
              data.image,
              height: 300,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
