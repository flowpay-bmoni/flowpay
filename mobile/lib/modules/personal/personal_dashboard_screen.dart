import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../core/design_system/design_system.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/repositories/activity_repository.dart';
import '../../core/repositories/approval_repository.dart';
import '../../core/repositories/wallet_repository.dart';
import '../../core/state/app_state.dart';
import '../../core/state/personal_provider.dart';
import 'ai_operator_modal.dart';
import 'components/ai_allocation_modal.dart';
import 'components/ai_command_bar.dart';
import 'components/ai_fx_conversion_modal.dart';
import 'components/pending_approvals_card.dart';
import 'money_missions_screen.dart';
import 'personal_activity_screen.dart';
import 'personal_shell.dart';
import 'send_money_screen.dart';
import 'wallet_provisioning_screen.dart';
import 'wallets_screen.dart';
import '../../core/navigation/personal_tab_provider.dart';

/// FLOWPAY — PERSONAL DASHBOARD
///
/// Route/Screen: Personal Dashboard
/// Tagline: "Your money. Your rules. AI executes."
///
/// Features:
/// - Total portfolio value & available balances (no fake precision, sandbox identified)
/// - Multi-currency wallet summaries (USD, NGN, MXN, CAD) using shared components
/// - AI Command interaction ("What should your money do?")
/// - Task-specific financial workflows (Allocation, Send, FX Convert)
/// - Pending Approvals queue with on-device B-Key PIN signing
/// - Active Money Missions summary with live toggling
/// - Shared Activity model transaction history
/// - Architecture powered by PersonalProvider decoupling data from widgets
class PersonalDashboardScreen extends StatefulWidget {
  final AppState appState;

  const PersonalDashboardScreen({super.key, required this.appState});

  @override
  State<PersonalDashboardScreen> createState() =>
      _PersonalDashboardScreenState();
}

