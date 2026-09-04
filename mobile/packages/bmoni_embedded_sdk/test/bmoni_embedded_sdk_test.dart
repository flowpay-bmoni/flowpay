import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk.dart';
import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk_method_channel.dart';
import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk_platform_interface.dart';
import 'package:bmoni_embedded_sdk/src/pin_store.dart';
import 'package:bmoni_embedded_sdk/src/wallet_address_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBmoniEmbeddedSdkPlatform
    with MockPlatformInterfaceMixin
    implements BmoniEmbeddedSdkPlatform {
  String? lastHash;
  String? lastMessage;
  bool deleteCalled = false;

  @override
  Future<String> initWallet() =>
      Future<String>.value('0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');

  @override
  Future<String> signTransactionHash(String hashHex) {
    lastHash = hashHex;
    return Future<String>.value('0x${'a' * 130}');
  }

  @override
  Future<String> signMessage(String message) {
    lastMessage = message;
    return Future<String>.value('0x${'b' * 130}');
  }

  @override
  Future<void> deleteWallet() async {
    deleteCalled = true;
  }
}

/// In-memory [PinStore] used in unit tests so we don't touch the
/// platform secure-storage channel.
class FakePinStore implements PinStore {
  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> set(String pin) async {
    _pin = pin;
  }

  @override
  Future<bool> matches(String pin) async => _pin == pin;

  @override
  Future<void> remove() async {
    _pin = null;
  }
}

/// In-memory [WalletAddressStore] for unit tests.
class FakeWalletAddressStore implements WalletAddressStore {
  String? _address;

  @override
  Future<String?> read() async => _address;

  @override
  Future<void> write(String address) async {
    _address = address;
  }

  @override
  Future<void> delete() async {
    _address = null;
  }
}

