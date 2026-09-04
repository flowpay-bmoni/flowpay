import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/components.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'account_capabilities.dart';
import 'account_mode_picker_modal.dart';
import 'auth_providers.dart';
import '../../modules/auth/signup_screen.dart';
import '../../modules/auth/login_screen.dart';

/// App-Auth Gate: Controls biometric unlock, account mode resolution,
/// and lifecycle background re-lock.
class AppAuthGate extends ConsumerStatefulWidget {
  final Widget personalShell;
  final Widget businessShell;
  final AppState? appState;

  const AppAuthGate({
    super.key,
    required this.personalShell,
    required this.businessShell,
    this.appState,
  });

  @override
  ConsumerState<AppAuthGate> createState() => _AppAuthGateState();
}

class _AppAuthGateState extends ConsumerState<AppAuthGate>
    with WidgetsBindingObserver {
  DateTime? _pausedTimestamp;
  final TextEditingController _pinController = TextEditingController();
  bool _pinError = false;
  bool _hasCheckedInitialPicker = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTimestamp = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTimestamp != null) {
        final elapsed = DateTime.now().difference(_pausedTimestamp!);
        // Re-lock if the app was backgrounded for more than 45 seconds
        if (elapsed.inSeconds >= 45) {
          ref.read(appLockStateProvider.notifier).lockApp();
        }
      }
      _pausedTimestamp = null;
    }
  }

  Future<void> _checkInitialModePicker(AccountCapabilities capabilities) async {
    if (_hasCheckedInitialPicker) return;
    _hasCheckedInitialPicker = true;

    final storage = ref.read(secureStorageServiceProvider);
    final storedMode = await storage.getAccountMode();

    // If returning user has both modes and no prior selection, show the picker
    if (storedMode == null && capabilities.hasBothModes && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final currentMode = ref.read(currentAccountModeProvider);
        final chosen = await AccountModePickerModal.show(
          context,
          initialMode: currentMode,
          capabilities: capabilities,
        );
        if (chosen != null && mounted) {
          await ref.read(appLockStateProvider.notifier).setAccountMode(chosen);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockStateProvider);

    // 1. User has no active authenticated session -> Absolutely no app entry. Show Login.
    if (!lockState.hasSession) {
      return const LoginScreen();
    }

    // 2. App is Locked -> Show Unlock Screen
    if (lockState.isLocked) {
      return _buildLockScreen(context, lockState);
    }

    // 3. App is Unlocked & Session Active -> Resolve Capabilities & Shell
    final profile = ref.watch(currentUserProfileProvider);
    if (profile != null) {
      widget.appState?.setUserId(profile.userId);
    }

    final capabilitiesAsync = ref.watch(accountCapabilitiesProvider);

    return capabilitiesAsync.when(
      loading: () => const Scaffold(
        backgroundColor: FlowPayColors.canvas,
        body: Center(
          child: CircularProgressIndicator(
            color: FlowPayColors.ink,
          ),
        ),
      ),
      error: (err, stack) => _renderActiveShell(),
      data: (capabilities) {
        _checkInitialModePicker(capabilities);
        return _renderActiveShell();
      },
    );
  }

  Widget _renderActiveShell() {
    final activeMode = ref.watch(currentAccountModeProvider);
    return switch (activeMode) {
      AccountMode.personal => widget.personalShell,
      AccountMode.business => widget.businessShell,
    };
  }

  Widget _buildLockScreen(BuildContext context, AppLockState lockState) {
    final isExpired = lockState.isAuthExpired;

    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Brand Icon & Badge
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: FlowPayColors.ink,
                  borderRadius: FlowPayRadii.card,
                ),
                child: Icon(
                  isExpired
                      ? Icons.timer_outlined
                      : (lockState.hasFaceId
                          ? Icons.face_unlock_outlined
                          : (lockState.hasFingerprint
                              ? Icons.fingerprint
                              : Icons.shield_outlined)),
                  size: 38,
                  color: isExpired ? FlowPayColors.amber : Colors.white,
                ),
              ),
              const SizedBox(height: 18),

              // Title & Subtitle
              Text(
                isExpired ? 'Session Expired' : 'FlowPay is Locked',
                style: FlowPayTypography.headline(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isExpired
                    ? 'Your session has expired. Enter your 6-digit PIN, use ${lockState.biometricLabel}, or log in to renew.'
                    : 'Enter your 6-digit PIN or authenticate via ${lockState.biometricLabel} to access FlowPay.',
                style: const TextStyle(
                  fontSize: 13,
                  color: FlowPayColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              // Status Badge
              if (isExpired)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: FlowPayColors.amber.withAlpha(30),
                    borderRadius: FlowPayRadii.chip,
                    border:
                        Border.all(color: FlowPayColors.amber.withAlpha(120)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: FlowPayColors.amber),
                      SizedBox(width: 6),
                      Text(
                        'Authentication Expired',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: FlowPayColors.amber,
                        ),
                      ),
                    ],
                  ),
                )
              else if (lockState.hasFaceId || lockState.hasFingerprint)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: FlowPayColors.surfaceAlt,
                    borderRadius: FlowPayRadii.chip,
                    border: Border.all(color: FlowPayColors.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        lockState.hasFaceId ? Icons.face : Icons.fingerprint,
                        size: 14,
                        color: FlowPayColors.ink,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${lockState.biometricLabel} Ready',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: FlowPayColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Direct In-App PIN Entry (Always accessible)
              _buildPinEntry(),
              const SizedBox(height: 16),

              // Error or Status message
              if (lockState.lastResult?.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FlowPayColors.surfaceAlt,
                    borderRadius: FlowPayRadii.input,
                    border: Border.all(color: FlowPayColors.hairline),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: FlowPayColors.ink,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          lockState.lastResult!.errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: FlowPayColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Primary Biometric Unlock Button
              FlowPayButton(
                text: lockState.isAuthenticating
                    ? 'Verifying...'
                    : 'Unlock with ${lockState.biometricLabel}',
                icon: lockState.hasFaceId ? Icons.face : Icons.fingerprint,
                onPressed: lockState.isAuthenticating
                    ? null
                    : () {
                        ref.read(appLockStateProvider.notifier).authenticate();
                      },
              ),

              const SizedBox(height: 12),

              // Log In Button
              OutlinedButton.icon(
                icon:
                    const Icon(Icons.login, size: 16, color: FlowPayColors.ink),
                label: const Text(
                  'Log In to Existing Account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FlowPayColors.ink,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: FlowPayColors.hairline),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  minimumSize: const Size(double.infinity, 46),
                  shape: const RoundedRectangleBorder(
                      borderRadius: FlowPayRadii.button),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),

              const SizedBox(height: 8),

              // Create New Account (Sign Up & KYC)
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_outlined,
                    size: 16, color: FlowPayColors.ink),
                label: const Text(
                  'Create New Account / Sign Up',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FlowPayColors.ink,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: FlowPayColors.hairline),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  minimumSize: const Size(double.infinity, 46),
                  shape: const RoundedRectangleBorder(
                      borderRadius: FlowPayRadii.button),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SignupScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // Log Out / Switch Account
              TextButton.icon(
                icon: const Icon(Icons.logout, size: 15, color: FlowPayColors.textSecondary),
                label: const Text(
                  'Log Out / Switch Account',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FlowPayColors.textSecondary,
                  ),
                ),
                onPressed: () {
                  ref.read(appLockStateProvider.notifier).logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry() {
    return Column(
      children: [
        const Text(
          'Enter 6-Digit PIN',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: FlowPayColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: FlowPayColors.surface,
            borderRadius: FlowPayRadii.input,
            border: Border.all(
              color:
                  _pinError ? FlowPayColors.stateError : FlowPayColors.hairline,
            ),
          ),
          child: TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 12,
              fontWeight: FontWeight.w700,
              color: FlowPayColors.ink,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              hintText: '••••••',
              hintStyle: TextStyle(
                color: FlowPayColors.textTertiary,
                letterSpacing: 8,
              ),
            ),
            onChanged: (val) async {
              if (val.length == 6) {
                final success = await ref
                    .read(appLockStateProvider.notifier)
                    .verifyFallbackPin(val);
                if (!success) {
                  setState(() => _pinError = true);
                } else {
                  _pinController.clear();
                  if (_pinError) setState(() => _pinError = false);
                }
              } else {
                if (_pinError) setState(() => _pinError = false);
              }
            },
          ),
        ),
        if (_pinError)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Incorrect 6-digit PIN. Try again.',
              style: TextStyle(
                fontSize: 11,
                color: FlowPayColors.stateError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
