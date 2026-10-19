import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// In-app splash shown after the (white) native launch screen while the app
/// boots. Mirrors the driver app startup screen with reversed colours: the
/// branded car photo sits under a translucent white overlay with the green
/// "Victoria Rides" wordmark layered on top.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _footerOpacity;
  Timer? _navigateTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.8, end: 1.05).chain(CurveTween(
          curve: Curves.easeOutBack,
        )),
        weight: 30,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 10),
    ]).animate(_controller);

    _logoOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 80),
    ]).animate(_controller);

    _taglineOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
    ]).animate(_controller);

    _footerOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 25),
    ]).animate(_controller);

    _controller.forward();
    _navigateTimer = Timer(const Duration(milliseconds: 3200), _bootstrap);
  }

  /// Restores any persisted session and routes to the right destination:
  /// the rider home when signed in, the one-time onboarding intro for
  /// first-time riders, otherwise the Login screen (sign up is linked from
  /// there and the legal consent gate is presented before sign up begins).
  Future<void> _bootstrap() async {
    Widget destination = const LoginScreen();
    final hasSession = await SessionController.instance.restore();
    if (hasSession && await AppRouter.ensureValidSession()) {
      destination = await AppRouter.resolveDestination();
      // Re-register the push token on a restored session. Token registration
      // only ran at login, so a returning rider whose token rotated would
      // otherwise never receive trip-completed / payment pushes.
      unawaited(FcmService.instance.syncToken());
    } else if (!await OnboardingScreen.hasSeen()) {
      destination = const OnboardingScreen();
    }
    if (!mounted) return;
    AppRouter.pushAndClearStack(context, destination);
  }

  @override
  void dispose() {
    _navigateTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Branded car photo (full colour).
          Image.asset(
            'assets/images/splash/splash_car.png',
            fit: BoxFit.cover,
          ),
          // Translucent white overlay (reversed from the driver app's
          // dark-green gradient) keeps the green wordmark readable.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3FFFFFF),
                  Color(0xF2FFFFFF),
                ],
              ),
            ),
          ),
          // Central content.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 4),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/icons/t-logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Opacity(
                    opacity: _taglineOpacity.value,
                    child: child,
                  ),
                  child: Column(
                    children: [
                      Text(
                        AppConstants.appFullName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'The safe and comfortable way to travel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
          // Loading dots.
          const Positioned(
            bottom: 64,
            left: 0,
            right: 0,
            child: _BouncingDots(),
          ),
          // Footer.
          Positioned(
            bottom: 104,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Opacity(
                opacity: _footerOpacity.value,
                child: child,
              ),
              child: const Text(
                'Powered by Victoria Travels',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = (_controller.value - index * 0.2) % 1.0;
            final t = Curves.easeInOut.transform(
              (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0),
            );
            return Transform.translate(
              offset: Offset(0, -t * 6),
              child: Opacity(
                opacity: 0.8 - t * 0.3,
                child: child,
              ),
            );
          },
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}
