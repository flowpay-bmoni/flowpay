import 'dart:typed_data';

import 'passkey_platform_stub.dart' if (dart.library.js_interop) 'passkey_platform_web.dart';

/// A passkey (WebAuthn credential with the PRF extension) that can derive a
/// secret only after the user verifies with Face ID / fingerprint / device PIN.
///
/// The vault uses that secret instead of the PIN to encrypt the wallet key, so a
/// copy of the encrypted key is useless without the passkey.
abstract class PasskeyAuthenticator {
  /// Whether this platform can create PRF passkeys (false on native and in tests).
  Future<bool> isSupported();

  /// Creates a passkey labelled [userName], asking it to evaluate PRF for [salt]
  /// right away. Throws [PasskeyException] if the user cancels or PRF isn't supported.
  Future<PasskeyRegistration> register({required String userName, required Uint8List salt});

  /// Best effort: asks the browser to drop a passkey FlowPay won't use (e.g. a
  /// setup that failed half-way), so it doesn't linger in the user's passkey list.
  Future<void> forget(String credentialId);

  /// Asks the user to verify, then returns the passkey's 32-byte PRF output for [salt].
  Future<Uint8List> prfSecret({required String credentialId, required Uint8List salt});

  /// The browser implementation on web; an unsupported stub elsewhere.
  factory PasskeyAuthenticator.platform() => createPlatformPasskeyAuthenticator();
}

class PasskeyRegistration {
  final String credentialId;
  /// PRF output for the salt, when the browser evaluates PRF at creation.
  final Uint8List? prfSecret;
  const PasskeyRegistration(this.credentialId, this.prfSecret);
}

class PasskeyException implements Exception {
  final String message;
  /// The user dismissed the prompt (not a wrong credential).
  final bool cancelled;
  const PasskeyException(this.message, {this.cancelled = false});

  @override
  String toString() => message;
}

/// Native platforms and tests: passkeys aren't offered (the PIN + OS keychain is used).
class UnsupportedPasskeyAuthenticator implements PasskeyAuthenticator {
  const UnsupportedPasskeyAuthenticator();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<PasskeyRegistration> register({required String userName, required Uint8List salt}) =>
      throw const PasskeyException('Passkeys are not available on this device.');

  @override
  Future<void> forget(String credentialId) async {}

  @override
  Future<Uint8List> prfSecret({required String credentialId, required Uint8List salt}) =>
      throw const PasskeyException('Passkeys are not available on this device.');
}
