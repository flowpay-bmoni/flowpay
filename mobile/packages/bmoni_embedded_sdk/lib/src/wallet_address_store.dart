// SPDX-License-Identifier: Apache-2.0
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the EIP-55 checksummed Ethereum address that
/// `BmoniEmbeddedSdk.initWallet` returns, so the address survives
/// across app launches without consumers needing to roll their own
/// cache.
///
/// The native BMONISigner SDK only returns the address once at
/// provisioning time — there is no native "get address" entry point.
/// The encrypted private key on disk is the only persistent native
/// artifact; this store is the SDK's own bookkeeping layer over
/// [FlutterSecureStorage] (Android Keystore / iOS Keychain).
class WalletAddressStore {
  /// Creates a [WalletAddressStore] backed by [storage] (a default
  /// [FlutterSecureStorage] is used when omitted).
  WalletAddressStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _addressKey = 'bmoni_wallet_address_v1';

  final FlutterSecureStorage _storage;

  /// Returns the persisted EIP-55 address, or `null` if no wallet is
  /// known to the SDK on this device.
  Future<String?> read() => _storage.read(key: _addressKey);

  /// Persists [address]. Overwrites any previously stored value.
  Future<void> write(String address) =>
      _storage.write(key: _addressKey, value: address);

  /// Removes the persisted address. Idempotent.
  Future<void> delete() => _storage.delete(key: _addressKey);
}
