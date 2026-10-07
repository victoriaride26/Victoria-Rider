/// Central app naming — single source of truth.
///
/// - Owner: Victoria Travels Bus Company Nigeria Limited
/// - Human-readable app: Victoria Rides
/// - Launcher (Rider): VT Rides / (Driver): VT Rides Driver
/// - In-app UI: [appFullName] where space permits, else [appShortName].
/// - Codebase identifiers (package, classes, channel IDs) stay as-is.
///
/// Change [appFullName]/[appShortName] here once and every derived message
/// below follows automatically. UI code must reference these constants
/// instead of hard-coding brand literals.
///
/// NOTE: platform files cannot reference Dart constants, so keep these in
/// sync manually:
/// - `android/app/src/main/AndroidManifest.xml` label == [launcherNameRider]
/// - `ios/Runner/Info.plist` CFBundleDisplayName == [launcherNameRider]
/// - `ios/Runner/Info.plist` NSLocationWhenInUseUsageDescription uses
///   [locationPermissionSystem].
abstract final class AppConstants {
  /// Short name for tight spaces (launcher, compact UI).
  static const String appShortName = 'VT Rides';

  /// Legacy alias for tight spaces.
  static const String appName = appShortName;

  /// Full human-readable name — use everywhere space permits in the UI.
  static const String appFullName = 'Victoria Rides';

  /// Launcher text for this (Rider) app. Driver app uses [launcherNameDriver].
  static const String launcherNameRider = appShortName;
  static const String launcherNameDriver = 'VT Rides Driver';

  /// Legal owner name.
  static const String companyName =
      'Victoria Travels Bus Company Nigeria Limited';

  // ── Derived UI strings (all follow appFullName) ──────────────────────

  /// Get-started headline.
  static const String welcomeTitle = 'Welcome to $appFullName';

  /// AppBar titles with room for the full name.
  static const String appBarTitle = appFullName;

  /// Drawer / settings footer. Update version alongside pubspec.
  static const String versionFooter = '$appFullName • v1.0.0';

  /// Logout confirmation body.
  static const String logoutConfirmMessage =
      'Are you sure you want to log out of your $appFullName account?';

  /// Delete-account confirmation body.
  static const String deleteAccountMessage =
      'This will permanently delete your $appFullName account and all associated data. This action cannot be undone.';

  /// Legal list subtitle.
  static const String termsSubtitle = 'Your agreement to use $appFullName';

  /// Legal placeholder body.
  static const String legalPlaceholder =
      'This content will be supplied by the $appFullName legal team. The structure is ready to display the final documents required for a ride-hailing app.';

  /// Safety feature description.
  static const String safetyDescription =
      '$appFullName ensures every trip is monitored with 24/7 safety assistance, emergency SOS contact sharing, and thoroughly vetted drivers.';

  /// Wallet funded (no amount).
  static const String walletFunded = 'Your $appFullName wallet has been funded.';

  /// Ride-history empty state.
  static const String rideHistoryEmpty =
      'You have not taken any rides yet. Start your journey with $appFullName today!';

  /// Fare-guard errors (backend is the only fare source).
  static const String fareEstimateMissing =
      'Estimated fare must be obtained from $appFullName.';
  static const String fareEstimateMissingAbort =
      'Cannot request ride: Estimated fare must be obtained from $appFullName, otherwise ABORT.';
  static const String fareEstimateMissingRequestAborted =
      'Estimated fare could not be obtained from $appFullName. Ride request aborted.';
  static const String rideSearchAbortedFare =
      'Ride search aborted: Estimated fare must be obtained from $appFullName.';

  /// Driver-status messages.
  static const String driverArrivedMessage =
      '🚗 Your $appFullName driver has arrived at the pickup point!';
  static const String findingDriverMessage =
      'Finding your $appFullName driver nearby...';

  /// Post-trip / payment messages.
  static const String tripCompletedSubtitle =
      'We hope you had a pleasant executive ride experience with $appFullName.';
  static const String paymentVerifying =
      'Confirming your transaction with $appFullName server.';

  /// Foreground-service notification title.
  static const String trackingNotificationTitle =
      '$appFullName — Tracking your location';

  /// Fallback push-notification title.
  static const String pushFallbackTitle = appFullName;

  /// Rider tray channel (user-visible in OS settings).
  static const String trayChannelName = appFullName;
  static const String trayChannelDesc =
      'Trip updates, payments and announcements';

  /// In-app location rationales (roomy body copy → full name).
  static const String locationServiceOffBody =
      "Your device's location services are switched off.\n\n$appFullName needs GPS to show your position on the map, find nearby drivers, and give you accurate pickup coordinates.";
  static const String locationDeniedForeverBody =
      'Location access was permanently denied.\n\nPlease open App Settings, go to Permissions, and allow Location so $appFullName can find you on the map.';
  static const String locationRationaleBody =
      '$appFullName needs your location to:\n\n\u2022 Show you on the map so drivers can find you\n\u2022 Give accurate pickup coordinates\n\u2022 Provide real distance and fare estimates\n\nYour location is only used while the app is open.';

  /// System permission string (mirror in Info.plist, which can't import Dart).
  static const String locationPermissionSystem =
      '$appFullName needs your location to show your pickup spot, find nearby drivers, and ensure accurate navigation.';

  /// Variable messages — still single-sourced via the brand constant.
  static String walletCredited(String amount) =>
      '$amount has been credited to your $appFullName wallet.';
  static String paymentThankYou(String fare) =>
      '$fare has been received. Thank you for riding with $appFullName!';
}
