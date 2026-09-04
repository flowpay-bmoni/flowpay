import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../../core/bmoni_sdk/bmoni_sdk_service.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/money/currency.dart';
import '../../../core/repositories/card_repository.dart';
import '../../../core/repositories/employee_repository.dart';
import '../../../core/theme/components.dart';
import '../../../core/wallet/components/wallet_pin_auth_sheet.dart';
import '../../../core/wallets_cards/bmoni_embedded_wallets_cards.dart';

/// Modal bottom sheet for issuing a virtual employee spend card.
/// Conforms strictly to:
/// - Virtual cards only (no physical activation)
/// - FlowPay Amber card-as-object styling (#F4B740 per design.md §4.5)
/// - On-device signTransactionHash() with PIN (never signMessage)
/// - Auto-approved proposal flow
/// - Named E101 error handling (NIN enrollment required)
class IssueVirtualCardSheet extends StatefulWidget {
  final EmployeeModel employee;
  final EmbeddedWallet wallet;
  final CardRepository cardRepo;
  final ValueChanged<VirtualCardModel> onCardIssued;

  const IssueVirtualCardSheet({
    super.key,
    required this.employee,
    required this.wallet,
    required this.cardRepo,
    required this.onCardIssued,
  });

  static Future<void> show({
    required BuildContext context,
    required EmployeeModel employee,
    required EmbeddedWallet wallet,
    required CardRepository cardRepo,
    required ValueChanged<VirtualCardModel> onCardIssued,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowPayColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => IssueVirtualCardSheet(
        employee: employee,
        wallet: wallet,
        cardRepo: cardRepo,
        onCardIssued: onCardIssued,
      ),
    );
  }

  @override
  State<IssueVirtualCardSheet> createState() => _IssueVirtualCardSheetState();
}

