# bmoni_embedded_sdk_example

End-to-end demo for the [`bmoni_embedded_sdk`](../) Flutter plugin.

The app exercises every public API exposed by `BmoniEmbeddedSdk` and
lets you switch the SDK between PIN-gated and direct-call modes at
runtime via the **Settings ⚙** action in the AppBar.

| API | UI control | Demonstrates |
| --- | --- | --- |
| `initialize(...)` | Settings ⚙ icon → bottom sheet | Toggles `pinLength` (4 / 6 / 8) and `requirePin` at runtime; the status banner, sign / delete buttons and PIN section all react live. |
| `initWallet()` | "Provision wallet" button | Provisions a fresh secp256k1 keypair, returns the EIP-55 address, and caches it for subsequent launches. |
| `walletAddress()` / `hasWallet()` | Wallet card auto-hydrates on launch | Reads the cached address back so the wallet card stays populated across cold starts. |
| `setPin` / `changePin` / `removePin` / `matchPin` | PIN section buttons | Manages the PIN persisted in `flutter_secure_storage`. |
| `signMessage(message, pin: …)` | "Sign message" button | Applies the EIP-191 `personal_sign` prefix and returns a 65-byte recoverable signature. PIN-gated when `requirePin: true`; called directly otherwise. |
| `signTransactionHash(hashHex, pin: …)` | "Sign hash" button | Signs a pre-computed 32-byte digest (ERC-4337 `userOpHash`, EIP-712 digest, …). Same gating policy as `signMessage`. |
| `deleteWallet(pin: …)` | "Delete wallet" trash icon (top-right of the wallet card) | Removes the encrypted private key from device storage. Same gating policy as `signMessage`. |

Errors surface as floating `SnackBar`s; successful actions emit a
secondary-coloured toast. The status banner above the wallet card shows
two monospaced chips with the live `pinLength` and `requirePin`
configuration so you always know which mode you're in.

## SDK initialisation

The example calls `BmoniEmbeddedSdk.initialize(...)` once at startup:

```dart
void main() {
  BmoniEmbeddedSdk.initialize(pinLength: 6, requirePin: true);
  runApp(const MyApp());
}
```

Open the Settings sheet at any time to flip those knobs and see the
UI adapt — the **PIN section card** stays available so you can still
manage stored credentials, but signing / deletion happen without a
PIN prompt when `requirePin: false`.

## Run the demo app

```bash
cd example
flutter pub get
flutter run
```

### Android prerequisites

The Android build resolves
`me.bkey.ip:bmonisigner:1.0.0` from the Bkey GitHub Packages Maven
registry.

1. **Maven repo registration.** Already wired in
   [`android/build.gradle.kts`](android/build.gradle.kts) — this is the
   exact snippet any app consuming `bmoni_embedded_sdk` needs in its
   own `allprojects { repositories { … } }` block (Gradle does not let
   a plugin inject repos into its consumer).
2. **Credentials.** Add them to `~/.gradle/gradle.properties`:

   ```properties
   bkey.gpr.user=<github-username>
   bkey.gpr.key=<github-personal-access-token>
   ```

   …or export `USERNAME` / `TOKEN` environment variables before building.

If the resolution is missing, the build fails with:

```
Could not find me.bkey.ip:bmonisigner:1.0.0.
```

which means step 1 is missing; a 401 during download means step 2 is.

### iOS prerequisites

`BMONISigner.xcframework` is fetched automatically — through Swift
Package Manager (default) or via the podspec's `prepare_command` for
CocoaPods consumers. No extra setup is required beyond the standard
`pod install` Flutter performs on first run.

## Run the integration tests

[`integration_test/plugin_integration_test.dart`](integration_test/plugin_integration_test.dart)
walks through both gating modes on a real device / simulator. Each
test resets the device's wallet + PIN state up front so the suite is
idempotent.

**`default config (requirePin: true)`** group:

1. `initWallet()` returns a 0x-prefixed 42-char EIP-55 address.
2. A second `initWallet()` raises
   `BmoniSignerErrorCode.walletAlreadyExists`.
3. PIN lifecycle — `setPin → matchPin → changePin → removePin`.
4. `signMessage(..., pin: '999999')` raises `pinMismatch`;
   `pin: '123456'` succeeds and produces a valid 65-byte recoverable
   signature.
5. Same coverage for `signTransactionHash`.
6. `deleteWallet(pin: '999999')` raises `pinMismatch`;
   `pin: '123456'` succeeds.

**`requirePin: false`** group (re-`initialize`d in `setUp`):

1. `signMessage('Welcome to BMONI!')` succeeds without any `pin`
   argument.
2. `signTransactionHash(hash)` succeeds without any `pin` argument.
3. `deleteWallet()` succeeds without any `pin` argument.

PINs default to 6 characters. Run on a connected device:

```bash
cd example
flutter test integration_test/plugin_integration_test.dart
```

## Code walkthrough

The full integration is in [`lib/main.dart`](lib/main.dart). The
default-mode happy-path looks like:

```dart
void main() {
  // Default: pinLength: 6, requirePin: true.
  BmoniEmbeddedSdk.initialize();
  runApp(const MyApp());
}

Future<void> bootstrap() async {
  try {
    // Provision (one-time per device).
    final String address = await BmoniEmbeddedSdk.initWallet();

    // Set the PIN that gates future signing operations. PINs are
    // exactly `BmoniEmbeddedSdk.pinLength` characters.
    if (!await BmoniEmbeddedSdk.hasPin()) {
      await BmoniEmbeddedSdk.setPin('123456');
    }

    // Personal sign (EIP-191) — requires a matching PIN.
    final String messageSig = await BmoniEmbeddedSdk.signMessage(
      'Welcome to BMONI!',
      pin: '123456',
    );

    // Sign a 32-byte digest.
    final String hashSig = await BmoniEmbeddedSdk.signTransactionHash(
      '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8',
      pin: '123456',
    );
  } on BmoniSignerException catch (e) {
    if (e.errorCode == BmoniSignerErrorCode.walletAlreadyExists) {
      // Re-provision: destructive — on-chain address becomes
      // unrecoverable from this device.
      await BmoniEmbeddedSdk.deleteWallet(pin: '123456');
      await BmoniEmbeddedSdk.initWallet();
    }
  }
}
```

When the developer prefers to gate sensitive actions elsewhere
(biometrics, OS lockscreen, server challenges, …), opt out at
`initialize` time. The SDK then forwards straight to the native
plugin — `pin` becomes optional and is ignored if supplied:

```dart
void main() {
  BmoniEmbeddedSdk.initialize(requirePin: false);
  runApp(const MyApp());
}

await BmoniEmbeddedSdk.initWallet();
final sig = await BmoniEmbeddedSdk.signMessage('hi');           // no PIN
await BmoniEmbeddedSdk.signTransactionHash('0x...', pin: 'ignored'); // ditto
await BmoniEmbeddedSdk.deleteWallet();                          // ditto
```

The `BmoniEmbeddedSdk.config`, `BmoniEmbeddedSdk.pinLength` and
`BmoniEmbeddedSdk.requirePin` getters expose the active configuration
so the UI can decide whether to render a PIN entry at all.
