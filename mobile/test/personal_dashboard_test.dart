import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import 'package:flowpay_mobile/app.dart';
import 'package:flowpay_mobile/core/state/app_state.dart';
import 'package:flowpay_mobile/modules/personal/components/ai_allocation_modal.dart';
import 'package:flowpay_mobile/modules/personal/components/ai_command_bar.dart';
import 'package:flowpay_mobile/modules/personal/components/ai_fx_conversion_modal.dart';
import 'package:flowpay_mobile/modules/personal/components/pending_approvals_card.dart';

import 'package:flowpay_mobile/core/auth/account_capabilities.dart';
import 'package:flowpay_mobile/core/auth/secure_storage_service.dart';

Future<void> unlockIntoPersonal(WidgetTester tester) async {
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

  group('FlowPay Personal Dashboard Tests', () {
    testWidgets(
        'Renders complete Personal Financial Dashboard with all core sections',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await unlockIntoPersonal(tester);

      // 1. Header & Purpose
      expect(find.text('Personal Account'), findsWidgets);
      expect(find.text('Your money. Your rules. AI executes.'), findsWidgets);
      expect(find.text('Sandbox Demo'), findsOneWidget);
      expect(find.text('B-Key Vault'), findsOneWidget);

      // 2. Portfolio Balance Section
      expect(find.text('Total Multi-Currency Portfolio'), findsOneWidget);
      expect(find.text('USD PRIMARY'), findsOneWidget);
      expect(find.textContaining('\$37,671'),
          findsOneWidget); // deterministic minor unit valuation
      expect(find.textContaining('Avail: \$24,500.00'), findsOneWidget);

      // 3. Quick Actions
      expect(find.text('Create Mission'), findsOneWidget);
      expect(find.text('Send Money'), findsOneWidget);
      expect(find.text('View Wallets'), findsOneWidget);

      // 4. Money Missions Feature Card & Active Rules
      expect(find.text('Money Missions'), findsOneWidget);
      expect(find.text('Active Strategy Rules'), findsOneWidget);
      expect(find.text('20% Emergency Fund Auto-Sweep'), findsOneWidget);

      // 5. Primary AI Interaction
      expect(find.byType(AiCommandBar), findsOneWidget);
      expect(find.text('What should your money do?'), findsOneWidget);
      expect(find.text('Allocate my \$2,000'), findsOneWidget);
      expect(find.text('Send \$500 to my designer'), findsOneWidget);

      // 6. Pending Approvals
      expect(find.byType(PendingApprovalsCard), findsOneWidget);
      expect(find.text('Actions Awaiting Your Approval'), findsOneWidget);
      expect(find.textContaining('Pending'), findsWidgets);

      // 7. Scroll to Multi-Currency Smart Wallets & Recent Activity
      await tester.scrollUntilVisible(
        find.textContaining('CNGN'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Multi-Currency Smart Wallets'), findsOneWidget);
      expect(find.textContaining('USDB'), findsWidgets);
      expect(find.textContaining('CNGN'), findsWidgets);

      await tester.scrollUntilVisible(
        find.textContaining('MEXe'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('MEXe'), findsWidgets);
      expect(find.textContaining('CADC'), findsWidgets);

      // 8. Recent Activity
      await tester.scrollUntilVisible(
        find.text('Recent Activity'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Emergency Fund Auto-Sweep'), findsWidgets);
    });

    testWidgets(
        'Tapping "Allocate my \$2,000" opens AiAllocationModal workflow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await unlockIntoPersonal(tester);

      // Tap suggestion chip
      await tester.tap(find.text('Allocate my \$2,000'));
      await tester.pumpAndSettle();

      // Verify AiAllocationModal opened
      expect(find.byType(AiAllocationModal), findsOneWidget);
      expect(find.text('Smart Capital Allocation'), findsOneWidget);
      expect(
          find.text('Task Workflow: Autonomous Split & Sweep'), findsOneWidget);
      expect(find.text('Activate Allocation Rule'), findsOneWidget);
    });

    testWidgets(
        'Tapping "Convert \$1,000 to Naira" opens AiFxConversionModal workflow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await unlockIntoPersonal(tester);

      // Drag horizontal suggestions row to bring 3rd suggestion chip into view
      await tester.drag(
          find.text('Allocate my \$2,000'), const Offset(-350, 0));
      await tester.pumpAndSettle();

      // Tap conversion suggestion chip
      await tester.tap(find.text('Convert \$1,000 to Naira'));
      await tester.pumpAndSettle();

      // Verify AiFxConversionModal opened
      expect(find.byType(AiFxConversionModal), findsOneWidget);
      expect(find.text('Instant Multi-Currency FX'), findsOneWidget);
      expect(
          find.text('Task Workflow: Zero-Spread BMONI Rail'), findsOneWidget);
      expect(find.text('Sign & Convert'), findsOneWidget);
    });

    testWidgets('Pending Approvals opens PIN signing dialog on Approve',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await unlockIntoPersonal(tester);

      // Tap first "Approve (PIN)" button in PendingApprovalsCard
      final approveBtn = find.text('Approve (PIN)').first;
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      // Verify PIN authorization dialog
      expect(find.text('Authorize Action'), findsOneWidget);
      expect(find.text('Enter 6-Digit B-Key Signing PIN'), findsOneWidget);
      expect(find.text('Sign & Execute'), findsOneWidget);
    });

    testWidgets('Toggling privacy hides and reveals balance', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();
      await tester.pumpWidget(FlowPayApp(appState: appState));
      await tester.pumpAndSettle();

      await unlockIntoPersonal(tester);

      // Initially balance visible
      expect(find.textContaining('\$37,671'), findsOneWidget);

      // Tap balance to toggle privacy
      await tester.tap(find.byType(BMoniWalletCardBalance));
      await tester.pumpAndSettle();

      // Now hidden with placeholder
      expect(find.text('••••••'), findsOneWidget);

      // Tap again to reveal
      await tester.tap(find.byType(BMoniWalletCardBalance));
      await tester.pumpAndSettle();

      // Balance visible again
      expect(find.textContaining('\$37,671'), findsOneWidget);
    });
  });
}
