/// Backend API endpoints for the Victoria Ride platform.
///
/// See https://historical-irma-easyclickictltd-90ebad9c.koyeb.app/api-docs/ for the live spec.
abstract final class ApiConfig {
  /// Base URL of the Victoria Ride API (no trailing slash).
  static const String baseUrl =
      'https://historical-irma-easyclickictltd-90ebad9c.koyeb.app';

  /// All routes are versioned under /api/v1.
  static const String apiV1 = '$baseUrl/api/v1';

  // --- Auth ---
  static const String register = '$apiV1/auth/register';
  static const String verifyEmail = '$apiV1/auth/verify-email';
  static const String emailSendOtp = '$apiV1/auth/email/send-otp';
  static const String login = '$apiV1/auth/login';
  static const String logout = '$apiV1/auth/logout';
  static const String refresh = '$apiV1/auth/refresh';
  static const String me = '$apiV1/auth/me';
  static const String phoneSendOtp = '$apiV1/auth/phone/send-otp';
  static const String phoneVerifyOtp = '$apiV1/auth/phone/verify-otp';
  static const String socialLogin = '$apiV1/auth/social-login';
  static const String forgotPassword = '$apiV1/auth/forgot-password';
  static const String resetPassword = '$apiV1/auth/reset-password';

  // --- Drivers / KYC ---
  static const String driverMe = '$apiV1/drivers/me';
  static const String driverOnboardingStatus = '$apiV1/drivers/onboarding/status';
  static const String driverVehicles = '$apiV1/drivers/me/vehicles';
  static const String kycDocuments = '$apiV1/drivers/kyc/documents';
  static const String kycStatus = '$apiV1/drivers/kyc/status';
  static String kycStatusFor(String driverId) =>
      '$apiV1/drivers/$driverId/kyc/status';
  static const String kycSubmit = '$apiV1/drivers/kyc/submit';
  static const String backgroundCheckConsent =
      '$apiV1/drivers/kyc/background-check/consent';
  static const String backgroundCheckStatus =
      '$apiV1/drivers/kyc/background-check/status';
  static const String onlineStatus = '$apiV1/drivers/me/online-status';
  static const String driverLocation = '$apiV1/drivers/me/location';
  static const String approvalPendingEmail =
      '$apiV1/drivers/kyc/approval-pending/email';

  // --- Driver Wallet ---
  static const String driverWallet = '$apiV1/drivers/wallet';
  static const String walletTransactions = '$apiV1/drivers/wallet/transactions';
  static const String walletBankAccount = '$apiV1/drivers/wallet/bank-account';
  static const String walletWithdraw = '$apiV1/drivers/wallet/withdraw';

  // --- Rider Wallet ---
  static const String riderWallet = '$apiV1/wallet';
  static const String riderWalletFund = '$apiV1/wallet/fund';
  static String riderWalletFundVerify(String reference) =>
      '$apiV1/wallet/fund/verify/$reference';
  static const String riderWalletTransactions = '$apiV1/wallet/transactions';

  // --- Rides (driver state machine) ---
  static String rideStatus(String rideId) =>
      '$apiV1/rides/$rideId/status';
  static String rideAccept(String rideId) => '$apiV1/rides/$rideId/accept';
  static String rideArrive(String rideId) => '$apiV1/rides/$rideId/arrive';
  static String rideStart(String rideId) => '$apiV1/rides/$rideId/start';
  static String rideCancel(String rideId) => '$apiV1/rides/$rideId/cancel';
  static String rideComplete(String rideId) => '$apiV1/rides/$rideId/complete';

  // --- Locations ---
  static const String locationsCountries = '$apiV1/locations/countries';
  static const String locationsStates = '$apiV1/locations/states';
  static String locationsLgas(String stateId) =>
      '$apiV1/locations/states/$stateId/lgas';
}
