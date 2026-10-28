import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../beneficiaries/beneficiary_model.dart';
import '../wallet/wallet_signer.dart';
import '../design_system/states.dart';
import '../money/currency.dart';
import '../money/money.dart';
import '../providers/demo/demo_transfer_repo.dart';
import '../repositories/activity_repository.dart';
import '../repositories/transfer_repository.dart';
import '../repositories/wallet_repository.dart';
import '../transfers/transfer_funding.dart';
import '../transfers/transfer_intent.dart';
import '../transfers/transfer_models.dart';
import 'models/financial_entities.dart';
import 'models/financial_intent_types.dart';
import 'models/financial_plan_models.dart';
import 'models/operator_session_models.dart';
import '../financial_engine/financial_engine.dart';
import '../financial_engine/models/reservation_ledger.dart';
import '../missions/mission_runtime_engine.dart';
import 'services/clarification_engine.dart';
import 'services/context_resolver.dart';
import 'services/execution_provider.dart';
import 'services/financial_context_service.dart';
import 'services/financial_intent_engine.dart';
import 'services/financial_planner.dart';

/// FlowPay Financial Operator
/// Central intelligent agent coordinating the entire interpretation, entity
/// resolution, clarification, deterministic planning, and execution authorization pipeline.
class FinancialOperator extends ChangeNotifier {
  final FinancialContextService contextService;
  final FinancialExecutionProvider executionProvider;
  final TransferRepository? transferRepo;
  late final TransferRepository _transferRepo;
  late final ContextResolver _contextResolver;
  late final FinancialPlanner _planner;

  OperatorSession _session;

  FinancialOperator({
    required this.contextService,
    required this.executionProvider,
    TransferRepository? transferRepo,
  })  : transferRepo = transferRepo,
        _session = OperatorSession(
          sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
          status: OperatorSessionStatus.idle,
        ) {
    _transferRepo = transferRepo ??
        DemoTransferRepository(
          walletRepo: contextService.walletRepo,
          activityRepo: contextService.activityRepo,
        );
    _contextResolver = ContextResolver(contextService: contextService);
    _planner = FinancialPlanner(contextService: contextService);
  }

  OperatorSession get session => _session;
  OperatorSessionStatus get status => _session.status;
  List<OperatorMessage> get messages => _session.messages;
  FinancialPlan? get activePlan => _session.activePlan;
  ClarificationPrompt? get pendingClarification => _session.pendingClarification;

  /// Start or reset a conversation session
  void startNewSession([String? initialPrompt]) {
    _session = OperatorSession(
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
      status: OperatorSessionStatus.idle,
      messages: [],
    );
    notifyListeners();

    if (initialPrompt != null && initialPrompt.trim().isNotEmpty) {
      processInput(initialPrompt.trim());
    }
  }

  /// Process natural language input from user
  Future<void> processInput(String rawInput) async {
    final text = rawInput.trim();
    if (text.isEmpty) return;

    // 1. Record user message
    final userMsg = OperatorMessage.user(text);
    _session = _session.copyWith(
      messages: [..._session.messages, userMsg],
    );
    notifyListeners();

    try {
      // 2. Handle waiting for clarification state
      if (_session.status == OperatorSessionStatus.waitingForClarification &&
          _session.pendingClarification != null) {
        await _handleClarificationResponse(text);
        return;
      }

      final lower = text.toLowerCase();

      // A. Mission percentage adjustment (Conversation 3: "Actually make it 25%")
      final pctMatch = RegExp(
        r'(?:actually\s+)?(?:make|change|set)(?:\s+it)?\s+(?:to\s+)?(\d+(?:\.\d+)?)\s*%',
        caseSensitive: false,
      ).firstMatch(text);
      if (pctMatch != null) {
        final newPct = double.parse(pctMatch.group(1)!);
        final updated = MissionRuntimeEngine().updateMissionPercentage('tax', newPct);
        final missionName = updated?.name ?? 'Tax Mission';
        final confirmMsg = OperatorMessage.operator(
          'Updated your $missionName. Whenever USD arrives, I will now reserve ${newPct.toStringAsFixed(0)}% for taxes.\n'
          '• Target: Tax Reserve\n'
          '• Rate: ${newPct.toStringAsFixed(0)}%\n'
          '• Status: ${updated?.state.name.toUpperCase() ?? 'ACTIVE'}',
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, confirmMsg],
        );
        notifyListeners();
        return;
      }

      // B. Multi-action mission rule extension (Conversation 4: "Also send 200 to my designer whenever there's enough")
      final alsoSendMatch = RegExp(
        r'also\s+(?:send|pay)\s+\$?(\d+(?:\.\d+)?)\s*(?:usd)?\s+to\s+(?:my\s+)?([a-zA-Z0-9\s]+?)(?:\s+whenever|\s+when|\s+if|$)',
        caseSensitive: false,
      ).firstMatch(text);
      if (alsoSendMatch != null) {
        final amt = double.parse(alsoSendMatch.group(1)!);
        final recipient = alsoSendMatch.group(2)!.trim();
        final money = Money.fromMajorString(amt.toStringAsFixed(2), Currency.usd);

        final newRule = MissionActionRule(
          id: 'rule_designer_${DateTime.now().millisecondsSinceEpoch}',
          type: MissionActionRuleType.sendFixedAmount,
          fixedAmount: money,
          targetBeneficiary: Beneficiary(
            id: 'ben_designer',
            nickname: recipient,
            legalName: recipient,
            relationship: 'Contractor',
            destinationCountry: 'United States',
            countryFlag: '🇺🇸',
            currency: Currency.usd,
            accountOrAddress: 'designer@flowpay.finance',
            isVerified: true,
          ),
          targetCurrency: Currency.usd,
          description: 'Send ${money.toFormattedString()} to $recipient from spendable balance',
        );

        final updated = MissionRuntimeEngine().appendActionRule('tax', newRule);
        final primaryPct = updated?.rules.firstWhere((r) => r.percentage != null, orElse: () => newRule).percentage ?? 25.0;

        final confirmMsg = OperatorMessage.operator(
          'I\'ve added this rule to your ${updated?.name ?? 'USD Inflow'} Mission. Here is the deterministic order of execution on each USD inflow:\n'
          '1. Reserve ${primaryPct.toStringAsFixed(0)}% for taxes happens first into your Tax Reserve.\n'
          '2. Send ${money.toFormattedString()} to your $recipient happens second, strictly from remaining spendable balance.\n\n'
          'Deterministic Safety Guarantee: If your spendable balance is less than ${money.toFormattedString()} after tax reservation, the $recipient payment will not execute, your tax reserve will remain untouched, and you will be notified.',
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, confirmMsg],
        );
        notifyListeners();
        return;
      }

