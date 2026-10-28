import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'passkey_authenticator.dart';

/// Bindings to `window.flowpayPasskey` (web/passkey.js).
@JS('flowpayPasskey')
external _FlowPayPasskeyJs? get _bridge;

extension type _FlowPayPasskeyJs._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> supported();
  external JSPromise<JSString> register(JSString userName, JSString salt);
  external JSPromise<JSAny?> forget(JSString credentialId);
  external JSPromise<JSString> prf(JSString credentialId, JSString salt);
}

PasskeyAuthenticator createPlatformPasskeyAuthenticator() => WebPasskeyAuthenticator();

class WebPasskeyAuthenticator implements PasskeyAuthenticator {
  @override
  Future<bool> isSupported() async {
    final bridge = _bridge;
    if (bridge == null) return false;
    try {
      return (await bridge.supported().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PasskeyRegistration> register({required String userName, required Uint8List salt}) async {
    final bridge = _requireBridge();
    final String raw;
    try {
      raw = (await bridge.register(userName.toJS, _b64u(salt).toJS).toDart).toDart;
    } catch (e) {
      throw _map(e);
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final prf = json['prf'] as String?;
    return PasskeyRegistration(
      json['id'] as String,
      prf == null ? null : base64Url.decode(base64Url.normalize(prf)),
    );
  }

  @override
  Future<void> forget(String credentialId) async {
    try {
      await _bridge?.forget(credentialId.toJS).toDart;
    } catch (_) {
      // Best effort only.
    }
  }

  @override
  Future<Uint8List> prfSecret({required String credentialId, required Uint8List salt}) async {
    final bridge = _requireBridge();
    try {
      final out = (await bridge.prf(credentialId.toJS, _b64u(salt).toJS).toDart).toDart;
      return base64Url.decode(base64Url.normalize(out));
    } catch (e) {
      throw _map(e);
    }
  }

  _FlowPayPasskeyJs _requireBridge() {
    final bridge = _bridge;
    if (bridge == null) throw const PasskeyException('Passkeys are not available in this browser.');
    return bridge;
  }

  static String _b64u(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// WebAuthn reports a dismissed prompt as NotAllowedError / AbortError.
  static PasskeyException _map(Object e) {
    final text = e.toString();
    final cancelled = text.contains('NotAllowedError') || text.contains('AbortError');
    return PasskeyException(
      cancelled ? 'Passkey confirmation was cancelled.' : text.replaceFirst(RegExp(r'^(Error|JavaScriptError):\s*'), ''),
      cancelled: cancelled,
    );
  }
}
