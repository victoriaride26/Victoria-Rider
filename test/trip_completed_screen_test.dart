import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/features/ride/presentation/screens/rate_driver_screen.dart';
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
    expect(find.text('Skip & Return to Dashboard'), findsOneWidget);
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

    // Tap the Pay button to open the RidePaymentSheet modal bottom sheet
    await tester.tap(find.text('Pay ₦3200 via Paystack'));
    await tester.pumpAndSettle();

    // Bottom sheet is displayed with ride payment options and close button
    expect(find.text('Ride Payment'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('Pay ₦3,200 via Paystack'), findsOneWidget);

    // Close button dismisses the bottom sheet safely
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Ride Payment'), findsNothing);
  });

  testWidgets('RateDriverScreen provides Skip rating button to terminate flow directly to Dashboard', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RateDriverScreen(
          rideId: 'VR-90210',
          driverName: 'Tersoo Tyokyaa',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Victoria'), findsOneWidget);
    expect(find.text('How was your ride with Tersoo?'), findsOneWidget);
    expect(find.text('Submit Rating'), findsOneWidget);
    // Rating is strictly optional: Skip is available both in AppBar and body
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Skip Rating & Return to Dashboard'), findsOneWidget);
  });
}
