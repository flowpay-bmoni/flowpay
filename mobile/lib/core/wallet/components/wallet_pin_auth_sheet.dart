import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../bmoni_sdk/bmoni_sdk_service.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/typography.dart';
import '../wallet_signer.dart';

/// Modal bottom sheet for on-device B-Key PIN signing authorization.
///
/// Features:
/// 1. Prominently reassures: "Your FlowPay wallet is secured on this device."
/// 2. Interactive 6-digit PIN pad with masked dots.
/// 3. Immediate feedback on incorrect PIN (`BmoniSignerErrorCode.pinMismatch`).
/// 4. Handles user cancellation cleanly without leaving hanging state.
/// 5. Never logs or persists the entered PIN.
class WalletPinAuthSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? amountDisplay;
  final String? recipient;
  final Future<String> Function(String pin) onAuthorize;

  const WalletPinAuthSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.amountDisplay,
    this.recipient,
    required this.onAuthorize,
  });

  /// Displays the interactive PIN authorization sheet.
  /// Returns the signature string on success, or throws [SigningCancelledException] if dismissed.
  static Future<String?> show({
    required BuildContext context,
    required String title,
    String? subtitle,
    String? amountDisplay,
    String? recipient,
    required Future<String> Function(String pin) onAuthorize,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WalletPinAuthSheet(
        title: title,
        subtitle: subtitle,
        amountDisplay: amountDisplay,
        recipient: recipient,
        onAuthorize: onAuthorize,
      ),
    );
  }

  @override
  State<WalletPinAuthSheet> createState() => _WalletPinAuthSheetState();
}

class _WalletPinAuthSheetState extends State<WalletPinAuthSheet> {
  String _pin = '';
  bool _isAuthorizing = false;
  String? _errorMessage;
  int _failedAttempts = 0;

  void _onDigitTapped(String digit) {
    if (_isAuthorizing) return;
    if (_pin.length >= 6) return;

    setState(() {
      _errorMessage = null;
      _pin += digit;
    });

    if (_pin.length == 6) {
      _submitPin();
    }
  }

  void _onBackspace() {
    if (_isAuthorizing) return;
    if (_pin.isEmpty) return;

    setState(() {
      _errorMessage = null;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  Future<void> _submitPin() async {
    setState(() {
      _isAuthorizing = true;
      _errorMessage = null;
    });

    try {
      // Verify against on-device PIN store first
      final isValid = await BmoniSdkService.matchPin(_pin);
      if (!isValid) {
        _failedAttempts++;
        if (mounted) {
          setState(() {
            _isAuthorizing = false;
            _errorMessage =
                'Incorrect PIN ($_failedAttempts/5 attempts). Please try again.';
            _pin = '';
          });
        }
        return;
      }

      // Execute on-device signing callback
      final signature = await widget.onAuthorize(_pin);

      if (mounted) {
        Navigator.of(context).pop(signature);
      }
    } on BmoniSignerException catch (e) {
      _failedAttempts++;
      if (mounted) {
        setState(() {
          _isAuthorizing = false;
          _errorMessage = e.errorCode == BmoniSignerErrorCode.pinMismatch
              ? 'Incorrect PIN. Please re-enter.'
              : e.message;
          _pin = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthorizing = false;
          _errorMessage = 'Signing error: $e';
          _pin = '';
        });
      }
    }
  }

  void _cancelSigning() {
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: isDark ? FlowPayColors.canvas : BMoniColors.grey50,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: FlowPayColors.hairline),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: FlowPayColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header with Cancel button
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: FlowPayTypography.title(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('wallet_pin_cancel_button'),
                icon:
                    const Icon(Icons.close, color: FlowPayColors.textSecondary),
                onPressed: _cancelSigning,
                tooltip: 'Cancel Signing',
              ),
            ],
          ),

          // Operation Details card (if present)
          if (widget.amountDisplay != null || widget.recipient != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: FlowPayColors.surfaceAlt,
                borderRadius: FlowPayRadii.card,
                border: Border.all(color: FlowPayColors.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock,
                      size: 20, color: FlowPayColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.amountDisplay != null)
                          Text(
                            widget.amountDisplay!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: FlowPayColors.ink,
                            ),
                          ),
                        if (widget.recipient != null)
                          Text(
                            'To: ${widget.recipient!}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: FlowPayColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Trust Reassurance Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FlowPayColors.primary.withAlpha(20),
              borderRadius: FlowPayRadii.chip,
              border: Border.all(color: FlowPayColors.primary.withAlpha(50)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined,
                    size: 16, color: FlowPayColors.primary),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Your FlowPay wallet is secured on this device.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: FlowPayColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 6 PIN Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              final isFilled = index < _pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? FlowPayColors.primary : Colors.transparent,
                  border: Border.all(
                    color: _errorMessage != null
                        ? FlowPayColors.stateError
                        : isFilled
                            ? FlowPayColors.primary
                            : FlowPayColors.hairline,
                    width: 2,
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 12),

          // Error banner
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: FlowPayColors.stateError.withAlpha(25),
                borderRadius: FlowPayRadii.chip,
                border: Border.all(color: FlowPayColors.stateError),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FlowPayColors.stateError,
                ),
              ),
            ),

          if (_isAuthorizing) ...[
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: FlowPayColors.primary),
            const SizedBox(height: 12),
            const Text(
              'Signing on-device with B-Key Secure Enclave...',
              style:
                  TextStyle(fontSize: 12, color: FlowPayColors.textSecondary),
            ),
            const SizedBox(height: 32),
          ] else ...[
            const SizedBox(height: 16),
            _buildKeypad(),
          ],
        ],
      ),
    ),
  ),
);
}

  Widget _buildKeypad() {
    return Column(
      children: [
        for (var row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ]) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row
                .map((d) => _buildKey(d, onTap: () => _onDigitTapped(d)))
                .toList(),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 64, height: 64),
            _buildKey('0', onTap: () => _onDigitTapped('0')),
            _buildBackspaceKey(),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(String label, {required VoidCallback onTap}) {
    return InkResponse(
      key: Key('pin_key_$label'),
      onTap: onTap,
      radius: 32,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: FlowPayColors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: FlowPayColors.hairline),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: FlowPayColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return InkResponse(
      key: const Key('pin_key_backspace'),
      onTap: _onBackspace,
      radius: 32,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: FlowPayColors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: FlowPayColors.hairline),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.backspace_outlined,
          color: FlowPayColors.ink,
          size: 20,
        ),
      ),
    );
  }
}
