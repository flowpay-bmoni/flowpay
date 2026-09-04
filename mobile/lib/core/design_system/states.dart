import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'buttons.dart';
import 'status_badges.dart';

export 'status_badges.dart' show FlowPayAppStatus, FlowPayAppStatusX;

/// Reusable Loading State Widget
class FlowPayLoadingState extends StatelessWidget {
  final String? message;
  final double size;

  const FlowPayLoadingState({
    super.key,
    this.message,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: FlowPaySpacing.insetXxl,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: FlowPayColors.primary,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: FlowPaySpacing.lg),
              Text(
                message!,
                style: FlowPayTypography.bodyMd.copyWith(
                  color: isDark
                      ? FlowPayColors.darkTextSecondary
                      : FlowPayColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable Error State Widget
class FlowPayErrorState extends StatelessWidget {
  final String title;
  final String message;
  final String? retryText;
  final VoidCallback? onRetry;
  final IconData icon;

  const FlowPayErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.retryText = 'Try Again',
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: FlowPaySpacing.insetXxl,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowPayColors.error.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: FlowPayColors.error),
            ),
            const SizedBox(height: FlowPaySpacing.lg),
            Text(
              title,
              style: FlowPayTypography.headingSm.copyWith(
                color: isDark
                    ? FlowPayColors.darkTextPrimary
                    : FlowPayColors.lightTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FlowPaySpacing.xs),
            Text(
              message,
              style: FlowPayTypography.bodyMd.copyWith(
                color: isDark
                    ? FlowPayColors.darkTextSecondary
                    : FlowPayColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null && retryText != null) ...[
              const SizedBox(height: FlowPaySpacing.xl),
              FlowPayButton(
                text: retryText!,
                icon: Icons.refresh,
                variant: FlowPayButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable Empty State Widget
class FlowPayEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionText;
  final VoidCallback? onAction;

  const FlowPayEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: FlowPaySpacing.insetXxl,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark
                    ? FlowPayColors.darkSurfaceElevated
                    : FlowPayColors.lightSurfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? FlowPayColors.darkBorder
                      : FlowPayColors.lightBorder,
                ),
              ),
              child: Icon(
                icon,
                size: 36,
                color: isDark
                    ? FlowPayColors.darkTextTertiary
                    : FlowPayColors.lightTextTertiary,
              ),
            ),
            const SizedBox(height: FlowPaySpacing.lg),
            Text(
              title,
              style: FlowPayTypography.headingSm.copyWith(
                color: isDark
                    ? FlowPayColors.darkTextPrimary
                    : FlowPayColors.lightTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FlowPaySpacing.xs),
            Text(
              description,
              style: FlowPayTypography.bodyMd.copyWith(
                color: isDark
                    ? FlowPayColors.darkTextSecondary
                    : FlowPayColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: FlowPaySpacing.xl),
              FlowPayButton(
                text: actionText!,
                onPressed: onAction!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Universal State View Renderer
/// Handles all 9 shared states seamlessly without code duplication across modules.
class FlowPayStateView extends StatelessWidget {
  final FlowPayAppStatus status;
  final Widget content;
  final String? loadingMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String? emptyTitle;
  final String? emptyMessage;
  final IconData? emptyIcon;
  final String? emptyActionText;
  final VoidCallback? onEmptyAction;

  const FlowPayStateView({
    super.key,
    required this.status,
    required this.content,
    this.loadingMessage,
    this.errorMessage,
    this.onRetry,
    this.emptyTitle,
    this.emptyMessage,
    this.emptyIcon,
    this.emptyActionText,
    this.onEmptyAction,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case FlowPayAppStatus.loading:
      case FlowPayAppStatus.processing:
        return FlowPayLoadingState(
          message: loadingMessage ??
              (status == FlowPayAppStatus.processing
                  ? 'Processing on-chain...'
                  : 'Loading...'),
        );
      case FlowPayAppStatus.error:
      case FlowPayAppStatus.failed:
        return FlowPayErrorState(
          title: status == FlowPayAppStatus.failed ? 'Action Failed' : 'Error',
          message: errorMessage ?? 'An error occurred during operation.',
          onRetry: onRetry,
        );
      case FlowPayAppStatus.empty:
        return FlowPayEmptyState(
          icon: emptyIcon ?? Icons.inbox_outlined,
          title: emptyTitle ?? 'No data found',
          description: emptyMessage ?? 'Items will appear here once available.',
          actionText: emptyActionText,
          onAction: onEmptyAction,
        );
      case FlowPayAppStatus.success:
      case FlowPayAppStatus.completed:
      case FlowPayAppStatus.available:
      case FlowPayAppStatus.pending:
      case FlowPayAppStatus.awaitingApproval:
      case FlowPayAppStatus.cancelled:
        return content;
    }
  }
}
