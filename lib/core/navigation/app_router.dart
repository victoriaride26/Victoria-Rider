import 'package:flutter/material.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/rider/presentation/screens/rider_home_shell.dart';
import '../network/api_client.dart';
import '../services/session_controller.dart';

/// Resolves the next destination for an authenticated rider.
///
/// Riders have no KYC/approval gate (that's driver-only), so a rider with a
/// valid session always lands on [RiderHomeShell].
abstract final class AppRouter {
  AppRouter._();

  /// Validates the stored session (refreshing once on 401).
  ///
  /// Returns true when a usable access token is present afterwards.
  static Future<bool> ensureValidSession() async {
    if (!SessionController.instance.hasSession) return false;
    try {
      await AuthRepository.instance.me();
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Resolves the next screen for a signed-in rider.
  static Future<Widget> resolveDestination() async {
    return const RiderHomeShell();
  }

  /// Pushes [destination] as the new root, removing every route below it
  /// (including the splash screen) so the back button can't return to them.
  static void pushAndClearStack(BuildContext context, Widget destination) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => destination),
      (route) => false,
    );
  }
}
