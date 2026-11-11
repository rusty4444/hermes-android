import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/native_login_keepalive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/native_login_keepalive');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('exported callback uses the production channel on Android', () async {
    const production = MethodChannel(
      'com.hermesagent.hermes_android/native_login',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(production, (call) async {
          calls.add(call);
          return true;
        });
    try {
      await (await acquireNativeLoginLease())();
      expect(calls.map((call) => call.method), ['acquire', 'release']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(production, null);
    }
  });

  test('unsupported platforms never touch the method channel', () async {
    final adapter = NativeLoginKeepAlive(
      channel: channel,
      platform: TargetPlatform.iOS,
    );
    await (await adapter.acquire())();
    expect(calls, isEmpty);
  });

  test('Android web does not invoke a native service', () async {
    final adapter = NativeLoginKeepAlive(
      channel: channel,
      platform: TargetPlatform.android,
      isWeb: true,
    );
    await (await adapter.acquire())();
    expect(calls, isEmpty);
  });

  for (final response in [
    false,
    null,
    'true',
    'platformError',
    'missingPlugin',
  ]) {
    test('Android fails closed and cleans up on $response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'release') return null;
            if (response == 'platformError') {
              throw PlatformException(code: 'denied', message: 'secret-url');
            }
            if (response == 'missingPlugin') throw MissingPluginException();
            return response;
          });
      final adapter = NativeLoginKeepAlive(
        channel: channel,
        platform: TargetPlatform.android,
      );
      await expectLater(
        adapter.acquire(),
        throwsA(
          isA<NativeLoginLeaseException>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(calls.map((call) => call.method), ['acquire', 'release']);
    });
  }

  test(
    'acquire timeout releases the same ID even if success arrives late',
    () async {
      final pending = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'acquire' ? pending.future : null;
          });
      final adapter = NativeLoginKeepAlive(
        channel: channel,
        platform: TargetPlatform.android,
        channelTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        adapter.acquire(),
        throwsA(isA<NativeLoginLeaseException>()),
      );
      expect(calls.map((call) => call.method), ['acquire', 'release']);
      expect(
        (calls[0].arguments as Map)['leaseId'],
        (calls[1].arguments as Map)['leaseId'],
      );
      pending.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(2));
    },
  );

  test('release failures are bounded and do not mask login outcome', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'release') throw PlatformException(code: 'secret');
          return true;
        });
    final adapter = NativeLoginKeepAlive(
      channel: channel,
      platform: TargetPlatform.android,
    );
    await (await adapter.acquire())();
    expect(calls, hasLength(2));
  });

  test('release timeout is bounded and idempotent', () async {
    final pending = Completer<ByteData?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channel.name, (message) async {
          final call = channel.codec.decodeMethodCall(message);
          calls.add(call);
          return call.method == 'release'
              ? pending.future
              : channel.codec.encodeSuccessEnvelope(true);
        });
    final adapter = NativeLoginKeepAlive(
      channel: channel,
      platform: TargetPlatform.android,
      channelTimeout: const Duration(milliseconds: 20),
    );
    final release = await adapter.acquire();
    await release();
    await release();
    expect(calls.map((call) => call.method), ['acquire', 'release']);
    pending.completeError(PlatformException(code: 'late-secret'));
    await Future<void>.delayed(Duration.zero);
  }, timeout: const Timeout(Duration(seconds: 2)));

  test('Android acquisition returns an idempotent matching release', () async {
    final adapter = NativeLoginKeepAlive(
      channel: channel,
      platform: TargetPlatform.android,
    );
    final release = await adapter.acquire();
    expect(calls.map((call) => call.method), ['acquire']);
    final id = (calls.single.arguments as Map)['leaseId'];
    expect(id, isA<String>());
    expect(id, isNotEmpty);
    await Future.wait([release(), release()]);
    expect(calls.map((call) => call.method), ['acquire', 'release']);
    expect((calls.last.arguments as Map)['leaseId'], id);
  });
}
