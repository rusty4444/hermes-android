import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/apk_update_installer.dart';
import 'package:hermes_android/core/services/app_update_service.dart';

AppReleaseApk _apk({int size = 100}) => AppReleaseApk(
  abi: 'arm64-v8a',
  name: 'app-arm64-v8a-release.apk',
  url: Uri.parse(
    'https://github.com/rusty4444/hermes-android/releases/download/v3.2.6/app-arm64-v8a-release.apk',
  ),
  sha256: 'a' * 64,
  size: size,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_apk_update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  bool allowed = true;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    allowed = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'canUpdate':
          return allowed;
        case 'supportedAbis':
          return ['arm64-v8a', 'armeabi-v7a'];
        case 'hasPreparedUpdate':
          return true;
        case 'download':
          return null;
        case 'install':
          return 'permission_required';
        case 'cancel':
          return null;
      }
      throw MissingPluginException();
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('queries native eligibility before selecting ABI', () async {
    final installer = ApkUpdateInstaller(channel: channel);
    expect(await installer.supportedAbis(), ['arm64-v8a', 'armeabi-v7a']);
    expect(calls.map((call) => call.method), ['canUpdate', 'supportedAbis']);
    calls.clear();
    allowed = false;
    expect(await installer.supportedAbis(), isEmpty);
    expect(calls.map((call) => call.method), ['canUpdate']);
  });

  test(
    'native progress events reach the caller and reject concurrent starts',
    () async {
      final progress = <(int, int)>[];
      Object? concurrentError;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'download') return null;
        // The download() call registered the progress handler before invoking
        // this method, so a platform message here is delivered to it.
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('progress', {'received': 50, 'total': 100}),
          ),
          (_) {},
        );
        // A second installer cannot take over the messenger's handler.
        try {
          await ApkUpdateInstaller(
            channel: channel,
          ).download(apk: _apk(), tag: 'v3.2.6', onProgress: (_, _) {});
        } catch (error) {
          concurrentError = error;
        }
        return null;
      });

      await ApkUpdateInstaller(channel: channel).download(
        apk: _apk(),
        tag: 'v3.2.6',
        onProgress: (a, b) => progress.add((a, b)),
      );

      expect(progress, [(50, 100)]);
      expect(concurrentError, isA<StateError>());
    },
  );

  test('passes verified release metadata and requests installation', () async {
    final installer = ApkUpdateInstaller(channel: channel);
    final apk = _apk(size: 123);
    await installer.download(apk: apk, tag: 'v3.2.6', onProgress: (_, _) {});
    expect(calls.single.method, 'download');
    expect(calls.single.arguments, {
      'tag': 'v3.2.6',
      'url': apk.url.toString(),
      'name': apk.name,
      'sha256': apk.sha256,
      'size': 123,
    });
    expect(await installer.install(), 'permission_required');
    await installer.cancel();
    expect(calls.map((call) => call.method), ['download', 'install', 'cancel']);
  });

  test(
    'cancelling while hasPreparedUpdate is in flight invokes native cancel',
    () async {
      final installer = ApkUpdateInstaller(channel: channel);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'hasPreparedUpdate') {
          await installer.cancel();
          return true;
        }
        return null;
      });
      expect(
        await installer.hasPreparedUpdate(_apk(size: 123), 'v3.2.6'),
        isFalse,
      );
      expect(calls.map((call) => call.method), ['hasPreparedUpdate', 'cancel']);
    },
  );
}
