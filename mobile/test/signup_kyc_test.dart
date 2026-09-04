import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowpay_mobile/app.dart';
import 'package:flowpay_mobile/core/auth/secure_storage_service.dart';
import 'package:flowpay_mobile/core/design_system/input_fields.dart';
import 'package:flowpay_mobile/core/state/app_state.dart';
import 'package:flowpay_mobile/modules/auth/signup_screen.dart';
import 'package:flowpay_mobile/modules/auth/kyc_screen.dart';
import 'package:flowpay_mobile/modules/auth/set_pin_screen.dart';
import 'package:flowpay_mobile/modules/auth/login_screen.dart';

Future<void> enterField(WidgetTester tester, String label, String value) async {
  final field = find.descendant(
    of: find.widgetWithText(FlowPayTextField, label),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, value);
}

void main() {
  setUp(() {
    SecureStorageService.resetMemoryCacheForTesting();
  });

  group('Signup, KYC and Account Separation Tests', () {
    testWidgets('Opens SignupScreen from LoginScreen and renders form controls',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // App starts unauthenticated on LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text("Don't have an account? Sign Up"), findsOneWidget);

      // Tap Create New Account
      await tester.tap(find.text("Don't have an account? Sign Up"));
      await tester.pumpAndSettle();

      // Verify on SignupScreen
      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.text('Create an Account'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
      expect(find.text('Proceed to Identity Verification'), findsOneWidget);
    });

    testWidgets('Personal signup input and navigation to KYC screen',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Don't have an account? Sign Up"));
      await tester.pumpAndSettle();

      // Fill personal form fields
      await enterField(tester, 'Full Legal Name', 'Alice Wonderland');
      await enterField(tester, 'Personal Email', 'alice@example.com');
      await enterField(tester, 'Phone Number', '+2348011223344');
      await tester.pumpAndSettle();

      // Proceed to Identity Verification
      await tester.tap(find.text('Proceed to Identity Verification'));
      await tester.pumpAndSettle();

      // Verify on KycScreen in Personal mode
      expect(find.byType(KycScreen), findsOneWidget);
      expect(find.text('Identity Verification'), findsOneWidget);
      expect(find.text('Step 1: Government Identity'), findsOneWidget);
      expect(find.text('Step 2: Facial Biometric Liveness'), findsOneWidget);
      expect(find.text('Start Liveness Scan'), findsOneWidget);
    });

    testWidgets(
        'Completing Personal KYC lands strictly in Personal Shell with Personal-only header',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Don't have an account? Sign Up"));
      await tester.pumpAndSettle();

      // Fill personal form fields
      await enterField(tester, 'Full Legal Name', 'Alice Wonderland');
      await enterField(tester, 'Personal Email', 'alice@example.com');
      await enterField(tester, 'Phone Number', '+2348011223344');
      await tester.pumpAndSettle();

      // Proceed to KYC
      await tester.tap(find.text('Proceed to Identity Verification'));
      await tester.pumpAndSettle();

      // Fill KYC fields
      await enterField(
          tester, 'Bank Verification Number (BVN) / NIN', '12345678901');
      await enterField(tester, 'Date of Birth (YYYY-MM-DD)', '1995-05-15');
      await enterField(tester, 'Residential Address', '10 Marina Road, Lagos');
      await tester.pumpAndSettle();

      // Run facial scan
      await tester.tap(find.text('Start Liveness Scan'));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('Facial Biometrics Verified ✅'), findsOneWidget);

      // Complete Verification & Proceed to Set PIN
      await tester.tap(find.text('Complete KYC & Set PIN'));
      await tester.pumpAndSettle();

      // Verify on SetPinScreen
      expect(find.byType(SetPinScreen), findsOneWidget);
      expect(find.text('Set Your 6-Digit PIN'), findsOneWidget);

      // Enter 6 digits
      for (var d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Confirmation stage
      expect(find.text('Confirm Your 6-Digit PIN'), findsOneWidget);
      for (var d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Should now be in PersonalShell
      expect(find.text('Personal Account'), findsWidgets);
      final navBar = find.byType(NavigationBar);
      expect(find.descendant(of: navBar, matching: find.text('Overview')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Wallets')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Missions')),
          findsOneWidget);
    });

    testWidgets(
        'Business signup input, corporate KYB, Set PIN, and strict Business Shell landing',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Don't have an account? Sign Up"));
      await tester.pumpAndSettle();

      // Select Business
      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();

      // Fill business signup fields
      await enterField(tester, 'Full Legal Name', 'Bob Founder');
      await enterField(tester, 'Work Email', 'bob@acme.com');
      await enterField(tester, 'Phone Number', '+2348099887766');
      await enterField(
          tester, 'Registered Company Name', 'Acme Technologies Ltd');
      await enterField(tester, 'Registration / Tax Number', 'RC-9988776');
      await enterField(tester, 'Your Company Role', 'Founder & CEO');
      await tester.pumpAndSettle();

      // Proceed to Corporate KYB
      await tester.tap(find.text('Proceed to Identity Verification'));
      await tester.pumpAndSettle();

      // Verify on KycScreen in Business mode
      expect(find.byType(KycScreen), findsOneWidget);
      expect(find.text('Corporate KYB Compliance'), findsOneWidget);
      expect(find.text('Step 1: Corporate Legal Entity'), findsOneWidget);
      expect(find.text('Step 2: Authorized Signatory Verification'),
          findsOneWidget);
      expect(find.text('Disbursement Rails Activated'), findsOneWidget);

      // Fill KYB fields
      await enterField(
          tester, 'Corporate Tax ID / RFC / EIN', 'TIN-11223344');
      await enterField(
          tester, 'Registered Business Office Address', 'Plot 5, Victoria Island, Lagos');
      await enterField(
          tester, 'Authorized Officer Identity / BVN', 'SIG-998877');
      await tester.pumpAndSettle();

      // Submit Corporate Verification & proceed to Set PIN
      await tester.tap(find.text('Activate Rails & Set PIN'));
      await tester.pumpAndSettle();

      // Verify on SetPinScreen
      expect(find.byType(SetPinScreen), findsOneWidget);
      for (var d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Confirm PIN
      for (var d in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.text(d));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Should now be in BusinessShell with Business navigation
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Payroll'), findsOneWidget);
      expect(find.text('Audit'), findsOneWidget);
    });

    testWidgets('Logs in via email and PIN from LoginScreen',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // Starts on LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Log In to FlowPay'), findsOneWidget);

      // Enter login credentials into the two TextFields on LoginScreen
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'user@flowpay.finance');
      await tester.enterText(textFields.at(1), '123456');
      await tester.pumpAndSettle();

      // Tap Log In
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      // Lands in Personal shell
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Wallets'), findsWidgets);
    });
  });
}
