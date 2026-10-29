import '../../core/stellar/stellar_key_vault.dart';
import '../../core/financial_operator/services/stellar_execution_provider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../core/wallet/wallet_signer.dart';
import '../../core/design_system/design_system.dart';
import '../../core/financial_operator/financial_operator.dart';
import '../../core/financial_operator/models/financial_plan_models.dart';
import '../../core/financial_operator/models/operator_session_models.dart';
import '../../core/financial_operator/services/execution_provider.dart';
import '../../core/financial_operator/services/financial_context_service.dart';
import '../../core/state/app_state.dart';
import '../../core/wallet/components/wallet_pin_auth_sheet.dart';
import 'components/add_beneficiary_modal.dart';
import 'components/ai_clarification_card.dart';
import 'components/ai_financial_plan_card.dart';
import 'components/choose_beneficiary_modal.dart';

/// FlowPay AI Financial Operator Modal
/// Embedded intelligent financial operator interface supporting natural language
/// multi-action requests, entity disambiguation, multi-turn clarification,
/// structured plan review, and on-device wallet PIN signing.
class AiOperatorModal extends StatefulWidget {
  final AppState appState;
  final String? initialPrompt;

  const AiOperatorModal({
    super.key,
    required this.appState,
    this.initialPrompt,
  });

  @override
  State<AiOperatorModal> createState() => _AiOperatorModalState();
}

class _AiOperatorModalState extends State<AiOperatorModal> {
  late final FinancialOperator _operator;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSigning = false;

