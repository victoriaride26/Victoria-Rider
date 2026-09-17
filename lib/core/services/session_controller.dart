import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

/// Persistence contract for session tokens.
///
/// Production uses device secure storage; tests can substitute
/// [InMemoryTokenStore] to stay hermetic.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Secure-storage backed [TokenStore].
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Ephemeral [TokenStore] for widget tests.
class InMemoryTokenStore implements TokenStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Holds the driver's auth session (access + refresh tokens) and persists
/// them so sessions survive app restarts.
class SessionController {
  SessionController._();

  static final SessionController instance = SessionController._();

  /// Overridable in tests to avoid touching real device storage.
  @visibleForTesting
  static TokenStore tokenStore = const SecureTokenStore();

  static const _kAccessToken = 'vr_access_token';
  static const _kRefreshToken = 'vr_refresh_token';
  static const _kUser = 'vr_user';
  static const _kRememberMe = 'vr_remember_me';
  static const _kEmail = 'vr_remember_email';

  String? accessToken;
  String? refreshToken;

  /// Temporary onboarding token received from /auth/social-login when phone
  /// verification is required before full session issuance.
  String? onboardingToken;

  /// When false, tokens are kept in memory only and never written to
  /// secure storage, so the session does not survive an app restart.
  bool rememberMe = true;

  /// Last email used to sign in, surfaced to prefill the login field.
  String? rememberedEmail;

  /// Cached profile from the last login/refresh response.
  ///
  /// `GET /auth/me` only returns JWT claims (id, role), so the full user
  /// object captured at sign-in is the authoritative local source for
  /// names/email.
  Map<String, dynamic>? user;

  static bool _isValidToken(String? token) {
    if (token == null) return false;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    return lower != 'null' &&
        lower != 'undefined' &&
        lower != 'bearer null' &&
        lower != 'bearer undefined' &&
        lower != 'bearer';
  }

  bool get hasSession => _isValidToken(accessToken);

  /// Loads the persisted "remember me" preference and email. Call once at
  /// startup before relying on [rememberMe] / [rememberedEmail].
  Future<void> loadPrefs() async {
    try {
      final rm = await tokenStore.read(_kRememberMe);
      rememberMe = rm != 'false';
      final email = await tokenStore.read(_kEmail);
      rememberedEmail = (email != null && email.isNotEmpty) ? email : null;
    } catch (_) {
      rememberMe = true;
      rememberedEmail = null;
    }
  }

  /// Restores a persisted session. Returns true when a token was found.
  ///
  /// When [rememberMe] is disabled the session is treated as signed out and
  /// any previously persisted tokens are dropped.
  Future<bool> restore() async {
    await loadPrefs();
    try {
      final rawAccess = await tokenStore.read(_kAccessToken);
      final rawRefresh = await tokenStore.read(_kRefreshToken);
      accessToken = _isValidToken(rawAccess) ? rawAccess!.trim() : null;
      refreshToken = _isValidToken(rawRefresh) ? rawRefresh!.trim() : null;
      final rawUser = await tokenStore.read(_kUser);
      if (rawUser != null && rawUser.isNotEmpty) {
        user = jsonDecode(rawUser) as Map<String, dynamic>;
      }
    } catch (_) {
      accessToken = null;
      refreshToken = null;
      user = null;
    }
    if (!rememberMe) {
      accessToken = null;
      refreshToken = null;
      user = null;
      await _deleteStoredSession();
      return false;
    }
    return hasSession;
  }

  /// Persists a fresh pair of tokens returned by the API.
  ///
  /// Tokens are only written to secure storage when [rememberMe] is true;
  /// otherwise they stay in memory for the current session only.
  Future<void> save({
    required String? accessToken,
    String? refreshToken,
    Map<String, dynamic>? user,
  }) async {
    if (_isValidToken(accessToken)) {
      this.accessToken = accessToken!.trim();
      if (rememberMe) await tokenStore.write(_kAccessToken, this.accessToken!);
    }
    if (_isValidToken(refreshToken)) {
      this.refreshToken = refreshToken!.trim();
      if (rememberMe) {
        await tokenStore.write(_kRefreshToken, this.refreshToken!);
      }
    }
    if (user != null) {
      this.user = user;
      if (rememberMe) await tokenStore.write(_kUser, jsonEncode(user));
    }
  }

  /// Records the user's "remember me" choice and the email to prefill.
  ///
  /// When [rememberMe] is false any previously persisted session is removed
  /// so the driver is not silently signed back in next launch.
  Future<void> saveRememberPrefs({
    required bool rememberMe,
    String? email,
  }) async {
    this.rememberMe = rememberMe;
    try {
      await tokenStore.write(_kRememberMe, rememberMe ? 'true' : 'false');
      if (rememberMe) {
        if (email != null && email.isNotEmpty) {
          rememberedEmail = email;
          await tokenStore.write(_kEmail, email);
        }
      } else {
        rememberedEmail = null;
        await tokenStore.delete(_kEmail);
        await _deleteStoredSession();
      }
    } catch (_) {
      // Preference write failures are non-fatal.
    }
  }

  /// Removes only the stored token/user keys, leaving in-memory state intact.
  Future<void> _deleteStoredSession() async {
    try {
      await tokenStore.delete(_kAccessToken);
      await tokenStore.delete(_kRefreshToken);
      await tokenStore.delete(_kUser);
    } catch (_) {
      // Storage failures are non-fatal.
    }
  }

  /// Clears all session state from memory and storage.
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    onboardingToken = null;
    user = null;
    try {
      await tokenStore.delete(_kAccessToken);
      await tokenStore.delete(_kRefreshToken);
      await tokenStore.delete(_kUser);
    } catch (_) {
      // Storage failures on sign-out are non-fatal.
    }
  }
}
