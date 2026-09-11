import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/core/theme/app_theme.dart';
import 'package:vtrides/features/ride/presentation/screens/searching_for_driver_screen.dart';

void main() {
  testWidgets('SearchingForDriverScreen renders without overflow on constrained height',
      (tester) async {
    // Set small screen constraints matching the error scenario (312x348)
    tester.view.physicalSize = const Size(312, 348);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const SearchingForDriverScreen(rideId: 'test-ride-123'),
      ),
    );

    await tester.pump();

    // Verify key elements render
    expect(find.text('Searching for Driver'), findsOneWidget);
    expect(find.text('Finding your Victoria driver nearby...'), findsOneWidget);
    expect(find.text('Cancel Request'), findsOneWidget);

    // No exceptions or overflow should have been thrown
    expect(tester.takeException(), isNull);
  });
}
