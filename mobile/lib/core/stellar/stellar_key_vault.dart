import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' hide KeyPair;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';

import 'passkey/passkey_authenticator.dart';

/// Why a vault operation failed. UI maps these to plain-English messages.
enum StellarVaultErrorCode {
  noWallet,
  walletAlreadyExists,
  pinInvalid,
  pinMismatch,
  lockedOut,
  storageFailure,
  signingFailed,
  /// The passkey prompt was dismissed (not counted as a failed attempt).
  passkeyCancelled,
  /// Passkeys can't be used (unsupported, PRF missing, or the passkey failed).
  passkeyUnavailable,
  /// The recovery key must be saved before switching to a passkey.
  backupRequired,
  /// A PIN was given for a passkey wallet, or the passkey for a PIN wallet.
  wrongUnlockMethod,
}

class StellarVaultException implements Exception {
  final StellarVaultErrorCode code;
  final String message;

  /// Set when [code] is [StellarVaultErrorCode.lockedOut].
  final Duration? retryAfter;

  const StellarVaultException(this.code, this.message, {this.retryAfter});

  @override
  String toString() => 'StellarVaultException(${code.name}): $message';
}

/// Minimal key-value persistence. Unlike the legacy storage helpers, failures
/// here PROPAGATE — a wallet the user thinks is saved must actually be saved.
abstract class VaultStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureVaultStore implements VaultStore {
  final FlutterSecureStorage _storage;

