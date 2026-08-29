import 'package:flutter/material.dart';

import '../../features/auth/data/auth_repository.dart';
import '../network/api_client.dart';
import '../services/session_controller.dart';

/// Resolves the next destination for an authenticated rider.
///
/// The driver's router gated on KYC/approval state; riders will gate on
/// their own onboarding/profile state. Implement [resolveDestination] when
/// the rider's home shell and onboarding screens exist.
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

  /// Pushes [destination] as the new root, removing every route below it
  /// (including the splash screen) so the back button can't return to them.
  static void pushAndClearStack(BuildContext context, Widget destination) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => destination),
      (route) => false,
    );
  }
}
