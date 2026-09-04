import 'dart:async';

import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  // Initialize the SDK with the default PIN policy. The Settings sheet
  // in the example app lets you toggle these knobs at runtime so you
  // can experience both gating modes.
  BmoniEmbeddedSdk.initialize(pinLength: 6, requirePin: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'BMONI Embedded SDK',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const _HomeScreen(),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  final TextEditingController _messageController = TextEditingController(
    text: 'Welcome to BMONI!',
  );
  final TextEditingController _hashController = TextEditingController(
    text: '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8',
  );

  String? _walletAddress;
  String? _lastSignature;
  bool _hasPin = false;
  bool _busy = false;
  late BmoniEmbeddedSdkConfig _config;

  @override
  void initState() {
    super.initState();
    _config = BmoniEmbeddedSdk.config;
    _hydrateFromStorage();
  }

  /// Loads any persistent SDK state (PIN existence + cached wallet
  /// address) into this widget so the UI reflects the device's actual
  /// state on cold start.
  Future<void> _hydrateFromStorage() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      BmoniEmbeddedSdk.hasPin(),
      BmoniEmbeddedSdk.walletAddress(),
    ]);
    if (!mounted) return;
    setState(() {
      _hasPin = results[0]! as bool;
      _walletAddress = results[1] as String?;
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _hashController.dispose();
    super.dispose();
  }

  Future<void> _refreshHasPin() async {
    final bool hasPin = await BmoniEmbeddedSdk.hasPin();
    if (!mounted) return;
    setState(() => _hasPin = hasPin);
  }

  void _showSnack(String message, {bool error = false}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? scheme.error : scheme.secondary,
        showCloseIcon: true,
      ),
    );
  }

  Future<T?> _runAction<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } on BmoniSignerException catch (e) {
      _showSnack(e.message, error: true);
    } on PlatformException catch (e) {
      _showSnack('Platform error: ${e.message ?? e.code}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  // ----------------------------------------------------------------
  // Wallet flows
  // ----------------------------------------------------------------

  Future<void> _initWallet() async {
    setState(() => _busy = true);
    try {
      final String address = await BmoniEmbeddedSdk.initWallet();
      if (!mounted) return;
      setState(() {
        _walletAddress = address;
        _lastSignature = null;
      });
      _showSnack('Wallet provisioned.');
    } on BmoniSignerException catch (e) {
      if (e.errorCode == BmoniSignerErrorCode.walletAlreadyExists && mounted) {
        // Native wallet exists but the Dart-side address cache is
        // empty — most commonly because the wallet was provisioned
        // before the cache existed. Offer the destructive recovery
        // path (delete + re-provision).
        await _offerWalletRecovery();
      } else {
        _showSnack(e.message, error: true);
      }
    } on PlatformException catch (e) {
      _showSnack('Platform error: ${e.message ?? e.code}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerWalletRecovery() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('A wallet already exists'),
        content: const Text(
          'This device has a wallet provisioned by BMONISigner, but '
          'the SDK cache does not know its address.\n\n'
          'The native SDK only returns the address at provisioning '
          'time, so the only way to get back to a usable state from '
          'here is to delete the existing wallet and provision a new '
          'one.\n\n'
          'This is destructive — the old address is unrecoverable '
          'from this device after deletion.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete & re-provision'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // The native delete is gated on the PIN when requirePin is true,
    // but the cache state is inconsistent enough that we take the
    // escape hatch: drop the PIN first (destructive, but consistent
    // with "reset everything to a clean slate") and then delete.
    try {
      setState(() => _busy = true);
      // Flip the gate off so we can blow away the stale wallet without
      // knowing its PIN, then restore the original config.
      BmoniEmbeddedSdk.initialize(requirePin: false);
      await BmoniEmbeddedSdk.deleteWallet();
      BmoniEmbeddedSdk.initialize(
        pinLength: _config.pinLength,
        requirePin: _config.requirePin,
      );
      final String address = await BmoniEmbeddedSdk.initWallet();
      if (!mounted) return;
      setState(() {
        _walletAddress = address;
        _lastSignature = null;
      });
      _showSnack('Wallet re-provisioned.');
    } on BmoniSignerException catch (e) {
      _showSnack('Recovery failed: ${e.message}', error: true);
    } on PlatformException catch (e) {
      _showSnack('Platform error: ${e.message ?? e.code}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteWallet() async {
    final _GatedPin? gated = await _resolveGatedPin(
      title: 'Delete wallet',
      subtitle:
          'This permanently removes the encrypted private key from this device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (gated == null) return;
    final bool? ok = await _runAction(() async {
      await BmoniEmbeddedSdk.deleteWallet(pin: gated.pin);
      return true;
    });
    if (ok != true || !mounted) return;
    setState(() {
      _walletAddress = null;
      _lastSignature = null;
    });
    _showSnack('Wallet deleted.');
  }

  // ----------------------------------------------------------------
  // PIN flows
  // ----------------------------------------------------------------

  Future<void> _setPin() async {
    final String? pin = await _PinEntrySheet.show(
      context,
      title: 'Create a PIN',
      subtitle:
          'Used to unlock signing and wallet deletion. Store it somewhere safe.',
      confirmLabel: 'Save PIN',
    );
    if (pin == null) return;
    final bool? ok = await _runAction(() async {
      await BmoniEmbeddedSdk.setPin(pin);
      return true;
    });
    if (ok != true || !mounted) return;
    await _refreshHasPin();
    _showSnack('PIN set.');
  }

  Future<void> _changePin() async {
    final _ChangePinResult? result = await _ChangePinSheet.show(context);
    if (result == null) return;
    final bool? ok = await _runAction(() async {
      await BmoniEmbeddedSdk.changePin(
        currentPin: result.currentPin,
        newPin: result.newPin,
      );
      return true;
    });
    if (ok != true || !mounted) return;
    _showSnack('PIN changed.');
  }

  Future<void> _removePin() async {
    final String? pin = await _PinEntrySheet.show(
      context,
      title: 'Remove PIN',
      subtitle:
          'Signing and delete will be unavailable until you create a new PIN.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (pin == null) return;
    final bool? ok = await _runAction(() async {
      await BmoniEmbeddedSdk.removePin(pin);
      return true;
    });
    if (ok != true || !mounted) return;
    await _refreshHasPin();
    _showSnack('PIN removed.');
  }

  Future<void> _matchPin() async {
    final String? pin = await _PinEntrySheet.show(
      context,
      title: 'Verify PIN',
      subtitle: 'Check that the PIN you remember matches the stored one.',
      confirmLabel: 'Verify',
    );
    if (pin == null) return;
    final bool? matches = await _runAction(
      () => BmoniEmbeddedSdk.matchPin(pin),
    );
    if (matches == null || !mounted) return;
    _showSnack(
      matches ? 'PIN matches.' : 'PIN does NOT match.',
      error: !matches,
    );
  }

  // ----------------------------------------------------------------
  // Signing flows
  // ----------------------------------------------------------------

  Future<void> _signMessage() async {
    if (_messageController.text.isEmpty) {
      _showSnack('Enter a message to sign.', error: true);
      return;
    }
    final _GatedPin? gated = await _resolveGatedPin(
      title: 'Sign message',
      subtitle: '"${_truncate(_messageController.text, 60)}"',
      confirmLabel: 'Sign',
    );
    if (gated == null) return;
    final String? signature = await _runAction(
      () =>
          BmoniEmbeddedSdk.signMessage(_messageController.text, pin: gated.pin),
    );
    if (signature == null || !mounted) return;
    setState(() => _lastSignature = signature);
  }

  Future<void> _signHash() async {
    if (_hashController.text.isEmpty) {
      _showSnack('Enter a 32-byte hash to sign.', error: true);
      return;
    }
    final _GatedPin? gated = await _resolveGatedPin(
      title: 'Sign hash',
      subtitle: _truncate(_hashController.text, 50),
      confirmLabel: 'Sign',
    );
    if (gated == null) return;
    final String? signature = await _runAction(
      () => BmoniEmbeddedSdk.signTransactionHash(
        _hashController.text,
        pin: gated.pin,
      ),
    );
    if (signature == null || !mounted) return;
    setState(() => _lastSignature = signature);
  }

  /// When `requirePin` is `true`, prompts the user with a PIN sheet and
  /// returns the entered value (or `null` if dismissed). When
  /// `requirePin` is `false`, returns a sentinel without showing any
  /// UI so the caller can proceed straight to the SDK call.
  Future<_GatedPin?> _resolveGatedPin({
    required String title,
    required String confirmLabel,
    String? subtitle,
    bool destructive = false,
  }) async {
    if (!_config.requirePin) {
      return const _GatedPin(null);
    }
    final String? pin = await _PinEntrySheet.show(
      context,
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
    if (pin == null) return null;
    return _GatedPin(pin);
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  Future<void> _openSettings() async {
    final BmoniEmbeddedSdkConfig? next = await _SettingsSheet.show(
      context,
      current: _config,
    );
    if (next == null) return;
    BmoniEmbeddedSdk.initialize(
      pinLength: next.pinLength,
      requirePin: next.requirePin,
    );
    if (!mounted) return;
    setState(() => _config = BmoniEmbeddedSdk.config);
    _showSnack(
      'SDK reconfigured: pinLength=${next.pinLength}, requirePin=${next.requirePin}.',
    );
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BMONI Embedded SDK'),
        scrolledUnderElevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'SDK settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _busy ? null : _openSettings,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _StatusBanner(
                  walletAddress: _walletAddress,
                  hasPin: _hasPin,
                  config: _config,
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Wallet',
                  children: <Widget>[
                    if (_walletAddress != null) ...<Widget>[
                      _MonoBox(label: 'Address', value: _walletAddress!),
                      const SizedBox(height: 12),
                      _DestructiveGatedButton(
                        enabled: !_busy && _canSign(),
                        missingRequirement: _missingRequirement(),
                        onPressed: _deleteWallet,
                        icon: Icons.delete_outline,
                        label: 'Delete wallet',
                      ),
                    ] else ...<Widget>[
                      FilledButton.icon(
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Provision wallet'),
                        onPressed: _busy ? null : _initWallet,
                      ),
                      const SizedBox(height: 8),
                      // Always available even before the user has tried
                      // to provision: handles the post-upgrade case
                      // where a native wallet exists but the Dart-side
                      // address cache is empty (so `Provision wallet`
                      // would just throw `walletAlreadyExists`).
                      TextButton.icon(
                        icon: Icon(Icons.restart_alt, color: scheme.error),
                        label: Text(
                          'Already have a wallet on this device? Reset it',
                          style: TextStyle(color: scheme.error),
                        ),
                        onPressed: _busy ? null : _offerWalletRecovery,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.lock_outline,
                  title: 'PIN',
                  subtitle: _pinSectionSubtitle(),
                  children: <Widget>[
                    if (!_hasPin)
                      FilledButton.icon(
                        icon: const Icon(Icons.password),
                        label: const Text('Set PIN'),
                        onPressed: _busy ? null : _setPin,
                      )
                    else ...<Widget>[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.cached),
                        label: const Text('Change PIN'),
                        onPressed: _busy ? null : _changePin,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Verify PIN'),
                        onPressed: _busy ? null : _matchPin,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: Icon(
                          Icons.delete_forever_outlined,
                          color: scheme.error,
                        ),
                        label: Text(
                          'Remove PIN',
                          style: TextStyle(color: scheme.error),
                        ),
                        onPressed: _busy ? null : _removePin,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.short_text,
                  title: 'Sign message (EIP-191)',
                  subtitle:
                      'Applies the personal_sign prefix and signs with secp256k1.',
                  children: <Widget>[
                    TextField(
                      controller: _messageController,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(labelText: 'Message'),
                    ),
                    const SizedBox(height: 12),
                    _GatedButton(
                      enabled: !_busy && _canSign(),
                      missingRequirement: _missingRequirement(),
                      onPressed: _signMessage,
                      icon: Icons.draw_outlined,
                      label: 'Sign message',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  icon: Icons.fingerprint,
                  title: 'Sign transaction hash',
                  subtitle:
                      'Signs a pre-computed 32-byte digest (userOpHash, EIP-712, …).',
                  children: <Widget>[
                    TextField(
                      controller: _hashController,
                      decoration: const InputDecoration(
                        labelText: '32-byte hash (hex)',
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _GatedButton(
                      enabled: !_busy && _canSign(),
                      missingRequirement: _missingRequirement(),
                      onPressed: _signHash,
                      icon: Icons.draw_outlined,
                      label: 'Sign hash',
                    ),
                  ],
                ),
                if (_lastSignature != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.check_circle_outline,
                    title: 'Latest signature',
                    children: <Widget>[
                      _MonoBox(label: 'r ‖ s ‖ v', value: _lastSignature!),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  /// Whether the sign / delete buttons should be enabled.
  ///
  /// When `requirePin` is `true`, both a wallet **and** a PIN must
  /// exist. When `requirePin` is `false`, only a wallet is needed —
  /// the PIN is bypassed entirely.
  bool _canSign() {
    if (_walletAddress == null) return false;
    if (_config.requirePin) return _hasPin;
    return true;
  }

  /// Returns a user-facing description of the first missing
  /// prerequisite, or `null` if every gate is satisfied. Fed into
  /// [_GatedButton] so a disabled sign / delete button surfaces a
  /// tooltip explaining exactly what's still required.
  String? _missingRequirement() {
    if (_canSign()) return null;
    final bool needsWallet = _walletAddress == null;
    final bool needsPin = _config.requirePin && !_hasPin;
    if (needsWallet && needsPin) {
      return 'Provision a wallet and set a PIN first.';
    }
    if (needsWallet) return 'Provision a wallet first.';
    if (needsPin) return 'Set a PIN first.';
    return null;
  }

  String _pinSectionSubtitle() {
    if (!_config.requirePin) {
      return _hasPin
          ? 'A PIN is set, but gating is OFF — sign / delete bypass it.'
          : 'PIN gating is OFF — set / change / remove still work for app-side use.';
    }
    return _hasPin
        ? 'A PIN is set on this device.'
        : 'No PIN — sign and delete are unavailable until you set one.';
  }
}

/// Result returned from [_resolveGatedPin]: a non-null wrapper that
/// carries the (possibly null) PIN to forward to the SDK call. A null
/// wrapper means "user dismissed the prompt" and the caller should
/// abort.
class _GatedPin {
  const _GatedPin(this.pin);
  final String? pin;
}

// --------------------------------------------------------------------
// Header banner
// --------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.walletAddress,
    required this.hasPin,
    required this.config,
  });

  final String? walletAddress;
  final bool hasPin;
  final BmoniEmbeddedSdkConfig config;

  bool get _ready => walletAddress != null && (!config.requirePin || hasPin);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _ready
                    ? Icons.verified_user_outlined
                    : Icons.shield_moon_outlined,
                color: scheme.onPrimaryContainer,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _ready ? 'Ready to sign' : 'Setup required',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusLine(walletAddress, hasPin, config),
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              _ConfigChip(
                label: 'PIN length: ${config.pinLength}',
                scheme: scheme,
              ),
              _ConfigChip(
                label: 'requirePin: ${config.requirePin}',
                scheme: scheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLine(
    String? address,
    bool hasPin,
    BmoniEmbeddedSdkConfig config,
  ) {
    if (!config.requirePin) {
      return address == null
          ? 'PIN gating is OFF — provision a wallet to start signing.'
          : 'PIN gating is OFF — sign / delete are called directly.';
    }
    if (address == null && !hasPin) {
      return 'Provision a wallet, then create a PIN to start signing.';
    }
    if (address == null) {
      return 'PIN is set — provision a wallet to start signing.';
    }
    if (!hasPin) {
      return 'Wallet provisioned — create a PIN to enable signing.';
    }
    return 'Wallet provisioned and PIN set.';
  }
}

class _ConfigChip extends StatelessWidget {
  const _ConfigChip({required this.label, required this.scheme});

  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------
// Section card
// --------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: text.titleMedium),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MonoBox extends StatelessWidget {
  const _MonoBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------
// PIN entry modal sheets
// --------------------------------------------------------------------

class _PinEntrySheet extends StatefulWidget {
  const _PinEntrySheet({
    required this.title,
    required this.confirmLabel,
    this.subtitle,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;
  final bool destructive;

  /// Shows the sheet and returns the entered PIN, or `null` if dismissed.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String? subtitle,
    bool destructive = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _PinEntrySheet(
        title: title,
        confirmLabel: confirmLabel,
        subtitle: subtitle,
        destructive: destructive,
      ),
    );
  }

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.length != BmoniEmbeddedSdk.pinLength) return;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            if (widget.subtitle != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            _PinField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: widget.destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                    )
                  : null,
              onPressed: _controller.text.length == BmoniEmbeddedSdk.pinLength
                  ? _submit
                  : null,
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePinResult {
  const _ChangePinResult({required this.currentPin, required this.newPin});

  final String currentPin;
  final String newPin;
}

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet();

  static Future<_ChangePinResult?> show(BuildContext context) {
    return showModalBottomSheet<_ChangePinResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => const _ChangePinSheet(),
    );
  }

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _current.text.length == BmoniEmbeddedSdk.pinLength &&
      _next.text.length == BmoniEmbeddedSdk.pinLength;

  void _submit() {
    if (!_isValid) return;
    Navigator.of(
      context,
    ).pop(_ChangePinResult(currentPin: _current.text, newPin: _next.text));
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Change PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Confirm your current PIN, then choose a new one.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text('Current PIN', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _PinField(
              controller: _current,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('New PIN', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _PinField(
              controller: _next,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isValid ? _submit : null,
              child: const Text('Change PIN'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final int pinLength = BmoniEmbeddedSdk.pinLength;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      obscuringCharacter: '●',
      keyboardType: TextInputType.number,
      maxLength: pinLength,
      textAlign: TextAlign.center,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: const TextStyle(
        fontSize: 24,
        letterSpacing: 12,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '$pinLength digits',
        hintStyle: TextStyle(
          fontSize: 14,
          letterSpacing: 0,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------
// Settings sheet — runtime SDK configuration
// --------------------------------------------------------------------

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.current});

  final BmoniEmbeddedSdkConfig current;

  static Future<BmoniEmbeddedSdkConfig?> show(
    BuildContext context, {
    required BmoniEmbeddedSdkConfig current,
  }) {
    return showModalBottomSheet<BmoniEmbeddedSdkConfig>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => _SettingsSheet(current: current),
    );
  }

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  static const List<int> _pinLengthChoices = <int>[4, 6, 8];

  late int _pinLength = widget.current.pinLength;
  late bool _requirePin = widget.current.requirePin;

  void _save() {
    Navigator.of(context).pop(
      BmoniEmbeddedSdkConfig(pinLength: _pinLength, requirePin: _requirePin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final EdgeInsets viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('SDK settings', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Reconfigures BmoniEmbeddedSdk.initialize(...). The PIN '
              'currently stored on the device stays put — but if you '
              'change the PIN length, you will need to remove and '
              're-create it for verification to succeed.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text('PIN length', style: text.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                for (final int n in _pinLengthChoices)
                  ButtonSegment<int>(value: n, label: Text('$n')),
              ],
              selected: <int>{_pinLength},
              onSelectionChanged: (Set<int> selection) =>
                  setState(() => _pinLength = selection.first),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require PIN before sign / delete'),
              subtitle: Text(
                _requirePin
                    ? 'signMessage / signTransactionHash / deleteWallet '
                          'verify the supplied PIN before invoking the '
                          'native plugin.'
                    : 'signMessage / signTransactionHash / deleteWallet '
                          'forward straight to the native plugin and ignore '
                          'any supplied PIN.',
              ),
              value: _requirePin,
              onChanged: (bool value) => setState(() => _requirePin = value),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Apply')),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------
// Gated button — shows a tooltip with the missing prerequisite when
// disabled, so the user always knows what to do next instead of
// staring at an unexplained dead button.
// --------------------------------------------------------------------

class _GatedButton extends StatelessWidget {
  const _GatedButton({
    required this.enabled,
    required this.missingRequirement,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final String? missingRequirement;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final FilledButton button = FilledButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: enabled ? onPressed : null,
    );
    if (enabled || missingRequirement == null) return button;
    return Tooltip(
      message: missingRequirement!,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      child: button,
    );
  }
}

/// Destructive variant of [_GatedButton] — renders an outlined button
/// in the theme's error color. Used for the explicit "Delete wallet"
/// action so it stands apart from the positive primary CTAs.
class _DestructiveGatedButton extends StatelessWidget {
  const _DestructiveGatedButton({
    required this.enabled,
    required this.missingRequirement,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final String? missingRequirement;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final OutlinedButton button = OutlinedButton.icon(
      icon: Icon(icon, color: scheme.error),
      label: Text(label, style: TextStyle(color: scheme.error)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
      ),
      onPressed: enabled ? onPressed : null,
    );
    if (enabled || missingRequirement == null) return button;
    return Tooltip(
      message: missingRequirement!,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      child: button,
    );
  }
}
