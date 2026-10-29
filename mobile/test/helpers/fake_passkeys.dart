import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flowpay_mobile/core/stellar/passkey/passkey_authenticator.dart';

/// Behaves like a WebAuthn PRF authenticator: the secret is a function of a
/// device-held key, the credential and the salt; prompts can be cancelled.
class FakePasskeys implements PasskeyAuthenticator {
  final String deviceSecret;
  bool supported;
  bool cancelNext = false;
  int prompts = 0;
  /// Like Chrome/Safari that evaluate PRF during create (one prompt to enable).
  bool prfAtCreate;
  final List<String> forgotten = [];
  /// Cancel the PRF prompt that follows a successful registration.
  bool cancelPrfAfterRegister = false;
  FakePasskeys({this.deviceSecret = 'device-a', this.supported = true, this.prfAtCreate = false});

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<PasskeyRegistration> register({required String userName, required Uint8List salt}) async {
    prompts++;
    if (cancelNext) {
      cancelNext = false;
      throw const PasskeyException('cancelled', cancelled: true);
    }
    final id = 'cred-${userName.hashCode}-$prompts';
    return PasskeyRegistration(id, prfAtCreate ? _secret(id, salt) : null);
  }

  @override
  Future<void> forget(String credentialId) async => forgotten.add(credentialId);

  Uint8List _secret(String credentialId, Uint8List salt) =>
      Uint8List.fromList(Hmac(sha256, utf8.encode(deviceSecret)).convert([...utf8.encode(credentialId), ...salt]).bytes);

  @override
  Future<Uint8List> prfSecret({required String credentialId, required Uint8List salt}) async {
    prompts++;
    if (cancelPrfAfterRegister) {
      cancelPrfAfterRegister = false;
      throw const PasskeyException('cancelled', cancelled: true);
    }
    if (cancelNext) {
      cancelNext = false;
      throw const PasskeyException('cancelled', cancelled: true);
    }
    return _secret(credentialId, salt);
  }
}
