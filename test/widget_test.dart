// Smoke test for the VT Rides app boot.
import 'package:flutter_test/flutter_test.dart';

import 'package:vtrides/core/services/session_controller.dart';
import 'package:vtrides/main.dart';

void main() {
  testWidgets('App boots to the splash screen', (WidgetTester tester) async {
    // Use an in-memory store so startup session restore is hermetic.
    SessionController.tokenStore = InMemoryTokenStore();
    await tester.pumpWidget(const VTRidesApp());
    // In-app splash auto-advances to Get Started after ~2s.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Victoria'), findsOneWidget);
  });
}
