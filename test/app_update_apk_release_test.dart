import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update_service.dart';

const _digest =
    '0037e440f19dad89318902f90a6b8ef29cfe0289304e62fde6b9d4896a6fbff4';

Map<String, Object?> _asset(
  String abi, {
  String? name,
  String? url,
  String? digest,
  Object? size = 8,
}) {
  final file = name ?? 'app-$abi-release.apk';
  return {
    'name': file,
    'browser_download_url':
        url ??
        'https://github.com/rusty4444/hermes-android/releases/download/v3.2.6/$file',
    'digest': digest ?? 'sha256:$_digest',
    'size': size,
    'state': 'uploaded',
  };
}

AppReleaseInfo _release(List<Map<String, Object?>> assets) =>
    AppUpdateService.parseRelease(
      jsonEncode({
        'tag_name': 'v3.2.6',
        'html_url':
            'https://github.com/rusty4444/hermes-android/releases/tag/v3.2.6',
        'assets': assets,
      }),
    )!;

void main() {
  test('selects the first supported published Android ABI', () {
    final release = _release([_asset('armeabi-v7a'), _asset('arm64-v8a')]);
    final apk = release.apkForAbis(['arm64-v8a', 'armeabi-v7a']);

    expect(apk?.name, 'app-arm64-v8a-release.apk');
    expect(apk?.sha256, _digest);
    expect(apk?.size, 8);
  });

  test('never substitutes another ABI when the preferred asset is invalid', () {
    final release = _release([
      _asset('arm64-v8a', digest: 'sha256:broken'),
      _asset('armeabi-v7a'),
    ]);
    expect(release.apkForAbis(['arm64-v8a', 'armeabi-v7a']), isNull);
  });

  test('rejects unsafe URLs, sizes, absent digests, and duplicate assets', () {
    for (final assets in [
      [_asset('arm64-v8a', url: 'https://evil.example/file.apk')],
      [
        _asset(
          'arm64-v8a',
          url:
              'http://github.com/rusty4444/hermes-android/releases/download/v3.2.6/app-arm64-v8a-release.apk',
        ),
      ],
      [
        _asset(
          'arm64-v8a',
          url:
              'https://github.com/rusty4444/hermes-android/releases/download/v3.2.5/app-arm64-v8a-release.apk',
        ),
      ],
      [_asset('arm64-v8a', digest: 'sha256:bad')],
      [_asset('arm64-v8a', size: 0)],
      [_asset('arm64-v8a', size: 201 * 1024 * 1024)],
      [_asset('arm64-v8a'), _asset('arm64-v8a')],
    ]) {
      expect(_release(assets).apkForAbis(['arm64-v8a']), isNull);
    }
  });

  test('unrecognised architectures and releases without assets fall back', () {
    expect(_release([_asset('arm64-v8a')]).apkForAbis(['mips']), isNull);
    expect(_release([]).apkForAbis(['arm64-v8a']), isNull);
  });

  test('prerelease metadata cannot offer an installable APK', () {
    final info = AppUpdateService.parseRelease(
      jsonEncode({
        'tag_name': 'v3.2.6',
        'html_url':
            'https://github.com/rusty4444/hermes-android/releases/tag/v3.2.6',
        'prerelease': true,
        'assets': [_asset('arm64-v8a')],
      }),
    )!;
    expect(info.apkForAbis(['arm64-v8a']), isNull);
  });

  test('nonstandard tags cannot select an unsupported native download', () {
    final info = AppUpdateService.parseRelease(
      jsonEncode({
        'tag_name': 'v3.2.6-beta.1',
        'html_url':
            'https://github.com/rusty4444/hermes-android/releases/tag/v3.2.6-beta.1',
        'assets': [
          _asset(
            'arm64-v8a',
            url:
                'https://github.com/rusty4444/hermes-android/releases/download/v3.2.6-beta.1/app-arm64-v8a-release.apk',
          ),
        ],
      }),
    )!;
    expect(info.apkForAbis(['arm64-v8a']), isNull);
  });
}
