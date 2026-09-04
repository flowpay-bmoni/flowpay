import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowpay_mobile/core/state/app_state.dart';
import 'package:flowpay_mobile/modules/business/payroll_screen.dart';

void main() {
  group('FlowPay Global Payroll Screen Widget Tests', () {
    testWidgets(
        'Renders global payroll header, core message, and aggregate bill',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState();

      await tester.pumpWidget(
        MaterialApp(
          home: PayrollScreen(appState: appState),
        ),
      );

      // Let initial async load complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Header & Core Message
      expect(find.text('Global Payroll'), findsOneWidget);
      expect(
          find.text('One Employer. Many Countries. One Bill.'), findsOneWidget);

      // 2. Aggregate Bill Card
      expect(find.text('One Aggregate Bill'), findsOneWidget);
      expect(find.text('TOTAL AGGREGATE SETTLEMENT'), findsOneWidget);
      expect(find.textContaining('\$6,000.00'), findsOneWidget);
      expect(find.textContaining('Saved: \$495.00 (97%)'), findsOneWidget);

      // 3. Parallel Multi-Rail Breakdown
      expect(find.text('PARALLEL MULTI-RAIL DISBURSEMENTS'), findsOneWidget);
      expect(find.text('Bunch Dillon'), findsOneWidget);
      expect(find.text('Samson Jabo'), findsOneWidget);

      // 4. Destination Rail Verification Badges
      expect(find.text('CNGN Rail Active & Verified'), findsOneWidget);
      expect(find.text('MEXe Rail Active & Verified'), findsOneWidget);

      // 5. "Run Payroll" action button
      expect(find.text('Run Payroll'), findsOneWidget);
    });

    testWidgets(
        'Tapping Run Payroll opens Confirmation modal with employee count, country count, total',
        (tester) async {
      final appState = AppState();

      await tester.pumpWidget(
        MaterialApp(
          home: PayrollScreen(appState: appState),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap "Run Payroll"
      await tester.tap(find.text('Run Payroll'));
      await tester.pumpAndSettle();

      // Confirmation Modal must appear
      expect(find.text('Confirm Global Payroll'), findsOneWidget);
      expect(find.text('TOTAL EMPLOYEES'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('COUNTRIES'), findsOneWidget);
      expect(find.text('3 (NG, MX, CA)'), findsOneWidget);
      expect(find.text('AGGREGATE DISBURSEMENT'), findsOneWidget);
      expect(find.text('\$6,000.00'), findsAtLeastNWidgets(2));
      expect(find.text('Saved \$495.00'), findsOneWidget);
      expect(find.text('Approve Payroll'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets(
        'Tapping Approve Payroll prompts for PIN and runs through 4-stage execution pipeline',
        (tester) async {
      final appState = AppState();

      await tester.pumpWidget(
        MaterialApp(
          home: PayrollScreen(appState: appState),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Open confirmation modal
      await tester.tap(find.text('Run Payroll'));
      await tester.pumpAndSettle();

      // Tap "Approve Payroll"
      await tester.tap(find.text('Approve Payroll'));
      await tester.pumpAndSettle();

      // PIN Dialog appears
      expect(find.text('B-Key PIN Signing'), findsOneWidget);
      expect(find.text('Authorize & Sign'), findsOneWidget);

      // Tap Authorize & Sign
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Authorize & Sign'));
      await tester.pump();

      // Execution Pipeline appears with all 4 timeline states
      expect(find.text('Execution Pipeline'), findsOneWidget);
      expect(find.text('Validated'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Wait for execution to finish
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      // Completed Run Banner appears
      expect(find.text('Payroll Completed Successfully'), findsOneWidget);
      expect(find.text('Download Payslips & Receipts'), findsOneWidget);
    });
  });
}
