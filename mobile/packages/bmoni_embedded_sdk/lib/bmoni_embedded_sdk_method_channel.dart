// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bmoni_embedded_sdk_platform_interface.dart';
import 'src/bmoni_signer_exception.dart';

/// Wallet/signing methods exposed by the plugin's [MethodChannel].
///
/// Each entry's [methodName] is the exact string sent over the channel —
/// the native Android (`ChannelMethods`) and iOS (`ChannelMethods`)
/// counterparts share these identifiers. Adding a new entry forces every
/// consumer of this enum to handle it.
@visibleForTesting
enum SignerChannelMethod {
  initWallet('initWallet'),
  signTransactionHash('signTransactionHash'),
  signMessage('signMessage'),
  deleteWallet('deleteWallet');

  const SignerChannelMethod(this.methodName);

  /// Wire-level identifier sent to the native plugin.
  final String methodName;
}

/// An implementation of [BmoniEmbeddedSdkPlatform] that uses method channels.
class MethodChannelBmoniEmbeddedSdk extends BmoniEmbeddedSdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('bmoni_embedded_sdk');

  static const String _signerErrorCode = 'BMONI_SIGNER_ERROR';

  @override
  Future<String> initWallet() {
    return _invokeSignerString(SignerChannelMethod.initWallet);
  }

  @override
  Future<String> signTransactionHash(String hashHex) {
    return _invokeSignerString(
      SignerChannelMethod.signTransactionHash,
      <String, Object?>{'hashHex': hashHex},
    );
  }

  @override
  Future<String> signMessage(String message) {
    return _invokeSignerString(
      SignerChannelMethod.signMessage,
      <String, Object?>{'message': message},
    );
  }

  @override
  Future<void> deleteWallet() {
    return _invokeSignerVoid(SignerChannelMethod.deleteWallet);
  }

  /// Invokes a signer method that is expected to return a [String] value
  /// and converts native `BMONI_SIGNER_ERROR` [PlatformException]s into a
  /// strongly-typed [BmoniSignerException].
  Future<String> _invokeSignerString(
    SignerChannelMethod method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final String? value = await methodChannel.invokeMethod<String>(
        method.methodName,
        arguments,
      );
      if (value == null) {
        throw BmoniSignerException(
          errorCode: BmoniSignerErrorCode.unexpectedNativeNull,
          message: 'Native call ${method.methodName} returned null',
        );
      }
      return value;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  /// Invokes a signer method that does not return a value.
  Future<void> _invokeSignerVoid(
    SignerChannelMethod method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await methodChannel.invokeMethod<void>(method.methodName, arguments);
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
  }

  /// Converts a native `BMONI_SIGNER_ERROR` [PlatformException] into a
  /// [BmoniSignerException]. Other [PlatformException]s pass through
  /// unchanged.
  Object _mapPlatformException(PlatformException e) {
    if (e.code != _signerErrorCode) {
      return e;
    }
    final Object? details = e.details;
    final int errorCode = details is Map
        ? (details['errorCode'] as num?)?.toInt() ?? -1
        : -1;
    return BmoniSignerException(
      errorCode: errorCode,
      message: e.message ?? 'Unknown signer error',
    );
  }
}
