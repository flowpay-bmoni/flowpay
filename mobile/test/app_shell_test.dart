import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowpay_mobile/app.dart';
import 'package:flowpay_mobile/core/state/app_state.dart';
import 'package:flowpay_mobile/core/theme/components.dart';

import 'package:flowpay_mobile/core/auth/account_capabilities.dart';
import 'package:flowpay_mobile/core/auth/secure_storage_service.dart';

Future<void> unlockApp(WidgetTester tester) async {
  if (find.text('FlowPay is Locked').evaluate().isNotEmpty) {
    final pinField = find.byType(TextField);
    if (pinField.evaluate().isNotEmpty) {
      await tester.enterText(pinField, '112233');
      await tester.pumpAndSettle();
    }
  }

  if (find.text('Select Account Mode').evaluate().isNotEmpty) {
    await tester.tap(find.text('Continue in Personal Mode'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() async {
    SecureStorageService.resetMemoryCacheForTesting();
    final storage = SecureStorageService();
    await storage.saveUserProfile(
      UserProfile(
        userId: 'test-user-id',
        email: 'test@flowpay.finance',
        fullName: 'Test User',
        country: 'Nigeria',
        phone: '+2348012345678',
        accountType: AccountType.personal,
        kycStatus: KycStatus.verified,
        createdAt: DateTime(2025, 1, 1),
      ),
    );
    await storage.saveCapabilities(
      AccountCapabilities.demo(),
    );
    await storage.setFallbackPin('112233');
    await storage.setAppLockEnabled(true);
  });

  group('FlowPay Application Shell & Auth Gate Tests', () {
    testWidgets(
        'Initializes behind AppAuthGate and unlocks into Personal Shell',
        (tester) async {
      final appState = AppState();

      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // App starts locked behind AppAuthGate
      expect(find.text('FlowPay is Locked'), findsOneWidget);
      expect(find.text('Enter 6-Digit PIN'), findsOneWidget);

      // Perform PIN Unlock
      await unlockApp(tester);

      // Now unlocked into Personal Shell
      expect(find.byType(SegmentedRoleSwitch), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);

      // Personal navigation tabs within bottom NavigationBar
      final navBar = find.byType(NavigationBar);
      expect(find.descendant(of: navBar, matching: find.text('Overview')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Wallets')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Missions')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Activity')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Security')),
          findsOneWidget);

      // Personal Dashboard content
      expect(find.text('Personal Account'), findsOneWidget);
      expect(find.text('Money Missions'), findsOneWidget);
    });

    testWidgets(
        'Tapping Business in Role Switch seamlessly transitions to Business Shell',
        (tester) async {
      final appState = AppState();

      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // Unlock
      await unlockApp(tester);

      // Tap "Business" on the Segmented Role Switch
      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();

      // Business navigation tabs within bottom NavigationBar
      final navBar = find.byType(NavigationBar);
      expect(find.descendant(of: navBar, matching: find.text('Dashboard')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Team')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Payroll')),
          findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.text('Audit')),
          findsOneWidget);

      // Business Dashboard content
      expect(find.text('Business Dashboard'), findsOneWidget);
      expect(
          find.text('One Employer. Many Countries. One Bill.'), findsOneWidget);
    });

    testWidgets('Switches tabs cleanly in Business mode', (tester) async {
      final appState = AppState();

      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // Unlock and switch to Business
      await unlockApp(tester);
      await tester.tap(find.text('Business'));
      await tester.pumpAndSettle();

      final navBar = find.byType(NavigationBar);

      // Tap Team tab in nav bar
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Team')));
      await tester.pumpAndSettle();
      expect(find.text('Global Team'), findsOneWidget);

      // Tap Payroll tab in nav bar
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Payroll')));
      await tester.pumpAndSettle();
      expect(find.text('One Aggregate Bill'), findsOneWidget);

      // Tap Audit tab in nav bar
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Audit')));
      await tester.pumpAndSettle();
      expect(find.text('Global Payroll Fan-Out'), findsOneWidget);
    });

    testWidgets('Switches tabs cleanly in Personal mode', (tester) async {
      final appState = AppState();

      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // Unlock
      await unlockApp(tester);

      final navBar = find.byType(NavigationBar);

      // Tap Wallets tab in nav bar
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Wallets')));
      await tester.pumpAndSettle();
      expect(find.text('Secure Hardware Isolation'), findsOneWidget);

      // Tap Missions tab in nav bar
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Missions')));
      await tester.pumpAndSettle();
      expect(find.text('Your money. Your rules. AI executes.'), findsOneWidget);

      // Tap Security tab in nav bar
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Security')));
      await tester.pumpAndSettle();
      expect(find.text('B-Key Hardware Enclave Active'), findsOneWidget);
    });

    testWidgets('Lock button locks app back to AppAuthGate', (tester) async {
      final appState = AppState();

      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      // Unlock
      await unlockApp(tester);

      expect(find.text('FlowPay is Locked'), findsNothing);

      // Tap Lock FlowPay action button
      await tester.tap(find.byTooltip('Lock FlowPay'));
      await tester.pumpAndSettle();

      // App is re-locked
      expect(find.text('FlowPay is Locked'), findsOneWidget);
    });

    testWidgets('Toggles theme mode dynamically', (tester) async {
      final appState = AppState();

      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      expect(appState.isDarkMode, isTrue);

      appState.toggleTheme();
      await tester.pumpAndSettle();

      expect(appState.isDarkMode, isFalse);
      expect(appState.themeMode, ThemeMode.light);
    });
  });
}