class _PersonalDashboardScreenState extends State<PersonalDashboardScreen> {
  late final PersonalProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = widget.appState.personalProvider;
    _provider.loadDashboard();
  }

  void _openAiAllocationModal({Money? amount}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAllocationModal(
        personalProvider: _provider,
        initialAmount: amount ?? Money.fromMajorString('2000.00', Currency.usd),
      ),
    );
  }

  void _openAiFxConversionModal({Money? amount}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiFxConversionModal(
        personalProvider: _provider,
        initialAmount: amount ?? Money.fromMajorString('1000.00', Currency.usd),
      ),
    );
  }

  void _navigateToTab(int tabIndex,
      {required Widget fallbackScreen, required String routeName}) {
    widget.appState.setPersonalTabIndex(tabIndex);
    final hasShell =
        context.findAncestorWidgetOfExactType<PersonalShell>() != null;
    if (!hasShell) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => fallbackScreen,
          settings: RouteSettings(name: routeName),
        ),
      );
    }
  }

  void _openSendMoneyScreen({String? initialAmount, String? initialRecipient}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendMoneyScreen(appState: widget.appState),
        settings: const RouteSettings(name: AppRoutes.personalSendMoney),
      ),
    );
  }

  void _openAiOperatorModal(String customPrompt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiOperatorModal(appState: widget.appState),
    );
  }

  Future<void> _handleApprove(PendingApprovalModel approval, String pin) async {
    try {
      final success = await _provider.approveAction(approval.id, pin: pin);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Action approved and signed on BMONI: ${approval.title}'),
            backgroundColor: BMoniColors.brand500,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed: $e'), backgroundColor: BMoniColors.error400),
      );
    }
  }

  Future<void> _handleReject(PendingApprovalModel approval) async {
    await _provider.rejectAction(approval.id, reason: 'Dismissed by user');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Action dismissed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.canPop(context);

    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        final totalPortfolio = _provider.totalPortfolioUsd;
        final totalFormatted =
            totalPortfolio.formatFormatted(includeSymbol: true);
        final wholePart = totalFormatted.split('.')[0];
        final decimalPart = '.${totalPortfolio.toMajorString().split('.')[1]}';

        Widget content = RefreshIndicator(
          onRefresh: _provider.refresh,
          color: BMoniColors.brand500,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Header Subtitle & Status Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Personal Account',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? BMoniColors.grey50
                                    : BMoniColors.grey950,
                              ),
                            ),
                            // Clear Sandbox / Demo Indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: BMoniColors.accent400.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: BMoniColors.accent400.withAlpha(70)),
                              ),
                              child: Text(
                                widget.appState.isDemo
                                    ? 'Sandbox Demo'
                                    : 'BMONI Live Testnet',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: BMoniColors.accent400,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Your money. Your rules. AI executes.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BMoniColors.brand400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WalletProvisioningScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BMoniColors.brand500.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: BMoniColors.brand500.withAlpha(80)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 12, color: BMoniColors.brand400),
                          SizedBox(width: 4),
                          Text(
                            'B-Key Vault',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: BMoniColors.brand400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Premium Portfolio Section (BMoniWalletCard)
              BMoniWalletCard(
                height: 240,
                background: const BMoniWalletCardBackground.gradient(
                  LinearGradient(
                    colors: [
                      Color(0xFF4A0E4E),
                      Color(0xFF28092B),
                      Color(0xFF160418),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                balanceChild: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Multi-Currency Portfolio',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: BMoniColors.grey400,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'USD PRIMARY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: BMoniColors.brand200,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    BMoniWalletCardBalance(
                      wholePart: wholePart,
                      decimalPart: decimalPart,
                      isHidden: _provider.isBalanceHidden,
                      onToggleHidden: _provider.toggleBalanceVisibility,
                      balanceColor: Colors.white,
                      decimalColor: BMoniColors.brand200,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _provider.secondaryValuationNgn,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BMoniColors.brand300,
                          ),
                        ),
                        Text(
                          'Avail: ${_provider.availableBalanceUsd.formatFormatted(includeSymbol: true)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: BMoniColors.grey400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Quick Actions Row
              Row(
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.bolt,
                      label: 'Create Mission',
                      accentColor: BMoniColors.brand400,
                      onPressed: () {
                        _navigateToTab(
                          PersonalTab.missions,
                          fallbackScreen:
                              MoneyMissionsScreen(appState: widget.appState),
                          routeName: AppRoutes.personalMissions,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.arrow_outward,
                      label: 'Send Money',
                      accentColor: BMoniColors.accent400,
                      onPressed: () => _openSendMoneyScreen(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'View Wallets',
                      accentColor: BMoniColors.success400,
                      onPressed: () {
                        _navigateToTab(
                          PersonalTab.wallets,
                          fallbackScreen:
                              WalletsScreen(appState: widget.appState),
                          routeName: AppRoutes.personalWallets,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 4. Money Missions Feature Card (Prominently displaying "Money Missions" & Tagline)
              InkWell(
                onTap: () {
                  _navigateToTab(
                    PersonalTab.missions,
                    fallbackScreen:
                        MoneyMissionsScreen(appState: widget.appState),
                    routeName: AppRoutes.personalMissions,
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        BMoniColors.offbrand900,
                        BMoniColors.brand950.withAlpha(200),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: BMoniColors.brand500.withAlpha(70),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: BMoniColors.brand500.withAlpha(35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.bolt,
                            color: BMoniColors.brand400, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Money Missions',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: BMoniColors.grey50,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '"Your money. Your rules. AI executes."',
                              style: TextStyle(
                                fontSize: 12,
                                color: BMoniColors.grey400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: BMoniColors.grey400),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 5. Primary AI Interaction ("What should your money do?")
              AiCommandBar(
                onCommandSubmit: (prompt) => _openAiOperatorModal(prompt),
                onAllocateTap: () => _openAiAllocationModal(
                  amount: Money.fromMajorString('2000.00', Currency.usd),
                ),
                onSendMoneyTap: () => _openSendMoneyScreen(
                  initialAmount: '500.00',
                  initialRecipient: 'samson.jabo@example.mx',
                ),
                onConvertTap: () => _openAiFxConversionModal(
                  amount: Money.fromMajorString('1000.00', Currency.usd),
                ),
              ),
              const SizedBox(height: 16),

              // 6. Pending Approvals Queue (Highlighted when actions need explicit signature)
              if (_provider.pendingApprovals.isNotEmpty)
                PendingApprovalsCard(
                  pendingApprovals: _provider.pendingApprovals,
                  onApprove: _handleApprove,
                  onReject: _handleReject,
                ),
              const SizedBox(height: 14),

              // 6. Active Strategy Rules Section
              SectionHeader(
                title: 'Active Strategy Rules',
                backgroundColor: Colors.transparent,
                showBottomDivider: false,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                titleStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                ),
                trailing: TextButton(
                  onPressed: () {
                    _navigateToTab(
                      PersonalTab.missions,
                      fallbackScreen:
                          MoneyMissionsScreen(appState: widget.appState),
                      routeName: AppRoutes.personalMissions,
                    );
                  },
                  child: Text(
                    'Manage (${_provider.activeMissionCount} Active)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: BMoniColors.brand400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              ..._provider.missions.map((m) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? FlowPayColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: m.isActive
                          ? BMoniColors.brand500.withAlpha(80)
                          : FlowPayColors.darkBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: m.isActive
                              ? BMoniColors.brand500.withAlpha(30)
                              : FlowPayColors.darkSurfaceElevated,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bolt,
                          size: 18,
                          color: m.isActive
                              ? BMoniColors.brand400
                              : BMoniColors.grey600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color:
                                    isDark ? Colors.white : BMoniColors.grey950,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m.stats,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: BMoniColors.brand300,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: m.isActive,
                        activeThumbColor: BMoniColors.brand500,
                        onChanged: (_) => _provider.toggleMission(m.id),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),

              // 7. Active Multi-Currency Wallets Section
              SectionHeader(
                title: 'Multi-Currency Smart Wallets',
                backgroundColor: Colors.transparent,
                showBottomDivider: false,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                titleStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                ),
                trailing: TextButton(
                  onPressed: () {
                    _navigateToTab(
                      PersonalTab.wallets,
                      fallbackScreen: WalletsScreen(appState: widget.appState),
                      routeName: AppRoutes.personalWallets,
                    );
                  },
                  child: const Text(
                    'View All (4)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: BMoniColors.brand400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Wallets breakdown
              ..._provider.wallets.map((w) {
                return _WalletSummaryCard(
                  wallet: w,
                  isDark: isDark,
                  onCopyAddress: () {
                    Clipboard.setData(ClipboardData(text: w.address));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Copied ${w.currency.code} address: ${w.address}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 16),

              // 8. Recent Activity Section
              SectionHeader(
                title: 'Recent Activity',
                backgroundColor: Colors.transparent,
                showBottomDivider: false,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                titleStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                ),
                trailing: TextButton(
                  onPressed: () {
                    _navigateToTab(
                      PersonalTab.activity,
                      fallbackScreen:
                          PersonalActivityScreen(appState: widget.appState),
                      routeName: AppRoutes.personalActivity,
                    );
                  },
                  child: const Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: BMoniColors.brand400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              ..._provider.recentActivities.take(5).map((act) {
                IconData catIcon = Icons.history;
                if (act.category == ActivityCategory.mission) {
                  catIcon = Icons.bolt;
                }
                if (act.category == ActivityCategory.transfer) {
                  catIcon = Icons.arrow_outward;
                }
                if (act.category == ActivityCategory.card) {
                  catIcon = Icons.credit_card;
                }
                if (act.category == ActivityCategory.fx) {
                  catIcon = Icons.currency_exchange;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? FlowPayColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: FlowPayColors.darkBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? FlowPayColors.darkSurfaceElevated
                              : FlowPayColors.lightSurfaceElevated,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(catIcon,
                            size: 16, color: FlowPayColors.primaryLight),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              act.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color:
                                    isDark ? Colors.white : BMoniColors.grey950,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              act.description,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? BMoniColors.grey400
                                    : BMoniColors.grey700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FlowPayStatusBadge(
                            appStatus: act.status,
                            showDot: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            act.timeAgo,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? BMoniColors.grey500
                                  : BMoniColors.grey600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
          ),
        );

        if (canPop) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Personal Dashboard'),
            ),
            body: content,
          );
        }

        return content;
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? FlowPayColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FlowPayColors.darkBorder),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : BMoniColors.grey950,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSummaryCard extends StatelessWidget {
  final WalletAccount wallet;
  final bool isDark;
  final VoidCallback onCopyAddress;

  const _WalletSummaryCard({
    required this.wallet,
    required this.isDark,
    required this.onCopyAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? FlowPayColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FlowPayColors.darkBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: FlowPayCurrencyDisplay(
              code: wallet.currency.code,
              symbol: wallet.currency.symbol,
              name: wallet.currency.name,
              tokenName: 'BMONI ${wallet.stablecoinToken}',
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FlowPayAmountDisplay(
                amount: wallet.balance.formatFormatted(),
                size: AmountDisplaySize.medium,
              ),
              const SizedBox(height: 3),
              InkWell(
                onTap: onCopyAddress,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${wallet.address.substring(0, 6)}...${wallet.address.substring(wallet.address.length - 4)}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: BMoniColors.grey400,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy,
                        size: 10, color: BMoniColors.grey400),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
