// SPDX-License-Identifier: Apache-2.0
/// Bmoni Embedded SDK for Flutter.
///
/// Provides Ethereum wallet provisioning and signing primitives backed by
/// platform-native secure key storage (Android Keystore on Android,
/// Secure Enclave on iOS), optionally guarded by a user-supplied PIN.
library;

import 'package:flutter/foundation.dart';

import 'bmoni_embedded_sdk_platform_interface.dart';
import 'src/bmoni_embedded_sdk_config.dart';
import 'src/bmoni_signer_exception.dart';
import 'src/pin_store.dart';
import 'src/wallet_address_store.dart';

export 'src/bmoni_embedded_sdk_config.dart';
export 'src/bmoni_signer_exception.dart';

/// High-level entry point for the Bmoni Embedded SDK.
///
/// The SDK is a thin static facade over the native `BMONISigner`
/// libraries: every method forwards to the platform implementation
/// registered via [BmoniEmbeddedSdkPlatform.instance].
///
/// Apps should call [initialize] once at startup to choose the PIN
/// policy. The defaults are equivalent to:
///
/// ```dart
/// BmoniEmbeddedSdk.initialize(pinLength: 6, requirePin: true);
/// ```
///
/// When [BmoniEmbeddedSdkConfig.requirePin] is `true` (default), the
/// sensitive operations ([signMessage], [signTransactionHash],
/// [deleteWallet]) require a `pin` argument and verify it against the
/// digest persisted via [setPin] / [changePin]. When it is `false`,
/// those methods forward straight to the native plugin.
///
/// `BmoniEmbeddedSdk` is intentionally uninstantiable — the class holds
/// no per-instance state, so callers should invoke the methods directly:
///
/// ```dart
/// BmoniEmbeddedSdk.initialize(pinLength: 6, requirePin: true);
/// final address = await BmoniEmbeddedSdk.initWallet();
/// await BmoniEmbeddedSdk.setPin('123456');
/// final signature = await BmoniEmbeddedSdk.signMessage(
///   'Welcome!',
///   pin: '123456',
/// );
/// ```
final class BmoniEmbeddedSdk {
  /// Private constructor — this class only exposes static members.
  const BmoniEmbeddedSdk._();

  static BmoniEmbeddedSdkConfig _config = const BmoniEmbeddedSdkConfig();
  static PinStore _pinStore = PinStore();
  static WalletAddressStore _walletAddressStore = WalletAddressStore();

  /// The currently active configuration. Useful for app-side UI to
  /// adapt to the chosen PIN length / gating policy.
  static BmoniEmbeddedSdkConfig get config => _config;

  /// Required length of a valid PIN. Shorthand for
  /// `BmoniEmbeddedSdk.config.pinLength`.
  static int get pinLength => _config.pinLength;

  /// Whether PIN verification is enforced before signing and deletion.
  /// Shorthand for `BmoniEmbeddedSdk.config.requirePin`.
  static bool get requirePin => _config.requirePin;

  /// Test seam for swapping in a fake [PinStore]. Production code should
  /// rely on the default secure-storage-backed implementation.
  @visibleForTesting
  static set pinStore(PinStore store) => _pinStore = store;

  /// Test seam for swapping in a fake [WalletAddressStore]. Production
  /// code should rely on the default secure-storage-backed
  /// implementation.
  @visibleForTesting
  static set walletAddressStore(WalletAddressStore store) =>
      _walletAddressStore = store;

  /// Configures the SDK. Call once early in `main()` (before the first
  /// signer call). Subsequent calls replace the previous configuration.
  ///
  /// * [pinLength] — number of characters required for a valid PIN.
  ///   Defaults to `6`. Must be positive.
  /// * [requirePin] — when `true` (default) the SDK verifies the
  ///   supplied PIN before calling [signMessage], [signTransactionHash]
  ///   or [deleteWallet]. When `false` those methods forward directly
  ///   to the native plugin and any supplied `pin` is ignored.
  static void initialize({int pinLength = 6, bool requirePin = true}) {
    if (pinLength <= 0) {
      throw ArgumentError.value(pinLength, 'pinLength', 'must be positive');
    }
    _config = BmoniEmbeddedSdkConfig(
      pinLength: pinLength,
      requirePin: requirePin,
    );
  }

  // ------------------------------------------------------------------
  // Wallet provisioning
  // ------------------------------------------------------------------

