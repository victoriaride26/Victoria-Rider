import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/core/theme/app_theme.dart';
import 'package:vtrides/features/payments/data/rider_wallet_repository.dart';
import 'package:vtrides/features/payments/presentation/widgets/fund_wallet_sheet.dart';

void main() {
  group('Rider Wallet Models', () {
    test('WalletFundResult parses standard Paystack response', () {
      final json = {
        'success': true,
        'data': {
          'authorization_url': 'https://checkout.paystack.com/test12345',
          'access_code': 'ac_98765',
          'reference': 'ref_test_001',
        }
      };
      final result = WalletFundResult.fromJson(json);
      expect(result.authorizationUrl, 'https://checkout.paystack.com/test12345');
      expect(result.reference, 'ref_test_001');
      expect(result.accessCode, 'ac_98765');
    });

    test('WalletTransaction parses kobo amount into NGN', () {
      final json = {
        'id': 'tx_123',
        'amount': 250000, // 2,500 NGN in kobo
        'type': 'CREDIT',
        'status': 'SUCCESS',
        'description': 'Wallet Top-up',
        'reference': 'ref_tx_123',
        'createdAt': '2026-09-03T12:00:00.000Z',
      };
      final tx = WalletTransaction.fromJson(json);
      expect(tx.id, 'tx_123');
      expect(tx.amountNgn, 2500.0);
      expect(tx.isCredit, true);
      expect(tx.title, 'Wallet Top-up');
    });
  });

  group('FundWalletSheet Widget', () {
    testWidgets('Renders input, preset amount chips, and pay button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: FundWalletSheet(currentBalance: 5000.0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fund Your Wallet'), findsOneWidget);
      expect(find.text('Current balance: '), findsOneWidget);
      expect(find.text('Paystack'), findsOneWidget);

      // Verify preset amount chips
      expect(find.text('₦1,000'), findsOneWidget);
      expect(find.text('₦2,500'), findsOneWidget);
      expect(find.text('₦5,000'), findsOneWidget);
      expect(find.text('₦10,000'), findsOneWidget);
      expect(find.text('₦20,000'), findsOneWidget);

      // Default amount is 2500
      expect(find.text('Proceed to Payment (₦2,500)'), findsOneWidget);

      // Tap ₦10,000 chip
      await tester.tap(find.text('₦10,000'));
      await tester.pumpAndSettle();

      expect(find.text('Proceed to Payment (₦10,000)'), findsOneWidget);
    });
  });
}
