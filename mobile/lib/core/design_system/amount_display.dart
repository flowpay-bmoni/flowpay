import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';
import 'status_badges.dart';

enum AmountDisplaySize { large, medium, small, micro }

class FlowPayAmountDisplay extends StatelessWidget {
  final String amount;
  final String? currencySymbol;
  final String? currencyCode;
  final AmountDisplaySize size;
  final String? secondaryAmount;
  final Color? color;
  final bool isCredit;
  final bool isDebit;
  final String? statusLabel;
  final FlowPayAppStatus? status;

  const FlowPayAmountDisplay({
    super.key,
    required this.amount,
    this.currencySymbol = '\$',
    this.currencyCode,
    this.size = AmountDisplaySize.medium,
    this.secondaryAmount,
    this.color,
    this.isCredit = false,
    this.isDebit = false,
    this.statusLabel,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color fg;
    if (color != null) {
      fg = color!;
    } else if (isCredit) {
      fg = FlowPayColors.accent;
    } else if (isDebit) {
      fg = isDark
          ? FlowPayColors.darkTextPrimary
          : FlowPayColors.lightTextPrimary;
    } else {
      fg = isDark
          ? FlowPayColors.darkTextPrimary
          : FlowPayColors.lightTextPrimary;
    }

    TextStyle mainStyle;
    double symbolSize;

    switch (size) {
      case AmountDisplaySize.large:
        mainStyle = FlowPayTypography.financialLarge;
        symbolSize = 24;
        break;
      case AmountDisplaySize.medium:
        mainStyle = FlowPayTypography.financialMedium;
        symbolSize = 18;
        break;
      case AmountDisplaySize.small:
        mainStyle = FlowPayTypography.financialSmall;
        symbolSize = 15;
        break;
      case AmountDisplaySize.micro:
        mainStyle = FlowPayTypography.financialMicro;
        symbolSize = 13;
        break;
    }

    final sign = isCredit ? '+' : (isDebit ? '-' : '');

    // Format amount into integer and decimal parts while preserving/adding commas
    String cleanAmount = amount.replaceAll(RegExp(r'[^0-9.,]'), '');
    String intPart = cleanAmount;
    String decPart = '';
    if (cleanAmount.contains('.')) {
      final parts = cleanAmount.split('.');
      intPart = parts[0];
      decPart = '.${parts[1]}';
    }

    // If intPart lacks commas and is more than 3 digits, insert thousands separators
    if (!intPart.contains(',')) {
      intPart = intPart.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (sign.isNotEmpty)
              Text(
                sign,
                style: mainStyle.copyWith(color: fg),
              ),
            if (currencySymbol != null)
              Text(
                currencySymbol!,
                style: TextStyle(
                  fontSize: symbolSize,
                  fontWeight: FontWeight.w600,
                  color: fg.withAlpha(210),
                ),
              ),
            Text(
              intPart.isEmpty ? '0' : intPart,
              style: mainStyle.copyWith(
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (decPart.isNotEmpty)
              Text(
                decPart,
                style: TextStyle(
                  fontSize: symbolSize,
                  fontWeight: FontWeight.w600,
                  color: fg.withAlpha(180),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            if (currencyCode != null) ...[
              const SizedBox(width: 5),
              Text(
                currencyCode!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark
                      ? FlowPayColors.darkTextTertiary
                      : FlowPayColors.lightTextTertiary,
                ),
              ),
            ],
            if (status != null || statusLabel != null) ...[
              const SizedBox(width: 8),
              if (status != null)
                FlowPayStatusBadge(appStatus: status)
              else
                FlowPayBadge(label: statusLabel!, color: FlowPayColors.accent),
            ],
          ],
        ),
        if (secondaryAmount != null) ...[
          const SizedBox(height: 3),
          Text(
            secondaryAmount!,
            style: FlowPayTypography.caption.copyWith(
              color: isDark
                  ? FlowPayColors.darkTextSecondary
                  : FlowPayColors.lightTextSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}
