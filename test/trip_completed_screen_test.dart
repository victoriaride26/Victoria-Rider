import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/features/ride/presentation/screens/trip_completed_screen.dart';

void main() {
  testWidgets('TripCompletedScreen displays full addresses and payment confirmation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TripCompletedScreen(
          rideId: 'VR-90210',
          driverName: 'Tersoo Tyokyaa',
          fareNgn: 2500.0,
          pickupAddress: 'Wurukum Roundabout, Makurdi, Benue State',
          dropoffAddress: 'Federal University of Agriculture Makurdi',
          paymentMethod: 'CARD',
          isPaymentConfirmed: true,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Trip Completed!'), findsOneWidget);
    // Verified: Trip ID is removed from trip summary screen
    expect(find.text('Trip #VR-90210'), findsNothing);
    expect(find.text('₦2500'), findsOneWidget);
    expect(find.text('Payment Confirmed'), findsOneWidget);
    expect(find.text('Wurukum Roundabout, Makurdi, Benue State'), findsOneWidget);
    expect(find.text('Federal University of Agriculture Makurdi'), findsOneWidget);
    expect(find.text('Tersoo Tyokyaa'), findsOneWidget);
    expect(find.text('CARD (PAYSTACK)'), findsOneWidget);
    expect(find.text('Rate Driver'), findsOneWidget);
    // Verified: Back to Home link and back button removed for forward-only flow
    expect(find.text('Back to Home'), findsNothing);
  });

  testWidgets('TripCompletedScreen displays pending payment state and Pay button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TripCompletedScreen(
          rideId: 'VR-90210',
          driverName: 'Tersoo Tyokyaa',
          fareNgn: 3200.0,
          pickupAddress: 'Wurukum Roundabout, Makurdi',
          dropoffAddress: 'High Level Market, Makurdi',
          paymentMethod: 'CARD',
          isPaymentConfirmed: false,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Payment Pending'), findsOneWidget);
    expect(find.text('Pay ₦3200 via Paystack'), findsOneWidget);
    // Verified: Rate Driver is hidden until payment is completed
    expect(find.text('Rate Driver'), findsNothing);
    expect(find.text('Trip #VR-90210'), findsNothing);
  });
}
