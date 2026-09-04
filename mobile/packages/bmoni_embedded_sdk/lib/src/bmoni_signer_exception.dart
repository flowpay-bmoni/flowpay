// SPDX-License-Identifier: Apache-2.0
/// Exception thrown by the Bmoni Embedded SDK signer APIs.
///
/// Wraps the native `BMONISignerException` (Android) or `BMONISignerError`
/// (iOS) and exposes a numeric [errorCode] alongside the human-readable
/// [message]. Use the [BmoniSignerErrorCode] constants to compare against
/// well-known error conditions returned by the native SDKs.
class BmoniSignerException implements Exception {
  /// Creates a [BmoniSignerException] with the given [errorCode] and
  /// [message].
  const BmoniSignerException({required this.errorCode, required this.message});

  /// Numeric error code reported by the native SDK.
  ///
  /// On Android these mirror the constants exposed on
  /// `me.bkey.ip.bmonisigner.BMONISigner` (for example
  /// [BmoniSignerErrorCode.walletAlreadyExists]). On iOS the SDK reports
  /// status codes via the `BMONISignerError` enum; the same numeric values
  /// are forwarded here when available.
  final int errorCode;

  /// Human-readable description supplied by the native SDK.
  final String message;

  /// Hex-formatted representation of [errorCode] (matching the native
  /// SDK's logging style).
  String get errorCodeHex => '0x${errorCode.toRadixString(16).toUpperCase()}';

  @override
  String toString() => 'BmoniSignerException($errorCodeHex): $message';
}

/// Numeric error codes shared across platforms.
///
/// The `0x3001xxxx` range mirrors the native `BMONISigner` constants
/// documented on `me.bkey.ip.bmonisigner.BMONISigner`. The `0x4xxxxxxx`
/// range is reserved for SDK-side errors such as PIN gating.
///
/// Use these constants to branch on specific failure modes without
/// depending on the message text.
abstract final class BmoniSignerErrorCode {
  /// The wallet operation completed successfully. Provided for parity with
  /// the native SDK; it is never thrown via [BmoniSignerException].
  static const int success = 0;

  // ------------------------------------------------------------------
  // Native BMONISigner error codes (0x3001xxxx).
  //
  // Read out of the shipped binaries rather than transcribed: `javap
  // -constants me.bkey.ip.bmonisigner.BMONISigner` and the constant
  // getters in BMONISigner.framework both give this 0x3001xxxx block.
  // ------------------------------------------------------------------

  /// The supplied message argument was invalid (empty / not UTF-8).
  static const int signInvalidMessage = 0x30010001;

  /// The on-disk wallet private key could not be decrypted or recovered.
  static const int signInvalidPrivateKey = 0x30010002;

  /// The supplied transaction hash was not a valid 32-byte hex string.
  static const int signInvalidHash = 0x30010003;

  /// A general signing pipeline error occurred (decryption, ECDSA, etc.).
  static const int signProcess = 0x30010004;

  /// Generating a fresh secp256k1 keypair failed.
  static const int signKeygen = 0x30010005;

  /// Computing the EIP-55 checksummed address from the public key failed.
  static const int signEip55 = 0x30010006;

  /// `initWallet` was called while a wallet already exists on disk. Call
  /// `deleteWallet` first if you intend to overwrite it.
  static const int walletAlreadyExists = 0x30010010;

  // ------------------------------------------------------------------
  // SDK-level PIN gating errors (0x4xxxxxxx).
  // ------------------------------------------------------------------

  /// A PIN-gated operation was attempted but no PIN has been set on the
  /// device. Call `setPin` first.
  static const int pinNotSet = 0x40000001;

  /// `setPin` was called while a PIN already exists. Use `changePin` (or
  /// `removePin` followed by `setPin`) instead.
  static const int pinAlreadySet = 0x40000002;

  /// The supplied PIN did not match the stored digest.
  static const int pinMismatch = 0x40000003;

  /// The supplied PIN was rejected as invalid (e.g. empty string,
  /// wrong length, or missing while `requirePin` is `true`).
  static const int pinInvalid = 0x40000004;

  // ------------------------------------------------------------------
  // Plugin-bridge errors (0x5xxxxxxx).
  // ------------------------------------------------------------------

  /// A native method that promised a non-null result returned `null`.
  ///
  /// Indicates a bug in the platform plugin (Android / iOS) — the
  /// channel handler short-circuited without supplying the expected
  /// payload. Usually surfaced from `MethodChannelBmoniEmbeddedSdk`
  /// when a sign / init call returns `null`.
  static const int unexpectedNativeNull = 0x50000001;
}
