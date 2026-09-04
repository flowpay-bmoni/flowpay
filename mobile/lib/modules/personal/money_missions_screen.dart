import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../core/bmoni_sdk/bmoni_sdk_service.dart';
import '../../core/design_system/states.dart';
import '../../core/missions/mission_intent.dart';
import '../../core/missions/mission_validator.dart';
import '../../core/repositories/mission_repository.dart';
import '../../core/navigation/personal_tab_provider.dart';
import '../../core/state/app_state.dart';
import '../../core/wallet/components/wallet_pin_auth_sheet.dart';
import 'components/mission_card.dart';
import 'components/mission_preview_modal.dart';

class MoneyMissionsScreen extends StatefulWidget {
  final AppState appState;

  const MoneyMissionsScreen({super.key, required this.appState});

  @override
  State<MoneyMissionsScreen> createState() => _MoneyMissionsScreenState();
}

class _MoneyMissionsScreenState extends State<MoneyMissionsScreen> {
  final TextEditingController _inputController = TextEditingController(
    text:
        'Whenever I receive \$2,000, keep 30% in USD, convert 50% to Naira for expenses, and reserve 20% for tax.',
  );

  List<MoneyMissionModel> missions = [];
  bool isLoadingMissions = true;

  // AI Pipeline State
  bool isInterpreting = false;
  int processingStage = 0; // 0: Idle, 1: Understood, 2: Created, 3: Validated
  MissionIntent? currentIntent;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMissions();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadMissions() async {
    setState(() => isLoadingMissions = true);
    try {
      final list = await widget.appState.missionRepo.getMissions();
      if (mounted) {
        setState(() {
          missions = List.from(list);
          isLoadingMissions = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => isLoadingMissions = false);
      }
    }
  }

  void _prefillPrompt(String prompt) {
    setState(() {
      _inputController.text = prompt;
      currentIntent = null;
      errorMessage = null;
      processingStage = 0;
    });
  }

  Future<void> _handleInterpret() async {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      isInterpreting = true;
      processingStage = 1; // Stage 1: AI understood request
      errorMessage = null;
      currentIntent = null;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() => processingStage = 2); // Stage 2: Plan created

      // Call repository to interpret
      final intent = await widget.appState.missionRepo.interpretMission(prompt);

      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() => processingStage = 3); // Stage 3: Deterministic validation

      // Client-side deterministic validation guard
      final validation = ClientMissionValidator.validate(intent);
      if (!validation.isValid) {
        setState(() {
          isInterpreting = false;
          processingStage = 0;
          errorMessage = validation.errors.join('; ');
        });
        return;
      }

      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      setState(() {
        isInterpreting = false;
        currentIntent = intent;
      });

