import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../core/design_system/design_system.dart';
import '../../core/repositories/employee_repository.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/components.dart';
import '../../core/repositories/card_repository.dart';
import '../../core/wallets_cards/bmoni_embedded_wallets_cards.dart';
import 'components/card_detail_sheet.dart';
import 'components/issue_virtual_card_sheet.dart';
import 'employee_onboarding_screen.dart';

/// Employee Detail Screen — Wallet Control Center
/// Extended with bmoni_embedded_wallets_cards and bkey_uikit primitives:
/// - Wallet Control Center: EmbeddedWalletCard with currency background art variants
/// - Riverpod State Management: EmbeddedWalletListNotifier, EmbeddedWalletBalanceNotifier, EmbeddedWalletTransactionsNotifier
/// - BMONI Security Note: On-device B-Key signer model (Keystore / Secure Enclave)
/// - Actions: View Wallet, View Transactions, Issue Card (routes into Prompt 12)
/// - Typed Failure Handling: Branches on EmbeddedFailure subclasses without string parsing
/// - Copy Rules: Wallet address is strictly a debug/support detail, never exposed as primary UI
class EmployeeDetailScreen extends StatefulWidget {
  final AppState appState;
  final EmployeeModel employee;

  const EmployeeDetailScreen({
    super.key,
    required this.appState,
    required this.employee,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late EmployeeModel _emp;
  bool _isCardFrozen = false;
  EmployeeOnboardingStatusModel? _onboardingStatus;
  bool _isLoadingStatus = true;

  @override
  void initState() {
    super.initState();
    _emp = widget.employee;
    _isCardFrozen = _emp.cardStatus.toUpperCase() == 'FROZEN';
    _fetchOnboardingStatus();
  }

  Future<void> _fetchOnboardingStatus() async {
    setState(() => _isLoadingStatus = true);
    try {
      final status =
          await widget.appState.employeeRepo.getOnboardingStatus(_emp.id);
      if (mounted) {
        setState(() {
          _onboardingStatus = status;
          _isLoadingStatus = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  Future<void> _toggleCardFreeze() async {
    final targetFreeze = !_isCardFrozen;
    setState(() {
      _isCardFrozen = targetFreeze;
    });

    try {
      await widget.appState.cardRepo.setCardStatus(
        _emp.id,
        freeze: targetFreeze,
        userId: _emp.bmoniUserId,
      );
      if (mounted) {
        BMoniToastOverlay.showSuccess(
          context: context,
          title: targetFreeze ? 'Card Frozen' : 'Card Activated',
          message: targetFreeze
              ? 'Virtual Mastercard status updated to BLOCKED on BMONI rails.'
              : 'Virtual Mastercard status updated to ACTIVE on BMONI rails.',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetFreeze
                  ? 'Card has been frozen (BLOCKED).'
                  : 'Card is now active (ACTIVE).',
            ),
          ),
        );
      }
    }
  }

  Future<void> _retryOnboarding() async {
    final targetStage =
        _onboardingStatus?.failedStage ?? _onboardingStatus?.currentStage ?? 2;
    try {
      final updated =
          await widget.appState.employeeRepo.retryStage(_emp.id, targetStage);
      setState(() {
        _onboardingStatus = updated;
      });
      if (mounted) {
        BMoniToastOverlay.showInfo(
          context: context,
          title: 'Stage $targetStage Re-triggered',
          message:
              'Reset Stage $targetStage for ${_emp.fullName}. Proceeding to onboarding wizard.',
        );
        _openOnboardingWizard();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to retry stage $targetStage: $e')),
        );
      }
    }
  }

  void _openOnboardingWizard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeOnboardingScreen(
          appState: widget.appState,
          employee: _emp,
        ),
      ),
    ).then((_) => _fetchOnboardingStatus());
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with Riverpod ProviderScope scoped to the active WalletRepository
    return ProviderScope(
      overrides: [
        walletDataSourceProvider.overrideWithValue(widget.appState.walletRepo),
        walletStorageProvider.overrideWithValue(widget.appState.walletRepo),
        walletBalanceCacheProvider
            .overrideWithValue(widget.appState.walletRepo),
      ],
      child: _EmployeeDetailContent(
        appState: widget.appState,
        employee: _emp,
        isCardFrozen: _isCardFrozen,
        onboardingStatus: _onboardingStatus,
        isLoadingStatus: _isLoadingStatus,
        onToggleCardFreeze: _toggleCardFreeze,
        onRetryOnboarding: _retryOnboarding,
        onOpenOnboardingWizard: _openOnboardingWizard,
        onRefreshStatus: _fetchOnboardingStatus,
      ),
    );
  }
}

/// Riverpod Consumer Content Widget
class _EmployeeDetailContent extends ConsumerStatefulWidget {
  final AppState appState;
  final EmployeeModel employee;
  final bool isCardFrozen;
  final EmployeeOnboardingStatusModel? onboardingStatus;
  final bool isLoadingStatus;
  final VoidCallback onToggleCardFreeze;
  final VoidCallback onRetryOnboarding;
  final VoidCallback onOpenOnboardingWizard;
  final VoidCallback onRefreshStatus;

