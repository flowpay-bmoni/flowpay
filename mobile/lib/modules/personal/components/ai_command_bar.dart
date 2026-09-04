import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

/// FlowPay Primary AI Interaction
/// "What should your money do?"
///
/// Directives:
/// 1. This is NOT a chatbot.
/// 2. It is an entry point into task-specific financial workflows.
/// 3. Provides 3 instant task suggestions:
///    - "Allocate my $2,000"
///    - "Send $500 to my designer"
///    - "Convert $1,000 to Naira"
class AiCommandBar extends StatefulWidget {
  final ValueChanged<String> onCommandSubmit;
  final VoidCallback onAllocateTap;
  final VoidCallback onSendMoneyTap;
  final VoidCallback onConvertTap;

  const AiCommandBar({
    super.key,
    required this.onCommandSubmit,
    required this.onAllocateTap,
    required this.onSendMoneyTap,
    required this.onConvertTap,
  });

  @override
  State<AiCommandBar> createState() => _AiCommandBarState();
}

class _AiCommandBarState extends State<AiCommandBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onCommandSubmit(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? FlowPayColors.darkSurface : FlowPayColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: FlowPayColors.primary.withAlpha(80),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: FlowPayColors.primary.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FlowPayColors.primary.withAlpha(35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: FlowPayColors.primaryLight,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What should your money do?',
                      style: FlowPayTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? FlowPayColors.darkTextPrimary
                            : FlowPayColors.lightTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Task-specific autonomous execution • Strictly PIN-signed',
                      style: FlowPayTypography.caption.copyWith(
                        color: FlowPayColors.primaryLight,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Command Input Field with Action Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? FlowPayColors.darkSurfaceElevated
                  : FlowPayColors.lightSurfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: FlowPayColors.darkBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _handleSubmit(),
                    style: TextStyle(
                      color: isDark
                          ? FlowPayColors.darkTextPrimary
                          : FlowPayColors.lightTextPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'e.g. "Send \$150 to Samson" or "Sweep 20% to savings"',
                      hintStyle: TextStyle(
                        color: isDark
                            ? FlowPayColors.darkTextTertiary
                            : FlowPayColors.lightTextTertiary,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _handleSubmit,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: FlowPayColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Task-specific quick suggestions
          Text(
            'QUICK FINANCIAL ACTIONS',
            style: FlowPayTypography.caption.copyWith(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? FlowPayColors.darkTextTertiary
                  : FlowPayColors.lightTextTertiary,
            ),
          ),
          const SizedBox(height: 8),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SuggestionChip(
                  icon: Icons.pie_chart_outline,
                  label: 'Allocate my \$2,000',
                  accentColor: BMoniColors.brand400,
                  onTap: widget.onAllocateTap,
                ),
                const SizedBox(width: 8),
                _SuggestionChip(
                  icon: Icons.send_outlined,
                  label: 'Send \$500 to my designer',
                  accentColor: BMoniColors.accent400,
                  onTap: widget.onSendMoneyTap,
                ),
                const SizedBox(width: 8),
                _SuggestionChip(
                  icon: Icons.currency_exchange,
                  label: 'Convert \$1,000 to Naira',
                  accentColor: BMoniColors.success400,
                  onTap: widget.onConvertTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withAlpha(70)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? FlowPayColors.darkTextPrimary
                    : FlowPayColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
