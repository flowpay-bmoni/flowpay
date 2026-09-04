import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk.dart';
import 'package:bmoni_embedded_sdk/bmoni_embedded_sdk_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelBmoniEmbeddedSdk platform =
      MethodChannelBmoniEmbeddedSdk();
  const MethodChannel channel = MethodChannel('bmoni_embedded_sdk');

  final List<MethodCall> log = <MethodCall>[];

  void mockReturn(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          log.add(methodCall);
          return handler(methodCall);
        });
  }

  setUp(() {
    log.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initWallet returns the EIP-55 address', () async {
    const address = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
    mockReturn((_) => address);
    expect(await platform.initWallet(), address);
    expect(log.single.method, 'initWallet');
  });

  test('signTransactionHash forwards the hash argument', () async {
    const hash =
        '0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8';
    const signature = '0xdead';
    mockReturn((_) => signature);

    expect(await platform.signTransactionHash(hash), signature);

    final MethodCall call = log.single;
    expect(call.method, 'signTransactionHash');
    expect(call.arguments, <String, Object?>{'hashHex': hash});
  });

  test('signMessage forwards the message argument', () async {
    const message = 'Welcome to BMONI!';
    const signature = '0xbeef';
    mockReturn((_) => signature);

    expect(await platform.signMessage(message), signature);

    final MethodCall call = log.single;
    expect(call.method, 'signMessage');
    expect(call.arguments, <String, Object?>{'message': message});
  });

  test('deleteWallet completes without a return value', () async {
    mockReturn((_) => null);
    await platform.deleteWallet();
    expect(log.single.method, 'deleteWallet');
  });

  test('BMONI_SIGNER_ERROR PlatformException is converted to '
      'BmoniSignerException', () async {
    mockReturn((_) {
      throw PlatformException(
        code: 'BMONI_SIGNER_ERROR',
        message: 'wallet already exists',
        details: <String, Object?>{
          'errorCode': BmoniSignerErrorCode.walletAlreadyExists,
        },
      );
    });

    expect(
      () => platform.initWallet(),
      throwsA(
        isA<BmoniSignerException>()
            .having(
              (BmoniSignerException e) => e.errorCode,
              'errorCode',
              BmoniSignerErrorCode.walletAlreadyExists,
            )
            .having(
              (BmoniSignerException e) => e.message,
              'message',
              'wallet already exists',
            ),
      ),
    );
  });

  test(
    'PlatformException with a different code is rethrown unchanged',
    () async {
      mockReturn((_) {
        throw PlatformException(code: 'OTHER', message: 'oops');
      });

      expect(
        () => platform.signMessage('hi'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'a null return from a String-typed signer call surfaces as '
    'BmoniSignerException(unexpectedNativeNull)',
    () async {
      mockReturn((_) => null);

      expect(
        () => platform.signMessage('hi'),
        throwsA(
          isA<BmoniSignerException>().having(
            (BmoniSignerException e) => e.errorCode,
            'errorCode',
            BmoniSignerErrorCode.unexpectedNativeNull,
          ),
        ),
      );
    },
  );
}
