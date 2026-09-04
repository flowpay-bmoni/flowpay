import 'package:flutter/material.dart';
import '../../core/design_system/design_system.dart';
import '../../core/repositories/employee_repository.dart';
import '../../core/state/app_state.dart';
import 'components/add_employee_modal.dart';
import 'employee_detail_screen.dart';

/// Global Team Screen
/// Conforms to FlowPay Design System & bkey_uikit specifications:
/// - Full employee rows with: Name, Flag, Payroll Currency & Amount, Onboarding Stage, Wallet & Card badges
/// - Shared FlowPay empty state when there are no employees
/// - Pull-to-refresh & instant detail navigation
class EmployeesScreen extends StatefulWidget {
  final AppState appState;

  const EmployeesScreen({super.key, required this.appState});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<EmployeeModel> employees = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    final emps = await widget.appState.employeeRepo.getEmployees();
    if (mounted) {
      setState(() {
        employees = emps;
        isLoading = false;
      });
    }
  }

  void _showAddEmployeeDialog() async {
    await AddEmployeeModal.show(context, widget.appState.businessProvider);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Global Team',
          style: FlowPayTypography.title(color: FlowPayColors.ink)
              .copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.person_add_rounded, color: FlowPayColors.ink),
            tooltip: 'Add Employee',
            onPressed: _showAddEmployeeDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: FlowPayColors.ink))
          : employees.isEmpty
              ? FlowPayEmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No employees yet',
                  description:
                      'Add remote team members across Nigeria and Mexico to automate multi-rail payroll and virtual cards.',
                  actionText: 'Add Employee',
                  onAction: _showAddEmployeeDialog,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: FlowPayColors.ink,
                  backgroundColor: FlowPayColors.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: employees.length,
                    itemBuilder: (ctx, i) {
                      final emp = employees[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EmployeeRowCard(
                          employee: emp,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EmployeeDetailScreen(
                                  appState: widget.appState,
                                  employee: emp,
                                ),
                              ),
                            ).then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmployeeRowCard extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback onTap;

  const _EmployeeRowCard({
    required this.employee,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formattedPayroll = employee.payrollAmount != null
        ? employee.payrollAmount!.formatFormatted()
        : '${employee.targetCurrency.symbol}2,000.00';

    return FlowPayCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Flag, Name, Email, Country
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: FlowPayColors.surfaceAlt,
                child: Text(
                  employee.flagEmoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: FlowPayTypography.body(color: FlowPayColors.ink)
                          .copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      employee.email,
                      style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Onboarding Lifecycle Stage Badge
              FlowPayStatusBadge(status: employee.status),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: FlowPayColors.hairline, height: 1),
          const SizedBox(height: 10),

          // Row 2: Payroll Amount & Status Badges (Wallet & Card)
          Row(
            children: [
              // Payroll Currency & Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PAYROLL (${employee.targetCurrency.code})',
                    style: FlowPayTypography.captionStyle(
                            color: FlowPayColors.textTertiary)
                        .copyWith(
                      fontSize: 10,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formattedPayroll,
                    style: FlowPayTypography.body(color: FlowPayColors.ink)
                        .copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Wallet Status Badge
              _MiniBadge(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet: ${employee.walletStatus}',
                isActive: employee.walletStatus.toUpperCase() == 'ACTIVE' ||
                    employee.walletStatus.toUpperCase() == 'PROVISIONED',
              ),
              const SizedBox(width: 6),

              // Card Status Badge
              _MiniBadge(
                icon: Icons.credit_card_rounded,
                label: 'Card: ${employee.cardStatus}',
                isActive: employee.cardStatus.toUpperCase() == 'ACTIVE' ||
                    employee.cardStatus.toUpperCase() == 'ISSUED',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;

  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? FlowPayColors.surfaceAlt : Colors.black12,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FlowPayColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: isActive ? FlowPayColors.signal : FlowPayColors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isActive ? FlowPayColors.ink : FlowPayColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
