import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/apk_update_installer.dart';
import 'package:hermes_android/core/services/app_update_service.dart';

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

  testWidgets('native progress events cross the platform channel', (
    tester,
  ) async {
    final pending = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'download') await pending.future;
      return null;
    });
    final installer = ApkUpdateInstaller(channel: channel);
    final apk = AppReleaseApk(
      abi: 'arm64-v8a',
      name: 'app-arm64-v8a-release.apk',
      url: Uri.parse(
        'https://github.com/rusty4444/hermes-android/releases/download/v3.2.6/app-arm64-v8a-release.apk',
      ),
      sha256: 'a' * 64,
      size: 100,
    );
    final progress = <(int, int)>[];
    final result = installer.download(
      apk: apk,
      tag: 'v3.2.6',
      onProgress: (a, b) => progress.add((a, b)),
    );
    await tester.pump();
    final other = ApkUpdateInstaller(channel: channel);
    await expectLater(
      other.download(apk: apk, tag: 'v3.2.6', onProgress: (_, _) {}),
      throwsStateError,
    );
    await other.cancel();
    final reply = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('progress', {'received': 50, 'total': 100}),
      ),
      (_) => reply.complete(),
    );
    await tester.pump();
    await reply.future;
    expect(progress, [(50, 100)]);
    pending.complete();
    await tester.pump();
    await result;
    debugDefaultTargetPlatformOverride = null;
  });

  test('passes verified release metadata and requests installation', () async {
    final installer = ApkUpdateInstaller(channel: channel);
    final apk = AppReleaseApk(
      abi: 'arm64-v8a',
      name: 'app-arm64-v8a-release.apk',
      url: Uri.parse(
        'https://github.com/rusty4444/hermes-android/releases/download/v3.2.6/app-arm64-v8a-release.apk',
      ),
      sha256: 'a' * 64,
      size: 123,
    );
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
}