  /// Provisions a new Ethereum wallet on the device.
  ///
  /// Generates a fresh random secp256k1 keypair, encrypts the private key
  /// with a platform-managed wrapping key (Android Keystore / iOS Secure
  /// Enclave), persists the ciphertext to secure app storage, zeroizes
  /// the plaintext key in RAM, and returns the EIP-55 checksummed
  /// Ethereum address (e.g. `0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed`).
  ///
  /// The returned address is also persisted by the SDK in
  /// [FlutterSecureStorage] so subsequent launches can read it back via
  /// [walletAddress] / [hasWallet] without re-running the native
  /// derivation (which is unavailable post-provisioning anyway).
  ///
  /// Throws a [BmoniSignerException] with
  /// [BmoniSignerErrorCode.walletAlreadyExists] if a wallet has already
  /// been provisioned on this device. Call [deleteWallet] first to
  /// re-provision.
  ///
  /// > Warning: deleting a wallet makes its on-chain address
  /// > unrecoverable from this device.
  static Future<String> initWallet() async {
    final String address =
        await BmoniEmbeddedSdkPlatform.instance.initWallet();
    await _walletAddressStore.write(address);
    return address;
  }

  /// Returns the EIP-55 checksummed address of the wallet currently
  /// provisioned on this device, or `null` if no wallet exists.
  ///
  /// Reads from the SDK's [FlutterSecureStorage]-backed cache populated
  /// by [initWallet]. The native BMONISigner SDK does not expose an
  /// equivalent — the address is only handed back at provisioning time
  /// — so this getter is the canonical way to recover it on
  /// subsequent launches.
  static Future<String?> walletAddress() => _walletAddressStore.read();

  /// Whether a wallet has been provisioned on this device.
  ///
  /// Convenience for `(await walletAddress()) != null`. Useful for
  /// branching the UI between "create wallet" and "show address"
  /// states without paying the cost of fetching the full string.
  static Future<bool> hasWallet() async =>
      (await _walletAddressStore.read()) != null;

  // ------------------------------------------------------------------
  // PIN management — independent of [requirePin]
  // ------------------------------------------------------------------

  /// Whether a PIN has been set on the device.
  ///
  /// Useful for branching the UI between "create PIN" and "enter PIN"
  /// states. Available regardless of the [requirePin] configuration.
  static Future<bool> hasPin() => _pinStore.hasPin();

  /// Persists [pin] for use by future signing operations.
  ///
  /// Throws [BmoniSignerErrorCode.pinInvalid] if [pin] is not exactly
  /// [pinLength] characters, or [BmoniSignerErrorCode.pinAlreadySet]
  /// if a PIN already exists on the device. Use [changePin] to rotate
  /// an existing PIN.
  static Future<void> setPin(String pin) async {
    _requireValidPin(pin);
    if (await _pinStore.hasPin()) {
      throw const BmoniSignerException(
        errorCode: BmoniSignerErrorCode.pinAlreadySet,
        message: 'A PIN is already set; call changePin or removePin first',
      );
    }
    await _pinStore.set(pin);
  }

