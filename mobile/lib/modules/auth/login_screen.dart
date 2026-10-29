import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/auth/wallet_login.dart';
import '../../core/design_system/design_system.dart';
import '../../core/stellar/stellar_key_vault.dart';
import 'signup_screen.dart';

/// Sign in with the wallet on this device.
///
/// There is no password: the PIN unlocks the on-device Stellar key, which signs a
/// server challenge (SEP-10 style). On a new device the user first restores the
/// wallet from their recovery key.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pin = TextEditingController();
  final _recoveryKey = TextEditingController();
  bool? _hasWallet;

  /// The wallet on this device is unlocked with a passkey, not a PIN.
  bool _usesPasskey = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vault = StellarKeyVault.instance;
    final has = await vault.hasWallet();
    final passkey = has && await vault.usesPasskey().catchError((_) => false);
    if (mounted) {
      setState(() {
        _hasWallet = has;
        _usesPasskey = passkey;
      });
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _recoveryKey.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_usesPasskey) return _signInWithPasskey();
    final pin = _pin.text.trim();
    if (pin.length != StellarKeyVault.pinLength) {
      setState(
          () => _error = 'Enter your ${StellarKeyVault.pinLength}-digit PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hasWallet == false) {
        await StellarKeyVault.instance
            .importWallet(secretSeed: _recoveryKey.text, pin: pin);
      } else if (!await StellarKeyVault.instance.verifyPin(pin)) {
        // Checked on-device first: typos fail instantly and never hit the network.
        setState(() => _error = 'Incorrect PIN.');
        return;
      }
      final result = await WalletLogin.signIn(pin: pin);
      await ref.read(secureStorageServiceProvider).saveAuthToken(result.token);
      await ref
          .read(appLockStateProvider.notifier)
          .loginAsPersona(result.profile);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on StellarVaultException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One passkey prompt signs the server challenge, which both proves the user
  /// and signs them in — no separate local check.
  Future<void> _signInWithPasskey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await WalletLogin.signIn(pin: StellarKeyVault.passkey);
      await ref.read(secureStorageServiceProvider).saveAuthToken(result.token);
      await ref
          .read(appLockStateProvider.notifier)
          .loginAsPersona(result.profile);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on StellarVaultException catch (e) {
      setState(() => _error = e.code == StellarVaultErrorCode.passkeyCancelled
          ? 'Cancelled. Try again.'
          : e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restoring = _hasWallet == false;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: _hasWallet == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(restoring ? 'Restore your wallet' : 'Unlock your wallet',
                    style: FlowPayTypography.headingSm),
                const SizedBox(height: 8),
                Text(
                  restoring
                      ? 'This device has no FlowPay wallet yet. Paste the recovery key you saved, and choose a PIN for this device.'
                      : _usesPasskey
                          ? 'Your passkey (Face ID / fingerprint) unlocks the wallet on this device, which signs you in.'
                          : 'Your PIN unlocks the wallet on this device, which signs you in. FlowPay never sees your PIN.',
                  style: FlowPayTypography.bodySmall,
                ),
                const SizedBox(height: 20),
                if (restoring) ...[
                  TextField(
                    key: const Key('login_recovery_key'),
                    controller: _recoveryKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Recovery key (starts with S)'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_usesPasskey)
                  TextField(
                    key: const Key('login_pin'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: StellarKeyVault.pinLength,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                        labelText:
                            restoring ? 'New PIN for this device' : 'PIN',
                        counterText: ''),
                    onSubmitted: (_) => _signIn(),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      key: const Key('login_error'),
                      style: const TextStyle(color: FlowPayColors.stateError)),
                ],
                const SizedBox(height: 20),
                FlowPayButton(
                  key: const Key('login_submit'),
                  text: restoring
                      ? 'Restore and sign in'
                      : _usesPasskey
                          ? 'Sign in with passkey'
                          : 'Sign in',
                  icon: _usesPasskey ? Icons.fingerprint : null,
                  isLoading: _busy,
                  onPressed: _busy ? null : _signIn,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const SignupScreen())),
                  child: const Text('New to FlowPay? Create an account'),
                ),
              ],
            ),
    );
  }
}
