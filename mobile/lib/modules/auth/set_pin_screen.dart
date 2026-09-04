import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/account_capabilities.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/bmoni_sdk/bmoni_sdk_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/components.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';

/// Dedicated 6-Digit PIN Setup Screen.
/// Step 3 of the Onboarding Flow: Signup -> KYC -> Set PIN.
/// Conforms to official BMONI Embedded SDK guidelines:
/// 1. Asks user to enter and confirm 6-digit PIN.
/// 2. Provisions on-device wallet keypair via `BmoniSdkService.initWallet()`.
/// 3. Stores salted PBKDF2 digest in secure hardware storage via `BmoniSdkService.setPin()`.
class SetPinScreen extends ConsumerStatefulWidget {
  final UserProfile userProfile;

  const SetPinScreen({
    super.key,
    required this.userProfile,
  });

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  String _initialPin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _isSettingUp = false;
  String? _errorMessage;

  void _onDigitTapped(String digit) {
    if (_isSettingUp) return;

    setState(() {
      _errorMessage = null;
      if (!_isConfirming) {
        if (_initialPin.length < 6) {
          _initialPin += digit;
          if (_initialPin.length == 6) {
            // Transition to confirmation stage
            Future.delayed(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _isConfirming = true);
            });
          }
        }
      } else {
        if (_confirmPin.length < 6) {
          _confirmPin += digit;
          if (_confirmPin.length == 6) {
            _validateAndComplete();
          }
        }
      }
    });
  }

  void _onBackspace() {
    if (_isSettingUp) return;

    setState(() {
      _errorMessage = null;
      if (!_isConfirming) {
        if (_initialPin.isNotEmpty) {
          _initialPin = _initialPin.substring(0, _initialPin.length - 1);
        }
      } else {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        } else {
          // Go back to stage 1 if user hits backspace on empty confirm
          _isConfirming = false;
          _initialPin = '';
        }
      }
    });
  }

  Future<void> _validateAndComplete() async {
    if (_initialPin != _confirmPin) {
      setState(() {
        _errorMessage = 'PINs do not match. Please try again.';
        _confirmPin = '';
        _initialPin = '';
        _isConfirming = false;
      });
      return;
    }

    setState(() => _isSettingUp = true);

    try {
      // 1. Provision hardware keypair on device via BMONI Embedded SDK
      await BmoniSdkService.initWallet();

      // 2. Set 6-digit PIN in BMONI SDK (salted PBKDF2 digest in Secure Storage)
      await BmoniSdkService.setPin(_initialPin);

      // 3. Store fallback PIN and establish active user session
      final storage = ref.read(secureStorageServiceProvider);
      await storage.setFallbackPin(_initialPin);

      if (!mounted) return;
      // Log in user and unlock into corresponding shell
      await ref
          .read(appLockStateProvider.notifier)
          .loginAsPersona(widget.userProfile, pin: _initialPin);

      if (!mounted) return;
      // Pop back to root (AppAuthGate will render the unlocked shell)
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSettingUp = false;
          _errorMessage = 'Failed to configure PIN: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePin = _isConfirming ? _confirmPin : _initialPin;

    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: FlowPayColors.ink),
          onPressed: () {
            if (_isConfirming) {
              setState(() {
                _isConfirming = false;
                _confirmPin = '';
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: const PoweredByBmoniBadge(),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),

                        // Hero Security Icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: FlowPayColors.surfaceAlt,
                            borderRadius: FlowPayRadii.card,
                            border: Border.all(color: FlowPayColors.hairline),
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            size: 32,
                            color: FlowPayColors.primary,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title & Instructions
                        Text(
                          _isConfirming
                              ? 'Confirm Your 6-Digit PIN'
                              : 'Set Your 6-Digit PIN',
                          style: FlowPayTypography.headline(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isConfirming
                              ? 'Re-enter your 6-digit PIN to verify and encrypt your B-Key signer.'
                              : 'This PIN authorizes transfers, payroll disbursements, and unlocks FlowPay.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: FlowPayColors.textSecondary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 32),

                        // 6 PIN Dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            final isFilled = index < activePin.length;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFilled
                                    ? FlowPayColors.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isFilled
                                      ? FlowPayColors.primary
                                      : FlowPayColors.hairline,
                                  width: 2,
                                ),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 16),

                        // Error banner
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: FlowPayColors.stateError.withAlpha(30),
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

                        if (_isSettingUp) ...[
                          const Spacer(),
                          const CircularProgressIndicator(
                              color: FlowPayColors.primary),
                          const SizedBox(height: 12),
                          const Text(
                            'Provisioning B-Key hardware keypair...',
                            style: TextStyle(
                                fontSize: 13, color: FlowPayColors.textSecondary),
                          ),
                          const Spacer(),
                        ] else ...[
                          const Spacer(),

                          // Custom Numeric Keypad
                          _buildKeypad(),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
          const SizedBox(height: 14),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 72, height: 72),
            _buildKey('0', onTap: () => _onDigitTapped('0')),
            _buildBackspaceKey(),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(String label, {required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: 'Digit $label',
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: FlowPayColors.surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: FlowPayColors.hairline),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: FlowPayColors.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return Semantics(
      button: true,
      label: 'Backspace',
      child: InkResponse(
        onTap: _onBackspace,
        radius: 36,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: FlowPayColors.surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: FlowPayColors.hairline),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.backspace_outlined,
            color: FlowPayColors.ink,
            size: 22,
          ),
        ),
      ),
    );
  }
}
