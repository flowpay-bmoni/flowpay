## 0.0.2

* **Fix:** corrected the native `BmoniSignerErrorCode` constants. The
  `0x3xxxxxxx` values shipped in 0.0.1 were each low by `0x10000`
  (`walletAlreadyExists` was `0x30000010`, the native SDK reports
  `0x30010010`), so `catch`/`switch` branches comparing against them
  never matched a real native failure. The values are now read out of
  the shipped binaries: `javap -constants
  me.bkey.ip.bmonisigner.BMONISigner` on the Android AAR and the
  constant getters in `BMONISigner.framework` both give the
  `0x3001xxxx` block, and a device run confirms `initWallet` on an
  existing wallet reports `0x30010010`.

## 0.0.1

* Initial release of the Bmoni Embedded SDK for Flutter.
* `BmoniEmbeddedSdk.initialize(pinLength: …, requirePin: …)` lets the
  consumer pick the PIN length (default `6`) and whether sign / delete
  operations verify a PIN before invoking the native plugin (default
  `true`). The active configuration is exposed via
  `BmoniEmbeddedSdk.config`.
* `BmoniEmbeddedSdk` static facade exposing the BMONISigner wallet APIs:
  * `initWallet()` returns the EIP-55 checksummed Ethereum address.
  * `signTransactionHash(hashHex, pin: …)` signs a pre-computed 32-byte
    digest. PIN-gated when `requirePin: true`.
  * `signMessage(message, pin: …)` applies the EIP-191 `personal_sign`
    prefix. PIN-gated when `requirePin: true`.
  * `deleteWallet(pin: …)` removes the encrypted private key
    (idempotent at the native layer). PIN-gated when
    `requirePin: true`.
  * `walletAddress()` / `hasWallet()` read back the EIP-55 address
    cached by the SDK in `flutter_secure_storage` so consumers can
    recover it across launches (the native BMONISigner SDK only
    returns the address at provisioning time). The cache is
    populated on `initWallet()` success and wiped on `deleteWallet()`
    success.
* PIN management via `setPin`, `changePin`, `removePin`, `matchPin`,
  `hasPin` — independent of `requirePin`. PINs are exactly
  `BmoniEmbeddedSdk.pinLength` characters (configured at
  `initialize`); `setPin` / `changePin` raise
  `BmoniSignerErrorCode.pinInvalid` for inputs of any other length.
  The PIN is persisted as a salted PBKDF2-HMAC-SHA256 digest inside
  `flutter_secure_storage` (Android Keystore / iOS Keychain); the raw
  PIN never touches disk.
* Typed `BmoniSignerException` and `BmoniSignerErrorCode` for ergonomic
  native-error handling. Codes in the `0x3xxxxxxx` range originate in
  the native BMONISigner SDK; `0x4xxxxxxx` codes are SDK-level (PIN
  gating).
* Android plugin wraps `me.bkey.ip.bmonisigner.BMONISigner` 1.0.0 and
  dispatches signing work on a background executor.
* iOS plugin wraps the BMONISigner Swift API (`initWallet`,
  `signTransactionHash`, `signMessage`, `deleteWallet`) and dispatches
  signing work on a `userInitiated` queue.
* Podspec vendors `BMONISigner.xcframework` 1.0.0 for CocoaPods
  consumers (matching the SwiftPM binary target).
* Example app with a full wallet / signing demo.