void main() {
  final BmoniEmbeddedSdkPlatform initialPlatform =
      BmoniEmbeddedSdkPlatform.instance;

  /// Resets the SDK back to its default configuration so each test
  /// starts from a known state regardless of what its predecessor did.
  /// Also installs in-memory fakes for the storage-backed singletons so
  /// no test ever reaches the platform secure-storage channel.
  setUp(() {
    BmoniEmbeddedSdk.initialize();
    BmoniEmbeddedSdk.pinStore = FakePinStore();
    BmoniEmbeddedSdk.walletAddressStore = FakeWalletAddressStore();
  });

  test('$MethodChannelBmoniEmbeddedSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBmoniEmbeddedSdk>());
  });

  group('initialize', () {
    test('defaults to pinLength: 6 and requirePin: true', () {
      BmoniEmbeddedSdk.initialize();
      expect(BmoniEmbeddedSdk.config.pinLength, 6);
      expect(BmoniEmbeddedSdk.config.requirePin, isTrue);
      expect(BmoniEmbeddedSdk.pinLength, 6);
      expect(BmoniEmbeddedSdk.requirePin, isTrue);
    });

    test('overrides pinLength and requirePin', () {
      BmoniEmbeddedSdk.initialize(pinLength: 4, requirePin: false);
      expect(BmoniEmbeddedSdk.config.pinLength, 4);
      expect(BmoniEmbeddedSdk.config.requirePin, isFalse);
    });

    test('rejects non-positive pinLength', () {
      expect(
        () => BmoniEmbeddedSdk.initialize(pinLength: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => BmoniEmbeddedSdk.initialize(pinLength: -3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setPin honours the configured pinLength', () async {
      BmoniEmbeddedSdk.initialize(pinLength: 4);
      BmoniEmbeddedSdk.pinStore = FakePinStore();

      await BmoniEmbeddedSdk.setPin('1234');
      expect(await BmoniEmbeddedSdk.matchPin('1234'), isTrue);

      await expectLater(
        () => BmoniEmbeddedSdk.setPin('123'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinInvalid,
          ),
        ),
      );
    });
  });

  group('BmoniEmbeddedSdk facade', () {
    late MockBmoniEmbeddedSdkPlatform mock;
    late FakePinStore fakePinStore;
    const String pin = '123456';

    setUp(() async {
      mock = MockBmoniEmbeddedSdkPlatform();
      BmoniEmbeddedSdkPlatform.instance = mock;
      fakePinStore = FakePinStore();
      BmoniEmbeddedSdk.pinStore = fakePinStore;
      await BmoniEmbeddedSdk.setPin(pin);
    });

    test('initWallet returns the EIP-55 address', () async {
      expect(
        await BmoniEmbeddedSdk.initWallet(),
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      );
    });

    test('signTransactionHash forwards the hash argument', () async {
      const hash =
          '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8';
      final String signature =
          await BmoniEmbeddedSdk.signTransactionHash(hash, pin: pin);
      expect(mock.lastHash, hash);
      expect(signature.startsWith('0x'), isTrue);
      expect(signature.length, 132);
    });

    test('signMessage forwards the message argument', () async {
      final String signature = await BmoniEmbeddedSdk.signMessage(
        'Welcome to BMONI!',
        pin: pin,
      );
      expect(mock.lastMessage, 'Welcome to BMONI!');
      expect(signature.startsWith('0x'), isTrue);
      expect(signature.length, 132);
    });

    test('deleteWallet invokes the platform implementation', () async {
      await BmoniEmbeddedSdk.deleteWallet(pin: pin);
      expect(mock.deleteCalled, isTrue);
    });
  });

  group('Wallet address cache', () {
    late MockBmoniEmbeddedSdkPlatform mock;
    const String pin = '123456';

    setUp(() async {
      mock = MockBmoniEmbeddedSdkPlatform();
      BmoniEmbeddedSdkPlatform.instance = mock;
      await BmoniEmbeddedSdk.setPin(pin);
    });

    test('walletAddress is null and hasWallet is false on a fresh device',
        () async {
      expect(await BmoniEmbeddedSdk.walletAddress(), isNull);
      expect(await BmoniEmbeddedSdk.hasWallet(), isFalse);
    });

    test('initWallet persists the address so it survives a relaunch',
        () async {
      final String returned = await BmoniEmbeddedSdk.initWallet();

      expect(returned, '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');
      expect(await BmoniEmbeddedSdk.walletAddress(), returned);
      expect(await BmoniEmbeddedSdk.hasWallet(), isTrue);
    });

    test('deleteWallet wipes the cached address', () async {
      await BmoniEmbeddedSdk.initWallet();
      expect(await BmoniEmbeddedSdk.hasWallet(), isTrue);

      await BmoniEmbeddedSdk.deleteWallet(pin: pin);

      expect(await BmoniEmbeddedSdk.walletAddress(), isNull);
      expect(await BmoniEmbeddedSdk.hasWallet(), isFalse);
    });

    test('deleteWallet keeps the cache untouched when the PIN check fails',
        () async {
      await BmoniEmbeddedSdk.initWallet();

      await expectLater(
        () => BmoniEmbeddedSdk.deleteWallet(pin: '000000'),
        throwsA(isA<BmoniSignerException>()),
      );

      // Cache must still hold the address — the native delete never ran.
      expect(
        await BmoniEmbeddedSdk.walletAddress(),
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      );
      expect(mock.deleteCalled, isFalse);
    });
  });

  group('PIN management', () {
    setUp(() {
      BmoniEmbeddedSdk.pinStore = FakePinStore();
    });

    test('hasPin is false on a fresh device', () async {
      expect(await BmoniEmbeddedSdk.hasPin(), isFalse);
    });

    test('setPin then matchPin succeeds for the same value', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      expect(await BmoniEmbeddedSdk.matchPin('123456'), isTrue);
      expect(await BmoniEmbeddedSdk.matchPin('000000'), isFalse);
    });

    test('setPin twice throws pinAlreadySet', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      expect(
        () => BmoniEmbeddedSdk.setPin('654321'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinAlreadySet,
          ),
        ),
      );
    });

    test('setPin enforces a ${BmoniEmbeddedSdk.pinLength}-character PIN',
        () async {
      for (final String invalid in <String>['', '12345', '1234567']) {
        await expectLater(
          () => BmoniEmbeddedSdk.setPin(invalid),
          throwsA(
            isA<BmoniSignerException>().having(
              (BmoniSignerException e) => e.errorCode,
              'errorCode',
              BmoniSignerErrorCode.pinInvalid,
            ),
          ),
          reason: 'expected pinInvalid for input "$invalid"',
        );
      }
    });

    test('changePin enforces the length of newPin', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      await expectLater(
        () => BmoniEmbeddedSdk.changePin(currentPin: '123456', newPin: '12345'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinInvalid,
          ),
        ),
      );
    });

    test('changePin rotates the digest after current PIN check', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      await BmoniEmbeddedSdk.changePin(
        currentPin: '123456',
        newPin: '654321',
      );
      expect(await BmoniEmbeddedSdk.matchPin('123456'), isFalse);
      expect(await BmoniEmbeddedSdk.matchPin('654321'), isTrue);
    });

    test('changePin with wrong currentPin throws pinMismatch', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      expect(
        () => BmoniEmbeddedSdk.changePin(
          currentPin: '999999',
          newPin: '654321',
        ),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinMismatch,
          ),
        ),
      );
    });

    test('removePin clears the digest after current PIN check', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      await BmoniEmbeddedSdk.removePin('123456');
      expect(await BmoniEmbeddedSdk.hasPin(), isFalse);
    });
  });

  group('PIN gating on signing/delete', () {
    late MockBmoniEmbeddedSdkPlatform mock;

    setUp(() {
      mock = MockBmoniEmbeddedSdkPlatform();
      BmoniEmbeddedSdkPlatform.instance = mock;
      BmoniEmbeddedSdk.pinStore = FakePinStore();
    });

    test('signMessage without a PIN throws pinNotSet', () async {
      expect(
        () => BmoniEmbeddedSdk.signMessage('hi', pin: '000000'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinNotSet,
          ),
        ),
      );
    });

    test('signMessage with the wrong PIN throws pinMismatch', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      expect(
        () => BmoniEmbeddedSdk.signMessage('hi', pin: '000000'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinMismatch,
          ),
        ),
      );
    });

    test('signTransactionHash with the wrong PIN throws pinMismatch', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      expect(
        () => BmoniEmbeddedSdk.signTransactionHash(
          '0x${'a' * 64}',
          pin: '000000',
        ),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinMismatch,
          ),
        ),
      );
    });

    test('deleteWallet with the wrong PIN does not call the platform',
        () async {
      await BmoniEmbeddedSdk.setPin('123456');
      try {
        await BmoniEmbeddedSdk.deleteWallet(pin: '000000');
        fail('expected pinMismatch');
      } on BmoniSignerException catch (e) {
        expect(e.errorCode, BmoniSignerErrorCode.pinMismatch);
      }
      expect(mock.deleteCalled, isFalse);
    });

    test(
        'signMessage without a pin argument when requirePin is true '
        'throws pinInvalid', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      await expectLater(
        () => BmoniEmbeddedSdk.signMessage('hi'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinInvalid,
          ),
        ),
      );
    });
  });

  group('PIN gating disabled (requirePin: false)', () {
    late MockBmoniEmbeddedSdkPlatform mock;

    setUp(() {
      BmoniEmbeddedSdk.initialize(requirePin: false);
      mock = MockBmoniEmbeddedSdkPlatform();
      BmoniEmbeddedSdkPlatform.instance = mock;
      BmoniEmbeddedSdk.pinStore = FakePinStore();
    });

    test('signMessage forwards directly without a pin argument', () async {
      final String signature = await BmoniEmbeddedSdk.signMessage('hi');
      expect(signature.startsWith('0x'), isTrue);
      expect(mock.lastMessage, 'hi');
    });

    test('signMessage ignores any supplied pin', () async {
      await BmoniEmbeddedSdk.setPin('123456');
      final String signature =
          await BmoniEmbeddedSdk.signMessage('hi', pin: 'this-is-ignored');
      expect(signature.startsWith('0x'), isTrue);
      expect(mock.lastMessage, 'hi');
    });

    test('signTransactionHash forwards directly without a pin argument',
        () async {
      const String hash =
          '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8';
      final String signature =
          await BmoniEmbeddedSdk.signTransactionHash(hash);
      expect(signature.startsWith('0x'), isTrue);
      expect(mock.lastHash, hash);
    });

    test('deleteWallet forwards directly without a pin argument', () async {
      await BmoniEmbeddedSdk.deleteWallet();
      expect(mock.deleteCalled, isTrue);
    });

    test(
        'changePin still validates the configured pinLength even when '
        'requirePin is false', () async {
      BmoniEmbeddedSdk.initialize(pinLength: 6, requirePin: false);
      BmoniEmbeddedSdk.pinStore = FakePinStore();
      await BmoniEmbeddedSdk.setPin('123456');
      await expectLater(
        () => BmoniEmbeddedSdk.changePin(
          currentPin: '123456',
          newPin: '12345',
        ),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.pinInvalid,
          ),
        ),
      );
    });
  });

  group('BmoniSignerException', () {
    test('renders the error code in hex via toString', () {
      const exception = BmoniSignerException(
        errorCode: BmoniSignerErrorCode.walletAlreadyExists,
        message: 'wallet already exists',
      );
      expect(exception.errorCodeHex, '0x30010010');
      expect(exception.toString(), contains('0x30010010'));
      expect(exception.toString(), contains('wallet already exists'));
    });

    test('PIN error codes live in the 0x4xxxxxxx range', () {
      const exception = BmoniSignerException(
        errorCode: BmoniSignerErrorCode.pinMismatch,
        message: 'PIN does not match',
      );
      expect(exception.errorCodeHex, '0x40000003');
    });
  });
}
