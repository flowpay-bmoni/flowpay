// Integration tests for the bmoni_embedded_sdk plugin.
//
// These tests exercise the real native BMONISigner SDK on the host
// device / simulator, so they need:
//   * an Android device with the `me.bkey.ip:bmonisigner:1.0.0` artifact
//     resolved (see the project README for GitHub Packages setup), or
//   * an iOS device / simulator with the BMONISigner.xcframework wired
//     in via Swift Package Manager / CocoaPods.
//
// Run from `example/`:
//   flutter test integration_test/plugin_integration_test.dart

import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String pin = '123456';

  /// Best-effort reset of every persistent piece of state the SDK owns
  /// on this device, regardless of the current configuration.
  Future<void> resetState() async {
    try {
      await BmoniEmbeddedSdk.deleteWallet(pin: pin);
    } on BmoniSignerException {
      try {
        await BmoniEmbeddedSdk.deleteWallet();
      } on BmoniSignerException {
        /* ignore — no wallet to delete */
      }
    }
    if (await BmoniEmbeddedSdk.hasPin()) {
      try {
        await BmoniEmbeddedSdk.removePin(pin);
      } on BmoniSignerException {
        /* ignore — stored PIN may differ from the canonical one */
      }
    }
  }

  setUp(() async {
    BmoniEmbeddedSdk.initialize();
    await resetState();
  });
  tearDownAll(() async {
    BmoniEmbeddedSdk.initialize();
    await resetState();
  });

  group('default config (requirePin: true)', () {
    testWidgets('initWallet returns a 0x-prefixed 42-char EIP-55 address', (
      WidgetTester _,
    ) async {
      final String address = await BmoniEmbeddedSdk.initWallet();

      expect(address, startsWith('0x'));
      expect(address.length, 42);
      expect(
        RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address),
        isTrue,
        reason: 'Expected EIP-55 hex address, got "$address"',
      );
    });

    testWidgets('initWallet throws walletAlreadyExists on the second call', (
      WidgetTester _,
    ) async {
      await BmoniEmbeddedSdk.initWallet();

      await expectLater(
        BmoniEmbeddedSdk.initWallet,
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.walletAlreadyExists,
          ),
        ),
      );
    });

    testWidgets('PIN lifecycle: set, match, change, remove', (
      WidgetTester _,
    ) async {
      expect(await BmoniEmbeddedSdk.hasPin(), isFalse);

      await BmoniEmbeddedSdk.setPin(pin);
      expect(await BmoniEmbeddedSdk.hasPin(), isTrue);
      expect(await BmoniEmbeddedSdk.matchPin(pin), isTrue);
      expect(await BmoniEmbeddedSdk.matchPin('000000'), isFalse);

      await BmoniEmbeddedSdk.changePin(currentPin: pin, newPin: '654321');
      expect(await BmoniEmbeddedSdk.matchPin('654321'), isTrue);

      await BmoniEmbeddedSdk.removePin('654321');
      expect(await BmoniEmbeddedSdk.hasPin(), isFalse);
    });

    testWidgets('signMessage requires a matching PIN', (WidgetTester _) async {
      await BmoniEmbeddedSdk.initWallet();
      await BmoniEmbeddedSdk.setPin(pin);

      await expectLater(
        () => BmoniEmbeddedSdk.signMessage('Welcome!', pin: '999999'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinMismatch,
          ),
        ),
      );

      final String signature = await BmoniEmbeddedSdk.signMessage(
        'Welcome to BMONI!',
        pin: pin,
      );
      expect(signature, startsWith('0x'));
      expect(signature.length, 132); // 0x + 65 bytes * 2 hex chars
      final int v = int.parse(signature.substring(130), radix: 16);
      expect(v == 27 || v == 28, isTrue, reason: 'v must be 27 or 28');
    });

    testWidgets('signTransactionHash requires a matching PIN', (
      WidgetTester _,
    ) async {
      await BmoniEmbeddedSdk.initWallet();
      await BmoniEmbeddedSdk.setPin(pin);

      const String hash =
          '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8';

      await expectLater(
        () => BmoniEmbeddedSdk.signTransactionHash(hash, pin: '999999'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinMismatch,
          ),
        ),
      );

      final String signature = await BmoniEmbeddedSdk.signTransactionHash(
        hash,
        pin: pin,
      );
      expect(signature, startsWith('0x'));
      expect(signature.length, 132);
      final int v = int.parse(signature.substring(130), radix: 16);
      expect(v == 27 || v == 28, isTrue);
    });

    testWidgets('deleteWallet requires a matching PIN', (
      WidgetTester _,
    ) async {
      await BmoniEmbeddedSdk.initWallet();
      await BmoniEmbeddedSdk.setPin(pin);

      await expectLater(
        () => BmoniEmbeddedSdk.deleteWallet(pin: '999999'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinMismatch,
          ),
        ),
      );

      await BmoniEmbeddedSdk.deleteWallet(pin: pin);
    });
  });

  group('requirePin: false', () {
    setUp(() {
      BmoniEmbeddedSdk.initialize(requirePin: false);
    });

    testWidgets('signMessage works without a pin argument', (
      WidgetTester _,
    ) async {
      await BmoniEmbeddedSdk.initWallet();

      final String signature = await BmoniEmbeddedSdk.signMessage(
        'Welcome to BMONI!',
      );
      expect(signature, startsWith('0x'));
      expect(signature.length, 132);
    });

    testWidgets('signTransactionHash works without a pin argument', (
      WidgetTester _,
    ) async {
      await BmoniEmbeddedSdk.initWallet();

      const String hash =
          '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8';
      final String signature = await BmoniEmbeddedSdk.signTransactionHash(hash);
      expect(signature, startsWith('0x'));
      expect(signature.length, 132);
    });

    testWidgets('deleteWallet works without a pin argument', (
      WidgetTester _,
    ) async {
      await BmoniEmbeddedSdk.initWallet();
      await BmoniEmbeddedSdk.deleteWallet();
    });
  });
}
