import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/session_controller.dart';
import '../../../../core/theme/app_theme.dart';
import 'get_started_screen.dart';

/// In-app splash shown after the (white) native launch screen while the
/// app boots, before advancing to the Get Started screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), _bootstrap);
  }

  /// Restores any persisted session and routes to the right destination:
  /// the rider home when signed in, otherwise the Get Started screen.
  Future<void> _bootstrap() async {
    Widget destination = const GetStartedScreen();
    final hasSession = await SessionController.instance.restore();
    if (hasSession && await AppRouter.ensureValidSession()) {
      destination = await AppRouter.resolveDestination();
    }
    if (!mounted) return;
    AppRouter.pushAndClearStack(context, destination);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: AppColors.primaryFixed),
          ],
        ),
      ),
    );
  }
}