  /// Rotates the device PIN.
  ///
  /// Verifies [currentPin] against the stored digest before persisting
  /// [newPin]. Throws [BmoniSignerErrorCode.pinNotSet],
  /// [BmoniSignerErrorCode.pinMismatch], or
  /// [BmoniSignerErrorCode.pinInvalid] as applicable. [newPin] must be
  /// exactly [pinLength] characters.
  static Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    _requireValidPin(newPin);
    await _requirePinMatch(currentPin);
    await _pinStore.set(newPin);
  }

  /// Removes the persisted PIN after verifying [currentPin].
  ///
  /// Once removed, signing / delete operations behave as if no PIN was
  /// ever set: with [requirePin] = `true` they raise
  /// [BmoniSignerErrorCode.pinNotSet]; with [requirePin] = `false`
  /// they simply forward to the native plugin.
  static Future<void> removePin(String currentPin) async {
    await _requirePinMatch(currentPin);
    await _pinStore.remove();
  }

  /// Returns whether [pin] matches the persisted digest.
  ///
  /// Returns `false` (rather than throwing) when no PIN is set, so this
  /// method can be used as a UI guard. Use [hasPin] when the absence of
  /// a PIN should be distinguished from a wrong PIN.
  static Future<bool> matchPin(String pin) => _pinStore.matches(pin);

  // ------------------------------------------------------------------
  // Signing & deletion (PIN-gated when requirePin is true)
  // ------------------------------------------------------------------

  /// Signs a pre-computed 32-byte digest with the wallet's private key.
  ///
  /// Use for canonical Ethereum digests such as an ERC-4337
  /// `userOpHash`, an EIP-712 typed-data digest, or a raw transaction
  /// hash. No prefix and no additional hashing is applied — the supplied
  /// hash is signed directly.
  ///
  /// [hashHex] must decode to exactly 32 bytes. The `0x` prefix is
  /// optional.
  ///
  /// When [requirePin] is `true` (default), [pin] is **required** and
  /// must match the PIN previously set via [setPin] / [changePin] —
  /// passing a wrong-length / wrong / missing PIN raises
  /// [BmoniSignerException]. When [requirePin] is `false`, [pin] is
  /// ignored.
  ///
  /// Returns the recoverable ECDSA signature as a `0x`-prefixed
  /// 130-character hex string in `r(32) || s(32) || v(1)` format, with
  /// `v ∈ {27, 28}` and `s` low-s normalized (EIP-2 compliant).
  static Future<String> signTransactionHash(
    String hashHex, {
    String? pin,
  }) async {
    await _enforcePinIfRequired(pin);
    return BmoniEmbeddedSdkPlatform.instance.signTransactionHash(hashHex);
  }

  /// Signs a UTF-8 [message] using the EIP-191 `personal_sign` prefix.
  ///
  /// Internally applies the prefix
  /// `"\x19Ethereum Signed Message:\n{len}" || msg`, computes Keccak-256
  /// over the prefixed payload, and signs the digest with secp256k1
  /// ECDSA. Use for SIWE, login challenges, and other off-chain auth
  /// flows.
  ///
  /// When [requirePin] is `true` (default), [pin] is **required** and
  /// must match the PIN previously set via [setPin] / [changePin].
  /// When [requirePin] is `false`, [pin] is ignored.
  ///
  /// Returns the recoverable ECDSA signature as a `0x`-prefixed
  /// 130-character hex string in `r(32) || s(32) || v(1)` format, with
  /// `v ∈ {27, 28}` and `s` low-s normalized (EIP-2 compliant).
  static Future<String> signMessage(String message, {String? pin}) async {
    await _enforcePinIfRequired(pin);
    return BmoniEmbeddedSdkPlatform.instance.signMessage(message);
  }

  /// Removes the encrypted private key file from device storage.
  ///
  /// Idempotent at the native layer: returns normally if no wallet
  /// exists. Deleting the wallet permanently severs this device's
  /// access to the wallet's on-chain address. The SDK also wipes the
  /// cached address so [walletAddress] / [hasWallet] reflect the new
  /// state immediately.
  ///
  /// When [requirePin] is `true` (default), [pin] is **required** and
  /// must match the PIN previously set via [setPin] / [changePin].
  /// When [requirePin] is `false`, [pin] is ignored.
  static Future<void> deleteWallet({String? pin}) async {
    await _enforcePinIfRequired(pin);
    await BmoniEmbeddedSdkPlatform.instance.deleteWallet();
    await _walletAddressStore.delete();
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  static void _requireValidPin(String pin) {
    if (pin.length != _config.pinLength) {
      throw BmoniSignerException(
        errorCode: BmoniSignerErrorCode.pinInvalid,
        message:
            'PIN must be exactly ${_config.pinLength} characters '
            '(received ${pin.length})',
      );
    }
  }

  /// When [requirePin] is `true`, verifies [pin] against the stored
  /// digest. When `false`, returns immediately without inspecting [pin].
  static Future<void> _enforcePinIfRequired(String? pin) async {
    if (!_config.requirePin) {
      return;
    }
    if (pin == null) {
      throw const BmoniSignerException(
        errorCode: BmoniSignerErrorCode.pinInvalid,
        message:
            'PIN is required (BmoniEmbeddedSdk.config.requirePin is true)',
      );
    }
    await _requirePinMatch(pin);
  }

  static Future<void> _requirePinMatch(String pin) async {
    if (!await _pinStore.hasPin()) {
      throw const BmoniSignerException(
        errorCode: BmoniSignerErrorCode.pinNotSet,
        message: 'No PIN has been set; call setPin first',
      );
    }
    if (!await _pinStore.matches(pin)) {
      throw const BmoniSignerException(
        errorCode: BmoniSignerErrorCode.pinMismatch,
        message: 'PIN does not match',
      );
    }
  }
}
