import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

class FlowPayCurrencyDisplay extends StatelessWidget {
  final String code;
  final String symbol;
  final String name;
  final String? tokenName;
  final bool isCompact;

  const FlowPayCurrencyDisplay({
    super.key,
    required this.code,
    required this.symbol,
    required this.name,
    this.tokenName,
    this.isCompact = false,
  });

  Color _getBadgeColor() {
    switch (code.toUpperCase()) {
      case 'USD':
        return FlowPayColors.usdBadge;
      case 'NGN':
        return FlowPayColors.ngnBadge;
      case 'MXN':
        return FlowPayColors.mxnBadge;
      default:
        return FlowPayColors.primary.withAlpha(50);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getBadgeColor(),
          borderRadius: FlowPaySpacing.borderRadiusSm,
          border: Border.all(
            color: isDark
                ? FlowPayColors.darkBorderLight
                : FlowPayColors.lightBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              symbol,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              code,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: _getBadgeColor(),
          child: Text(
            symbol,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: FlowPaySpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: FlowPayTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? FlowPayColors.darkTextPrimary
                      : FlowPayColors.lightTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tokenName != null)
                Text(
                  tokenName!,
                  style: FlowPayTypography.caption.copyWith(
                    color: isDark
                        ? FlowPayColors.darkTextTertiary
                        : FlowPayColors.lightTextTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
