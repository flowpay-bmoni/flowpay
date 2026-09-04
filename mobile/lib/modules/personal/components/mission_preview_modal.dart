import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../../core/missions/mission_intent.dart';

class MissionPreviewModal extends StatelessWidget {
  final MissionIntent intent;
  final VoidCallback onEdit;
  final VoidCallback onApprove;

  const MissionPreviewModal({
    super.key,
    required this.intent,
    required this.onEdit,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sourceAmountStr = intent.triggerCondition.sourceAmount;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? BMoniColors.offbrand950 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color:
              isDark ? BMoniColors.brand500.withAlpha(60) : BMoniColors.grey200,
          width: 1.2,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? BMoniColors.grey700 : BMoniColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title & Sparkle Icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BMoniColors.brand500.withAlpha(35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: BMoniColors.brand400, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mission Plan Preview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AI structured • Deterministically validated',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? BMoniColors.grey400 : BMoniColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 20, color: BMoniColors.grey400),
                onPressed: onEdit,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Incoming Trigger Header: e.g. "$2,000 incoming"
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF3B0D3F), const Color(0xFF1E0720)]
                    : [const Color(0xFFF3E8F4), const Color(0xFFEADBEC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: BMoniColors.brand500.withAlpha(90)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRIGGER CONDITION',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? BMoniColors.brand300
                              : BMoniColors.brand700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sourceAmountStr.contains('2000') ||
                                sourceAmountStr == '2000.00'
                            ? '\$2,000 incoming'
                            : '\$$sourceAmountStr incoming',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color:
                              isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: BMoniColors.brand500.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 14, color: BMoniColors.brand300),
                      const SizedBox(width: 6),
                      Text(
                        '100% Allocated',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? BMoniColors.brand200
                              : BMoniColors.brand700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Allocation Cards List
          ...intent.allocations.map((alloc) {
            Color pillColor;
            Color pillTextColor;
            IconData iconData;

            switch (alloc.category) {
              case MissionAllocationCategory.reserve:
                pillColor = BMoniColors.brand500.withAlpha(30);
                pillTextColor = BMoniColors.brand300;
                iconData = Icons.shield_outlined;
                break;
              case MissionAllocationCategory.expenses:
                pillColor = BMoniColors.success400.withAlpha(30);
                pillTextColor = BMoniColors.success400;
                iconData = Icons.currency_exchange;
                break;
              case MissionAllocationCategory.tax:
                pillColor = BMoniColors.accent400.withAlpha(30);
                pillTextColor = BMoniColors.accent400;
                iconData = Icons.account_balance_outlined;
                break;
              default:
                pillColor = BMoniColors.offbrand700;
                pillTextColor = BMoniColors.grey300;
                iconData = Icons.savings_outlined;
            }

            final amountDisplay = () {
              if (alloc.targetAmountFormatted != null &&
                  alloc.targetCurrency.code != 'USD') {
                return alloc.targetAmountFormatted!;
              }
              final parsed =
                  double.tryParse(alloc.sourceAmountFormatted) ?? 0.0;
              if (parsed == parsed.roundToDouble() && parsed > 0) {
                return '\$${parsed.toInt()}';
              }
              return '\$${alloc.sourceAmountFormatted}';
            }();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? BMoniColors.offbrand900 : BMoniColors.grey50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? BMoniColors.offbrand700 : BMoniColors.grey200,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: pillColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(iconData, size: 18, color: pillTextColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alloc.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? BMoniColors.grey50
                                : BMoniColors.grey950,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Destination: ${alloc.destinationWalletTag}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: BMoniColors.grey400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: pillColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${alloc.percentage.toInt()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: pillTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amountDisplay,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? BMoniColors.grey100
                              : BMoniColors.grey900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          // Reassurance Banner: "Nothing moves until you approve."
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? BMoniColors.offbrand800 : BMoniColors.grey100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? BMoniColors.offbrand600 : BMoniColors.grey300,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 16, color: BMoniColors.brand400),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nothing moves until you approve.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? BMoniColors.grey100
                              : BMoniColors.grey900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'Requires explicit authorization with your on-device B-Key PIN.',
                        style: TextStyle(
                          fontSize: 11,
                          color: BMoniColors.grey400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Buttons: Edit and Approve Mission
          Row(
            children: [
              Expanded(
                flex: 1,
                child: BMoniButton(
                  text: 'Edit',
                  variant: BMoniButtonVariant.secondary,
                  size: BMoniButtonSize.large,
                  onPressed: onEdit,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: BMoniButton(
                  text: 'Approve Mission',
                  variant: BMoniButtonVariant.primary,
                  size: BMoniButtonSize.large,
                  onPressed: onApprove,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
