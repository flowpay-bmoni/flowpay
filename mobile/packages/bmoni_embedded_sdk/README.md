# bmoni_embedded_sdk

[![Pub Version](https://img.shields.io/pub/v/bmoni_embedded_sdk)](https://pub.dev/packages/bmoni_embedded_sdk)
[![Platform Support](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue)](#platform-support)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)

A Flutter plugin that exposes the **BMONISigner** native SDKs for Ethereum wallet provisioning and transaction/message signing on Android and iOS.

> **Security First:** Private keys are generated on-device, encrypted with a platform-managed wrapping key (Android Keystore on Android, Secure Enclave on iOS), and persisted only as ciphertext. Plaintext keys never leave the secure boundary and are zeroized in RAM after each operation.

---

## ✨ Features

- **Customizable PIN policies:** `initialize(pinLength: …, requirePin: …)` — opt into a custom PIN length (default `6`) and toggle whether sign/delete operations verify the PIN before invoking the native plugin (default `true`).
- **One-tap Provisioning:** `initWallet()` — provision a fresh secp256k1 wallet and return its EIP-55 checksummed address. The address is persisted in the SDK's secure-storage cache so subsequent launches can read it back via `walletAddress()` / `hasWallet()`.
- **PIN Management:** `setPin`, `changePin`, `removePin`, `matchPin`, `hasPin`. The PIN is persisted as a salted PBKDF2-HMAC-SHA256 digest inside [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage), which sits on top of Android Keystore / iOS Keychain.
- **Robust Signing:**
  - `signTransactionHash(hashHex, pin: …)` — sign a pre-computed 32-byte digest (ERC-4337 `userOpHash`, EIP-712 digest, raw transaction hash, etc.).
  - `signMessage(message, pin: …)` — sign a UTF-8 message with the EIP-191 `personal_sign` prefix (SIWE, login challenges, etc.).
- **Lifecycle Management:** `deleteWallet(pin: …)` — remove the encrypted private key from device storage. Idempotent at the native layer.
- **Typed Exceptions:** Strongly-typed `BmoniSignerException` carrying the native or SDK-level error code for easy branching.

*Note: All signatures are returned as `0x`-prefixed 130-character hex strings in recoverable `r(32) || s(32) || v(1)` format with `v ∈ {27, 28}` and low-s normalized (EIP-2 compliant), so they can be verified server-side with `ecrecover`.*

---

## 🚀 Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  bmoni_embedded_sdk: ^0.0.2
```

Then run:

```sh
flutter pub get
```

---

## 💻 Usage

`BmoniEmbeddedSdk` is a static facade — call its methods directly without instantiating it. Configure it once early in `main()`:

```dart
import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk.dart';

void main() {
  // pinLength defaults to 6. requirePin defaults to true.
  BmoniEmbeddedSdk.initialize(pinLength: 6, requirePin: true);
  runApp(const MyApp());
}
```

### Basic Wallet Flow

```dart
try {
  // 1. Provision a wallet (one-time per device). The returned address
  //    is also cached in secure storage; subsequent launches can read
  //    it back without re-provisioning.
  final String address = await BmoniEmbeddedSdk.hasWallet()
      ? (await BmoniEmbeddedSdk.walletAddress())!
      : await BmoniEmbeddedSdk.initWallet();
  print('Wallet address: $address');

  // 2. Set the PIN that gates future signing operations.
  //    PINs are exactly `BmoniEmbeddedSdk.pinLength` (default 6)
  //    characters; other lengths throw `pinInvalid`.
  if (!await BmoniEmbeddedSdk.hasPin()) {
    await BmoniEmbeddedSdk.setPin('123456');
  }

  // 3. Sign a personal message (EIP-191) — requires a matching PIN
  //    when requirePin is true.
  final messageSig = await BmoniEmbeddedSdk.signMessage(
    'Welcome to BMONI!',
    pin: '123456',
  );

  // 4. Sign a 32-byte digest (e.g. ERC-4337 userOpHash).
  final hashSig = await BmoniEmbeddedSdk.signTransactionHash(
    '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8',
    pin: '123456',
  );
} on BmoniSignerException catch (e) {
  switch (e.errorCode) {
    case BmoniSignerErrorCode.walletAlreadyExists:
      // Re-provision flow — destructive, on-chain address becomes
      // unrecoverable from this device.
      await BmoniEmbeddedSdk.deleteWallet(pin: '123456');
      await BmoniEmbeddedSdk.initWallet();
      break;
    case BmoniSignerErrorCode.pinMismatch:
    case BmoniSignerErrorCode.pinNotSet:
      // Prompt the user to (re)enter / set their PIN.
      break;
  }
}
```

### ⚙️ Configuration

`BmoniEmbeddedSdk.initialize(...)` accepts:

| Parameter | Type | Default | Effect |
| --- | --- | --- | --- |
| `pinLength` | `int` | `6` | Number of characters required for a valid PIN. Enforced by `setPin` / `changePin`. |
| `requirePin` | `bool` | `true` | Whether `signMessage` / `signTransactionHash` / `deleteWallet` verify a supplied PIN against the stored digest before forwarding to the native plugin. |

The active configuration is exposed via `BmoniEmbeddedSdk.config` (and the convenience getters `BmoniEmbeddedSdk.pinLength` / `BmoniEmbeddedSdk.requirePin`) so app-side UI can adapt — e.g. render a PIN input of the right length, or hide PIN flows entirely when gating is off.

#### `requirePin: false` mode

When the developer chooses to manage authentication elsewhere (biometrics, OS lockscreen, server-side challenge, …), pass `requirePin: false`. In that mode:

* `signMessage`, `signTransactionHash` and `deleteWallet` forward straight to the native plugin and **ignore** any supplied `pin` argument.
* The PIN management methods (`setPin`, `changePin`, …) keep working — toggling `requirePin` only changes whether a stored PIN is enforced as a gate.

```dart
BmoniEmbeddedSdk.initialize(requirePin: false);

await BmoniEmbeddedSdk.initWallet();
final sig = await BmoniEmbeddedSdk.signMessage('hi'); // no pin required
```

### 🔍 Reading the Wallet Address Back

The native BMONISigner SDK only returns the address from the call that originally provisioned the wallet — there is no `getAddress()` on the native side. The Dart facade transparently caches the address in `flutter_secure_storage` after `initWallet()` succeeds and wipes it on `deleteWallet()`, so you can recover it at any time:

```dart
if (await BmoniEmbeddedSdk.hasWallet()) {
  final String address = (await BmoniEmbeddedSdk.walletAddress())!;
  // Render the wallet UI, fetch on-chain state, etc.
} else {
  // Show the "create wallet" flow → call BmoniEmbeddedSdk.initWallet().
}
```

### 🔐 PIN Management

The SDK enforces a fixed-length PIN equal to `BmoniEmbeddedSdk.pinLength`. Calling `setPin` / `changePin` with any other length throws `BmoniSignerException(errorCode: pinInvalid)`. The PIN is persisted as a salted PBKDF2-HMAC-SHA256 digest inside [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage); the raw PIN never touches disk.

```dart
// One-time setup.
await BmoniEmbeddedSdk.setPin('123456');

// Rotate.
await BmoniEmbeddedSdk.changePin(currentPin: '123456', newPin: '654321');

// Verify without throwing — useful for UI prompts.
final ok = await BmoniEmbeddedSdk.matchPin('654321');

// Tear down (e.g. on logout).
await BmoniEmbeddedSdk.removePin('654321');
```

### 🛡️ Server-Side Verification

Signatures are ECDSA recoverable, so verifiers only need the address returned by `initWallet()`:

```solidity
address recovered = ecrecover(hash, v, r, s);
require(recovered == expectedAddress, "invalid signature");
```

---

## 🛑 Error Handling

Native failures surface as a [`BmoniSignerException`](lib/src/bmoni_signer_exception.dart) carrying both a numeric `errorCode` and a human-readable `message`. Compare against the [`BmoniSignerErrorCode`](lib/src/bmoni_signer_exception.dart) constants:

| Constant | Hex | Meaning |
| --- | --- | --- |
| `walletAlreadyExists` | `0x30010010` | `initWallet` called while a wallet is already on disk. |
| `signInvalidMessage` | `0x30010001` | The supplied message could not be processed. |
| `signInvalidPrivateKey` | `0x30010002` | Stored key could not be recovered / decrypted. |
| `signInvalidHash` | `0x30010003` | Hash argument was not a valid 32-byte hex string. |
| `signProcess` | `0x30010004` | Generic ECDSA signing failure. |
| `signKeygen` | `0x30010005` | secp256k1 keypair generation failed. |
| `signEip55` | `0x30010006` | EIP-55 checksum derivation failed. |
| `pinNotSet` | `0x40000001` | A PIN-gated call was attempted but no PIN exists. |
| `pinAlreadySet` | `0x40000002` | `setPin` called while a PIN already exists. |
| `pinMismatch` | `0x40000003` | The supplied PIN did not match the stored digest. |
| `pinInvalid` | `0x40000004` | The supplied PIN was empty / otherwise invalid. |
| `unexpectedNativeNull` | `0x50000001` | A native method that promised a non-null result returned `null` (plugin-bridge bug). |

* **`0x3001xxxx`** range originate in the native BMONISigner SDK.
* **`0x4xxxxxxx`** range are SDK-level (PIN gating, etc.).
* **`0x5xxxxxxx`** range come from the Dart-side method channel bridge.

---

## 📱 Platform Support

| Android | iOS |
|---------|-----|
| ✅      | ✅  |

## 📋 Requirements

- Flutter `>=3.3.0`
- Dart SDK `^3.11.5`
- iOS `13.0+`
- Android `minSdk 24+`

---

## 💡 Example

See the [`example`](example) directory for a full working demo with wallet provisioning, message signing, and hash signing flows.

---

## 📄 License

Copyright 2026 Bkey, Inc.

Licensed under the [Apache License, Version 2.0](LICENSE) — you may use, modify, and distribute the SDK (including in proprietary applications) provided you preserve the copyright and license notices and comply with the terms in the [LICENSE](LICENSE) file.

For commercial support or enterprise inquiries, contact [developers@bkey.me](mailto:developers@bkey.me).
