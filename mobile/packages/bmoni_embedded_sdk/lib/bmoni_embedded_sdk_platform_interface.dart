// SPDX-License-Identifier: Apache-2.0
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'bmoni_embedded_sdk_method_channel.dart';

abstract class BmoniEmbeddedSdkPlatform extends PlatformInterface {
  /// Constructs a BmoniEmbeddedSdkPlatform.
  BmoniEmbeddedSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static BmoniEmbeddedSdkPlatform _instance = MethodChannelBmoniEmbeddedSdk();

  /// The default instance of [BmoniEmbeddedSdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelBmoniEmbeddedSdk].
  static BmoniEmbeddedSdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BmoniEmbeddedSdkPlatform] when
  /// they register themselves.
  static set instance(BmoniEmbeddedSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Provisions a new Ethereum wallet backed by the platform's secure key
  /// storage and returns the EIP-55 checksummed address.
  Future<String> initWallet() {
    throw UnimplementedError('initWallet() has not been implemented.');
  }

  /// Signs a pre-computed 32-byte transaction or UserOperation hash.
  Future<String> signTransactionHash(String hashHex) {
    throw UnimplementedError('signTransactionHash() has not been implemented.');
  }

  /// Signs a UTF-8 message using the EIP-191 `personal_sign` prefix.
  Future<String> signMessage(String message) {
    throw UnimplementedError('signMessage() has not been implemented.');
  }

  /// Deletes the wallet's encrypted private key file from on-device
  /// storage. Idempotent: returns normally if no wallet exists.
  Future<void> deleteWallet() {
    throw UnimplementedError('deleteWallet() has not been implemented.');
  }
}
