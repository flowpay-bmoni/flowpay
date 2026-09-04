import 'package:flutter/material.dart';
import '../../../core/state/business_provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/typography.dart';

/// Business Metrics Grid
/// Conforms to design.md §3.1, §3.2, §3.4 & §3.5:
/// Displays all 6 employer metrics in 20dp cards with hairline borders,
/// pill badges, and tabular figures for numbers.
class BusinessMetricsGrid extends StatelessWidget {
  final BusinessProvider businessProvider;

  const BusinessMetricsGrid({super.key, required this.businessProvider});

  @override
  Widget build(BuildContext context) {
    final totalUsd = businessProvider.totalPayrollUsd;
    final pendingUsd = businessProvider.pendingPayrollUsd;
    final employeeCount = businessProvider.employeeCount;
    final onboardedCount = businessProvider.onboardedEmployeeCount;
    final walletsCount = businessProvider.walletsProvisionedCount;
    final cardsCount = businessProvider.cardsActiveCount;

    return Column(
      children: [
        // Metric Row 1: Total Payroll & Pending Payroll
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.payments_outlined,
                iconColor: FlowPayColors.ink,
                label: 'TOTAL PAYROLL',
                value: totalUsd.formatFormatted(),
                subtitle: 'Monthly aggregate run',
                badgeText: 'USD BASE',
                badgeBg: FlowPayColors.surfaceAlt,
                badgeFg: FlowPayColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.hourglass_top_outlined,
                iconColor: const Color(0xFFB45309),
                label: 'PENDING PAYROLL',
                value: pendingUsd.formatFormatted(),
                subtitle: 'Ready to disburse',
                badgeText: 'SCHEDULED',
                badgeBg: FlowPayColors.amber.withValues(alpha: 0.16),
                badgeFg: const Color(0xFFB45309),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Metric Row 2: Employee Count & Employee Status
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.people_outline_rounded,
                iconColor: FlowPayColors.ink,
                label: 'EMPLOYEE COUNT',
                value: '$employeeCount Members',
                subtitle: 'Global remote team',
                badgeText: 'TEAM',
                badgeBg: FlowPayColors.surfaceAlt,
                badgeFg: FlowPayColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.verified_user_outlined,
                iconColor: FlowPayColors.signal,
                label: 'EMPLOYEE STATUS',
                value: '$onboardedCount / $employeeCount Onboarded',
                subtitle: '100% KYC verified',
                badgeText: 'ACTIVE',
                badgeBg: FlowPayColors.signal.withValues(alpha: 0.12),
                badgeFg: FlowPayColors.signal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Metric Row 3: Countries & Wallet/Card Status
        Row(
          children: [
            const Expanded(
              child: _MetricCard(
                icon: Icons.public_rounded,
                iconColor: FlowPayColors.ink,
                label: 'COUNTRIES',
                value: '3 Rails',
                subtitle: '🇳🇬 NG • 🇲🇽 MX • 🇨🇦 CA',
                badgeText: 'MULTI-RAIL',
                badgeBg: FlowPayColors.surfaceAlt,
                badgeFg: FlowPayColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.credit_card_outlined,
                iconColor: FlowPayColors.signal,
                label: 'WALLET / CARD STATUS',
                value: '$walletsCount Wallets • $cardsCount Cards',
                subtitle: 'Hardware-secured & active',
                badgeText: 'LIVE',
                badgeBg: FlowPayColors.signal.withValues(alpha: 0.12),
                badgeFg: FlowPayColors.signal,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
  final String badgeText;
  final Color badgeBg;
  final Color badgeFg;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeFg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlowPayColors.surface,
        borderRadius: FlowPayRadii.card,
        border: Border.all(color: FlowPayColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: FlowPayRadii.chip,
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textTertiary)
                .copyWith(
              fontSize: 11,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: FlowPayTypography.amount(color: FlowPayColors.ink).copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textSecondary)
                .copyWith(
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
