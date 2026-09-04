import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/repositories/mission_repository.dart';
import '../../../core/state/personal_provider.dart';
import '../../../core/theme/colors.dart';

class AiAllocationModal extends StatefulWidget {
  final PersonalProvider personalProvider;
  final Money initialAmount;

  const AiAllocationModal({
    super.key,
    required this.personalProvider,
    required this.initialAmount,
  });

  @override
  State<AiAllocationModal> createState() => _AiAllocationModalState();
}

class _AiAllocationModalState extends State<AiAllocationModal> {
  late TextEditingController _amountController;
  bool _isExecuting = false;

  // Suggested allocation splits
  final double _savingsPct = 50.0;
  final double _payrollPct = 30.0;
  final double _reservePct = 20.0;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.initialAmount.majorUnits.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _currentAmount {
    return double.tryParse(_amountController.text) ?? 2000.0;
  }

  Future<void> _handleExecuteAllocation() async {
    setState(() => _isExecuting = true);

    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    // Create new autonomous allocation mission
    final newMission = MoneyMissionModel(
      id: 'm_alloc_${DateTime.now().millisecondsSinceEpoch}',
      title:
          'Smart Portfolio Allocation (${_savingsPct.toInt()}/${_payrollPct.toInt()}/${_reservePct.toInt()})',
      tagline:
          'Auto-allocates \$$_currentAmount: ${_savingsPct.toInt()}% NGN Savings, ${_payrollPct.toInt()}% Payroll, ${_reservePct.toInt()}% Reserve',
      ruleType: MissionRuleType.autoSweep,
      isActive: true,
      stats: 'Active autonomous strategy',
      conditionSummary: 'Incoming wires >= \$$_currentAmount',
      actionSummary: 'Distribute across savings and operational vaults',
      targetCurrency: Currency.ngn,
      percentage: _savingsPct,
    );

    await widget.personalProvider.missionRepo.createMission(newMission);
    await widget.personalProvider.refresh();

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Allocation mission activated! Auto-allocating \$$_currentAmount.'),
        backgroundColor: BMoniColors.brand500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _currentAmount;
    final savingsAmt = total * (_savingsPct / 100);
    final payrollAmt = total * (_payrollPct / 100);
    final reserveAmt = total * (_reservePct / 100);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? FlowPayColors.darkSurfaceElevated
              : FlowPayColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BMoniColors.brand500.withAlpha(35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pie_chart_outline,
                    color: BMoniColors.brand400, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Capital Allocation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : BMoniColors.grey950,
                    ),
                  ),
                  const Text(
                    'Task Workflow: Autonomous Split & Sweep',
                    style: TextStyle(
                        fontSize: 12,
                        color: BMoniColors.brand400,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Amount to Allocate
          const Text('Amount to Allocate',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BMoniColors.grey400)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? FlowPayColors.darkSurface
                  : FlowPayColors.lightSurfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FlowPayColors.darkBorder),
            ),
            child: Row(
              children: [
                const Text('\$',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BMoniColors.brand500.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('USDB',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: BMoniColors.brand400)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const Text('Recommended Distribution',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BMoniColors.grey400)),
          const SizedBox(height: 10),

          // Distribution breakdown cards
          _DistributionRow(
            label: 'High-Yield NGN Savings (${_savingsPct.toInt()}%)',
            sublabel:
                'Auto-convert to CNGN @ 1550 = ₦${(savingsAmt * 1550).round()}',
            amount: '\$${savingsAmt.toStringAsFixed(2)}',
            color: BMoniColors.success400,
            icon: Icons.savings_outlined,
          ),
          const SizedBox(height: 8),
          _DistributionRow(
            label: 'Contractor Payroll Pool (${_payrollPct.toInt()}%)',
            sublabel: 'Reserved for remote disbursements (Nigeria, Mexico)',
            amount: '\$${payrollAmt.toStringAsFixed(2)}',
            color: BMoniColors.accent400,
            icon: Icons.groups_outlined,
          ),
          const SizedBox(height: 8),
          _DistributionRow(
            label: 'Emergency Reserve (${_reservePct.toInt()}%)',
            sublabel: 'Secure USDB hardware buffer',
            amount: '\$${reserveAmt.toStringAsFixed(2)}',
            color: BMoniColors.brand400,
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: 20),

          BMoniButton(
            text: 'Activate Allocation Rule',
            variant: BMoniButtonVariant.primary,
            size: BMoniButtonSize.large,
            isLoading: _isExecuting,
            onPressed: _handleExecuteAllocation,
          ),
        ],
      ),
    ),
  ),
);
  }
}

class _DistributionRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final String amount;
  final Color color;
  final IconData icon;

  const _DistributionRow({
    required this.label,
    required this.sublabel,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FlowPayColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlowPayColors.darkBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(sublabel,
                    style: const TextStyle(
                        fontSize: 11, color: BMoniColors.grey400)),
              ],
            ),
          ),
          Text(amount,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ],
      ),
    );
  }
}
