import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtrides/core/services/session_controller.dart';
import 'package:vtrides/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:vtrides/features/auth/presentation/screens/login_screen.dart';
import 'package:vtrides/features/auth/presentation/screens/reset_password_screen.dart';

void main() {
  setUp(() {
    SessionController.tokenStore = InMemoryTokenStore();
  });

  group('ForgotPasswordScreen (email OTP)', () {
    testWidgets('renders email field and send button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ForgotPasswordScreen()),
      );

      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Send Reset Code'), findsOneWidget);
      expect(find.text('you@example.com'), findsOneWidget);
    });

    testWidgets('validates empty and invalid email', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ForgotPasswordScreen()),
      );

      await tester.tap(find.text('Send Reset Code'));
      await tester.pump();
      expect(find.text('Enter your email'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField),
        'not-an-email',
      );
      await tester.tap(find.text('Send Reset Code'));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    test('isValidResetEmail accepts only emails', () {
      expect(isValidResetEmail('user@example.com'), isTrue);
      expect(isValidResetEmail('  user@example.com  '), isTrue);
      expect(isValidResetEmail('not-an-email'), isFalse);
      expect(isValidResetEmail('08031234567'), isFalse);
      expect(isValidResetEmail(''), isFalse);
    });
  });

  group('ResetPasswordScreen (email OTP)', () {
    testWidgets('renders OTP and password fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordScreen(email: 'user@example.com'),
        ),
      );

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('user@example.com'), findsWidgets);
      expect(find.text('6-digit code'), findsOneWidget);
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Resend code'), findsOneWidget);
    });

    testWidgets('validates OTP and passwords on empty submit', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordScreen(email: 'user@example.com'),
        ),
      );

      await tester.tap(find.text('Reset Password'));
      await tester.pump();
      expect(find.text('Enter the 6-digit code'), findsOneWidget);
      expect(find.text('Create a password'), findsOneWidget);
      expect(find.text('Confirm your password'), findsOneWidget);
    });
  });

  group('LoginScreen forgot-password entry', () {
    testWidgets('has Forgot Password link opening the email flow',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LoginScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forgot Password?'), findsOneWidget);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.text('Send Reset Code'), findsOneWidget);
    });
  });
}