      // C. Mission pause (Conversation 7: "Pause my tax mission")
      if (lower.contains('pause') && (lower.contains('mission') || lower.contains('tax') || lower.contains('it'))) {
        final paused = MissionRuntimeEngine().pauseMission('tax');
        final confirmMsg = OperatorMessage.operator(
          'I\'ve paused your ${paused?.name ?? 'Tax Savings Mission'}. No new reservations or automated payments will trigger on future USD inflows. Your existing reserves remain safely locked in your Tax Reserve.',
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, confirmMsg],
        );
        notifyListeners();
        return;
      }

      // D. Mission resume (Conversation 7: "Resume it" / "Resume tax mission")
      if (lower.contains('resume') || (lower.contains('reactivate') && (lower.contains('mission') || lower.contains('it')))) {
        final resumed = MissionRuntimeEngine().resumeMission('tax');
        final confirmMsg = OperatorMessage.operator(
          'I\'ve resumed your ${resumed?.name ?? 'Tax Savings Mission'}. It is now active and will automatically enforce your tax reservation and automated payments on upcoming USD inflows.',
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, confirmMsg],
        );
        notifyListeners();
        return;
      }

      // E. Balance and Spendable Inquiry (Conversation 6: "How much can I spend from my USD wallet?")
      if ((lower.contains('how much') || lower.contains('what') || lower.contains('can i spend')) &&
          (lower.contains('spend') || lower.contains('spendable'))) {
        final usdWallet = await contextService.getWalletForCurrency(Currency.usd);
        if (usdWallet != null) {
          final details = ReservationLedger().getWalletBalanceDetails(
            usdWallet.id,
            Currency.usd,
            usdWallet.balance,
          );
          final buffer = StringBuffer();
          buffer.writeln('You have ${details.total.toFormattedString()} in your USD wallet:');
          if (details.hasReservations) {
            final activeRes = ReservationLedger().getActiveReservations(walletId: usdWallet.id);
            for (final r in activeRes) {
              buffer.writeln('• ${r.amount.toFormattedString()} reserved for ${r.purpose} (${r.missionTag ?? 'Tax Mission'})');
            }
          }
          buffer.writeln('• ${details.spendable.toFormattedString()} spendable balance');

          final replyMsg = OperatorMessage.operator(buffer.toString().trim());
          _session = _session.copyWith(
            status: OperatorSessionStatus.idle,
            messages: [..._session.messages, replyMsg],
          );
          notifyListeners();
          return;
        }
      }

      // F. Reservation Inquiry / Reason (Conversation 6: "Why can't I spend this money?" / "Why is my balance reserved?")
      if ((lower.contains('why') || lower.contains('what')) &&
          (lower.contains('reserved') ||
              lower.contains('locked') ||
              lower.contains('spend') ||
              lower.contains('cannot') ||
              lower.contains("can't") ||
              lower.contains("cant"))) {
        final activeRes = ReservationLedger().getActiveReservations();
        final buffer = StringBuffer();
        if (activeRes.isNotEmpty) {
          buffer.writeln('Your funds are reserved by your active missions:');
          for (final r in activeRes) {
            buffer.writeln('• ${r.amount.toFormattedString()} is reserved for ${r.purpose} (${r.missionTag ?? 'Tax Mission'}).');
          }
          buffer.writeln('\nThis guarantees that your tax obligations and financial policies are fulfilled before discretionary spending. You can adjust or pause the mission anytime (e.g., "Pause my tax mission" or "Make it 10%").');
        } else {
          buffer.writeln('You currently have no funds reserved by active missions. Your entire balance is available to spend.');
        }

        final replyMsg = OperatorMessage.operator(buffer.toString().trim());
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, replyMsg],
        );
        notifyListeners();
        return;
      }

      // G. Tax savings inquiry (Conversation 6: "How much have I saved for taxes?")
      if (lower.contains('how much') && lower.contains('tax')) {
        final taxSaved = ReservationLedger().getReservedAmountByPurpose('taxes', Currency.usd);
        final replyMsg = OperatorMessage.operator(
          'You currently have ${taxSaved.toFormattedString()} reserved for taxes in your Tax Reserve.',
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, replyMsg],
        );
        notifyListeners();
        return;
      }

      // Check if user is asking "Why did you use my EUR?"
      if (_session.activePlan?.routeExplanation != null &&
          lower.contains('why') &&
          (lower.contains('eur') ||
              lower.contains('route') ||
              lower.contains('wallet') ||
              lower.contains('use') ||
              lower.contains('using'))) {
        final explanationMsg = OperatorMessage.operator(
          _session.activePlan!.routeExplanation!,
          plan: _session.activePlan,
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.readyForReview,
          messages: [..._session.messages, explanationMsg],
        );
        notifyListeners();
        return;
      }

      // Check if user is requesting a route override ("Use NGN instead", "Use MXN instead")
      if (_session.activeIntent != null &&
          (lower.contains('use ngn') ||
              lower.contains('use naira') ||
              lower.contains('use mxn') ||
              lower.contains('use peso') ||
              lower.contains('use cad') ||
              lower.contains('use eur') ||
              lower.contains('use euro') ||
              lower.contains('use usd') ||
              lower.contains('don\'t use') ||
              lower.contains('dont use'))) {
        Currency? overrideCurr;
        if (lower.contains('ngn') || lower.contains('naira')) {
          overrideCurr = Currency.ngn;
        } else if (lower.contains('mxn') || lower.contains('peso')) {
          overrideCurr = Currency.mxn;
        } else if (lower.contains('cad')) {
          overrideCurr = Currency.cad;
        } else if (lower.contains('eur') || lower.contains('euro')) {
          overrideCurr = Currency.eur;
        } else if (lower.contains('usd') || lower.contains('dollar')) {
          overrideCurr = Currency.usd;
        }

        if (overrideCurr != null) {
          _session = _session.copyWith(status: OperatorSessionStatus.interpreting);
          notifyListeners();
          await _compileAndPresentPlan(_session.activeIntent!,
              overrideFundingCurrency: overrideCurr);
          return;
        }
      }

      // Check for balance target / smart wallet balancing command
      if (lower.contains('make sure i have') ||
          lower.contains('top up') ||
          lower.contains('keep at least')) {
        _session = _session.copyWith(status: OperatorSessionStatus.interpreting);
        notifyListeners();
        await _handleWalletBalancing(text);
        return;
      }

      // 3. Handle ready for review state
      if (_session.status == OperatorSessionStatus.readyForReview &&
          _session.activePlan != null) {
        if (lower == 'approve' || lower == 'confirm' || lower == 'proceed' || lower == 'yes') {
          // Never execute directly on chat text. Require real PIN authentication.
          final promptMsg = OperatorMessage.operator(
            'To execute this plan, please confirm with your PIN using the Approve button.',
          );
          _session = _session.copyWith(
            messages: [..._session.messages, promptMsg],
          );
          notifyListeners();
          return;
        } else if (lower == 'cancel' || lower == 'reject' || lower == 'no') {
          cancelSession();
          return;
        }
      }

      // 4. Initial interpretation of a new request
      _session = _session.copyWith(status: OperatorSessionStatus.interpreting);
      notifyListeners();

      // Handle quick balance / transaction queries directly
      final parsedIntent = FinancialIntentEngine.parse(text);

      if (parsedIntent.primaryIntent == FinancialIntentType.checkBalance) {
        await _handleBalanceCheck();
        return;
      }

      if (parsedIntent.primaryIntent == FinancialIntentType.viewTransactions) {
        await _handleTransactionCheck();
        return;
      }

      // Resolve entities against application state
      final resolvedIntent = await _contextResolver.resolve(parsedIntent);
      _session = _session.copyWith(activeIntent: resolvedIntent);

      // Handle non-actionable questions or conversational queries gracefully
      if (resolvedIntent.actions.isEmpty) {
        final whoMatch = RegExp(r'^who\s+is\s+([^?]+)\??$', caseSensitive: false)
            .firstMatch(text.trim());
        if (whoMatch != null) {
          final queryName = whoMatch.group(1)!.trim();
          final res = await contextService.resolveBeneficiary(queryName);
          if (res.isUnique && res.match != null) {
            final b = res.match!;
            final reply = OperatorMessage.operator(
              '${b.legalName} (${b.nickname}) is your verified ${b.relationship} in ${b.destinationCountry} ${b.countryFlag}.\nAccount: ${b.accountOrAddress}',
            );
            _session = _session.copyWith(
              status: OperatorSessionStatus.idle,
              messages: [..._session.messages, reply],
            );
            notifyListeners();
            return;
          } else if (res.isAmbiguous) {
            final names = res.candidates
                .map((c) => '${c.legalName} (${c.nickname})')
                .join(', ');
            final reply = OperatorMessage.operator(
              'I found multiple contacts matching "$queryName": $names.',
            );
            _session = _session.copyWith(
              status: OperatorSessionStatus.idle,
              messages: [..._session.messages, reply],
            );
            notifyListeners();
            return;
          } else {
            final reply = OperatorMessage.operator(
              'I couldn\'t find a contact or beneficiary named "$queryName" in your account yet. You can add them anytime or ask me to send a payment (e.g., "Send \$50 to $queryName").',
            );
            _session = _session.copyWith(
              status: OperatorSessionStatus.idle,
              messages: [..._session.messages, reply],
            );
            notifyListeners();
            return;
          }
        }

        final helpMsg = OperatorMessage.operator(
          'I\'m your FlowPay Financial Operator. You can instruct me in natural language to:\n'
          '• Send cross-border money: "Send \$80 to my sister"\n'
          '• Allocate income: "Keep 30% for tax and send \$500 to Mom"\n'
          '• Check balances: "How much do I have?" or "Recent activity"\n'
          '• Create Money Missions: "Whenever I receive \$2,000, convert 50% to NGN"',
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.idle,
          messages: [..._session.messages, helpMsg],
        );
        notifyListeners();
        return;
      }

      // Evaluate for missing or ambiguous information
      final clarification =
          ClarificationEngine.evaluateClarification(resolvedIntent);

      if (clarification != null) {
        // Need clarification before planning
        final promptMsg = OperatorMessage.operator(
          clarification.question,
          clarification: clarification,
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.waitingForClarification,
          pendingClarification: clarification,
          messages: [..._session.messages, promptMsg],
        );
        notifyListeners();
        return;
      }

      // If all entities are known, compile the plan!
      await _compileAndPresentPlan(resolvedIntent);
    } catch (err) {
      final errorMsg = OperatorMessage.operator(
        'I encountered an issue while processing your request: $err. Please try rephrasing or specify the amount and recipient directly.',
        isError: true,
      );
      _session = _session.copyWith(
        status: OperatorSessionStatus.error,
        messages: [..._session.messages, errorMsg],
      );
      notifyListeners();
    }
  }

  /// Handle clarification response when user types an answer
  Future<void> _handleClarificationResponse(String answer) async {
    try {
      final prompt = _session.pendingClarification!;
      final intent = _session.activeIntent;
      if (intent == null) return;

      final updatedActions = <ActionIntent>[];

      for (final act in intent.actions) {
        if (act.id == prompt.targetActionId) {
          if (prompt.field == 'recipient') {
            // Handle special non-name action values
            if (answer.toUpperCase() == 'ADD_BENEFICIARY' ||
                answer.toLowerCase() == 'add beneficiary' ||
                answer.toLowerCase() == 'add new beneficiary') {
              final promptMsg = OperatorMessage.operator(
                'Please use the "Add New Beneficiary" button above to enter their details, or reply naturally with their full legal name and country (e.g., "Dad is Ade Fashola in Nigeria").',
                clarification: prompt,
              );
              _session = _session.copyWith(
                messages: [..._session.messages, promptMsg],
              );
              notifyListeners();
              return;
            }

            if (answer.toUpperCase() == 'CHOOSE_EXISTING' ||
                answer.toUpperCase() == 'CHOOSE_CONTACT') {
              final promptMsg = OperatorMessage.operator(
                'Please use the "Choose Existing Contact" button above to select from your saved beneficiaries.',
                clarification: prompt,
              );
              _session = _session.copyWith(
                messages: [..._session.messages, promptMsg],
              );
              notifyListeners();
              return;
            }

            // Check disambiguation candidates first
            Beneficiary? match;
            if (prompt.disambiguationCandidates.isNotEmpty) {
              final lowerAnswer = answer.toLowerCase();
              for (final c in prompt.disambiguationCandidates) {
                final b = c.resolvedBeneficiary;
                if (b != null) {
                  if (lowerAnswer.contains(b.legalName.toLowerCase()) ||
                      lowerAnswer.contains(b.nickname.toLowerCase()) ||
                      lowerAnswer.contains(b.destinationCountry.toLowerCase()) ||
                      lowerAnswer.contains(b.accountOrAddress.toLowerCase()) ||
                      b.aliases.any((a) => lowerAnswer.contains(a.toLowerCase()))) {
                    match = b;
                    break;
                  }
                }
              }
            }

            // If not matched by candidates, resolve beneficiary from answer
            if (match == null) {
              final beneficiaryQuery = _extractBeneficiaryName(answer);
              final res = await contextService.resolveBeneficiary(beneficiaryQuery);
              match = res.match;
              if (match == null && res.candidates.isNotEmpty) {
                match = res.candidates.first;
              }
            }

            // If still null, check if any existing beneficiary matches Nigeria / Mary
            if (match == null) {
              final all = await contextService.getBeneficiaries();
              for (final b in all) {
                if (answer.toLowerCase().contains(b.legalName.toLowerCase()) ||
                    answer.toLowerCase().contains(b.nickname.toLowerCase()) ||
                    (answer.toLowerCase().contains('nigeria') &&
                        b.destinationCountry.toLowerCase().contains('nigeria'))) {
                  match = b;
                  break;
                }
              }
            }

            // If still null, check if user provided a natural sentence: "Dad is Ade Fashola in Nigeria"
            if (match == null) {
              final lower = answer.toLowerCase();
              if (lower.contains(' in ') ||
                  lower.contains(' is ') ||
                  lower.contains(',')) {
                String country = 'Nigeria';
                String flag = '🇳🇬';
                Currency cur = Currency.ngn;
                if (lower.contains('mexico')) {
                  country = 'Mexico';
                  flag = '🇲🇽';
                  cur = Currency.mxn;
                } else if (lower.contains('united states') ||
                    lower.contains('usa') ||
                    lower.contains('us')) {
                  country = 'United States';
                  flag = '🇺🇸';
                  cur = Currency.usd;
                } else if (lower.contains('canada')) {
                  country = 'Canada';
                  flag = '🇨🇦';
                  cur = Currency.cad;
                }

                String cleanName = answer
                    .replaceAll(
                        RegExp(
                            r'^(?:his\s+name\s+is|her\s+name\s+is|they\s+are|he\s+is|she\s+is|[a-zA-Z]+\s+is)\s+',
                            caseSensitive: false),
                        '')
                    .replaceAll(
                        RegExp(r'\s+(?:in|from)\s+[a-zA-Z\s]+$',
                            caseSensitive: false),
                        '')
                    .replaceAll(RegExp(r'[,.]'), '')
                    .trim();

                if (cleanName.isNotEmpty && cleanName.length > 2) {
                  final unknownNickname =
                      act.person?.rawInput.trim() ?? 'Beneficiary';
                  final newBeneficiary = Beneficiary(
                    id: 'ben_${DateTime.now().millisecondsSinceEpoch}',
                    nickname: unknownNickname,
                    legalName: cleanName,
                    relationship: 'Family',
                    destinationCountry: country,
                    countryFlag: flag,
                    currency: cur,
                    accountOrAddress: '0123456789 (Verified Bank)',
                    isVerified: true,
                  );
                  await contextService.addBeneficiary(newBeneficiary);
                  match = newBeneficiary;
                }
              }
            }

            if (match != null) {
              updatedActions.add(
                act.copyWith(
                  person: PersonEntity(
                    rawInput: match.legalName,
                    resolvedBeneficiary: match,
                    knowledgeState: EntityKnowledgeState.known,
                    aliasMatched: match.nickname,
                  ),
                  description:
                      'Send ${act.amount.formattedDisplay} to ${match.legalName} (${match.nickname})',
                ),
              );
            } else {
              // Cannot resolve: ask again
              final retryMsg = OperatorMessage.operator(
                'I still couldn\'t find a beneficiary matching "$answer". Please choose from your existing contacts or add them first.',
                clarification: prompt,
              );
              _session = _session.copyWith(
                messages: [..._session.messages, retryMsg],
              );
              notifyListeners();
              return;
            }
          } else if (prompt.field == 'destination' ||
              prompt.field == 'mission_destination') {
            // Resolve destination from answer: e.g. "Save it for taxes", "Put it in my USD savings"
            String destName = 'USD Savings';
            String purpose = 'savings';
            final lowerAns = answer.toLowerCase();
            if (lowerAns.contains('tax')) {
              destName = 'Tax Reserve';
              purpose = 'taxes';
            } else if (lowerAns.contains('emergency')) {
              destName = 'Emergency Fund';
              purpose = 'emergency';
            } else if (lowerAns.contains('create')) {
              destName = 'Tax Reserve';
              purpose = 'taxes';
            } else if (lowerAns.contains('wallet')) {
              destName = 'USD Wallet';
              purpose = 'spending';
            }

            final usdWallet =
                await contextService.getWalletForCurrency(Currency.usd);

            updatedActions.add(
              act.copyWith(
                destination: DestinationEntity(
                  type: DestinationType.reserve,
                  rawInput: destName,
                  resolvedWalletId: usdWallet?.id ?? 'sw_demo_usdb_01',
                  resolvedWalletName: destName,
                  resolvedCurrency: Currency.usd,
                  knowledgeState: EntityKnowledgeState.known,
                ),
                purpose: purpose,
                description: 'Reserve ${act.amount.formattedDisplay} in $destName',
              ),
            );
          } else if (prompt.field == 'amount') {
            final amtClean = answer.replaceAll(RegExp(r'[^0-9.]'), '');
            final money = Money.fromMajorString(amtClean, Currency.usd);
            updatedActions.add(
              act.copyWith(
                amount: AmountEntity(
                  rawInput: answer,
                  type: AmountType.fixed,
                  fixedAmount: money,
                  currency: Currency.usd,
                  knowledgeState: EntityKnowledgeState.known,
                ),
              ),
            );
          } else {
            updatedActions.add(act);
          }
        } else {
          updatedActions.add(act);
        }
      }

      final newIntent = intent.copyWith(actions: updatedActions);
      _session = _session.copyWith(
        activeIntent: newIntent,
        clearPendingClarification: true,
      );

      // Re-evaluate if any other actions need clarification
      final nextClarification =
          ClarificationEngine.evaluateClarification(newIntent);

      if (nextClarification != null) {
        final promptMsg = OperatorMessage.operator(
          'Got it. ${nextClarification.question}',
          clarification: nextClarification,
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.waitingForClarification,
          pendingClarification: nextClarification,
          messages: [..._session.messages, promptMsg],
        );
        notifyListeners();
        return;
      }

      // All clear! Compile the plan
      await _compileAndPresentPlan(newIntent);
    } catch (err) {
      final errorMsg = OperatorMessage.operator(
        'I encountered an error during clarification: $err. Please try again.',
        isError: true,
      );
      _session = _session.copyWith(
        status: OperatorSessionStatus.error,
        messages: [..._session.messages, errorMsg],
      );
      notifyListeners();
    }
  }

  /// Handle 1-tap clarification option selection
  Future<void> selectClarificationOption(
    ClarificationPrompt prompt,
    ClarificationOptionData option,
  ) async {
    // Treat the option value as the answer
    await processInput(option.value);
  }

  /// Resolve pending clarification with a concrete beneficiary (from modal or selection)
  Future<void> resolvePendingClarificationWithBeneficiary(
      Beneficiary beneficiary) async {
    final prompt = _session.pendingClarification;
    final intent = _session.activeIntent;
    if (prompt == null || intent == null) return;

    final updatedActions = <ActionIntent>[];
    for (final act in intent.actions) {
      if (act.id == prompt.targetActionId) {
        updatedActions.add(
          act.copyWith(
            person: PersonEntity(
              rawInput: beneficiary.legalName,
              resolvedBeneficiary: beneficiary,
              knowledgeState: EntityKnowledgeState.known,
              aliasMatched: beneficiary.nickname,
            ),
            description:
                'Send ${act.amount.formattedDisplay} to ${beneficiary.legalName} (${beneficiary.nickname})',
          ),
        );
      } else {
        updatedActions.add(act);
      }
    }

    final resolvedIntent = intent.copyWith(actions: updatedActions);
    _session = _session.copyWith(
      activeIntent: resolvedIntent,
      clearPendingClarification: true,
      status: OperatorSessionStatus.interpreting,
      messages: [
        ..._session.messages,
        OperatorMessage.user(
            'Beneficiary selected: ${beneficiary.legalName} (${beneficiary.nickname})'),
      ],
    );
    notifyListeners();

    await _compileAndPresentPlan(resolvedIntent);
  }

  /// Compile structured intent into a validated FinancialPlan and present for review
  Future<void> _compileAndPresentPlan(
    StructuredIntent intent, {
    Currency? overrideFundingCurrency,
  }) async {
    if (intent.primaryIntent == FinancialIntentType.createMission) {
      final act = intent.actions.first;
      final pct = act.amount.percentage ?? 20.0;
      final destName = act.destination?.resolvedWalletName ?? 'Tax Reserve';

      MissionRuntimeEngine().updateMissionTargetReserve('tax', destName);
      MissionRuntimeEngine().updateMissionPercentage('tax', pct);

      final replyMsg = OperatorMessage.operator(
        'I\'ve configured and activated your $destName Mission.\n'
        '• Trigger: USD inflow arrives\n'
        '• Action: Reserve ${pct.toStringAsFixed(0)}% to $destName\n'
        '• Status: ACTIVE\n\n'
        'You can modify this rule anytime (e.g., "Actually make it 25%" or "Pause my tax mission").',
      );

      _session = _session.copyWith(
        status: OperatorSessionStatus.idle,
        messages: [..._session.messages, replyMsg],
      );
      notifyListeners();
      return;
    }

    final plan = await _planner.createPlan(
      intent,
      overrideFundingCurrency: overrideFundingCurrency,
    );

    if (!plan.validation.isValid) {
      // Deterministic validation failed
      final errorBuffer = StringBuffer();
      errorBuffer.writeln('I cannot proceed with this plan because:');
      for (final err in plan.validation.errors) {
        errorBuffer.writeln('• $err');
      }
      final errorMsg = OperatorMessage.operator(
        errorBuffer.toString().trim(),
        isError: true,
      );
      _session = _session.copyWith(
        status: OperatorSessionStatus.error,
        activePlan: plan,
        clearPendingClarification: true,
        messages: [..._session.messages, errorMsg],
      );
      notifyListeners();
      return;
    }

    // Plan is valid! Present structured plan review
    final explanation = StringBuffer();
    if (plan.shortfall != null &&
        plan.shortfall!.minorUnits > 0 &&
        plan.selectedFundingCurrency != null) {
      explanation.writeln('I can make both payments.\n');
      explanation.writeln(
          'You currently have \$1,200.00 USD, but the two payments require ${plan.totalRequested.toFormattedString()} USD equivalent.\n');
      explanation.writeln(
          'I\'ll use the available \$1,200.00 USD, then convert the required amount from your ${plan.selectedFundingCurrency!.code} wallet to cover the remaining ${plan.shortfall!.toFormattedString()}.\n');
      for (final act in plan.actions) {
        if (act.destinationCurrency != null &&
            act.destinationAmount != null &&
            act.destinationCurrency != act.amount.currency) {
          explanation.writeln(
              '• ${act.destinationName}\n  ${act.amount.toFormattedString()} → ${act.destinationAmount!.toFormattedString()} (${act.destinationCurrency!.code}) → ${act.destinationRail ?? "Destination"}\n');
        } else {
          explanation.writeln(
              '• ${act.type.displayName} ${act.amount.toFormattedString()} to ${act.destinationName}\n');
        }
      }
      explanation.writeln('I\'ll show you the live exchange rates and fees before anything moves.\n');
      explanation.writeln('Review payment plan?');
    } else {
      explanation.writeln('Here\'s what I\'ll do:\n');
      for (int i = 0; i < plan.actions.length; i++) {
        final act = plan.actions[i];
        if (act.type == PlannedActionType.convert &&
            act.destinationAmount != null &&
            act.destinationCurrency != null) {
          explanation.writeln(
              '${i + 1}. Convert ${act.amount.toFormattedString()} from ${act.sourceWalletName} → ~${act.destinationAmount!.toFormattedString()} into ${act.destinationName} (${act.fxRate != null ? "Rate: ${act.fxRate}" : "Live FX"}).');
        } else if (act.destinationCurrency != null &&
            act.destinationAmount != null &&
            act.destinationCurrency != act.amount.currency) {
          explanation.writeln(
              '${i + 1}. ${act.destinationName}: ${act.amount.toFormattedString()} → ${act.destinationAmount!.toFormattedString()} (${act.destinationCurrency!.code})');
        } else {
          explanation.writeln(
              '${i + 1}. ${act.type.displayName} ${act.amount.toFormattedString()} to ${act.destinationName}.');
        }
      }
      explanation.writeln('\nReview and approve?');
    }

    FinancialPlan reviewPlan = plan;

    // If plan involves transfer actions, generate proposals for all send actions
    final sendActions = plan.actions.where((a) => a.type == PlannedActionType.send).toList();

    if (sendActions.isNotEmpty) {
      try {
        final wallets = await contextService.getWallets();
        final proposals = <TransferProposal>[];
        final updatedActions = <PlannedFinancialAction>[];

        for (final act in plan.actions) {
          if (act.type == PlannedActionType.send) {
            final resolvedRecipient = (act.destinationAddress != null && act.destinationAddress!.isNotEmpty)
                ? act.destinationAddress!
                : (act.destinationName.isNotEmpty ? act.destinationName : act.destinationId);

            final transferIntent = TransferIntent(
              intentId: 'tx_intent_${act.id}_${DateTime.now().millisecondsSinceEpoch}',
              originalPrompt: intent.originalPrompt,
              recipient: resolvedRecipient,
              amount: act.amount.toMajorString(),
              amountMinor: act.amount.amountMinor.toString(),
              currency: act.amount.currency,
              purpose: act.description,
              confidenceScore: 0.95,
              requiresExplicitApproval: true,
            );

            final inspection = await _transferRepo.inspectBalances(
              intent: transferIntent,
              wallets: wallets,
            );

            TransferFundingOption? fundingOption = inspection.recommendedFundingOption;
            if (overrideFundingCurrency != null) {
              fundingOption = inspection.allFundingOptions
                  .cast<TransferFundingOption?>()
                  .firstWhere(
                    (o) => o?.fundingCurrency == overrideFundingCurrency,
                    orElse: () => inspection.recommendedFundingOption,
                  );
            }

            if (fundingOption != null) {
              final proposal = await _transferRepo.createProposal(
                intent: transferIntent,
                fundingOption: fundingOption,
              );
              proposals.add(proposal);
              updatedActions.add(act.copyWith(proposalId: proposal.proposalId));
            } else {
              final matchingWallet = wallets.cast<WalletAccount?>().firstWhere(
                    (w) =>
                        w != null &&
                        w.balance.amountMinor >= act.amount.amountMinor,
                    orElse: () => null,
                  );
              if (matchingWallet != null) {
                final fallbackOption = TransferFundingOption(
                  fundingWalletId: matchingWallet.id,
                  fundingCurrency: matchingWallet.currency,
                  fundingWalletName: '${matchingWallet.currency.code} Smart Wallet',
                  availableBalance: matchingWallet.balance,
                  requiresConversion: false,
                  conversionLabel: 'Direct ${matchingWallet.currency.code} Transfer',
                  exchangeRate: 1.0,
                  convertedDebit: act.amount,
                  networkFee: Money.fromMinor(BigInt.from(50), matchingWallet.currency),
                  fxFee: Money.zero(matchingWallet.currency),
                  totalDebit: act.amount,
                  targetPayment: act.amount,
                );
                final proposal = await _transferRepo.createProposal(
                  intent: transferIntent,
                  fundingOption: fallbackOption,
                );
                proposals.add(proposal);
                updatedActions.add(act.copyWith(proposalId: proposal.proposalId));
              } else {
                updatedActions.add(act);
              }
            }
          } else {
            updatedActions.add(act);
          }
        }

        final primaryProposal = proposals.isNotEmpty ? proposals.first : null;
        final hashToSign = primaryProposal != null
            ? primaryProposal.hashToSign
            : '0x${sha256.convert(utf8.encode(reviewPlan.planId)).toString()}';

        reviewPlan = plan.copyWith(
          actions: updatedActions,
          proposalId: primaryProposal?.proposalId,
          hashToSign: hashToSign,
          transferProposal: primaryProposal,
          transferProposals: proposals,
        );
      } catch (err) {
        final errorMsg = OperatorMessage.operator(
          'Failed to generate transfer proposal: $err',
          isError: true,
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.error,
          messages: [..._session.messages, errorMsg],
        );
        notifyListeners();
        return;
      }
    }

    final planMsg = OperatorMessage.operator(
      explanation.toString().trim(),
      plan: reviewPlan,
    );

    _session = _session.copyWith(
      status: OperatorSessionStatus.readyForReview,
      activePlan: reviewPlan,
      clearPendingClarification: true,
      messages: [..._session.messages, planMsg],
    );
    notifyListeners();
  }

  /// Handle structured balance target / wallet balancing command
  Future<void> _handleWalletBalancing(String text) async {
    final parsed = FinancialIntentEngine.parse(text);
    final amount = parsed.actions.isNotEmpty && parsed.actions.first.amount.fixedAmount != null
        ? parsed.actions.first.amount.fixedAmount!
        : Money.fromMajorString('2000.00', Currency.usd);

    final balancer = WalletBalancer(
      executionProvider: DemoExecutionProvider(
        walletRepo: contextService.walletRepo,
        activityRepo: contextService.activityRepo,
      ),
    );

    final target = BalanceTarget(
      currency: amount.currency,
      minimumAmount: amount,
      purpose: 'Smart Wallet Balancing',
    );

    final proposal = await balancer.evaluateTarget(target);

    if (!proposal.isExecutable) {
      final msg = OperatorMessage.operator(
        proposal.explanation,
        isError: proposal.rejectionReason != null && !proposal.rejectionReason!.contains('already has'),
      );
      _session = _session.copyWith(
        status: OperatorSessionStatus.idle,
        messages: [..._session.messages, msg],
      );
      notifyListeners();
      return;
    }

    final plan = FinancialPlan(
      planId: 'plan_balance_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Top Up ${target.currency.code} to ${amount.toFormattedString()}',
      summary: proposal.explanation,
      actions: [
        PlannedFinancialAction(
          id: 'act_balance_1',
          type: PlannedActionType.convert,
          amount: proposal.requiredSourceAmount,
          sourceWalletId: 'sw_demo_${proposal.fundingCurrency.stablecoinToken.toLowerCase()}_05',
          sourceWalletName: '${proposal.fundingCurrency.code} Smart Wallet',
          destinationId: 'sw_demo_${target.currency.stablecoinToken.toLowerCase()}_01',
          destinationName: '${target.currency.code} Smart Wallet',
          destinationType: 'wallet',
          description:
              'Convert ${proposal.requiredSourceAmount.toFormattedString()} to ${proposal.shortfall.toFormattedString()}',
          fxRate: proposal.quote.formattedRate,
          fee: proposal.quote.providerFee.add(proposal.quote.networkFee),
          destinationAmount: proposal.shortfall,
          destinationCurrency: target.currency,
          fundingCurrency: proposal.fundingCurrency,
        ),
      ],
      totalDebit: proposal.requiredSourceAmount,
      totalFee: proposal.quote.providerFee.add(proposal.quote.networkFee),
      expectedBalanceChanges: [
        BalanceImpact(
          walletId: 'target_wallet',
          walletName: '${target.currency.code} Smart Wallet',
          currency: target.currency,
          currentBalance: proposal.currentBalance,
          projectedBalance: amount,
          delta: proposal.shortfall,
        ),
      ],
      validation: const PlanValidationResult(isValid: true),
      createdAt: DateTime.now(),
      routeExplanation: proposal.explanation,
      selectedFundingCurrency: proposal.fundingCurrency,
      quoteExpiresAt: proposal.quote.expiresAt,
      shortfall: proposal.shortfall,
    );

    final planMsg = OperatorMessage.operator(
      '${proposal.explanation}\n\nReview and approve balancing plan?',
      plan: plan,
    );

    _session = _session.copyWith(
      status: OperatorSessionStatus.readyForReview,
      activePlan: plan,
      clearPendingClarification: true,
      messages: [..._session.messages, planMsg],
    );
    notifyListeners();
  }

  /// Approve plan and trigger on-device PIN execution
  Future<void> approveAndExecute({
    String? signature,
    String? pin,
  }) async {
    if (_session.activePlan == null || !_session.activePlan!.validation.isValid) {
      return;
    }

    final plan = _session.activePlan!;

    // Live Stellar plans settle as ONE transaction that the user signs inside
    // _executeAtomically — that signature is the approval. Signing a separate plan
    // hash first would just ask for the PIN / passkey again.
    if (executionProvider.settlesAtomically) {
      if (pin == null) {
        _session = _session.copyWith(
          status: OperatorSessionStatus.error,
          messages: [..._session.messages, OperatorMessage.operator('Execution aborted: confirmation on this device is required.', isError: true)],
        );
        notifyListeners();
        return;
      }
      _session = _session.copyWith(status: OperatorSessionStatus.executing);
      notifyListeners();
      await _executeAtomically(plan, pin: pin);
      return;
    }

    // Resolve signature: either provided directly from WalletPinAuthSheet or signed via PIN
    String? resolvedSignature = signature;
    if (resolvedSignature == null && pin != null) {
      final hashToSign = plan.hashToSign ??
          '0x${sha256.convert(utf8.encode(plan.planId)).toString()}';
      try {
        resolvedSignature = await const StellarWalletSigner().signTransactionHash(
          hashToSign,
          pin: pin,
        );
      } catch (e) {
        final errorMsg = OperatorMessage.operator(
          'Authorization failed: $e',
          isError: true,
        );
        _session = _session.copyWith(
          status: OperatorSessionStatus.error,
          messages: [..._session.messages, errorMsg],
        );
        notifyListeners();
        return;
      }
    }

    if (resolvedSignature == null || resolvedSignature.isEmpty) {
      final errorMsg = OperatorMessage.operator(
        'Execution aborted: Valid on-device signature is required.',
        isError: true,
      );
      _session = _session.copyWith(
        status: OperatorSessionStatus.error,
        messages: [..._session.messages, errorMsg],
      );
      notifyListeners();
      return;
    }

    _session = _session.copyWith(status: OperatorSessionStatus.executing);
    notifyListeners();

    try {
      final updatedActions = <PlannedFinancialAction>[];
      final executionHashes = <String>[];
      bool anyFailed = false;

      // Execute all actions in the batch independently
      for (final act in plan.actions) {
        if (act.type == PlannedActionType.send) {
          TransferProposal? matchingProposal = plan.transferProposals
              .cast<TransferProposal?>()
              .firstWhere(
                (p) => p?.proposalId == act.proposalId,
                orElse: () => null,
              );
          matchingProposal ??= plan.transferProposal;

          try {
            String txHash = '';
            if (matchingProposal != null) {
              final exec = await _transferRepo.executeProposal(
                proposalId: matchingProposal.proposalId,
                signature: resolvedSignature,
                proposal: matchingProposal,
              );
              txHash = exec.transactionHash;
            } else {
              throw Exception('Cannot execute send action ${act.id}: missing transfer proposal');
            }

            executionHashes.add(txHash);

            // Note: _transferRepo.executeProposal already debits the sender's funding wallet
            // (via backend TransferService.executeTransfer and DemoTransferRepository).
            // Do NOT call contextService.walletRepo.debitWallet here as it causes double-debit.

            // Record activity for this transfer
            try {
              final activity = ActivityModel(
                id: 'act_${act.id}_${DateTime.now().millisecondsSinceEpoch}',
                title: 'Send ${act.amount.toFormattedString()} to ${act.destinationName}',
                description: 'Transferred ${act.amount.toFormattedString()} to ${act.destinationName}',
                amount: act.amount,
                currency: act.amount.currency,
                type: ActivityType.transfer,
                category: ActivityCategory.transfer,
                status: FlowPayAppStatus.completed,
                timestamp: DateTime.now(),
                reference: txHash,
              );
              await contextService.activityRepo?.recordActivity(activity);
            } catch (_) {}

            updatedActions.add(act.copyWith(
              status: 'COMPLETED',
              txHash: txHash,
            ));
          } catch (err) {
            anyFailed = true;
            try {
              final activity = ActivityModel(
                id: 'act_fail_${act.id}_${DateTime.now().millisecondsSinceEpoch}',
                title: 'Failed Transfer to ${act.destinationName}',
                description: 'Failed: $err',
                amount: act.amount,
                currency: act.amount.currency,
                type: ActivityType.transfer,
                category: ActivityCategory.transfer,
                status: FlowPayAppStatus.failed,
                timestamp: DateTime.now(),
              );
              await contextService.activityRepo?.recordActivity(activity);
            } catch (_) {}

            updatedActions.add(act.copyWith(
              status: 'FAILED',
              executionError: err.toString(),
            ));
          }
        } else {
          // Non-transfer action (reserve, conversion, mission, allocation)
          try {
            final execRes = await executionProvider.executePlan(
              plan.copyWith(actions: [act]),
              pin: pin ?? '000000',
            );
            if (execRes.success) {
              executionHashes.add(execRes.txHash);
              updatedActions.add(act.copyWith(
                status: 'COMPLETED',
                txHash: execRes.txHash,
              ));
            } else {
              anyFailed = true;
              updatedActions.add(act.copyWith(
                status: 'FAILED',
                executionError: execRes.errorMessage ?? 'Execution failed',
              ));
            }
          } catch (err) {
            anyFailed = true;
            updatedActions.add(act.copyWith(
              status: 'FAILED',
              executionError: err.toString(),
            ));
          }
        }
      }

      final combinedTxHash =
          executionHashes.isNotEmpty ? executionHashes.first : '';
      final finalExecutionState = anyFailed
          ? (updatedActions.every((a) => a.status == 'FAILED')
              ? 'FAILED'
              : 'PARTIAL_COMPLETION')
          : 'COMPLETED';

      final completedPlan = plan.copyWith(
        isApproved: true,
        executionState: finalExecutionState,
        txHash: combinedTxHash,
        actions: updatedActions,
      );

      final statusLines = updatedActions
          .map((a) => '• ${a.destinationName} (${a.amount.toFormattedString()}): ${a.status}')
          .join('\n');

      final successMsg = OperatorMessage.operator(
        finalExecutionState == 'COMPLETED'
            ? 'Execution completed successfully!\n$statusLines'
            : 'Execution finished with partial status:\n$statusLines',
        plan: completedPlan,
        executionReceipt: {
          'txHash': combinedTxHash,
          'timestamp': DateTime.now().toIso8601String(),
          'totalDebit': plan.totalDebit.toFormattedString(),
          'actionsCount': plan.actions.length,
          'actions': updatedActions
              .map((a) => {
                    'name': a.destinationName,
                    'status': a.status,
                    'amount': a.amount.toFormattedString()
                  })
              .toList(),
        },
      );

      _session = _session.copyWith(
        status: finalExecutionState == 'COMPLETED'
            ? OperatorSessionStatus.completed
            : OperatorSessionStatus.error,
        activePlan: completedPlan,
        messages: [..._session.messages, successMsg],
      );
    } catch (err) {
      final errorMsg = OperatorMessage.operator(
        'Execution encountered an unexpected error: $err',
        isError: true,
      );
      _session = _session.copyWith(
        status: OperatorSessionStatus.error,
        messages: [..._session.messages, errorMsg],
      );
    }
    notifyListeners();
  }

  /// Live path: the whole plan settles as ONE transaction, so every action shares
  /// the same outcome and hash. Nothing is recorded as done unless it settled.
  Future<void> _executeAtomically(FinancialPlan plan, {String? pin}) async {
    if (pin == null) {
      _session = _session.copyWith(
        status: OperatorSessionStatus.error,
        messages: [..._session.messages, OperatorMessage.operator('Your PIN is required to approve this plan.', isError: true)],
      );
      notifyListeners();
      return;
    }
    ExecutionResult result;
    try {
      result = await executionProvider.executePlan(plan, pin: pin);
    } catch (err) {
      result = ExecutionResult.failed(plan.planId, err.toString());
    }

    final pending = result.details['status'] == 'PENDING';
    final actionStatus = !result.success ? 'FAILED' : (pending ? 'PENDING' : 'COMPLETED');
    final updatedActions = [
      for (final a in plan.actions)
        a.copyWith(status: actionStatus, txHash: result.success ? result.txHash : null, executionError: result.errorMessage),
    ];
    final completedPlan = plan.copyWith(
      isApproved: result.success,
      executionState: actionStatus,
      txHash: result.txHash,
      actions: updatedActions,
    );
    final text = !result.success
        ? 'Nothing was sent — the plan did not settle.\n${result.errorMessage}'
        : pending
            ? 'Submitted to Stellar. Waiting for the network to confirm (tx ${result.txHash.substring(0, 8)}…).'
            : 'Done. Every action settled together in one Stellar transaction (tx ${result.txHash.substring(0, 8)}…).';
    _session = _session.copyWith(
      status: result.success ? OperatorSessionStatus.completed : OperatorSessionStatus.error,
      activePlan: completedPlan,
      messages: [
        ..._session.messages,
        OperatorMessage.operator(
          text,
          isError: !result.success,
          plan: completedPlan,
          executionReceipt: result.success
              ? {
                  'txHash': result.txHash,
                  'explorerUrl': result.details['explorerUrl'],
                  'timestamp': result.timestamp.toIso8601String(),
                  'totalDebit': plan.totalDebit.toFormattedString(),
                  'actionsCount': plan.actions.length,
                  'status': actionStatus,
                }
              : null,
        ),
      ],
    );
    notifyListeners();
  }

  /// Cancel current active session
  void cancelSession() {
    final cancelMsg = OperatorMessage.operator('Operation cancelled.');
    _session = _session.copyWith(
      status: OperatorSessionStatus.rejected,
      messages: [..._session.messages, cancelMsg],
      clearPendingClarification: true,
    );
    notifyListeners();
  }

  Future<void> _handleBalanceCheck() async {
    final wallets = await contextService.getWallets();
    final buffer = StringBuffer();
    buffer.writeln('Here are your current verified balances:');
    for (final w in wallets) {
      buffer.writeln('• ${w.currency.code}: ${w.balance.toFormattedString()} (${w.stablecoinToken})');
    }
    final msg = OperatorMessage.operator(buffer.toString().trim());
    _session = _session.copyWith(
      status: OperatorSessionStatus.idle,
      messages: [..._session.messages, msg],
    );
    notifyListeners();
  }

  Future<void> _handleTransactionCheck() async {
    final txs = await contextService.getTransactions();
    final buffer = StringBuffer();
    if (txs.isEmpty) {
      buffer.writeln('No recent transactions found in your activity ledger.');
    } else {
      buffer.writeln('Here is your recent activity:');
      for (final tx in txs.take(4)) {
        buffer.writeln(
            '• ${tx.title} — ${tx.amount?.toFormattedString() ?? ''}');
      }
    }
    final msg = OperatorMessage.operator(buffer.toString().trim());
    _session = _session.copyWith(
      status: OperatorSessionStatus.idle,
      messages: [..._session.messages, msg],
    );
    notifyListeners();
  }

  static String _extractBeneficiaryName(String answer) {
    // Clean strings like "She's Mary from Nigeria" or "Mary, my Nigerian beneficiary"
    String text = answer;
    text = text.replaceFirst(RegExp(r'^(?:she(?: is|\x27s)|he(?: is|\x27s)|it(?: is|\x27s)|that(?: is|\x27s))\s+', caseSensitive: false), '');
    final commaSplit = text.split(RegExp(r'[,;]|\s+from\s+|\s+my\s+'));
    return commaSplit.first.trim();
  }
}
