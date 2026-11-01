import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC 3.2.0-rc.4 has the exact identity and upgrades RC.3 splits', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^\s+]+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(match!.group(1), '3.2.0-rc.4');
    final baseCode = int.parse(match.group(2)!);
    expect(baseCode, 3024);
    expect(baseCode, greaterThan(3023));
    // Every RC.4 split must upgrade even the highest published RC.3 split.
    for (final abiCode in [1, 2, 3]) {
      expect(baseCode * 10 + abiCode, greaterThan(30233));
    }
    expect(
      [
        for (final abiCode in [1, 2, 3]) baseCode * 10 + abiCode,
      ],
      [30241, 30242, 30243],
    );
  });

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
    expect(releaseWorkflow, contains("REQUIRED_BASE_VERSION_CODE: '3024'"));
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
    expect(
      releaseWorkflow,
      contains(
        "EXPECTED_RELEASE_CERT_SHA256: '475baf431b16d050c8f658ac838783b273f7c10bba06ed1d16bb0a4239f592fb'",
      ),
    );
    expect(
      releaseWorkflow,
      contains(r'certificate SHA-256 digest:\s*([0-9a-fA-F]+)'),
    );
    expect(releaseWorkflow, contains('if certs != {expected_cert}:'));
    expect(qualityWorkflow, contains("MINIMUM_INSTALLED_VERSION_CODE: '2127'"));
    expect(qualityWorkflow, contains("REQUIRED_BASE_VERSION_CODE: '3024'"));
    expect(qualityWorkflow, contains('scripts.test_verify_release_apks'));
  });

  test('Store notes cover the base and every exact ABI split code', () {
    const directory = 'fastlane/metadata/android/en-US/changelogs';
    final notes = File('$directory/3024.txt').readAsStringSync();

    expect(notes.trim(), isNotEmpty);
    expect(notes.runes.length, lessThanOrEqualTo(500));
    for (final splitCode in [30241, 30242, 30243]) {
      expect(File('$directory/$splitCode.txt').readAsStringSync(), notes);
    }
  });
}