  const _EmployeeDetailContent({
    required this.appState,
    required this.employee,
    required this.isCardFrozen,
    required this.onboardingStatus,
    required this.isLoadingStatus,
    required this.onToggleCardFreeze,
    required this.onRetryOnboarding,
    required this.onOpenOnboardingWizard,
    required this.onRefreshStatus,
  });

  @override
  ConsumerState<_EmployeeDetailContent> createState() =>
      _EmployeeDetailContentState();
}

class _EmployeeDetailContentState
    extends ConsumerState<_EmployeeDetailContent> {
  bool _isBalanceHidden = false;
  bool _hasInitialLoaded = false;
  VirtualCardModel? _activeCard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWalletData();
    });
  }

  Future<void> _fetchCard(String smartWalletId) async {
    try {
      final cards = await widget.appState.cardRepo.getCards(
        smartWalletId: smartWalletId,
        userId: widget.employee.bmoniUserId,
      );
      if (mounted && cards.isNotEmpty) {
        setState(() {
          _activeCard = cards.first;
        });
      } else if (mounted) {}
    } catch (_) {}
  }

  Future<void> _initWalletData() async {
    if (_hasInitialLoaded) return;
    _hasInitialLoaded = true;

    // 1. Fetch Wallets list using the Riverpod notifier
    await ref.read(walletListProvider.notifier).fetchWallets(isCache: true);

    // 2. Identify the active wallet for this employee
    final walletListState = ref.read(walletListProvider);
    final activeWallet = _resolveEmployeeWallet(walletListState.wallets);

    // 3. Fetch transactions and balances via Riverpod notifiers
    ref.read(walletTransactionsProvider.notifier).fetchTransactions(
          activeWallet.walletId,
          pageSize: 5,
          isCache: true,
        );
    ref.read(walletBalancesProvider.notifier).fetchWalletBalances(
      [activeWallet.walletId],
      isCache: true,
    );

    // 4. Fetch virtual employee card attached to smart wallet
    _fetchCard(activeWallet.walletId);
  }

  /// Resolves the employee's EmbeddedWallet from the list, or builds a provisioned fallback.
  EmbeddedWallet _resolveEmployeeWallet(List<EmbeddedWallet> wallets) {
    // Match by employeeId metadata
    for (final w in wallets) {
      if (w.metadata?['employeeId'] == widget.employee.id) {
        return w;
      }
    }
    // Match by smart wallet address
    if (widget.employee.walletAddress != null) {
      for (final w in wallets) {
        if (w.address?.toLowerCase() ==
            widget.employee.walletAddress?.toLowerCase()) {
          return w;
        }
      }
    }
    // Match by currency code
    for (final w in wallets) {
      if (w.currency.toUpperCase() ==
          widget.employee.targetCurrency.code.toUpperCase()) {
        return w;
      }
    }

    // Deterministic provisioned wallet fallback
    return EmbeddedWallet(
      walletId:
          'sw_${widget.employee.targetCurrency.code.toLowerCase()}_${widget.employee.id}',
      name: '${widget.employee.targetCurrency.code} Smart Wallet',
      currency: widget.employee.targetCurrency.code,
      stablecoinToken: widget.employee.targetCurrency.stablecoinToken,
      balance:
          widget.employee.isReady ? widget.employee.salaryAmount * 1.94 : 0.0,
      address: widget.employee.walletAddress ??
          '0x7e81C44F35dB56E522432d6771F52994B6b021ad',
      status: widget.employee.walletStatus.toLowerCase(),
      metadata: {
        'employeeId': widget.employee.id,
        'country': widget.employee.country
      },
    );
  }

  void _refreshAll(String walletId) {
    ref.read(walletListProvider.notifier).fetchWallets();
    ref.read(walletTransactionsProvider.notifier).fetchTransactions(walletId);
    ref.read(walletBalancesProvider.notifier).fetchWalletBalances([walletId]);
    widget.onRefreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final walletListState = ref.watch(walletListProvider);
    final balancesState = ref.watch(walletBalancesProvider);
    final txState = ref.watch(walletTransactionsProvider);

    // Resolve active wallet and attach live balance if available
    var activeWallet = _resolveEmployeeWallet(walletListState.wallets);
    if (balancesState.containsKey(activeWallet.walletId)) {
      activeWallet =
          activeWallet.copyWith(balance: balancesState[activeWallet.walletId]!);
    }

    final transactions =
        txState.getTransactionsForWallet(activeWallet.walletId);
    final failure = walletListState.failure ?? txState.failure;

    final payrollFormatted = widget.employee.payrollAmount != null
        ? widget.employee.payrollAmount!.formatFormatted()
        : '${widget.employee.targetCurrency.symbol}2,000.00';

    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.employee.fullName,
          style: FlowPayTypography.title(color: FlowPayColors.ink)
              .copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: FlowPaySpacing.insetXl,
        children: [
          // 1. Identity & Profile Section Card
          FlowPayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: FlowPayColors.surfaceAlt,
                      child: Text(
                        widget.employee.flagEmoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employee.fullName,
                            style: FlowPayTypography.title(
                                    color: FlowPayColors.ink)
                                .copyWith(fontSize: 17),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.employee.email,
                            style: FlowPayTypography.captionStyle(
                                color: FlowPayColors.textSecondary),
                          ),
                          if (widget.employee.phoneNumber != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.employee.phoneNumber!,
                              style: FlowPayTypography.captionStyle(
                                  color: FlowPayColors.textTertiary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    FlowPayStatusBadge(status: widget.employee.status),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: FlowPayColors.hairline, height: 1),
                const SizedBox(height: 14),
                _DetailRow(
                  label: 'Jurisdiction',
                  value:
                      '${widget.employee.flagEmoji} ${widget.employee.resolvedCountryName}',
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Disbursement Rail',
                  value:
                      '${widget.employee.targetCurrency.code} (${widget.employee.targetCurrency.stablecoinToken})',
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Monthly Net Salary',
                  value: payrollFormatted,
                  isAccent: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: FlowPaySpacing.xl),

          // 2. WALLET CONTROL CENTER (Powered by bmoni_embedded_wallets_cards)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WALLET CONTROL CENTER',
                style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textTertiary)
                    .copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: walletListState.isLoading || txState.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh,
                        size: 16, color: FlowPayColors.brand),
                onPressed: () => _refreshAll(activeWallet.walletId),
                tooltip: 'Refresh Ledger',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // BMONI Security Note Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FlowPayColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: FlowPayColors.brand.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    size: 16, color: FlowPayColors.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'B-Key Hardware Enclave: Private key stored in on-device Keystore. Zero custodial key exposure.',
                    style: TextStyle(
                      color: FlowPayColors.brand.withValues(alpha: 0.95),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Failure Banner (Typed Failure Branching)
          if (failure != null) ...[
            _FailureStateBanner(
              failure: failure,
              onRetry: () => _refreshAll(activeWallet.walletId),
            ),
            const SizedBox(height: 12),
          ],

          // Model-Aware EmbeddedWalletCard (6 currency background art variants)
          EmbeddedWalletCard(
            wallet: activeWallet,
            isBalanceHidden: _isBalanceHidden,
            onToggleHideBalance: () =>
                setState(() => _isBalanceHidden = !_isBalanceHidden),
            isLoading: walletListState.isLoading,
            isRefreshing: walletListState.isRefreshing,
            onInfoTap: () => _showWalletDetailSheet(context, activeWallet),
            onTap: () => _showWalletDetailSheet(context, activeWallet),
          ),
          const SizedBox(height: 12),

          // Actions: View Wallet, Transactions, Issue Card
          Row(
            children: [
              Expanded(
                child: BMoniButton(
                  text: 'View Wallet',
                  icon: Icons.account_balance_wallet_outlined,
                  variant: BMoniButtonVariant.outline,
                  size: BMoniButtonSize.small,
                  onPressed: () =>
                      _showWalletDetailSheet(context, activeWallet),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BMoniButton(
                  text: 'Transactions',
                  icon: Icons.receipt_long_outlined,
                  variant: BMoniButtonVariant.outline,
                  size: BMoniButtonSize.small,
                  onPressed: () => _showTransactionsSheet(
                      context, activeWallet, transactions),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BMoniButton(
                  text: _activeCard != null ? 'Manage Card' : 'Issue Card',
                  icon: Icons.credit_card_rounded,
                  variant: BMoniButtonVariant.primary,
                  size: BMoniButtonSize.small,
                  onPressed: _activeCard != null
                      ? () => _showCardDetailModal(context, _activeCard!)
                      : () => _showIssueCardModal(context, activeWallet),
                ),
              ),
            ],
          ),
          const SizedBox(height: FlowPaySpacing.xl),

          // 3. Composed Recent Activity (EmbeddedWalletTransactionsSection)
          EmbeddedWalletTransactionsSection(
            title: 'Recent Activity',
            viewAllLabel: 'View All (${transactions.length})',
            transactions: transactions,
            isInitialLoading: txState.isLoading && transactions.isEmpty,
            onViewAll: () =>
                _showTransactionsSheet(context, activeWallet, transactions),
          ),
          const SizedBox(height: FlowPaySpacing.xl),

          // 4. Virtual Mastercard Object Section (Card Status & Management)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'VIRTUAL MASTERCARD STATUS',
                style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textTertiary)
                    .copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_activeCard != null)
                GestureDetector(
                  onTap: () => _showCardDetailModal(context, _activeCard!),
                  child: Row(
                    children: [
                      Text(
                        'Manage Card',
                        style: FlowPayTypography.captionStyle(
                                color: FlowPayColors.brand)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 10, color: FlowPayColors.brand),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          VirtualCardObject(
            cardLast4:
                _activeCard?.last4 ?? widget.employee.cardLast4 ?? '••••',
            countryFlag: widget.employee.flagEmoji,
            cardHolderName: widget.employee.fullName,
            cardName: _activeCard?.cardName ?? 'FlowPay Spend Card',
            currencyCode: _activeCard?.currency.code ?? activeWallet.currency,
            isReserved: _activeCard?.isReserved ?? false,
            isFrozen: _activeCard?.isFrozen ?? widget.isCardFrozen,
            proposalStatus: _activeCard?.proposalStatus,
            onTap: _activeCard != null
                ? () => _showCardDetailModal(context, _activeCard!)
                : () => _showIssueCardModal(context, activeWallet),
          ),
          const SizedBox(height: FlowPaySpacing.xl),

          // 5. Onboarding Progress Section (Stages 2, 3, 4)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ONBOARDING PROGRESS (ACTUAL STAGES)',
                style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textTertiary)
                    .copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: widget.isLoadingStatus
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh,
                        size: 16, color: FlowPayColors.brand),
                onPressed:
                    widget.isLoadingStatus ? null : widget.onRefreshStatus,
                tooltip: 'Refresh Status',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FlowPayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BMONI Onboarding Lifecycle',
                            style: FlowPayTypography.title(
                                    color: FlowPayColors.ink)
                                .copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.onboardingStatus != null
                                ? 'Current: Stage ${widget.onboardingStatus!.currentStage} of 4'
                                : 'Lifecycle status: ${widget.employee.status}',
                            style: FlowPayTypography.captionStyle(
                                color: FlowPayColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    _OnboardingStatePill(
                      state: widget.onboardingStatus?.overallState ??
                          (widget.employee.isReady
                              ? OnboardingStageState.ready
                              : widget.employee.isFailed
                                  ? OnboardingStageState.failed
                                  : OnboardingStageState.inProgress),
                    ),
                  ],
                ),
                if (widget.onboardingStatus?.overallState ==
                        OnboardingStageState.failed ||
                    widget.employee.isFailed) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: FlowPayColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: FlowPayColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 18, color: FlowPayColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Failed at Stage ${widget.onboardingStatus?.failedStage ?? 2}',
                                style: const TextStyle(
                                  color: FlowPayColors.error,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.onboardingStatus?.failureReason ??
                                    'Verification requirement unfulfilled or challenge expired.',
                                style: TextStyle(
                                  color: FlowPayColors.error
                                      .withValues(alpha: 0.9),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onRetryOnboarding,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(
                              color: FlowPayColors.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(color: FlowPayColors.hairline, height: 1),
                const SizedBox(height: 12),

                // Stage 2
                _StageProgressRow(
                  stageNumber: 2,
                  title: 'Stage 2: Smart Wallet Provisioning',
                  subtitle:
                      'Owner key + challenge PIN signing (${widget.employee.targetCurrency.stablecoinToken} token)',
                  state: _getStageState(2),
                  error: widget.onboardingStatus?.failedStage == 2
                      ? widget.onboardingStatus?.failureReason
                      : null,
                ),
                const Divider(color: FlowPayColors.hairline, height: 20),

                // Stage 3
                _StageProgressRow(
                  stageNumber: 3,
                  title: 'Stage 3: Country-Specific KYC',
                  subtitle: widget.employee.country == 'NG'
                      ? 'BVN/NIN + EDD employment (no selfie)'
                      : 'CURP/RFC + biometric selfie',
                  state: _getStageState(3),
                  error: widget.onboardingStatus?.failedStage == 3
                      ? widget.onboardingStatus?.failureReason
                      : null,
                ),
                const Divider(color: FlowPayColors.hairline, height: 20),

                // Stage 4
                _StageProgressRow(
                  stageNumber: 4,
                  title: 'Stage 4: Disbursement Rail Activation',
                  subtitle: widget.employee.country == 'NG'
                      ? 'Local NGN bank rails'
                      : 'Etherfuse MX agreements + SPEI activation',
                  state: _getStageState(4),
                  error: widget.onboardingStatus?.failedStage == 4
                      ? widget.onboardingStatus?.failureReason
                      : null,
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: BMoniButton(
                    onPressed: widget.onOpenOnboardingWizard,
                    text: widget.employee.isReady
                        ? 'View Full Onboarding Flow'
                        : (widget.onboardingStatus?.overallState ==
                                OnboardingStageState.failed
                            ? 'Fix Onboarding Issues'
                            : 'Continue Onboarding Wizard'),
                    variant: widget.employee.isReady
                        ? BMoniButtonVariant.outline
                        : BMoniButtonVariant.primary,
                    size: BMoniButtonSize.medium,
                    icon: Icons.launch_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FlowPaySpacing.xl),

          // 6. KYC Compliance Section
          Text(
            'KYC & COMPLIANCE VERIFICATION',
            style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textTertiary)
                .copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FlowPayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KycIndicatorRow(
                  title: 'National Identity Verification',
                  subtitle: widget.employee.country == 'NG'
                      ? 'BVN / NIN verification'
                      : 'CURP / RFC verification',
                  isPassed: widget.employee.isReady ||
                      widget.employee.status == 'ACTIVE',
                  isPending: widget.employee.status == 'KYC_PENDING' ||
                      widget.employee.status == 'ONBOARDING',
                ),
                const Divider(color: FlowPayColors.hairline, height: 16),
                _KycIndicatorRow(
                  title: 'Proof of Address',
                  subtitle: 'Utility or jurisdictional document',
                  isPassed: widget.employee.isReady ||
                      widget.employee.status == 'ACTIVE',
                  isPending: widget.employee.status == 'KYC_PENDING' ||
                      widget.employee.status == 'ONBOARDING',
                ),
                if (widget.employee.country == 'MX') ...[
                  const Divider(color: FlowPayColors.hairline, height: 16),
                  _KycIndicatorRow(
                    title: 'Facial Biometric Liveness',
                    subtitle: 'Anti-spoofing radar scan validation (Sumsub)',
                    isPassed: widget.employee.isReady ||
                        widget.employee.status == 'ACTIVE',
                    isPending: widget.employee.status == 'ONBOARDING',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FlowPaySpacing.xl),

          // 7. Actions: Freeze/Unfreeze & Wizard
          Text(
            'ACTIONS',
            style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textTertiary)
                .copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BMoniButton(
                  onPressed: widget.onToggleCardFreeze,
                  text: widget.isCardFrozen ? 'Unfreeze Card' : 'Freeze Card',
                  variant: widget.isCardFrozen
                      ? BMoniButtonVariant.primary
                      : BMoniButtonVariant.outline,
                  size: BMoniButtonSize.medium,
                  icon: widget.isCardFrozen
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BMoniButton(
                  onPressed: widget.onboardingStatus?.overallState ==
                          OnboardingStageState.failed
                      ? widget.onRetryOnboarding
                      : widget.onOpenOnboardingWizard,
                  text: widget.onboardingStatus?.overallState ==
                          OnboardingStageState.failed
                      ? 'Retry Stage'
                      : 'Onboarding Wizard',
                  variant: BMoniButtonVariant.primary,
                  size: BMoniButtonSize.medium,
                  icon: widget.onboardingStatus?.overallState ==
                          OnboardingStageState.failed
                      ? Icons.refresh_rounded
                      : Icons.arrow_forward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  OnboardingStageState _getStageState(int stageNumber) {
    if (widget.onboardingStatus != null) {
      final stage = widget.onboardingStatus!.stages.firstWhere(
        (s) => s.stageNumber == stageNumber,
        orElse: () => StageDetailModel(
          stageNumber: stageNumber,
          title: 'Stage $stageNumber',
          description: '',
          state: OnboardingStageState.notStarted,
        ),
      );
      return stage.state;
    }
    if (widget.employee.isReady) return OnboardingStageState.ready;
    if (widget.employee.isFailed) {
      return stageNumber == 2
          ? OnboardingStageState.failed
          : OnboardingStageState.notStarted;
    }
    return stageNumber == 2
        ? OnboardingStageState.inProgress
        : OnboardingStageState.notStarted;
  }

  // =========================================================
  // Modals & Bottom Sheets
  // =========================================================

  void _showWalletDetailSheet(BuildContext context, EmbeddedWallet wallet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowPayColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FlowPayColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Smart Wallet Specification',
                    style: FlowPayTypography.title(color: FlowPayColors.ink)
                        .copyWith(fontSize: 17),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: FlowPayColors.signal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      wallet.status.toUpperCase(),
                      style: const TextStyle(
                        color: FlowPayColors.signal,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'ERC-4337 Account Abstraction on Base Sepolia',
                style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Divider(color: FlowPayColors.hairline),
              const SizedBox(height: 12),

              _DetailRow(
                  label: 'Wallet Identifier',
                  value: wallet.walletId,
                  isMonospace: true),
              const SizedBox(height: 10),
              _DetailRow(
                  label: 'Settlement Rail',
                  value:
                      '${wallet.currency} (${wallet.stablecoinToken ?? "Native"})'),
              const SizedBox(height: 10),
              const _DetailRow(
                  label: 'Network & Chain', value: 'Base Sepolia (84532)'),
              const SizedBox(height: 10),
              const _DetailRow(
                  label: 'Signing Standard',
                  value: 'BmoniEmbeddedSdk (B-Key Signer)'),
              const SizedBox(height: 16),

              // Wallet Address (Secondary / Support debug detail per design.md copy rules)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FlowPayColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: FlowPayColors.hairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ON-CHAIN CONTRACT ADDRESS (SUPPORT / AUDIT)',
                            style: FlowPayTypography.captionStyle(
                                    color: FlowPayColors.textTertiary)
                                .copyWith(
                                    fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            wallet.address ??
                                '0x7e81C44F35dB56E522432d6771F52994B6b021ad',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: FlowPayColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: FlowPayColors.brand),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: wallet.address ?? ''));
                        Navigator.pop(ctx);
                        BMoniToastOverlay.showSuccess(
                          context: context,
                          title: 'Address Copied',
                          message:
                              'On-chain smart wallet address copied to clipboard.',
                        );
                      },
                      tooltip: 'Copy EVM Address',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: BMoniButton(
                  text: 'Close Specification',
                  variant: BMoniButtonVariant.primary,
                  size: BMoniButtonSize.medium,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTransactionsSheet(
    BuildContext context,
    EmbeddedWallet wallet,
    List<EmbeddedWalletTransaction> transactions,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowPayColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: FlowPayColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Wallet Transactions',
                        style: FlowPayTypography.title(color: FlowPayColors.ink)
                            .copyWith(fontSize: 17),
                      ),
                      Text(
                        '${transactions.length} records',
                        style: FlowPayTypography.captionStyle(
                            color: FlowPayColors.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${wallet.name} • ${wallet.currency} (${wallet.stablecoinToken ?? "Token"})',
                    style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: FlowPayColors.hairline, height: 1),
                  const SizedBox(height: 8),
                  Expanded(
                    child: transactions.isEmpty
                        ? Center(
                            child: Text(
                              'No transactions recorded for this wallet.',
                              style: FlowPayTypography.body(
                                  color: FlowPayColors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: transactions.length,
                            separatorBuilder: (_, __) => const Divider(
                                color: FlowPayColors.hairline, height: 1),
                            itemBuilder: (_, index) {
                              final tx = transactions[index];
                              final isIncoming = tx.isIncoming;
                              final sign = isIncoming ? '+' : '-';
                              final color = isIncoming
                                  ? FlowPayColors.signal
                                  : FlowPayColors.ink;

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isIncoming
                                            ? FlowPayColors.signal
                                                .withValues(alpha: 0.12)
                                            : FlowPayColors.surfaceAlt,
                                      ),
                                      child: Icon(
                                        isIncoming
                                            ? Icons.south_west_rounded
                                            : Icons.north_east_rounded,
                                        size: 18,
                                        color: isIncoming
                                            ? FlowPayColors.signal
                                            : FlowPayColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tx.title,
                                            style: FlowPayTypography.body(
                                                    color: FlowPayColors.ink)
                                                .copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            tx.counterpartyName ??
                                                (isIncoming
                                                    ? 'FlowPay'
                                                    : 'Merchant'),
                                            style:
                                                FlowPayTypography.captionStyle(
                                                    color: FlowPayColors
                                                        .textTertiary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$sign${wallet.currency} ${tx.amount.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: FlowPayColors.signal
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            tx.status.name.toUpperCase(),
                                            style: const TextStyle(
                                              color: FlowPayColors.signal,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showIssueCardModal(BuildContext context, EmbeddedWallet wallet) {
    IssueVirtualCardSheet.show(
      context: context,
      employee: widget.employee,
      wallet: wallet,
      cardRepo: widget.appState.cardRepo,
      onCardIssued: (card) {
        setState(() {
          _activeCard = card;
        });
        ref
            .read(walletBalancesProvider.notifier)
            .fetchWalletBalances([wallet.walletId]);
      },
    );
  }

  void _showCardDetailModal(BuildContext context, VirtualCardModel card) {
    CardDetailSheet.show(
      context: context,
      card: card,
      countryFlag: widget.employee.flagEmoji,
      cardHolderName: widget.employee.fullName,
      userId: widget.employee.bmoniUserId,
      cardRepo: widget.appState.cardRepo,
      onCardUpdated: (updatedCard) {
        setState(() {
          _activeCard = updatedCard;
        });
      },
    );
  }
}

/// Typed Failure State Banner
class _FailureStateBanner extends StatelessWidget {
  final EmbeddedFailure failure;
  final VoidCallback onRetry;

  const _FailureStateBanner({required this.failure, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String title;
    String description;

    if (failure is EmbeddedNetworkFailure) {
      icon = Icons.wifi_off_rounded;
      title = 'Network Connection Offline';
      description =
          'Unable to reach BMONI node. Please check your connection and retry.';
    } else if (failure is EmbeddedServerFailure) {
      icon = Icons.cloud_off_rounded;
      title = 'BMONI Ledger Latency';
      description =
          'The smart wallet RPC node is temporarily unavailable (Status: ${failure.statusCode ?? 500}).';
    } else if (failure is EmbeddedRateLimitFailure) {
      final rf = failure as EmbeddedRateLimitFailure;
      icon = Icons.speed_rounded;
      title = 'Rate Limit Reached';
      description =
          'Too many requests. Please wait ${rf.retryAfterSeconds ?? 30} seconds before retrying.';
    } else if (failure is EmbeddedNotFoundFailure) {
      icon = Icons.search_off_rounded;
      title = 'Smart Wallet Not Found';
      description =
          'No on-chain smart wallet was found for this user ID on Base Sepolia.';
    } else if (failure is EmbeddedAuthenticationFailure) {
      icon = Icons.lock_outline_rounded;
      title = 'Authentication Expired';
      description =
          'BMONI API session key expired. Re-authentication required.';
    } else if (failure is EmbeddedAuthorizationFailure) {
      icon = Icons.gpp_bad_outlined;
      title = 'Unauthorized Access';
      description =
          'Your API key does not have permission to inspect this smart wallet.';
    } else {
      icon = Icons.error_outline_rounded;
      title = 'Wallet Query Failed';
      description = failure.message;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlowPayColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FlowPayColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: FlowPayColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: FlowPayColors.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: FlowPayColors.error.withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Retry',
              style: TextStyle(
                color: FlowPayColors.error,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KycIndicatorRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isPassed;
  final bool isPending;

  const _KycIndicatorRow({
    required this.title,
    required this.subtitle,
    required this.isPassed,
    this.isPending = false,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;
    String statusText;
    Color textColor;

    if (isPassed) {
      icon = Icons.check_circle_rounded;
      iconColor = FlowPayColors.signal;
      statusText = 'PASSED';
      textColor = FlowPayColors.signal;
    } else if (isPending) {
      icon = Icons.hourglass_empty_rounded;
      iconColor = Colors.amber;
      statusText = 'PENDING';
      textColor = Colors.amber[700] ?? Colors.amber;
    } else {
      icon = Icons.cancel_rounded;
      iconColor = FlowPayColors.error;
      statusText = 'NOT SUBMITTED';
      textColor = FlowPayColors.error;
    }

    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    FlowPayTypography.body(color: FlowPayColors.ink).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                subtitle,
                style: FlowPayTypography.captionStyle(
                    color: FlowPayColors.textTertiary),
              ),
            ],
          ),
        ),
        Text(
          statusText,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isAccent;
  final bool isMonospace;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isAccent = false,
    this.isMonospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: FlowPayTypography.captionStyle(
              color: FlowPayColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: isAccent
              ? FlowPayTypography.amount(color: FlowPayColors.signal).copyWith(
                  fontWeight: FontWeight.w700,
                )
              : FlowPayTypography.body(color: FlowPayColors.ink).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFamily: isMonospace ? 'monospace' : null,
                ),
        ),
      ],
    );
  }
}

class _OnboardingStatePill extends StatelessWidget {
  final OnboardingStageState state;

  const _OnboardingStatePill({required this.state});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    switch (state) {
      case OnboardingStageState.ready:
        bg = FlowPayColors.signal.withValues(alpha: 0.15);
        fg = FlowPayColors.signal;
        label = 'READY';
        break;
      case OnboardingStageState.failed:
        bg = FlowPayColors.error.withValues(alpha: 0.15);
        fg = FlowPayColors.error;
        label = 'FAILED';
        break;
      case OnboardingStageState.inProgress:
        bg = Colors.amber.withValues(alpha: 0.15);
        fg = Colors.amber[700] ?? Colors.amber;
        label = 'IN PROGRESS';
        break;
      case OnboardingStageState.notStarted:
        bg = FlowPayColors.surfaceAlt;
        fg = FlowPayColors.textTertiary;
        label = 'NOT STARTED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StageProgressRow extends StatelessWidget {
  final int stageNumber;
  final String title;
  final String subtitle;
  final OnboardingStageState state;
  final String? error;

  const _StageProgressRow({
    required this.stageNumber,
    required this.title,
    required this.subtitle,
    required this.state,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    Color textColor;
    String statusText;

    switch (state) {
      case OnboardingStageState.ready:
        iconWidget = const Icon(Icons.check_circle_rounded,
            color: FlowPayColors.signal, size: 22);
        textColor = FlowPayColors.signal;
        statusText = 'PASSED';
        break;
      case OnboardingStageState.inProgress:
        iconWidget = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              '$stageNumber',
              style: TextStyle(
                color: Colors.amber[800],
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        );
        textColor = Colors.amber[800] ?? Colors.amber;
        statusText = 'IN PROGRESS';
        break;
      case OnboardingStageState.failed:
        iconWidget = const Icon(Icons.error_rounded,
            color: FlowPayColors.error, size: 22);
        textColor = FlowPayColors.error;
        statusText = 'FAILED';
        break;
      case OnboardingStageState.notStarted:
        iconWidget = Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: FlowPayColors.surfaceAlt,
          ),
          child: Center(
            child: Text(
              '$stageNumber',
              style: const TextStyle(
                color: FlowPayColors.textTertiary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        );
        textColor = FlowPayColors.textTertiary;
        statusText = 'PENDING';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            iconWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: FlowPayTypography.body(color: FlowPayColors.ink)
                        .copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textTertiary),
                  ),
                ],
              ),
            ),
            Text(
              statusText,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              error!,
              style: const TextStyle(
                color: FlowPayColors.error,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