      _showMissionPreviewModal(intent);
    } catch (err) {
      if (mounted) {
        setState(() {
          isInterpreting = false;
          processingStage = 0;
          errorMessage = 'Failed to interpret instruction: $err';
        });
      }
    }
  }

  void _showMissionPreviewModal(MissionIntent intent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MissionPreviewModal(
        intent: intent,
        onEdit: () {
          Navigator.pop(ctx);
        },
        onApprove: () {
          Navigator.pop(ctx);
          _startSigningAndExecutionFlow(intent);
        },
      ),
    );
  }

  Future<void> _startSigningAndExecutionFlow(MissionIntent intent) async {
    try {
      // 1. Backend generates proposal & cryptographic hash to sign
      final proposal = await widget.appState.missionRepo.proposeMission(intent);
      final hashToSign = proposal['hashToSign']?.toString() ??
          '0x7f4e912389ab4c10ef9238914ba1238914ab1238914ba1238914ba1238914baa';
      final missionId = proposal['missionId']?.toString() ?? intent.intentId;

      if (!mounted) return;

      // 2. Open BMONI B-Key PIN Signing Sheet
      final signature = await WalletPinAuthSheet.show(
        context: context,
        title: 'Sign Money Mission',
        subtitle: 'Authorize autonomous execution of "${intent.ruleTitle}"',
        amountDisplay: '\$${intent.triggerCondition.sourceAmount}',
        recipient: 'BMONI Settlement Rails',
        onAuthorize: (pin) async {
          // Hardware enclave signing via BMONI Embedded SDK
          return await BmoniSdkService.signTransactionHash(hashToSign,
              pin: pin);
        },
      );

      if (signature != null && mounted) {
        // 3. Complete execution on backend
        final result = await widget.appState.missionRepo.executeMission(
          missionId: missionId,
          signature: signature,
          pinValidated: true,
        );

        // 4. Create local active mission item
        final newMission = MoneyMissionModel(
          id: missionId,
          title: intent.ruleTitle,
          tagline: intent.explanation,
          ruleType: MissionRuleType.splitIncoming,
          isActive: true,
          status: MissionStatus.active,
          stats:
              '\$${intent.triggerCondition.sourceAmount} scheduled • 3 rails settled',
          conditionSummary: intent.triggerCondition.description,
          actionSummary: intent.explanation,
          allocations: intent.allocations,
          lastExecution: 'Just now',
          nextExecution:
              'On Incoming Transfer (\$${intent.triggerCondition.sourceAmount})',
          createdAt: DateTime.now(),
        );

        setState(() {
          missions.insert(0, newMission);
          currentIntent = null;
          processingStage = 0;
        });

        _showExecutionCelebrationDialog(newMission, result);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Signing cancelled or failed: $err'),
            backgroundColor: BMoniColors.error500,
          ),
        );
      }
    }
  }

  void _showExecutionCelebrationDialog(
      MoneyMissionModel mission, Map<String, dynamic> result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final txRef =
        result['transactionReference']?.toString() ?? 'bmoni_tx_active';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? BMoniColors.offbrand950 : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BMoniColors.success400.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check,
                  color: BMoniColors.success400, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              'Mission Activated & Signed!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? BMoniColors.grey50 : BMoniColors.grey950,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'FlowPay will autonomously monitor incoming funds and execute deterministic BMONI operations according to your plan.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? BMoniColors.grey300 : BMoniColors.grey700,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? BMoniColors.offbrand900 : BMoniColors.grey100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? BMoniColors.offbrand700 : BMoniColors.grey300,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Signing Enclave',
                          style: TextStyle(
                              fontSize: 11, color: BMoniColors.grey400)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'BMONI B-Key PIN Verified',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? BMoniColors.grey100
                                  : BMoniColors.grey900),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('BMONI Reference',
                          style: TextStyle(
                              fontSize: 11, color: BMoniColors.grey400)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          txRef.length > 18
                              ? '${txRef.substring(0, 16)}...'
                              : txRef,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: BMoniColors.brand300,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status',
                          style: TextStyle(
                              fontSize: 11, color: BMoniColors.grey400)),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'ACTIVE • Monitored',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: BMoniColors.success400),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: BMoniButton(
                    text: 'View Active Missions',
                    variant: BMoniButtonVariant.primary,
                    size: BMoniButtonSize.large,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: BMoniButton(
                    text: 'View in Activity',
                    variant: BMoniButtonVariant.secondary,
                    size: BMoniButtonSize.medium,
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                      widget.appState.setPersonalTabIndex(PersonalTab.activity);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMission(String id) async {
    final updated = await widget.appState.missionRepo.toggleMission(id);
    if (mounted) {
      setState(() {
        final idx = missions.indexWhere((m) => m.id == id);
        if (idx != -1) {
          missions[idx] = updated;
        }
      });
    }
  }

  Future<void> _handleManualTrigger(String id) async {
    final idx = missions.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final mission = missions[idx];

    // Show PIN signing sheet for test execution
    final signature = await WalletPinAuthSheet.show(
      context: context,
      title: 'Manual Test Execution',
      subtitle: 'Simulate incoming payment trigger for "${mission.title}"',
      amountDisplay: mission.thresholdAmount?.formatFormatted() ?? '\$2,000.00',
      recipient: 'BMONI Settlement Rails',
      onAuthorize: (pin) async {
        return await BmoniSdkService.signTransactionHash(
          '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          pin: pin,
        );
      },
    );

    if (signature != null && mounted) {
      final updated =
          await widget.appState.missionRepo.triggerManualExecution(id);
      if (!mounted) return;
      setState(() {
        missions[idx] = updated;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              '⚡ Mission triggered & executed successfully via BMONI rails!'),
          backgroundColor: BMoniColors.success500,
          action: SnackBarAction(
            label: 'View Activity',
            textColor: Colors.white,
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              widget.appState.setPersonalTabIndex(PersonalTab.activity);
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.canPop(context);

    Widget content = isLoadingMissions
        ? const FlowPayLoadingState(message: 'Loading Money Missions...')
        : RefreshIndicator(
            onRefresh: _loadMissions,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // 1. Financial Command Center Header & Telemetry
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What should your money do?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tell your money what to do.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: BMoniColors.brand300,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Set autonomous directives in plain English. FlowPay structures the rules; execution is strictly gated behind your on-device B-Key PIN.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? BMoniColors.grey400 : BMoniColors.grey600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Command Center Live Telemetry Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? BMoniColors.offbrand900 : BMoniColors.grey100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? BMoniColors.offbrand700 : BMoniColors.grey300,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: BMoniColors.success400,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Engine: Active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? BMoniColors.grey200 : BMoniColors.grey800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined,
                                size: 13, color: BMoniColors.brand400),
                            const SizedBox(width: 4),
                            Text(
                              'B-Key Guard',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? BMoniColors.grey300 : BMoniColors.grey700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Row(
                          children: [
                            const Icon(Icons.bolt,
                                size: 13, color: BMoniColors.accent400),
                            const SizedBox(width: 4),
                            Text(
                              'Deterministic',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? BMoniColors.grey300 : BMoniColors.grey700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Financial Command Center Console (Command Directive Input)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? BMoniColors.offbrand900 : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isInterpreting
                          ? BMoniColors.brand400
                          : (isDark
                              ? BMoniColors.offbrand700
                              : BMoniColors.grey200),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isInterpreting
                            ? BMoniColors.brand500.withAlpha(25)
                            : Colors.black.withAlpha(8),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: BMoniColors.brand500.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.terminal_rounded,
                                    size: 12, color: BMoniColors.brand400),
                                SizedBox(width: 4),
                                Text(
                                  'COMMAND DIRECTIVE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: BMoniColors.brand400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your money. Your rules. AI executes.',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? BMoniColors.grey400
                                    : BMoniColors.grey600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _inputController,
                        maxLines: 3,
                        minLines: 2,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color:
                              isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'e.g. "Whenever I receive \$2,000, keep 30% in USD, convert 50% to Naira for expenses, and reserve 20% for tax."',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? BMoniColors.grey500
                                : BMoniColors.grey400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Submit Directive Button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'Strictly PIN-authorized on BMONI',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? BMoniColors.grey400 : BMoniColors.grey600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          BMoniButton(
                            text: isInterpreting
                                ? 'Structuring Plan...'
                                : 'Interpret Directive',
                            icon: Icons.auto_awesome,
                            variant: BMoniButtonVariant.primary,
                            size: BMoniButtonSize.medium,
                            isLoading: isInterpreting,
                            onPressed: isInterpreting ? null : _handleInterpret,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Error Banner if validation failed
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: BMoniColors.error500.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: BMoniColors.error500.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: BMoniColors.error400, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                                fontSize: 12, color: BMoniColors.error300),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 3. Visible AI Pipeline Progress Indicator (Stages: Understood -> Created -> Validated)
                if (isInterpreting || processingStage > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? BMoniColors.offbrand950
                          : BMoniColors.grey100,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: BMoniColors.brand500.withAlpha(70)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.psychology,
                                size: 16, color: BMoniColors.brand400),
                            SizedBox(width: 6),
                            Text(
                              'Financial Safety AI Pipeline',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                                color: BMoniColors.brand300,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildStageRow(
                            'AI understood request', processingStage >= 1),
                        const SizedBox(height: 6),
                        _buildStageRow('Plan created (structured intent)',
                            processingStage >= 2),
                        const SizedBox(height: 6),
                        _buildStageRow(
                            'Deterministic validation passed (100% allocation)',
                            processingStage >= 3),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // 4. Suggested Actions Row (5 Suggestion Chips)
                Text(
                  'SUGGESTED DIRECTIVES',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.bold,
                    color: isDark ? BMoniColors.grey400 : BMoniColors.grey600,
                  ),
                ),
                const SizedBox(height: 10),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSuggestionChip(
                        icon: Icons.pie_chart_outline,
                        label: 'Split incoming payment',
                        color: BMoniColors.brand400,
                        prompt:
                            'Whenever I receive \$2,000, keep 30% in USD, convert 50% to Naira for expenses, and reserve 20% for tax.',
                      ),
                      const SizedBox(width: 8),
                      _buildSuggestionChip(
                        icon: Icons.savings_outlined,
                        label: 'Save for a goal',
                        color: BMoniColors.success400,
                        prompt:
                            'Whenever I receive \$1,500, save 25% into high-yield USD emergency vault.',
                      ),
                      const SizedBox(width: 8),
                      _buildSuggestionChip(
                        icon: Icons.currency_exchange,
                        label: 'Convert currency',
                        color: BMoniColors.accent400,
                        prompt:
                            'Convert \$1,000 to Naira whenever received for monthly payroll expenses.',
                      ),
                      const SizedBox(width: 8),
                      _buildSuggestionChip(
                        icon: Icons.send_outlined,
                        label: 'Send money',
                        color: const Color(0xFF38BDF8),
                        prompt:
                            'Send \$500 to Samson Jabo whenever contractor disbursement arrives.',
                      ),
                      const SizedBox(width: 8),
                      _buildSuggestionChip(
                        icon: Icons.account_balance_outlined,
                        label: 'Reserve for taxes',
                        color: const Color(0xFFFBBF24),
                        prompt:
                            'Reserve 20% for tax into escrow sub-account on every incoming payment.',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // 5. Active Missions Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Active Missions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark ? BMoniColors.grey50 : BMoniColors.grey950,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: BMoniColors.brand500.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: BMoniColors.brand400.withAlpha(60)),
                      ),
                      child: Text(
                        '${missions.where((m) => m.isActive).length} Active',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: BMoniColors.brand300,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Active Mission Cards List
                if (missions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? BMoniColors.offbrand900 : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? BMoniColors.offbrand700
                            : BMoniColors.grey200,
                      ),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.bolt, size: 36, color: BMoniColors.grey500),
                        SizedBox(height: 8),
                        Text(
                          'No Active Missions Yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: BMoniColors.grey300,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Type a directive above to set your first autonomous financial plan.',
                          style: TextStyle(
                              fontSize: 12, color: BMoniColors.grey500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ...missions.map((m) {
                    return MissionCard(
                      mission: m,
                      onToggleActive: (_) => _toggleMission(m.id),
                      onTriggerManual: () => _handleManualTrigger(m.id),
                    );
                  }),
              ],
            ),
          );

    if (canPop) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Money Missions'),
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildStageRow(String label, bool isCompleted) {
    return Row(
      children: [
        Icon(
          isCompleted ? Icons.check_circle : Icons.circle_outlined,
          size: 15,
          color: isCompleted ? BMoniColors.success400 : BMoniColors.grey500,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
              color: isCompleted ? BMoniColors.grey100 : BMoniColors.grey500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionChip({
    required IconData icon,
    required String label,
    required Color color,
    required String prompt,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => _prefillPrompt(prompt),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(70), width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? BMoniColors.grey100 : BMoniColors.grey900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
