import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowpay_mobile/app.dart';
import 'package:flowpay_mobile/core/navigation/personal_tab_provider.dart';
import 'package:flowpay_mobile/core/money/currency.dart';
import 'package:flowpay_mobile/core/state/app_state.dart';
import 'package:flowpay_mobile/modules/personal/personal_shell.dart';

import 'package:flowpay_mobile/core/auth/account_capabilities.dart';
import 'package:flowpay_mobile/core/auth/secure_storage_service.dart';

Future<void> _unlockApp(WidgetTester tester) async {
  if (find.text('FlowPay is Locked').evaluate().isNotEmpty) {
    final pinField = find.byType(TextField);
    if (pinField.evaluate().isNotEmpty) {
      await tester.enterText(pinField, '112233');
      await tester.pumpAndSettle();
    }
  }

  final continuePersonal = find.text('Continue in Personal Mode');
  if (continuePersonal.evaluate().isNotEmpty) {
    await tester.tap(continuePersonal);
    await tester.pumpAndSettle();
  }
}

Future<void> _enterPin(WidgetTester tester) async {
  expect(find.byKey(const Key('pin_key_1')), findsOneWidget);
  await tester.tap(find.byKey(const Key('pin_key_1')));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byKey(const Key('pin_key_2')));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byKey(const Key('pin_key_3')));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byKey(const Key('pin_key_4')));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byKey(const Key('pin_key_5')));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byKey(const Key('pin_key_6')));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
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

  group('FlowPay Personal End-to-End Feature Integration Tests', () {
    testWidgets(
        'Journey 1: Open FlowPay -> Wallet Exists -> Balances Visible -> Bottom Nav & Quick Actions Switch Tabs',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appState = AppState();
      await tester.pumpWidget(
        ProviderScope(
          child: FlowPayApp(appState: appState),
        ),
      );
      await tester.pumpAndSettle();

      // 1. App starts locked behind AppAuthGate, quick unlock
      await _unlockApp(tester);

      // 2. Personal Shell loaded, initial tab is Dashboard (Overview)
      expect(find.byType(PersonalShell), findsOneWidget);
      expect(find.text('Personal Account'), findsOneWidget);
      expect(find.text('B-Key Vault'), findsOneWidget);

      // Verify wallet balances visible
      expect(find.text('Total Multi-Currency Portfolio'), findsOneWidget);
      expect(find.textContaining('\$'), findsWidgets);

      // 3. Test Dashboard Quick Action -> "View Wallets" switches to Wallets tab
      await tester.tap(find.text('View Wallets'));
      await tester.pumpAndSettle();
      expect(appState.personalTabIndex, PersonalTab.wallets);
      expect(find.text('Configured Multi-Currency Wallets'), findsOneWidget);

      // 4. Test Bottom Navigation Bar switching to Missions tab
      final navBar = find.byType(NavigationBar);
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Missions')));
      await tester.pumpAndSettle();
      expect(appState.personalTabIndex, PersonalTab.missions);
      expect(find.text('Active Missions'), findsWidgets);

      // 5. Switch to Activity tab
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Activity')));
      await tester.pumpAndSettle();
      expect(appState.personalTabIndex, PersonalTab.activity);
      expect(find.text('Search by recipient, merchant, or reference...'),
          findsOneWidget);

      // 6. Switch to Security tab
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Security')));
      await tester.pumpAndSettle();
      expect(appState.personalTabIndex, PersonalTab.security);
      expect(find.text('B-Key Hardware Enclave Active'), findsOneWidget);

      // 7. Switch back to Dashboard (Overview)
      await tester
          .tap(find.descendant(of: navBar, matching: find.text('Overview')));
      await tester.pumpAndSettle();
      expect(appState.personalTabIndex, PersonalTab.overview);
      expect(find.text('Personal Account'), findsOneWidget);
    });

    testWidgets(
        'Journey 2: Money Mission Full Flow (NLP Prompt -> AI Interpretation -> Review -> PIN Sign -> Execution -> Activity Verification)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appState = AppState();
      await tester.pumpWidget(
        ProviderScope(
          child: FlowPayApp(appState: appState),
        ),
      );
      await tester.pumpAndSettle();
      await _unlockApp(tester);

      // 1. Navigate to Missions via Dashboard "Create Mission" quick action
      await tester.tap(find.text('Create Mission'));
      await tester.pumpAndSettle();
      expect(appState.personalTabIndex, PersonalTab.missions);

      // 2. Select a suggestion chip to populate intent
      await tester.tap(find.text('Split incoming payment'));
      await tester.pumpAndSettle();

      // Verify text populated in controller
      expect(find.textContaining('Whenever I receive \$2,000, keep 30% in USD'),
          findsWidgets);

      // 3. Tap "Interpret Directive"
      await tester.tap(find.text('Interpret Directive'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Verify AI interpretation and deterministic preview
      expect(find.text('Mission Plan Preview'), findsOneWidget);
      expect(find.text('\$2,000 incoming'), findsOneWidget);
      expect(find.text('100% Allocated'), findsOneWidget);

      // 4. Tap "Approve Mission"
      await tester.tap(find.text('Approve Mission'));
      await tester.pumpAndSettle();

      // 5. Enter PIN for BMONI Enclave signing
      await _enterPin(tester);

      // 6. Celebration dialog appears
      expect(find.text('Mission Activated & Signed!'), findsOneWidget);
      expect(find.text('BMONI B-Key PIN Verified'), findsOneWidget);
      expect(find.text('View in Activity'), findsOneWidget);

      // 7. Tap "View in Activity" -> transitions to Activity tab
      await tester.tap(find.text('View in Activity'));
      await tester.pumpAndSettle();

      expect(appState.personalTabIndex, PersonalTab.activity);
      expect(find.text('Search by recipient, merchant, or reference...'),
          findsOneWidget);

      // Verify that the mission entry appears in the Activity ledger
      expect(find.textContaining('Incoming 3-Way Split'), findsWidgets);
    });

    testWidgets(
        'Journey 3: Send Money Full Flow (Intent -> Balance Check & Conversion -> Review -> PIN Sign -> Execution -> Wallet Debit & Activity Ledger)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final appState = AppState();

      await tester.pumpWidget(
        ProviderScope(
          child: FlowPayApp(appState: appState),
        ),
      );
      await tester.pumpAndSettle();
      await _unlockApp(tester);

      // Get initial balances with FakeAsync time advancement
      final walletsFuture = appState.walletRepo.getWallets();
      await tester.pump(const Duration(milliseconds: 150));
      final initialWallets = await walletsFuture;
      final usdWallet =
          initialWallets.firstWhere((w) => w.currency == Currency.usd);
      final initialUsdMinor = usdWallet.balance.amountMinor;

      // 1. Tap "Send Money" quick action from Personal Dashboard
      final sendMoneyQuickAction = find.text('Send Money');
      expect(sendMoneyQuickAction, findsOneWidget);
      await tester.tap(sendMoneyQuickAction);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SendMoneyScreen is displayed
      expect(find.text('FlowPay BMONI Rail'), findsOneWidget);

      // 2. Select a pre-canned suggestion chip to set recipient & amount without typing
      final chipFinder = find.text('Send \$500 to my designer in Ghana');
      expect(chipFinder, findsOneWidget);
      await tester.tap(chipFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify recipient and amount are populated
      expect(find.text('my designer in Ghana'), findsOneWidget);

      // 3. Tap Review Transfer
      final reviewButtonFinder =
          find.byKey(const Key('send_money_review_button'));
      expect(reviewButtonFinder, findsOneWidget);
      await tester.tap(reviewButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      // 4. Modal appears with transfer details & funding option
      expect(find.text('Nothing moves until you approve.'), findsOneWidget);
      expect(find.textContaining('my designer in Ghana'), findsWidgets);

      // 5. Tap Approve & Send button in review modal
      await tester.tap(find.byKey(const Key('transfer_review_approve_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      // 6. Authenticate with PIN
      await _enterPin(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      // 7. Verify Transfer Settled celebration dialog appears
      expect(find.text('Transfer Settled'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);

      // 8. Tap "Activity" button on celebration dialog to view unified ledger
      await tester.tap(find.text('Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify navigation to Activity tab
      expect(appState.personalTabIndex, PersonalTab.activity);

      // 9. Verify wallet balance debited
      final updatedWalletsFuture = appState.walletRepo.getWallets();
      await tester.pump(const Duration(milliseconds: 150));
      final updatedWallets = await updatedWalletsFuture;
      final updatedUsdWallet =
          updatedWallets.firstWhere((w) => w.id == usdWallet.id);
      expect(updatedUsdWallet.balance.amountMinor < initialUsdMinor, isTrue,
          reason: 'USD wallet balance should have been debited');

      // 10. Verify Activity repo records this transfer
      final recentActivities =
          await appState.activityRepo.getRecentActivities();
      final transferItem = recentActivities.firstWhere(
        (a) => a.counterparty == 'my designer in Ghana',
        orElse: () => throw Exception(
            'Transfer to my designer in Ghana not recorded in activity'),
      );
      expect(transferItem.amount?.toMajorString(), '500.00');
    });
  });
}
