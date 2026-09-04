// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists a PBKDF2-hashed PIN inside [FlutterSecureStorage].
///
/// The raw PIN never touches disk: only a random per-device salt and the
/// derived PBKDF2-HMAC-SHA256 digest are persisted. Comparison runs in
/// constant time. The underlying secure storage is itself encrypted by
/// the platform key store (Android Keystore / iOS Keychain), so the
/// derivation is defense in depth — not the primary safeguard.
///
/// The 100 000-iteration PBKDF2 derivation runs on a background isolate
/// via [Isolate.run] so the UI thread stays responsive during PIN
/// set / match / change.
class PinStore {
  /// Creates a [PinStore] backed by [storage] (a default
  /// [FlutterSecureStorage] is used when omitted).
  PinStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _saltKey = 'bmoni_pin_salt_v1';
  static const String _hashKey = 'bmoni_pin_hash_v1';
  static const int _saltLength = 16;
  static const int _hashLength = 32;

  /// PBKDF2 iteration count. Tuned to take ~100 ms on a mid-range
  /// mobile CPU; safe to bump in a future migration.
  static const int _iterations = 100000;

  final FlutterSecureStorage _storage;

  /// Whether a PIN is currently set on the device.
  Future<bool> hasPin() async {
    final String? hash = await _storage.read(key: _hashKey);
    return hash != null;
  }

  /// Persists [pin] (overwriting any existing PIN).
  ///
  /// Callers that need "set only when absent" semantics should branch on
  /// [hasPin] first.
  Future<void> set(String pin) async {
    final Uint8List salt = _randomBytes(_saltLength);
    final Uint8List hash = await Isolate.run(
      () => _pbkdf2(pin, salt, _iterations, _hashLength),
    );
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _hashKey, value: base64Encode(hash));
  }

  /// Returns `true` iff [pin] hashes to the persisted digest. Returns
  /// `false` if no PIN has been set.
  Future<bool> matches(String pin) async {
    final String? saltStr = await _storage.read(key: _saltKey);
    final String? hashStr = await _storage.read(key: _hashKey);
    if (saltStr == null || hashStr == null) {
      return false;
    }
    final Uint8List salt = base64Decode(saltStr);
    final Uint8List expected = base64Decode(hashStr);
    final Uint8List actual = await Isolate.run(
      () => _pbkdf2(pin, salt, _iterations, _hashLength),
    );
    return _constantTimeEquals(actual, expected);
  }

  /// Removes the persisted PIN salt + hash. Idempotent.
  Future<void> remove() async {
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018 §5.2).
  ///
  /// Pure / synchronous and side-effect free so it can be safely
  /// dispatched onto a worker isolate via [Isolate.run].
  static Uint8List _pbkdf2(
    String password,
    Uint8List salt,
    int iterations,
    int dkLen,
  ) {
    final Hmac hmac = Hmac(sha256, utf8.encode(password));
    const int hLen = 32;
    final int blockCount = (dkLen + hLen - 1) ~/ hLen;
    final BytesBuilder out = BytesBuilder();

    for (int i = 1; i <= blockCount; i++) {
      final ByteData blockIndex = ByteData(4)..setUint32(0, i);
      final Uint8List initial = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..setRange(salt.length, salt.length + 4, blockIndex.buffer.asUint8List());

      // `Digest.bytes` already returns a fresh `Uint8List` per call, so
      // wrapping it in `Uint8List.fromList(...)` would just allocate
      // another copy in every iteration. We only mutate `t`, not `u`.
      List<int> u = hmac.convert(initial).bytes;
      final Uint8List t = Uint8List.fromList(u);

      for (int j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (int k = 0; k < hLen; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }

    // `BytesBuilder.toBytes()` and `Uint8List.sublist()` both return a
    // `Uint8List`, so no extra wrapping is needed.
    return out.toBytes().sublist(0, dkLen);
  }

  static Uint8List _randomBytes(int length) {
    final Random rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  /// Length-constant comparison of two byte sequences.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