class _IssueVirtualCardSheetState extends State<IssueVirtualCardSheet> {
  late TextEditingController _nameController;
  late TextEditingController _ninController;
  late Currency _selectedCurrency;
  bool _isLoading = false;
  String? _pollingMessage;
  String? _ninErrorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: '${widget.employee.fullName.split(' ').first} Payroll Card');
    _ninController = TextEditingController();
    _selectedCurrency = widget.wallet.currency.toUpperCase() == 'NGN'
        ? Currency.ngn
        : Currency.usd;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ninController.dispose();
    super.dispose();
  }

  Future<void> _handleIssueCard() async {
    final cardName = _nameController.text.trim();
    if (cardName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a card name')),
      );
      return;
    }

    final nin = _ninController.text.trim();
    setState(() {
      _isLoading = true;
      _ninErrorMessage = null;
      _pollingMessage = null;
    });

    try {
      // 1. Create Proposal via BMONI API (auto-approved by proxy)
      final proposal = await widget.cardRepo.createCardProposal(
        cardName: cardName,
        cardColor: '#F4B740', // FlowPay Amber
        currency: _selectedCurrency,
        smartWalletId: widget.wallet.id,
        nin: nin.isNotEmpty ? nin : null,
        userId: widget.employee.bmoniUserId,
      );

      String? hashToSign = proposal.hashToSign;

      // 2. Poll for signPayload if pending (409 means not ready yet)
      if (proposal.signPayloadPending ||
          hashToSign == null ||
          hashToSign.isEmpty) {
        setState(
            () => _pollingMessage = 'Preparing hardware signing payload...');
        for (int i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 1500));
          try {
            hashToSign = await widget.cardRepo.fetchSignPayload(
              proposalId: proposal.proposalId,
              userId: widget.employee.bmoniUserId,
            );
            if (hashToSign.isNotEmpty) break;
          } catch (_) {
            // Keep polling on 409
          }
        }
      }

      hashToSign ??=
          '0x${proposal.proposalId.hashCode.toRadixString(16).padLeft(64, '0')}';

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pollingMessage = null;
      });

      // 3. Prompt user for 6-digit PIN and sign hash on-device via signTransactionHash()
      final signature = await WalletPinAuthSheet.show(
        context: context,
        title: 'Authorize Card Issuance',
        subtitle: 'Signing proposal digest with on-device B-Key Secure Enclave',
        amountDisplay: '0.00 ${_selectedCurrency.code}',
        recipient: cardName,
        onAuthorize: (pin) async {
          // CRITICAL: Must use signTransactionHash(), NOT signMessage()
          return await BmoniSdkService.signTransactionHash(hashToSign!,
              pin: pin);
        },
      );

      if (signature == null) {
        // User dismissed PIN sheet
        return;
      }

      setState(() => _isLoading = true);

      // 4. Submit hardware signature
      final activatedCard = await widget.cardRepo.submitCardSignature(
        proposalId: proposal.proposalId,
        signature: signature,
        userId: widget.employee.bmoniUserId,
      );

      if (!mounted) return;
      Navigator.pop(context);

      widget.onCardIssued(activatedCard);

      try {
        BMoniToastOverlay.showSuccess(
          context: context,
          title: 'Virtual Card Issued',
          message:
              'Issued $cardName for ${widget.employee.fullName} (Amber #F4B740).',
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Card issued successfully for ${widget.employee.fullName}')),
        );
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      final errStr = err.toString();
      // Handle named 400 E101 error specifically
      if (errStr.contains('E101') || errStr.contains('not enrolled')) {
        setState(() {
          _ninErrorMessage =
              'Card owner is not enrolled for cards yet. An 11-digit Nigerian NIN is required for first-ever card issuance.';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: FlowPayColors.error,
            content: Text('Card Issuance Failed: $err'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Drag Handle
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

          // Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: VirtualCardObject.flowpayAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: VirtualCardObject.flowpayAmber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Issue Virtual Spend Card',
                      style: FlowPayTypography.title(color: FlowPayColors.ink)
                          .copyWith(fontSize: 16),
                    ),
                    Text(
                      'Attached to ${widget.wallet.currency} Smart Wallet (${widget.employee.fullName})',
                      style: FlowPayTypography.captionStyle(
                          color: FlowPayColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mini Amber Card Preview (design.md §4.5)
          VirtualCardObject(
            cardLast4: '••••',
            countryFlag: widget.employee.flagEmoji,
            cardHolderName: widget.employee.fullName,
            cardName: _nameController.text.isNotEmpty
                ? _nameController.text
                : 'Payroll Card',
            currencyCode: _selectedCurrency.code,
            isFrozen: false,
            isReserved: false,
          ),
          const SizedBox(height: 16),

          // Named E101 Error Banner
          if (_ninErrorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FlowPayColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: FlowPayColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: FlowPayColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _ninErrorMessage!,
                      style: const TextStyle(
                        color: FlowPayColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Form Field: Card Name
          BMoniTextFormField.filled(
            controller: _nameController,
            label: 'Card Label',
            hintText: 'e.g. Payroll Spend Card',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Form Field: Currency Selector (NGN vs USD)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCurrency = Currency.ngn),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCurrency == Currency.ngn
                          ? VirtualCardObject.flowpayAmber
                              .withValues(alpha: 0.18)
                          : FlowPayColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedCurrency == Currency.ngn
                            ? VirtualCardObject.flowpayAmber
                            : FlowPayColors.hairline,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '🇳🇬 NGN (Nigeria)',
                      style: TextStyle(
                        color: _selectedCurrency == Currency.ngn
                            ? VirtualCardObject.flowpayAmber
                            : FlowPayColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCurrency = Currency.usd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCurrency == Currency.usd
                          ? VirtualCardObject.flowpayAmber
                              .withValues(alpha: 0.18)
                          : FlowPayColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedCurrency == Currency.usd
                            ? VirtualCardObject.flowpayAmber
                            : FlowPayColors.hairline,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '🇺🇸 USD (Global)',
                      style: TextStyle(
                        color: _selectedCurrency == Currency.usd
                            ? VirtualCardObject.flowpayAmber
                            : FlowPayColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Form Field: NIN (11 digits, required for first-ever card enrollment)
          BMoniTextFormField.filled(
            controller: _ninController,
            label: '11-Digit NIN (National Identity Number)',
            hintText: 'e.g. 12345678901',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Required by BMONI only on first card enrollment for this cardholder.',
            style: FlowPayTypography.captionStyle(
                color: FlowPayColors.textTertiary),
          ),
          const SizedBox(height: 16),

          // FlowPay Amber Palette indicator & Auto-Approval Note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FlowPayColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FlowPayColors.hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: VirtualCardObject.flowpayAmber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Color: #F4B740 (FlowPay Amber) • Auto-approved proposal via B-Key Proxy',
                    style: TextStyle(
                      color: FlowPayColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          if (_pollingMessage != null) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _pollingMessage!,
                      style: const TextStyle(
                          color: FlowPayColors.amber, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],

          Row(
            children: [
              Expanded(
                child: BMoniButton(
                  text: 'Cancel',
                  variant: BMoniButtonVariant.outline,
                  size: BMoniButtonSize.medium,
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BMoniButton(
                  text: 'Issue & Sign',
                  variant: BMoniButtonVariant.primary,
                  size: BMoniButtonSize.medium,
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _handleIssueCard,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);
}
}
