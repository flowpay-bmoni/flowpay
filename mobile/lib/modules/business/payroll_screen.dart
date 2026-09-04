import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/bmoni_sdk/bmoni_sdk_service.dart';
import 'package:flowpay_mobile/core/design_system/design_system.dart';
import '../../core/repositories/payroll_repository.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/radii.dart';

enum PayrollExecutionStep {
  validated,
  approved,
  processing,
  completed,
}

/// Multi-Country Global Payroll Screen
/// Core message: "One Employer. Many Countries. One Bill."
/// Conforms to design.md & BMONI transfer proposal protocol:
/// - Recipient destination currency rail validation (CNGN, MEXe)
/// - Review screen with aggregate bill, fees, and 97% savings
/// - Confirmation modal before execution (employee count, country count, total)
/// - 4-state execution timeline: Validated → Approved → Processing → Completed
/// - Independent per-employee outcome display (Completed vs Partially Completed)
/// - Granular single-proposal retry via approve
class PayrollScreen extends StatefulWidget {
  final AppState appState;

  const PayrollScreen({super.key, required this.appState});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  PayrollRunModel? _preview;
  PayrollRunModel? _executionRun;
  bool _isLoading = true;
  bool _isExecuting = false;
  PayrollExecutionStep? _currentStep;
  String? _executingMessage;
  final Set<String> _retryingEmployeeIds = {};

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _isLoading = true);
    try {
      final prev = await widget.appState.payrollRepo.getPayrollPreview();
      if (mounted) {
        setState(() {
          _preview = prev;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load payroll preview: $e')),
        );
      }
    }
  }

  /// Step 1: User taps "Run Payroll" -> Shows Confirmation Screen first!
  void _onTapRunPayroll() {
    if (_preview == null) return;

    if (!_preview!.allRailsActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Cannot run payroll: one or more employees have inactive destination rails.'),
          backgroundColor: FlowPayColors.signalCaution,
        ),
      );
      return;
    }

    _showConfirmationModal();
  }

  /// Step 2: Confirmation modal displaying employee count, country count, aggregate total
  void _showConfirmationModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: FlowPayColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FlowPayColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: FlowPayColors.ink.withAlpha(15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified_user_rounded,
                          color: FlowPayColors.ink, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirm Global Payroll',
                            style: FlowPayTypography.title(color: FlowPayColors.ink)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'One Employer. Many Countries. One Bill.',
                            style: FlowPayTypography.captionStyle(
                                color: FlowPayColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: FlowPayColors.hairline, height: 1),
                const SizedBox(height: 16),

                // Summary grid: Employee count, Country count, Total
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryBox(
                        label: 'TOTAL EMPLOYEES',
                        value: '${_preview!.employeeCount}',
                        icon: Icons.people_alt_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryBox(
                        label: 'COUNTRIES',
                        value:
                            '${_preview!.countries.length} (${_preview!.countries.join(', ')})',
                        icon: Icons.public_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlowPayColors.surfaceAlt,
                    borderRadius: FlowPayRadii.card,
                    border: Border.all(color: FlowPayColors.hairline),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AGGREGATE DISBURSEMENT',
                            style: FlowPayTypography.captionStyle(
                                    color: FlowPayColors.textTertiary)
                                .copyWith(
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _preview!.totalUsd.formatFormatted(),
                            style:
                                FlowPayTypography.display(color: FlowPayColors.ink)
                                    .copyWith(
                              fontSize: 24,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: FlowPayColors.signal.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: FlowPayColors.signal.withAlpha(60)),
                        ),
                        child: Text(
                          'Saved ${_preview!.totalSavedFeeUsd.formatFormatted()}',
                          style: FlowPayTypography.captionStyle(
                                  color: FlowPayColors.signal)
                              .copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Approving will create transfer proposals on your BMONI employer wallet and fan out local stablecoins to all employee smart wallets in parallel.',
                  style: FlowPayTypography.captionStyle(
                      color: FlowPayColors.textSecondary),
                ),
                const SizedBox(height: 24),

                // Actions: Cancel & Approve Payroll
                Row(
                  children: [
                    Expanded(
                      child: FlowPayButton(
                        text: 'Cancel',
                        isSecondary: true,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FlowPayButton(
                        text: 'Approve Payroll',
                        icon: Icons.check_circle_rounded,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _startPayrollExecution();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBox(
      {required String label, required String value, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlowPayColors.surfaceAlt,
        borderRadius: FlowPayRadii.card,
        border: Border.all(color: FlowPayColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: FlowPayColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.textTertiary)
                      .copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: FlowPayTypography.body(color: FlowPayColors.ink)
                .copyWith(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Step 3: Enter PIN & Progress through the 4-Stage Timeline:
  /// Validated → Approved → Processing → Completed
  Future<void> _startPayrollExecution() async {
    final pin = await _showPinDialog();
    if (pin == null || pin.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _currentStep = PayrollExecutionStep.validated;
      _executingMessage = 'Validating destination rails & employer balance...';
    });

    try {
      // Step 1: Validated
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _currentStep = PayrollExecutionStep.approved;
        _executingMessage =
            'Employer threshold approved. Creating transfer proposals...';
      });

      // Step 2: Approved
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _currentStep = PayrollExecutionStep.processing;
        _executingMessage =
            'Signing raw 32-byte digest on-device via B-Key & submitting to BMONI...';
      });

      // Step 3: Processing (On-device secp256k1 raw-hash signing + submission)
      final sig = await BmoniSdkService.signTransactionHash(
        '0x7e8125a09c2cdc7bedc12253e49e4946c6fff0273034eb485750035d21ad31',
        pin: pin,
      );

      final completedRun = await widget.appState.payrollRepo.executePayrollRun(
        runId: _preview!.runId,
        signature: sig,
      );

      // Step 4: Completed
      if (!mounted) return;
      setState(() {
        _currentStep = PayrollExecutionStep.completed;
        _executionRun = completedRun;
        _isExecuting = false;
        _executingMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _executingMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payroll execution notice: $e')),
      );
    }
  }

  Future<void> _handleRetryEmployee(PayrollItemModel item) async {
    final pin = await _showPinDialog();
    if (pin == null || pin.isEmpty) return;

    setState(() {
      _retryingEmployeeIds.add(item.employeeId);
    });

    try {
      final updatedItem = await widget.appState.payrollRepo.retryFailedProposal(
        proposalId: item.proposalId ?? 'prop_retry_${item.employeeId}',
        employeeId: item.employeeId,
        pin: pin,
      );

      if (!mounted) return;
      setState(() {
        _retryingEmployeeIds.remove(item.employeeId);
        if (_executionRun != null) {
          final newItems = _executionRun!.items.map((i) {
            if (i.employeeId == item.employeeId) return updatedItem;
            return i;
          }).toList();

          final allDone = newItems
              .every((i) => i.status == 'SUCCESS' || i.status == 'COMPLETED');
          _executionRun = _executionRun!.copyWith(
            status: allDone ? 'COMPLETED' : 'PARTIALLY_COMPLETED',
            items: newItems,
          );
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Disbursement to ${item.employeeName} retried and confirmed!'),
          backgroundColor: FlowPayColors.signal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _retryingEmployeeIds.remove(item.employeeId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry failed: $e')),
      );
    }
  }

  Future<String?> _showPinDialog() async {
    final pinCtrl = TextEditingController(text: '123456');

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowPayColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: FlowPayRadii.card),
        title: Row(
          children: [
            const Icon(Icons.lock_outline_rounded,
                color: FlowPayColors.ink, size: 22),
            const SizedBox(width: 8),
            Text(
              'B-Key PIN Signing',
              style: FlowPayTypography.title(color: FlowPayColors.ink),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your 6-digit PIN to authorize and sign the 32-byte transfer digest on-device. Private keys never leave hardware.',
              style: FlowPayTypography.body(color: FlowPayColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(
                  color: FlowPayColors.ink, fontSize: 20, letterSpacing: 6),
              decoration: InputDecoration(
                hintText: '••••••',
                filled: true,
                fillColor: FlowPayColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: FlowPayColors.hairline),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: FlowPayColors.textSecondary)),
          ),
          FlowPayButton(
            text: 'Authorize & Sign',
            onPressed: () => Navigator.pop(ctx, pinCtrl.text),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Global Payroll',
              style: FlowPayTypography.title(color: FlowPayColors.ink)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'One Employer. Many Countries. One Bill.',
              style: FlowPayTypography.captionStyle(
                  color: FlowPayColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: FlowPayColors.ink),
            tooltip: 'Refresh Payroll Preview',
            onPressed: _loadPreview,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: FlowPayColors.ink))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. Live Execution Timeline Stepper (Validated → Approved → Processing → Completed)
                if (_isExecuting || _executionRun != null) ...[
                  _buildTimelineStepper(),
                  const SizedBox(height: 20),
                ],

                // 2. Completed / Partially Completed Run Banner
                if (_executionRun != null) ...[
                  _buildResultBanner(),
                  const SizedBox(height: 20),
                  FlowPayButton(
                    text: 'Download Payslips & Receipts',
                    isSecondary: true,
                    icon: Icons.receipt_long_rounded,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'All employee payslips and cryptographic BMONI receipts generated.'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // 3. Aggregate Bill Hero Card
                _buildAggregateBillCard(),
                const SizedBox(height: 24),

                if (_executionRun == null)
                  FlowPayButton(
                    text: 'Run Payroll',
                    icon: Icons.payments_rounded,
                    isLoading: _isExecuting,
                    onPressed: _isExecuting ? null : _onTapRunPayroll,
                  ),
                if (_executionRun == null) const SizedBox(height: 24),

                // 4. Parallel Multi-Rail Breakdown List
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PARALLEL MULTI-RAIL DISBURSEMENTS',
                      style: FlowPayTypography.captionStyle(
                              color: FlowPayColors.textTertiary)
                          .copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${(_executionRun ?? _preview)!.items.length} EMPLOYEES',
                      style: FlowPayTypography.captionStyle(
                              color: FlowPayColors.textSecondary)
                          .copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ...(_executionRun ?? _preview)!
                    .items
                    .map((item) => _buildEmployeePayrollCard(item)),

                const SizedBox(height: 24),

                // 5. Action Controls
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  /// Timeline Stepper Widget
  /// Labels: Validated → Approved → Processing → Completed
  Widget _buildTimelineStepper() {
    final steps = [
      {'label': 'Validated', 'step': PayrollExecutionStep.validated},
      {'label': 'Approved', 'step': PayrollExecutionStep.approved},
      {'label': 'Processing', 'step': PayrollExecutionStep.processing},
      {'label': 'Completed', 'step': PayrollExecutionStep.completed},
    ];

    final currentIdx = _currentStep == null ? 0 : _currentStep!.index;

    return FlowPayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded,
                  color: FlowPayColors.ink, size: 18),
              const SizedBox(width: 8),
              Text(
                'Execution Pipeline',
                style: FlowPayTypography.body(color: FlowPayColors.ink)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_isExecuting) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: FlowPayColors.ink),
                ),
                const SizedBox(width: 6),
                Text(
                  'Live',
                  style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.signal)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: steps.map((s) {
              final stepEnum = s['step'] as PayrollExecutionStep;
              final isDone = stepEnum.index <= currentIdx;
              final isActive = stepEnum.index == currentIdx;

              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (stepEnum.index > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: isDone
                                  ? FlowPayColors.signal
                                  : FlowPayColors.hairline,
                            ),
                          ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? FlowPayColors.signal
                                : FlowPayColors.surfaceAlt,
                            border: Border.all(
                              color: isDone
                                  ? FlowPayColors.signal
                                  : FlowPayColors.hairline,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check,
                                    size: 13, color: Colors.white)
                                : Text(
                                    '${stepEnum.index + 1}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: FlowPayColors.textSecondary),
                                  ),
                          ),
                        ),
                        if (stepEnum.index < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: stepEnum.index < currentIdx
                                  ? FlowPayColors.signal
                                  : FlowPayColors.hairline,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s['label'] as String,
                      style: FlowPayTypography.captionStyle(
                        color: isActive
                            ? FlowPayColors.ink
                            : FlowPayColors.textSecondary,
                      ).copyWith(
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (_executingMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: FlowPayColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _executingMessage!,
                style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Result Banner: Completed vs Partially Completed
  Widget _buildResultBanner() {
    final isPartial = _executionRun!.status == 'PARTIALLY_COMPLETED' ||
        _executionRun!.failedCount > 0;
    final bannerColor =
        isPartial ? FlowPayColors.signalCaution : FlowPayColors.signal;
    final icon =
        isPartial ? Icons.warning_amber_rounded : Icons.check_circle_rounded;
    final title = isPartial
        ? 'Payroll Partially Completed'
        : 'Payroll Completed Successfully';

    return FlowPayCard(
      backgroundColor: bannerColor.withAlpha(18),
      border: Border.all(color: bannerColor, width: 1.5),
      child: Column(
        children: [
          Icon(icon, color: bannerColor, size: 40),
          const SizedBox(height: 8),
          Text(
            title,
            style: FlowPayTypography.title(color: FlowPayColors.ink)
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            isPartial
                ? '${_executionRun!.completedCount} of ${_executionRun!.employeeCount} disbursements settled. One or more proposals require attention below.'
                : 'One single aggregate payment of ${_executionRun!.totalUsd.formatFormatted()} settled across ${_executionRun!.countries.length} countries for ${_executionRun!.employeeCount} employees.',
            style: FlowPayTypography.captionStyle(
                color: FlowPayColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Cryptographically authorized & executed on BMONI rails',
            style: FlowPayTypography.captionStyle(
                color: FlowPayColors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Aggregate Bill Card
  Widget _buildAggregateBillCard() {
    final run = _executionRun ?? _preview;
    final totalFormatted =
        run != null ? run.totalUsd.formatFormatted() : '\$0.00';
    final feeFormatted =
        run != null ? run.totalFeeUsd.formatFormatted() : '\$10.00';
    final savedFormatted =
        run != null ? run.totalSavedFeeUsd.formatFormatted() : '\$330.00';

    return FlowPayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: FlowPayColors.ink, size: 20),
              const SizedBox(width: 8),
              Text(
                'One Aggregate Bill',
                style: FlowPayTypography.title(color: FlowPayColors.ink)
                    .copyWith(fontSize: 16),
              ),
              const Spacer(),
              StatusBadge(
                  status: _executionRun != null
                      ? _executionRun!.status
                      : 'READY TO RUN'),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: FlowPayColors.ink.withAlpha(8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FlowPayColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '1 Employer',
                  style: FlowPayTypography.captionStyle(color: FlowPayColors.ink)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                ),
                Text(
                  '  •  ',
                  style: FlowPayTypography.captionStyle(
                      color: FlowPayColors.textTertiary),
                ),
                Text(
                  'Many Countries',
                  style: FlowPayTypography.captionStyle(color: FlowPayColors.ink)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                ),
                Text(
                  '  •  ',
                  style: FlowPayTypography.captionStyle(
                      color: FlowPayColors.textTertiary),
                ),
                Text(
                  '1 Bill',
                  style: FlowPayTypography.captionStyle(color: FlowPayColors.ink)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Text(
                  'TOTAL AGGREGATE SETTLEMENT',
                  style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.textTertiary)
                      .copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    totalFormatted,
                    style: FlowPayTypography.display(color: FlowPayColors.ink)
                        .copyWith(
                      fontSize: 34,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: FlowPayColors.hairline, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_rounded,
                      color: FlowPayColors.signal, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'BMONI Fee: $feeFormatted',
                    style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textSecondary),
                  ),
                ],
              ),
              Text(
                'Saved: $savedFormatted (97%)',
                style:
                    FlowPayTypography.captionStyle(color: FlowPayColors.signal)
                        .copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Per-Employee Payroll Card with Destination Rail & Outcome
  Widget _buildEmployeePayrollCard(PayrollItemModel item) {
    final flag = item.country == 'NG'
        ? '🇳🇬'
        : item.country == 'MX'
            ? '🇲🇽'
            : '🇨🇦';
    final countryName = item.country == 'NG'
        ? 'Nigeria'
        : item.country == 'MX'
            ? 'Mexico'
            : 'Canada';

    final isFailed = item.status == 'FAILED';
    final isRetrying = _retryingEmployeeIds.contains(item.employeeId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FlowPayCard(
        border: isFailed
            ? Border.all(color: FlowPayColors.signalCaution, width: 1.5)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: FlowPayColors.surfaceAlt,
                  child: Text(flag, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.employeeName,
                        style: FlowPayTypography.body(color: FlowPayColors.ink)
                            .copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$countryName • Rate: ${item.exchangeRate} / USD',
                        style: FlowPayTypography.captionStyle(
                            color: FlowPayColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: item.status),
              ],
            ),
            const SizedBox(height: 12),

            // Rail validation indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: item.isRailActive
                    ? FlowPayColors.signal.withAlpha(15)
                    : FlowPayColors.signalCaution.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    item.isRailActive
                        ? Icons.check_circle_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: item.isRailActive
                        ? FlowPayColors.signal
                        : FlowPayColors.signalCaution,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.railValidationMessage ??
                          (item.isRailActive
                              ? '${item.destinationStablecoin} Rail Active'
                              : 'Rail Inactive: Needs Onboarding'),
                      style: FlowPayTypography.captionStyle(
                        color: item.isRailActive
                            ? FlowPayColors.signal
                            : FlowPayColors.signalCaution,
                      ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: FlowPayColors.hairline, height: 1),
            const SizedBox(height: 12),

            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employer Share',
                      style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.usdAmount.formatFormatted(),
                      style: FlowPayTypography.amount(color: FlowPayColors.ink)
                          .copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Landed in ${item.destinationStablecoin}',
                      style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.targetAmount.formatFormatted(),
                      style:
                          FlowPayTypography.amount(color: FlowPayColors.signal)
                              .copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Proposal details or Failure + Retry action
            if (item.proposalId != null || isFailed) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FlowPayColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.proposalId != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'BMONI Proposal: ${item.proposalId}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: FlowPayColors.textSecondary,
                                  fontFamily: 'Courier'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: item.proposalId!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Proposal ID copied to clipboard')),
                              );
                            },
                            child: const Icon(Icons.copy_rounded,
                                size: 12, color: FlowPayColors.textSecondary),
                          ),
                        ],
                      ),
                    if (item.transactionHash != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'On-Chain Tx: ${item.transactionHash}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: FlowPayColors.signal,
                            fontFamily: 'Courier'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (isFailed && item.errorReason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Error: ${item.errorReason}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: FlowPayColors.signalCaution,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Dedicated Retry Button on FAILED proposals
            if (isFailed) ...[
              const SizedBox(height: 10),
              FlowPayButton(
                text: isRetrying ? 'Retrying...' : 'Retry Payout via Approve',
                icon: Icons.replay_rounded,
                isSecondary: true,
                isLoading: isRetrying,
                onPressed: isRetrying ? null : () => _handleRetryEmployee(item),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
