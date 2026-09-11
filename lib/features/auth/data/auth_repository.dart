import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/session_controller.dart';

/// Social identity providers supported by `/auth/social-login`.
enum SocialProvider { google, apple }

/// Result of an authentication call that yields a session.
class AuthSession {
  const AuthSession({this.accessToken, this.refreshToken, this.user});

  final String? accessToken;
  final String? refreshToken;
  final Map<String, dynamic>? user;
}

/// Result of `/auth/social-login` — the backend returns an
/// `onboardingToken` when the phone number still needs verification.
class SocialLoginResult {
  const SocialLoginResult({this.session, this.onboardingToken});

  final AuthSession? session;
  final String? onboardingToken;

  bool get requiresPhoneVerification =>
      session == null || session!.accessToken == null;
}

/// Authentication repository — maps the Victoria Ride API auth endpoints.
class AuthRepository {
  AuthRepository._();

  static final AuthRepository instance = AuthRepository._();

  final ApiClient _api = ApiClient.instance;

  /// POST /auth/register — creates a user account (defaults to a rider).
  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    String role = 'RIDER',
  }) async {
    await _api.post(
      ApiConfig.register,
      body: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': email.trim(),
        'password': password,
        'phone': normalizePhone(phone),
        'role': role,
      },
    );
  }

  /// POST /auth/login — exchanges credentials for tokens.
  ///
  /// Tokens are persisted in [SessionController] before returning.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final data = await _api.post(
      ApiConfig.login,
      body: {'email': email.trim(), 'password': password},
    );
    return _persistSession(data);
  }

  /// POST /auth/social-login — Google or Apple sign-in.
  ///
  /// [idToken] comes from the platform identity SDK. When the account's
  /// phone is not yet verified the backend responds with an
  /// `onboardingToken` instead of a full session.
  Future<SocialLoginResult> socialLogin({
    required SocialProvider provider,
    required String idToken,
  }) async {
    final data = await _api.post(
      ApiConfig.socialLogin,
      body: {
        'provider': provider == SocialProvider.google ? 'GOOGLE' : 'APPLE',
        'idToken': idToken,
      },
    );
    if (data is Map<String, dynamic>) {
      final onboardingToken = data['onboardingToken'];
      final hasTokens = data['token'] != null ||
          (data['tokens'] is Map &&
              (data['tokens'] as Map)['accessToken'] != null);
      if (!hasTokens && onboardingToken is String && onboardingToken.isNotEmpty) {
        return SocialLoginResult(onboardingToken: onboardingToken);
      }
    }
    return SocialLoginResult(session: await _persistSession(data));
  }

  /// GET /auth/me — validates the current access token and returns the user.
  Future<Map<String, dynamic>?> me() async {
    final data = await _api.get(ApiConfig.me);
    if (data is Map<String, dynamic>) {
      final user = data['user'];
      return user is Map<String, dynamic> ? user : data;
    }
    return null;
  }

  /// POST /auth/verify-email — confirms the driver's email address with
  /// the 6-digit OTP emailed at registration.
  Future<void> verifyEmail({
    required String email,
    required String otp,
  }) async {
    await _api.post(ApiConfig.verifyEmail, body: {
      'email': email.trim(),
      'otp': otp,
    });
  }

  /// POST /auth/email/send-otp — emails a fresh 6-digit verification code,
  /// used when the original code expires. The backend does not expose this
  /// endpoint yet; callers surface the failure gracefully.
  Future<void> sendEmailOtp(String email) async {
    await _api.post(ApiConfig.emailSendOtp, body: {'email': email.trim()});
  }

  /// POST /auth/refresh — rotates tokens using the stored refresh token.
  Future<bool> refreshSession() async {
    final refresh = SessionController.instance.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final data = await _api.post(
        ApiConfig.refresh,
        body: {'refreshToken': refresh},
      );
      await _persistSession(data);
      return SessionController.instance.hasSession;
    } on ApiException {
      return false;
    }
  }

  /// POST /auth/logout — invalidates the refresh token server-side and
  /// clears local state.
  Future<void> logout() async {
    final refresh = SessionController.instance.refreshToken;
    try {
      if (refresh != null && refresh.isNotEmpty) {
        await _api.post(ApiConfig.logout, body: {'refreshToken': refresh});
      }
    } finally {
      await SessionController.instance.clear();
    }
  }

  /// Normalizes a phone number to E.164 for the selected country code.
  ///
  /// Handles the values users actually type: spaces/dashes/parens,
  /// leading zeros (`0803...`), embedded country codes with or without
  /// a `00` prefix (`234803...`, `00234803...`) and stray `+` signs.
  /// The result is always `<countryCode><10 digits>` (no `+`), which is
  /// what the auth endpoints expect.
  static String normalizePhone(String raw, {String countryCode = '+234'}) {
    final cc = countryCode.replaceFirst(RegExp(r'^\+'), '');
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    // Strip international prefixes and duplicate country codes.
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith(cc)) {
      digits = digits.substring(cc.length);
    } else if (cc.length > 1 && digits.startsWith(cc.substring(1))) {
      digits = digits.substring(cc.length - 1);
    }
    // Local trunk zero(s): 0803... -> 803...
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '$cc$digits';
  }

  /// POST /auth/phone/send-otp — requests a phone verification OTP.
  ///
  /// Retries once on a server error (5xx); the endpoint has been seen
  /// to fail transiently ("illegal length" 500s) before succeeding.
  ///
  /// Returns the OTP echoed by the server. THIS IS DEV-ONLY — the backend
  /// returns `otp` in the response solely for app testing during development
  /// and must be removed/reversed in production. Do not rely on, log, or
  /// ship this value in a release build.
  ///
  // TODO(dev-only): strip this before release. In production the caller must
  // NOT receive the OTP from the API — the code should arrive only via the
  // actual SMS. Gate this return on !kReleaseMode (see otp_verification_screen)
  // and delete it once the backend stops echoing otp.
  Future<String?> sendPhoneOtp(String phone) async {
    final normalized = normalizePhone(phone);
    final data = await _postWithRetry(
      ApiConfig.phoneSendOtp,
      {'phone': normalized},
    );
    if (data is Map<String, dynamic>) {
      final otp = data['otp'];
      return otp is String && otp.isNotEmpty ? otp : null;
    }
    return null;
  }

  /// POST /auth/phone/verify-otp — confirms the phone number.
  ///
  /// Uses the same normalization as [sendPhoneOtp] so both calls hit
  /// the server with an identical value.
  Future<void> verifyPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    final normalized = normalizePhone(phone);
    await _postWithRetry(
      ApiConfig.phoneVerifyOtp,
      {'phone': normalized, 'otp': otp},
    );
  }

  /// POSTs [body] once, retrying a single time when the server answers
  /// 5xx. Client errors (4xx) surface immediately.
  Future<dynamic> _postWithRetry(String path, Map<String, dynamic> body) async {
    try {
      return await _api.post(path, body: body);
    } on ApiException catch (e) {
      if (!e.isServerError) rethrow;
      return _api.post(path, body: body);
    }
  }

  /// POST /auth/forgot-password — requests a reset OTP/link.
  Future<void> forgotPassword(String email) async {
    await _api.post(
      ApiConfig.forgotPassword,
      body: {'email': email.trim()},
    );
  }

  /// POST /auth/reset-password — resets the password with an emailed OTP.
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await _api.post(
      ApiConfig.resetPassword,
      body: {
        'email': email.trim(),
        'otp': otp,
        'newPassword': newPassword,
      },
    );
  }

  /// Normalizes the different token payload shapes returned by the API
  /// (`token`, `tokens.accessToken`, `accessToken`) and persists them.
  Future<AuthSession> _persistSession(dynamic data) async {
    String? access;
    String? refresh;
    Map<String, dynamic>? user;
    if (data is Map<String, dynamic>) {
      access = data['token'] as String?;
      final tokens = data['tokens'];
      if (tokens is Map<String, dynamic>) {
        access ??= tokens['accessToken'] as String?;
        refresh = tokens['refreshToken'] as String?;
      }
      access ??= data['accessToken'] as String?;
      refresh ??= data['refreshToken'] as String?;
      user = data['user'] is Map<String, dynamic>
          ? data['user'] as Map<String, dynamic>
          : null;
    }
    await SessionController.instance.save(
      accessToken: access,
      refreshToken: refresh,
      user: user,
    );
    return AuthSession(accessToken: access, refreshToken: refresh, user: user);
  }
}
