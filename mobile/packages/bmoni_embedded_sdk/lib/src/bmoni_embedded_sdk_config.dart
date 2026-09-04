// SPDX-License-Identifier: Apache-2.0
/// Runtime configuration for the Bmoni Embedded SDK.
///
/// Created via `BmoniEmbeddedSdk.initialize(...)`. Once installed, the
/// instance is exposed as `BmoniEmbeddedSdk.config` for inspection by
/// app-side UI (for example to render a PIN input of the right length
/// or to hide PIN flows entirely when [requirePin] is `false`).
class BmoniEmbeddedSdkConfig {
  /// Default configuration applied when `initialize` has not been
  /// called: `pinLength: 6`, `requirePin: true`.
  const BmoniEmbeddedSdkConfig({
    this.pinLength = 6,
    this.requirePin = true,
  }) : assert(pinLength > 0, 'pinLength must be positive');

  /// Number of characters required for a valid PIN.
  ///
  /// Enforced by `setPin` and `changePin` (the `newPin` argument). Any
  /// other length raises `BmoniSignerException(pinInvalid)`.
  ///
  /// Note: the digest stored by `setPin` is bound to the value at the
  /// time of writing, not to [pinLength]. Changing this after a PIN
  /// has been persisted will reject the existing PIN at verification
  /// time even though the digest itself is intact — call `removePin`
  /// (or `setPin` after deletion) to re-establish the PIN under the
  /// new length.
  final int pinLength;

  /// Whether the SDK should verify the supplied PIN before invoking the
  /// native signing / deletion calls.
  ///
  /// * `true` (default) — `signMessage`, `signTransactionHash` and
  ///   `deleteWallet` require a `pin` argument and verify it against
  ///   the stored digest. A missing or wrong PIN throws
  ///   `BmoniSignerException(pinInvalid | pinNotSet | pinMismatch)`
  ///   before the native plugin is touched.
  /// * `false` — the SDK forwards directly to the native plugin and
  ///   ignores any supplied `pin`. Useful when the app already gates
  ///   sensitive actions behind another auth surface (biometrics, OS
  ///   lockscreen, server-side challenge, …).
  ///
  /// PIN management methods (`setPin`, `changePin`, `removePin`,
  /// `matchPin`, `hasPin`) are unaffected by this flag — toggling it
  /// only changes whether a stored PIN gates signing.
  final bool requirePin;

  @override
  String toString() =>
      'BmoniEmbeddedSdkConfig(pinLength: $pinLength, requirePin: $requirePin)';
}
