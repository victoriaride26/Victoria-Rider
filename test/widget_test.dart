// Smoke test for the VT Rides app boot.
import 'package:flutter_test/flutter_test.dart';

import 'package:vtrides/main.dart';

void main() {
  testWidgets('App boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VTRidesApp());
    // Splash auto-advances to Get Started after ~2s.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('Welcome to Victoria'), findsOneWidget);
  });
}