  const SecureVaultStore([
    this._storage = const FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    ),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemoryVaultStore implements VaultStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Non-custodial Stellar key vault.
///
/// * The ed25519 keypair is generated on this device.
/// * The secret seed is encrypted with AES-256-GCM under a key derived from the
///   user's PIN (PBKDF2-HMAC-SHA256, random salt). A wrong PIN fails GCM
///   authentication — there is no separate PIN hash to attack or bypass.
/// * The plaintext seed only exists in memory for the duration of one signing
///   call. It is never logged, never returned to UI code (except the explicit
///   recovery-key export), and never sent to the backend.
/// * Repeated wrong PINs trigger an escalating lockout.
class StellarKeyVault {
  static const int pinLength = 6;
  static const int freeAttempts = 5;
  static const String _blobKey = 'flowpay_stellar_vault_v1';
  static const String _failuresKey = 'flowpay_stellar_vault_failures';
  /// Public key of the wallet whose recovery key the user confirmed saving.
  static const String _backedUpKey = 'flowpay_stellar_vault_backed_up';

  /// Pass as the `pin` argument when the wallet is protected by a passkey: the
  /// vault then asks the passkey (Face ID / fingerprint) instead of using a PIN.
  /// PINs are always 6 digits, so this can never collide with one.
  static const String passkey = 'passkey';
  static const String _kdfPin = 'pbkdf2-sha256';
  static const String _kdfPasskey = 'webauthn-prf-hkdf';

  /// Process-wide vault. Tests replace it with an in-memory instance via
  /// `test/flutter_test_config.dart`.
  static StellarKeyVault instance = StellarKeyVault();

  final VaultStore _store;
  final int _kdfIterations;
  final DateTime Function() _now;
  final PasskeyAuthenticator _passkeys;
  final AesGcm _cipher = AesGcm.with256bits();

  String? _cachedPublicKey;

  StellarKeyVault({
    VaultStore store = const SecureVaultStore(),
    int kdfIterations = 100000,
    DateTime Function()? clock,
    PasskeyAuthenticator? passkeys,
  })  : _store = store,
        _kdfIterations = kdfIterations,
        _now = clock ?? DateTime.now,
        _passkeys = passkeys ?? PasskeyAuthenticator.platform();

  // ── queries ────────────────────────────────────────────────────────────

  Future<bool> hasWallet() async => (await _readBlob()) != null;

  /// The wallet's public Stellar account ID (G...), or null when none exists.
  Future<String?> publicKey() async {
    if (_cachedPublicKey != null) return _cachedPublicKey;
    _cachedPublicKey = (await _readBlob())?['publicKey'] as String?;
    return _cachedPublicKey;
  }

  /// True once the user confirmed saving this wallet's recovery key (or restored
  /// the wallet from one). Until then the app keeps reminding them.
  Future<bool> isBackedUp() async {
    final pk = await publicKey();
    return pk != null && await _store.read(_backedUpKey) == pk;
  }

  /// Whether this platform can protect the wallet with a passkey.
  Future<bool> passkeySupported() => _passkeys.isSupported();

  /// True when the wallet key is encrypted under a passkey instead of a PIN.
  Future<bool> usesPasskey() async => (await _readBlob())?['kdf'] == _kdfPasskey;

  /// Re-encrypts the wallet key under a new passkey (Face ID / fingerprint) and
  /// removes the PIN-encrypted copy, so stolen storage can't be brute-forced.
  /// Requires the current [pin] and a saved recovery key (the passkey is tied to
  /// this site; the recovery key is the way back if it is ever lost).
  Future<void> enablePasskey({required String pin}) async {
    if (!await isBackedUp()) {
      throw const StellarVaultException(
          StellarVaultErrorCode.backupRequired, 'Save your recovery key before switching to a passkey.');
    }
    final keyPair = await _unlock(pin);
    final prfSalt = Uint8List.fromList(_cipher.newNonce() + _cipher.newNonce() + _cipher.newNonce().sublist(0, 8));
    final registration = await _passkeyCall(
        () => _passkeys.register(userName: 'FlowPay wallet ${_short(keyPair.accountId)}', salt: prfSalt));
    final credentialId = registration.credentialId;
    final List<int> secret;
    final SecretBox box;
    final List<int> hkdfSalt = _cipher.newNonce() + _cipher.newNonce();
    try {
      // One prompt when the browser evaluated PRF at creation; otherwise ask once more.
      secret = registration.prfSecret ??
          await _passkeyCall(() => _passkeys.prfSecret(credentialId: credentialId, salt: prfSalt));
      box = await _cipher.encrypt(utf8.encode(keyPair.secretSeed), secretKey: await _passkeyKey(secret, hkdfSalt));
    } catch (_) {
      // Setup failed after the passkey was created: don't leave it behind.
      await _passkeys.forget(credentialId);
      rethrow;
    }
    await _writeBlob({
      'v': 2,
      'publicKey': keyPair.accountId,
      'kdf': _kdfPasskey,
      'credentialId': credentialId,
      'prfSalt': base64Encode(prfSalt),
      'salt': base64Encode(hkdfSalt),
      ..._boxFields(box),
    });
  }

  /// Back to a PIN: confirms with the passkey, then encrypts under [newPin].
  Future<void> disablePasskey({required String newPin}) async {
    _assertPinFormat(newPin);
    final keyPair = await _unlock(passkey);
    await _persist(keyPair, newPin, allowOverwrite: true);
  }

  Future<void> markBackedUp() async {
    final pk = await publicKey();
    if (pk == null) throw const StellarVaultException(StellarVaultErrorCode.noWallet, 'No wallet on this device.');
    await _wrap(() => _store.write(_backedUpKey, pk));
  }

  // ── lifecycle ──────────────────────────────────────────────────────────

  /// Generates a new keypair, encrypts it under [pin], and persists it.
  Future<String> createWallet({required String pin}) =>
      _persist(KeyPair.random(), pin, allowOverwrite: false);

  /// Restores a wallet from a recovery key (S... secret seed).
  Future<String> importWallet({required String secretSeed, required String pin}) async {
    final KeyPair keyPair;
    try {
      keyPair = KeyPair.fromSecretSeed(secretSeed.trim());
    } catch (_) {
      throw const StellarVaultException(
          StellarVaultErrorCode.signingFailed, 'That recovery key is not a valid Stellar secret key.');
    }
    final account = await _persist(keyPair, pin, allowOverwrite: false);
    // Restored from a recovery key: the user evidently has it saved.
    await _wrap(() => _store.write(_backedUpKey, account));
    return account;
  }

  /// Returns the recovery key after verifying [pin]. Only for the explicit
  /// "back up recovery key" flow.
  Future<String> exportRecoveryKey({required String pin}) async =>
      (await _unlock(pin)).secretSeed;

  Future<bool> verifyPin(String pin) async {
    try {
      await _unlock(pin);
      return true;
    } on StellarVaultException catch (e) {
      if (e.code == StellarVaultErrorCode.pinMismatch) return false;
      rethrow;
    }
  }

  Future<void> changePin({required String currentPin, required String newPin}) async {
    if (await usesPasskey()) {
      throw const StellarVaultException(
          StellarVaultErrorCode.wrongUnlockMethod, 'This wallet uses a passkey. Switch back to a PIN first.');
    }
    final keyPair = await _unlock(currentPin);
    await _persist(keyPair, newPin, allowOverwrite: true);
  }

  /// Deletes the wallet. Requires the PIN so a stolen, unlocked phone can't wipe it silently.
  Future<void> deleteWallet({required String pin}) async {
    await _unlock(pin);
    await _wrap(() async {
      await _store.delete(_blobKey);
      await _store.delete(_failuresKey);
      await _store.delete(_backedUpKey);
    });
    _cachedPublicKey = null;
  }

  // ── signing ────────────────────────────────────────────────────────────

  /// Signs a base64 transaction envelope for [networkPassphrase] and returns the
  /// signed envelope.
  Future<String> signTransactionXdr(
    String envelopeXdr, {
    required String pin,
    required String networkPassphrase,
  }) async {
    final keyPair = await _unlock(pin);
    try {
      final tx = AbstractTransaction.fromEnvelopeXdrString(envelopeXdr);
      tx.sign(keyPair, Network(networkPassphrase));
      return tx.toEnvelopeXdrBase64();
    } catch (e) {
      throw StellarVaultException(StellarVaultErrorCode.signingFailed, 'Could not sign this transaction: $e');
    }
  }

  /// Raw ed25519 signature over [data], hex-encoded.
  Future<String> signBytes(Uint8List data, {required String pin}) async {
    final keyPair = await _unlock(pin);
    return _hex(keyPair.sign(data));
  }

  // ── internals ──────────────────────────────────────────────────────────

  Future<String> _persist(KeyPair keyPair, String pin, {required bool allowOverwrite}) async {
    _assertPinFormat(pin);
    if (!allowOverwrite && await hasWallet()) {
      throw const StellarVaultException(
          StellarVaultErrorCode.walletAlreadyExists, 'A wallet already exists on this device.');
    }
    final salt = _cipher.newNonce() + _cipher.newNonce(); // 24 random bytes
    final secretKey = await _deriveKey(pin, salt);
    final box = await _cipher.encrypt(utf8.encode(keyPair.secretSeed), secretKey: secretKey);
    await _writeBlob({
      'v': 1,
      'publicKey': keyPair.accountId,
      'kdf': _kdfPin,
      'iterations': _kdfIterations,
      'salt': base64Encode(salt),
      ..._boxFields(box),
    });
    return keyPair.accountId;
  }

  Future<KeyPair> _unlock(String pin) async {
    final blob = await _readBlob();
    if (blob == null) {
      throw const StellarVaultException(StellarVaultErrorCode.noWallet, 'No wallet exists on this device yet.');
    }
    if (blob['kdf'] == _kdfPasskey) return _unlockWithPasskey(blob, pin);
    if (pin == passkey) {
      throw const StellarVaultException(StellarVaultErrorCode.wrongUnlockMethod, 'This wallet is protected by a PIN.');
    }
    _assertPinFormat(pin);
    await _assertNotLockedOut();

    final secretKey = await _deriveKey(pin, base64Decode(blob['salt'] as String),
        iterations: blob['iterations'] as int);
    final box = _boxFrom(blob);
    try {
      final seed = utf8.decode(await _cipher.decrypt(box, secretKey: secretKey));
      await _wrap(() => _store.delete(_failuresKey));
      return KeyPair.fromSecretSeed(seed);
    } on SecretBoxAuthenticationError {
      await _recordFailure();
      throw const StellarVaultException(StellarVaultErrorCode.pinMismatch, 'Incorrect PIN.');
    }
  }

  Future<KeyPair> _unlockWithPasskey(Map<String, dynamic> blob, String pin) async {
    if (pin != passkey) {
      throw const StellarVaultException(
          StellarVaultErrorCode.wrongUnlockMethod, 'This wallet is unlocked with your passkey (Face ID / fingerprint).');
    }
    final secret = await _passkeyCall(() => _passkeys.prfSecret(
          credentialId: blob['credentialId'] as String,
          salt: base64Decode(blob['prfSalt'] as String),
        ));
    final box = _boxFrom(blob);
    try {
      final key = await _passkeyKey(secret, base64Decode(blob['salt'] as String));
      return KeyPair.fromSecretSeed(utf8.decode(await _cipher.decrypt(box, secretKey: key)));
    } on SecretBoxAuthenticationError {
      throw const StellarVaultException(StellarVaultErrorCode.pinMismatch, "That passkey doesn't unlock this wallet.");
    }
  }

  /// The encrypted seed, stored the same way for PIN and passkey wallets.
  static Map<String, String> _boxFields(SecretBox box) => {
        'nonce': base64Encode(box.nonce),
        'cipherText': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      };

  static SecretBox _boxFrom(Map<String, dynamic> blob) => SecretBox(
        base64Decode(blob['cipherText'] as String),
        nonce: base64Decode(blob['nonce'] as String),
        mac: Mac(base64Decode(blob['mac'] as String)),
      );

  /// AES key from the passkey's PRF output (HKDF-SHA256, wallet-specific salt).
  Future<SecretKey> _passkeyKey(List<int> prfSecret, List<int> salt) {
    if (prfSecret.length < 32) {
      throw const StellarVaultException(StellarVaultErrorCode.passkeyUnavailable, 'The passkey returned an invalid key.');
    }
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(secretKey: SecretKey(prfSecret), nonce: salt, info: utf8.encode('flowpay-wallet-key-v2'));
  }

  Future<T> _passkeyCall<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PasskeyException catch (e) {
      throw StellarVaultException(
          e.cancelled ? StellarVaultErrorCode.passkeyCancelled : StellarVaultErrorCode.passkeyUnavailable, e.message);
    }
  }

  Future<void> _writeBlob(Map<String, dynamic> blob) async {
    await _wrap(() async {
      await _store.write(_blobKey, jsonEncode(blob));
      await _store.delete(_failuresKey);
    });
    _cachedPublicKey = blob['publicKey'] as String;
  }

  static String _short(String accountId) => '${accountId.substring(0, 4)}…${accountId.substring(accountId.length - 4)}';

  Future<SecretKey> _deriveKey(String pin, List<int> salt, {int? iterations}) {
    return Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations ?? _kdfIterations, bits: 256)
        .deriveKeyFromPassword(password: pin, nonce: salt);
  }

