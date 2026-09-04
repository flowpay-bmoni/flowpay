import 'package:flutter/material.dart';
import '../../../core/state/business_provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/typography.dart';

/// Hero Bill Card
/// Conforms strictly to design.md §3.1, §3.4, §3.5 & §4.4:
/// - 20dp card radius
/// - Surface #FFFFFF with hairline #E6E4DE border, zero drop shadows
/// - Headline: "One Employer. Many Countries. One Bill."
/// - Tabular figures on aggregate numbers
/// - Signal green savings badge
class HeroBillCard extends StatelessWidget {
  final BusinessProvider businessProvider;
  final VoidCallback onRunPayroll;

  const HeroBillCard({
    super.key,
    required this.businessProvider,
    required this.onRunPayroll,
  });

  @override
  Widget build(BuildContext context) {
    final pending = businessProvider.pendingPayroll;
    final totalUsd = businessProvider.totalPayrollUsd;
    final savedUsd = businessProvider.savedFeeUsd;
    final savedPct = businessProvider.savedPercentage.toStringAsFixed(0);

    return Container(
      decoration: BoxDecoration(
        color: FlowPayColors.surface,
        borderRadius: FlowPayRadii.card,
        border: Border.all(color: FlowPayColors.hairline, width: 1),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Core Message Hook Banner
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: const BoxDecoration(
                  color: FlowPayColors.surfaceAlt,
                  borderRadius: FlowPayRadii.avatar,
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: FlowPayColors.ink,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One Employer. Many Countries. One Bill.',
                      style: FlowPayTypography.title(color: FlowPayColors.ink)
                          .copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Disburse international payroll to Nigeria (CNGN) & Mexico (MEXe) in parallel with instant virtual cards — settled in one single aggregate USD bill.',
                      style: FlowPayTypography.captionStyle(
                              color: FlowPayColors.textSecondary)
                          .copyWith(
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3 Core Pillars: One Employer • Many Countries • One Bill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FlowPayColors.surfaceAlt,
              borderRadius: FlowPayRadii.chip,
              border: Border.all(color: FlowPayColors.hairline),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.business_rounded, size: 14, color: FlowPayColors.primary),
                    SizedBox(width: 5),
                    Text(
                      '1 Employer',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: FlowPayColors.ink,
                      ),
                    ),
                  ],
                ),
                Text('•', style: TextStyle(color: FlowPayColors.textTertiary)),
                Row(
                  children: [
                    Icon(Icons.public_rounded, size: 14, color: FlowPayColors.accent),
                    SizedBox(width: 5),
                    Text(
                      'Many Countries',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: FlowPayColors.ink,
                      ),
                    ),
                  ],
                ),
                Text('•', style: TextStyle(color: FlowPayColors.textTertiary)),
                Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 14, color: FlowPayColors.signal),
                    SizedBox(width: 5),
                    Text(
                      '1 Bill',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: FlowPayColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: FlowPayColors.hairline, height: 1),
          const SizedBox(height: 16),

          // Total Aggregate Bill Figure
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL AGGREGATE PAYROLL',
                      style: FlowPayTypography.captionStyle(
                              color: FlowPayColors.textTertiary)
                          .copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalUsd.formatFormatted(),
                      style: FlowPayTypography.display(color: FlowPayColors.ink)
                          .copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: FlowPayColors.signal.withValues(alpha: 0.12),
                  borderRadius: FlowPayRadii.chip,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_downward_rounded,
                        color: FlowPayColors.signal, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Saved ${savedUsd.formatFormatted()} ($savedPct%)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: FlowPayColors.signal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sub-metrics (Rail fee vs Wire)
          Row(
            children: [
              Text(
                'BMONI Rail Fee: ${pending?.totalFeeUsd.formatFormatted() ?? "\$10.00"}',
                style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textSecondary),
              ),
              const Spacer(),
              Text(
                'Traditional Wire: ~\$340.00',
                style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textTertiary)
                    .copyWith(
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
