import 'package:flutter/material.dart';

import '../../features/auth/data/auth_repository.dart';

/// Bridge between the platform identity SDKs and `/auth/social-login`.
///
/// The backend contract is already wired through
/// [AuthRepository.socialLogin]; this class only needs to hand back the
/// provider `idToken`. Drop in `google_sign_in` / `sign_in_with_apple`
/// here once the native configuration (iOS entitlements, Android SHA
/// keys) is in place.
class SocialSignInService {
  SocialSignInService._();

  /// Returns the OIDC id token for [provider], or null when no platform
  /// sign-in flow has been configured for it yet.
  static Future<String?> getIdToken(SocialProvider provider) async {
    debugPrint(
      'SocialSignInService: ${provider.name} native SDK not configured — '
      'add google_sign_in / sign_in_with_apple and return its idToken here.',
    );
    return null;
  }
}