  Future<void> _assertNotLockedOut() async {
    final state = await _readFailures();
    final failures = state.$1;
    if (failures < freeAttempts || state.$2 == null) return;
    final lockSeconds = 30 * (1 << (failures - freeAttempts).clamp(0, 10));
    final unlockAt = state.$2!.add(Duration(seconds: lockSeconds));
    final now = _now();
    if (now.isBefore(unlockAt)) {
      final wait = unlockAt.difference(now);
      throw StellarVaultException(
        StellarVaultErrorCode.lockedOut,
        'Too many incorrect PINs. Try again in ${wait.inSeconds + 1} seconds.',
        retryAfter: wait,
      );
    }
  }

  Future<void> _recordFailure() async {
    final failures = (await _readFailures()).$1 + 1;
    await _wrap(() => _store.write(_failuresKey, '$failures|${_now().toIso8601String()}'));
  }

  Future<(int, DateTime?)> _readFailures() async {
    final raw = await _wrap(() => _store.read(_failuresKey));
    if (raw == null) return (0, null);
    final parts = raw.split('|');
    return (int.tryParse(parts.first) ?? 0, parts.length > 1 ? DateTime.tryParse(parts[1]) : null);
  }

  Future<Map<String, dynamic>?> _readBlob() async {
    final raw = await _wrap(() => _store.read(_blobKey));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  void _assertPinFormat(String pin) {
    if (!RegExp('^\\d{$pinLength}\$').hasMatch(pin)) {
      throw const StellarVaultException(StellarVaultErrorCode.pinInvalid, 'PIN must be exactly $pinLength digits.');
    }
  }

  Future<T> _wrap<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on StellarVaultException {
      rethrow;
    } catch (e) {
      throw StellarVaultException(StellarVaultErrorCode.storageFailure, 'Secure storage is unavailable: $e');
    }
  }

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