  @override
  void initState() {
    super.initState();
    final contextService = FinancialContextService(
      walletRepo: widget.appState.walletRepo,
      beneficiaryRepo: widget.appState.beneficiaryRepo,
      missionRepo: widget.appState.missionRepo,
      activityRepo: widget.appState.activityRepo,
    );
    final FinancialExecutionProvider executionProvider = widget.appState.isDemo
        ? DemoFinancialExecutionProvider(
            walletRepo: widget.appState.walletRepo,
            activityRepo: widget.appState.activityRepo,
          )
        : StellarFinancialExecutionProvider(apiClient: widget.appState.apiClient);

    _operator = FinancialOperator(
      contextService: contextService,
      executionProvider: executionProvider,
      transferRepo: widget.appState.transferRepo,
    );

    _operator.addListener(_onOperatorStateChanged);

    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _operator.processInput(widget.initialPrompt!.trim());
      });
    }
  }

  @override
  void dispose() {
    _operator.removeListener(_onOperatorStateChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _operator.dispose();
    super.dispose();
  }

  void _onOperatorStateChanged() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        // Second pass after cards (with expandable sections and badges) finish lay out
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  void _handleSubmit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();

    final lower = text.toLowerCase();
    if ((_operator.status == OperatorSessionStatus.readyForReview ||
         _operator.status == OperatorSessionStatus.error) &&
        _operator.activePlan != null &&
        !_operator.activePlan!.isApproved &&
        (lower == 'approve' ||
            lower == 'confirm' ||
            lower == 'proceed' ||
            lower == 'retry' ||
            lower == 'yes')) {
      _handleApprovePlan(_operator.activePlan!);
      return;
    }

    _operator.processInput(text);
  }

  Future<void> _handleOptionSelected(
    ClarificationPrompt clarification,
    ClarificationOptionData opt,
  ) async {
    if (opt.value == 'ADD_BENEFICIARY') {
      // Extract possible nickname from question, e.g. "Who is dad?" -> "Dad"
      String? nickname;
      final q = clarification.question;
      final match =
          RegExp(r'Who is ([^?]+)\?', caseSensitive: false).firstMatch(q);
      if (match != null) {
        nickname = match.group(1)!.trim();
        nickname = nickname[0].toUpperCase() +
            (nickname.length > 1 ? nickname.substring(1) : '');
      }

      await AddBeneficiaryModal.show(
        context,
        initialNickname: nickname,
        onSave: (beneficiary) async {
          await _operator.contextService.addBeneficiary(beneficiary);
          await _operator
              .resolvePendingClarificationWithBeneficiary(beneficiary);
        },
      );
      return;
    }

    if (opt.value == 'CHOOSE_EXISTING' || opt.value == 'CHOOSE_CONTACT') {
      final beneficiaries = await _operator.contextService.getBeneficiaries();
      if (!mounted) return;
      await ChooseBeneficiaryModal.show(
        context,
        beneficiaries: beneficiaries,
        onSelect: (beneficiary) async {
          await _operator
              .resolvePendingClarificationWithBeneficiary(beneficiary);
        },
      );
      return;
    }

    await _operator.selectClarificationOption(clarification, opt);
  }

  Future<void> _handleApprovePlan(FinancialPlan plan) async {
    setState(() => _isSigning = true);

    try {
      final hashToSign = plan.hashToSign ??
          '0x${sha256.convert(utf8.encode(plan.planId)).toString()}';

      if (_operator.executionProvider.settlesAtomically) {
        // Live: confirm the PIN here (so typos show in the sheet), then the operator
        // builds, signs and submits ONE Stellar transaction for the whole plan.
        final pin = await WalletPinAuthSheet.show(
          context: context,
          title: 'Confirm payment',
          subtitle: 'Enter your 6-digit PIN to confirm',
          amountDisplay: plan.totalDebit.toFormattedString(),
          recipient: plan.summary,
          onAuthorize: (pin) async {
            // PINs are checked here so typos show in the sheet. A passkey has no
            // typos: checking it here would just prompt twice (signing prompts once).
            if (pin != StellarKeyVault.passkey && !await StellarKeyVault.instance.verifyPin(pin)) {
              throw const StellarVaultException(StellarVaultErrorCode.pinMismatch, 'Incorrect PIN.');
            }
            return pin;
          },
        );
        if (pin != null) {
          await _operator.approveAndExecute(pin: pin);
          await widget.appState.personalProvider.refresh();
        }
        return;
      }

      final signature = await WalletPinAuthSheet.show(
        context: context,
        title: 'Confirm payment',
        subtitle: 'Enter your 6-digit PIN to confirm',
        amountDisplay: plan.totalDebit.toFormattedString(),
        recipient: plan.summary,
        onAuthorize: (pin) async {
          // Demo mode: sign the simulated plan hash.
          return await const StellarWalletSigner().signTransactionHash(
            hashToSign,
            pin: pin,
          );
        },
      );

      if (signature != null && signature.isNotEmpty) {
        await _operator.approveAndExecute(signature: signature);
        await widget.appState.personalProvider.refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authorization error: $e'),
            backgroundColor: FlowPayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark
            ? FlowPayColors.darkBackground
            : FlowPayColors.paper,
        borderRadius: FlowPayRadii.sheet,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            _buildHeader(isDark),

            // Telemetry / Status indicator bar
            _buildTelemetryBar(isDark),

            // Message Stream
            Expanded(
              child: _operator.messages.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: _operator.messages.length,
                      itemBuilder: (context, index) {
                        final msg = _operator.messages[index];
                        return _buildMessageItem(context, msg, isDark);
                      },
                    ),
            ),

            // Suggested quick actions when idle
            if (_operator.status == OperatorSessionStatus.idle ||
                _operator.messages.isEmpty)
              _buildSuggestionsRow(isDark),

            // Input Bar
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FlowPayColors.emerald600.withAlpha(isDark ? 40 : 25),
              borderRadius: FlowPayRadii.avatar,
            ),
            child: const Icon(Icons.psychology,
                color: FlowPayColors.emerald600, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FlowPay Financial Operator',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : FlowPayColors.ink,
                  ),
                ),
                Text(
                  'Understands your request • Never moves money without your PIN',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? FlowPayColors.darkTextSecondary : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: isDark ? Colors.white : FlowPayColors.ink),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryBar(bool isDark) {
    String statusLabel = 'READY';
    Color statusColor = FlowPayColors.emerald600;

    switch (_operator.status) {
      case OperatorSessionStatus.interpreting:
        statusLabel = 'UNDERSTANDING YOUR REQUEST';
        statusColor = FlowPayColors.accent;
        break;
      case OperatorSessionStatus.waitingForClarification:
        statusLabel = 'WAITING FOR CLARIFICATION';
        statusColor = FlowPayColors.accentLight;
        break;
      case OperatorSessionStatus.readyForReview:
        statusLabel = 'PLAN READY FOR REVIEW';
        statusColor = FlowPayColors.emerald600;
        break;
      case OperatorSessionStatus.executing:
        statusLabel = 'AUTHORIZING ON-DEVICE';
        statusColor = FlowPayColors.emerald600;
        break;
      case OperatorSessionStatus.completed:
        statusLabel = 'DONE';
        statusColor = FlowPayColors.emerald600;
        break;
      case OperatorSessionStatus.error:
        if (_operator.activePlan != null && !_operator.activePlan!.isApproved) {
          statusLabel = 'AUTH NOTICE • RETRY AVAILABLE';
          statusColor = FlowPayColors.accent;
        } else {
          statusLabel = 'HALTED / ERROR';
          statusColor = FlowPayColors.error;
        }
        break;
      case OperatorSessionStatus.rejected:
        statusLabel = 'CANCELLED';
        statusColor = FlowPayColors.darkTextMuted;
        break;
      case OperatorSessionStatus.idle:
      default:
        statusLabel = 'READY';
        statusColor = FlowPayColors.emerald600;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? FlowPayColors.darkSurface
            : Colors.white,
        borderRadius: FlowPayRadii.chip,
        border: Border.all(
          color: isDark ? FlowPayColors.darkBorder : FlowPayColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: statusColor,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          Text(
            'Your money is protected',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? FlowPayColors.darkTextSecondary : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: FlowPayColors.emerald600.withAlpha(isDark ? 40 : 25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 36, color: FlowPayColors.emerald600),
            ),
            const SizedBox(height: 18),
            Text(
              'What would you like to achieve?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : FlowPayColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask FlowPay in plain English to send money, set aside taxes, manage payments, or check your wallets.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? FlowPayColors.darkTextSecondary : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(
      BuildContext context, OperatorMessage msg, bool isDark) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: FlowPayColors.emerald600.withAlpha(isDark ? 35 : 20),
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: const Radius.circular(3),
            ),
            border: Border.all(
              color: FlowPayColors.emerald600.withAlpha(70),
            ),
          ),
          child: Text(
            msg.text,
            style: FlowPayTypography.bodyMd.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : FlowPayColors.ink,
            ),
          ),
        ),
      );
    }

    // Operator Message
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, right: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text Message Bubble
            if (msg.text.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? FlowPayColors.darkSurface
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16).copyWith(
                    bottomLeft: const Radius.circular(3),
                  ),
                  border: Border.all(
                    color: msg.isError
                        ? FlowPayColors.error.withAlpha(120)
                        : (isDark
                            ? FlowPayColors.darkBorder
                            : FlowPayColors.lightBorder),
                  ),
                ),
                child: Text(
                  msg.text,
                  style: FlowPayTypography.bodyMd.copyWith(
                    color: msg.isError
                        ? FlowPayColors.error
                        : (isDark ? Colors.white : FlowPayColors.ink),
                  ),
                ),
              ),

            // Embedded Clarification Card
            if (msg.clarification != null) ...[
              const SizedBox(height: 8),
              AiClarificationCard(
                title: msg.clarification!.question,
                questions: [
                  ClarificationQuestion(
                    id: msg.clarification!.id,
                    question: msg.clarification!.question,
                    description: msg.clarification!.description,
                    options: msg.clarification!.options.map((opt) {
                      return ClarificationOption(
                        id: opt.id,
                        label: opt.label,
                        subtitle: opt.subtitle,
                        onCustomAction: () =>
                            _handleOptionSelected(msg.clarification!, opt),
                      );
                    }).toList(),
                  ),
                ],
                onCancel: () => _operator.cancelSession(),
              ),
            ],

            // Embedded Structured Financial Plan Card
            if (msg.plan != null) ...[
              const SizedBox(height: 8),
              AiFinancialPlanCard(
                plan: msg.plan!,
                isExecuting: _isSigning,
                onApprove: () => _handleApprovePlan(msg.plan!),
                onCancel: () => _operator.cancelSession(),
                onOverrideRoute: (curr) {
                  _inputController.text = 'Use $curr instead';
                  _handleSubmit();
                },
                onAskWhy: () {
                  _inputController.text = 'Why did you use my EUR?';
                  _handleSubmit();
                },
              ),
            ],

            // Embedded Execution Receipt Card
            if (msg.executionReceipt != null) ...[
              const SizedBox(height: 8),
              _buildReceiptCard(msg.executionReceipt!, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> receipt, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlowPayColors.emerald600.withAlpha(isDark ? 25 : 15),
        borderRadius: FlowPayRadii.cardMedium,
        border: Border.all(color: FlowPayColors.emerald600.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: FlowPayColors.emerald600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Payment done',
                style: FlowPayTypography.bodyLg.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : FlowPayColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Reference: ${receipt['txHash']}',
            style: FlowPayTypography.captionStyle(
              color: isDark ? FlowPayColors.darkTextSecondary : const Color(0xFF6B7280),
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 4),
          Text(
            '${receipt['settledActions']} payment(s) completed',
            style: FlowPayTypography.captionStyle(
              color: isDark ? FlowPayColors.darkTextSecondary : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FlowPayButton(
              text: 'Done',
              size: FlowPayButtonSize.small,
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildSuggestionPill(
              'Send \$500 USD to Mom and pay my designer \$2,000 USD',
              isDark,
            ),
            const SizedBox(width: 8),
            _buildSuggestionPill(
              'Make sure I have \$2,000 in USD',
              isDark,
            ),
            const SizedBox(width: 8),
            _buildSuggestionPill(
              'Send 500 usd to mom, keep 300 usd for tax',
              isDark,
            ),
            const SizedBox(width: 8),
            _buildSuggestionPill(
              'Check my balance',
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionPill(String text, bool isDark) {
    return InkWell(
      onTap: () {
        _inputController.text = text;
        _handleSubmit();
      },
      borderRadius: FlowPayRadii.chip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? FlowPayColors.darkSurface
              : Colors.white,
          borderRadius: FlowPayRadii.chip,
          border: Border.all(
            color: FlowPayColors.emerald600.withAlpha(isDark ? 50 : 30),
          ),
        ),
        child: Text(
          text.length > 38 ? '${text.substring(0, 38)}...' : text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? FlowPayColors.emerald400 : FlowPayColors.emerald700,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: isDark
            ? FlowPayColors.darkBackground
            : FlowPayColors.paper,
        border: Border(
          top: BorderSide(
            color: isDark ? FlowPayColors.darkBorder : FlowPayColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? FlowPayColors.darkSurface : Colors.white,
                borderRadius: FlowPayRadii.input,
                border: Border.all(
                  color: isDark ? FlowPayColors.darkBorder : FlowPayColors.lightBorder,
                ),
              ),
              child: TextField(
                controller: _inputController,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : FlowPayColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'Type instructions or respond naturally...',
                  hintStyle: TextStyle(
                    color: isDark ? FlowPayColors.darkTextSecondary : const Color(0xFF9CA3AF),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FlowPayIconButton(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'Send',
            onPressed: _handleSubmit,
          ),
        ],
      ),
    );
  }
}
