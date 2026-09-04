import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';

enum FlowPayAppStatus {
  loading,
  success,
  error,
  empty,
  available,
  pending,
  awaitingApproval,
  processing,
  completed,
  failed,
  cancelled,
}

extension FlowPayAppStatusX on FlowPayAppStatus {
  String get label {
    switch (this) {
      case FlowPayAppStatus.loading:
        return 'Loading';
      case FlowPayAppStatus.success:
        return 'Success';
      case FlowPayAppStatus.error:
        return 'Error';
      case FlowPayAppStatus.empty:
        return 'Empty';
      case FlowPayAppStatus.available:
        return 'Available';
      case FlowPayAppStatus.pending:
        return 'Pending';
      case FlowPayAppStatus.awaitingApproval:
        return 'Awaiting Approval';
      case FlowPayAppStatus.processing:
        return 'Processing';
      case FlowPayAppStatus.completed:
        return 'Completed';
      case FlowPayAppStatus.failed:
        return 'Failed';
      case FlowPayAppStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case FlowPayAppStatus.loading:
      case FlowPayAppStatus.processing:
        return FlowPayColors.info;
      case FlowPayAppStatus.success:
      case FlowPayAppStatus.completed:
      case FlowPayAppStatus.available:
        return FlowPayColors.accent;
      case FlowPayAppStatus.pending:
      case FlowPayAppStatus.awaitingApproval:
        return FlowPayColors.warning;
      case FlowPayAppStatus.error:
      case FlowPayAppStatus.failed:
        return FlowPayColors.error;
      case FlowPayAppStatus.cancelled:
      case FlowPayAppStatus.empty:
        return FlowPayColors.darkTextTertiary;
    }
  }

  IconData get icon {
    switch (this) {
      case FlowPayAppStatus.loading:
        return Icons.hourglass_top_rounded;
      case FlowPayAppStatus.processing:
        return Icons.sync_rounded;
      case FlowPayAppStatus.success:
      case FlowPayAppStatus.completed:
        return Icons.check_circle_rounded;
      case FlowPayAppStatus.available:
        return Icons.account_balance_wallet_outlined;
      case FlowPayAppStatus.pending:
      case FlowPayAppStatus.awaitingApproval:
        return Icons.schedule_rounded;
      case FlowPayAppStatus.error:
      case FlowPayAppStatus.failed:
        return Icons.error_outline_rounded;
      case FlowPayAppStatus.cancelled:
      case FlowPayAppStatus.empty:
        return Icons.block_rounded;
    }
  }
}

class FlowPayBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool showDot;
  final IconData? icon;

  const FlowPayBadge({
    super.key,
    required this.label,
    this.color = FlowPayColors.primary,
    this.showDot = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: FlowPaySpacing.borderRadiusSm,
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ] else if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class FlowPayStatusBadge extends StatelessWidget {
  final FlowPayAppStatus? appStatus;
  final String? status;
  final bool showDot;
  final IconData? icon;

  const FlowPayStatusBadge({
    super.key,
    this.appStatus,
    this.status,
    this.showDot = true,
    this.icon,
  }) : assert(appStatus != null || status != null,
            'Provide either appStatus or status');

  @override
  Widget build(BuildContext context) {
    if (appStatus != null) {
      return FlowPayBadge(
        label: appStatus!.label,
        color: appStatus!.color,
        icon: icon ?? appStatus!.icon,
        showDot: showDot,
      );
    }

    final s = status!.toUpperCase();
    Color color;
    IconData resolvedIcon;

    switch (s) {
      case 'AVAILABLE':
        color = FlowPayColors.accent;
        resolvedIcon = Icons.account_balance_wallet_outlined;
        break;
      case 'ACTIVE':
      case 'LINKED':
      case 'SUCCESS':
      case 'COMPLETED':
      case 'PAID':
      case 'READY':
        color = FlowPayColors.accent;
        resolvedIcon = Icons.check_circle_rounded;
        break;
      case 'PENDING':
      case 'INVITED':
      case 'AWAITING_APPROVAL':
      case 'WALLET_PENDING':
      case 'KYC_PENDING':
      case 'SCHEDULED':
      case 'READY TO RUN':
        color = FlowPayColors.warning;
        resolvedIcon = Icons.schedule_rounded;
        break;
      case 'PROCESSING':
      case 'ONBOARDING':
      case 'EXECUTING':
      case 'LIVE':
        color = FlowPayColors.info;
        resolvedIcon = Icons.sync_rounded;
        break;
      case 'FROZEN':
      case 'SUSPENDED':
      case 'FAILED':
      case 'REJECTED':
      case 'PARTIALLY_COMPLETED':
        color = FlowPayColors.error;
        resolvedIcon = Icons.error_outline_rounded;
        break;
      case 'CANCELLED':
      case 'BLOCKED':
        color = FlowPayColors.darkTextTertiary;
        resolvedIcon = Icons.block_rounded;
        break;
      case 'SELF-CUSTODY (B-KEY)':
      case 'SECURE':
      case 'HARDWARE SECURED':
        color = FlowPayColors.primaryLight;
        resolvedIcon = Icons.lock_outline_rounded;
        break;
      case 'CREATED':
        color = FlowPayColors.info;
        resolvedIcon = Icons.add_circle_outline_rounded;
        break;
      default:
        color = FlowPayColors.darkTextSecondary;
        resolvedIcon = Icons.info_outline_rounded;
    }

    return FlowPayBadge(
      label: status!,
      color: color,
      icon: icon ?? resolvedIcon,
      showDot: showDot,
    );
  }
}

// Alias for backward compatibility
typedef StatusBadge = FlowPayStatusBadge;
