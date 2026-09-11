import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/core/services/session_controller.dart';
import 'package:vtrides/core/theme/app_theme.dart';
import 'package:vtrides/features/rider/presentation/screens/rider_home_shell.dart';
import 'package:vtrides/features/rider/presentation/widgets/rider_bottom_nav.dart';
import 'package:vtrides/features/rider/presentation/widgets/rider_drawer.dart';

void main() {
  setUp(() {
    SessionController.tokenStore = InMemoryTokenStore();
    SessionController.instance.user = {
      'firstName': 'Victoria',
      'lastName': 'Rider',
      'email': 'victoria@example.com',
    };
  });

  testWidgets('RiderHomeShell renders exactly ONE RiderBottomNav',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const RiderHomeShell(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify exactly ONE RiderBottomNav is rendered on the screen
    expect(find.byType(RiderBottomNav), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // Verify HomeScreen elements
    expect(find.text('Makurdi, Benue State'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Daily Ride'), findsOneWidget);
    expect(find.text('Saved Places'), findsOneWidget);
  });

  testWidgets('Tapping menu button opens the RiderDrawer',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const RiderHomeShell(),
      ),
    );
    await tester.pumpAndSettle();

    // Drawer is initially closed
    expect(find.byType(RiderDrawer), findsNothing);

    // Tap the hamburger menu button
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    // Drawer is now open
    expect(find.byType(RiderDrawer), findsOneWidget);
    expect(find.text('Victoria Rider'), findsOneWidget);
    expect(find.text('victoria@example.com'), findsOneWidget);
    expect(find.text('My Rides'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RiderDrawer),
        matching: find.text('Saved Places'),
      ),
      findsOneWidget,
    );
    expect(find.text('Log Out'), findsOneWidget);
  });
}
