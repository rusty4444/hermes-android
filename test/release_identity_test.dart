import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Build UX18 has the exact release identity and an upgrade-safe code',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*([^\s+]+)\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match, isNotNull);
      expect(match!.group(1), '2.1.1');
      expect(int.parse(match.group(2)!), 2141);
      expect(int.parse(match.group(2)!), greaterThan(2131));
      // F-Droid ABI split: packaged arm64 code is base * 10 + ABI code.
      expect(int.parse(match.group(2)!) * 10 + 2, 21412);
    },
  );

  test('Gradle and CI enforce the accepted APK upgrade floor', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseWorkflow = File(
      '.github/workflows/release.yml',
    ).readAsStringSync();
    final qualityWorkflow = File(
      '.github/workflows/pr-quality.yml',
    ).readAsStringSync();

    expect(gradle, contains('minimumInstalledVersionCode = 2127'));
    expect(
      gradle,
      contains('check(flutter.versionCode > minimumInstalledVersionCode)'),
    );
    // F-Droid ABI-split version-code scheme: base * 10 + abiCode.
    expect(
      gradle,
      contains('mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)'),
    );
    expect(gradle, contains('variant.versionCode * 10 + abiVersionCode'));
    expect(releaseWorkflow, contains("MINIMUM_INSTALLED_VERSION_CODE: '2127'"));
    expect(releaseWorkflow, contains("REQUIRED_BASE_VERSION_CODE: '2141'"));
    expect(releaseWorkflow, contains("ARM64_ABI_CODE: '2'"));
    expect(
      releaseWorkflow,
      contains('expected_code = base_code * 10 + abi_code'),
    );
    expect(
      releaseWorkflow,
      contains('Verify arm64 split APK effective versionCode'),
    );
    expect(releaseWorkflow, contains('GITHUB_REF_TYPE'));
    expect(releaseWorkflow, contains('Refuse an unsigned tagged release'));
    expect(releaseWorkflow, contains("env.HAS_RELEASE_KEYSTORE == 'true'"));
    expect(qualityWorkflow, contains("MINIMUM_INSTALLED_VERSION_CODE: '2127'"));
    expect(qualityWorkflow, contains("REQUIRED_BASE_VERSION_CODE: '2141'"));
  });
}
