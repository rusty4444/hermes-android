import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_licenses.dart';

const _noticeAssets = <String>[
  'LICENSE',
  'assets/fonts/OFL.txt',
  'third_party/embedded-push-notice.md',
  'third_party/embedded-push-relink.md',
  'third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt',
  'third_party/NOTICE.md',
  'third_party/licenses/graphify-MIT.txt',
  'third_party/licenses/hermes-agent-MIT.txt',
  'third_party/licenses/flutter-BSD-3-Clause.txt',
  'third_party/licenses/Apache-2.0.txt',
  'third_party/licenses/gradle-NOTICE.txt',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final asset in _noticeAssets) {
    test('bundles the complete local notice: $asset', () async {
      final bundled = await rootBundle.load(asset);
      expect(bundled.buffer.asUint8List(), await File(asset).readAsBytes());
      expect(bundled.lengthInBytes, greaterThan(0));
    });
  }

  test('the generated manifest declares every local notice', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), containsAll(_noticeAssets));
    expect(manifest.listAssets(), isNot(contains('graphify-out/graph.html')));
    expect(
      manifest.listAssets(),
      isNot(contains('test/fixtures/internal_background_messages.json')),
    );
    expect(
      manifest.listAssets(),
      isNot(contains('ios/Runner/AppDelegate.swift')),
    );
  });

  test('registration is synchronous, deferred and idempotent', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(
      () => Stream.value(
        const LicenseEntryWithLineBreaks([
          'test_dependency',
        ], 'Retained notice'),
      ),
    );
    final bundle = _RecordingAssetBundle();

    registerAppLicenses(assetBundle: bundle);
    registerAppLicenses(assetBundle: bundle);
    expect(bundle.requests, isEmpty);

    final entries = await LicenseRegistry.licenses.toList();
    expect(entries, hasLength(_noticeAssets.length + 1));
    expect(entries.first.packages, ['test_dependency']);
    expect(bundle.requests, _noticeAssets);
    expect(entries.skip(1).map((entry) => entry.packages.single), [
      'Hermes Android',
      'Cinzel',
      'embedded-fcm-distributor (3.1.0)',
      'embedded-fcm-distributor (3.1.0)',
      'embedded-fcm-distributor (3.1.0)',
      'Third-party source/build materials (scope)',
      'Graphify viewer template (source material)',
      'Hermes Agent message templates (source material)',
      'Flutter iOS scaffold (source material)',
      'Gradle wrapper (Library build material)',
      'Gradle wrapper (Library build material)',
    ]);
    for (var index = 0; index < _noticeAssets.length; index++) {
      final entry = entries[index + 1] as LicenseEntryWithLineBreaks;
      expect(entry.text, await File(_noticeAssets[index]).readAsString());
      expect(entry.paragraphs, isNotEmpty);
    }
    final mit = entries[1] as LicenseEntryWithLineBreaks;
    expect(mit.text, startsWith('MIT License\n'));
    expect(
      mit.text,
      contains('Copyright (c) 2026 Sam Russell and contributors'),
    );
    expect(mit.text, contains('Permission is hereby granted, free of charge'));
    expect(mit.text, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
    expect(mit.text, endsWith('SOFTWARE.\n'));
    final lgpl = entries[5] as LicenseEntryWithLineBreaks;
    expect(lgpl.text, contains('Copyright (C) 2022 Simon Gougeon'));
    expect(
      lgpl.text,
      contains(
        'version 2.1 of the License, or (at your option) any later version.',
      ),
    );

    registerAppLicenses(assetBundle: bundle);
    expect(
      await LicenseRegistry.licenses.toList(),
      hasLength(_noticeAssets.length + 1),
    );
  });
}

class _RecordingAssetBundle extends AssetBundle {
  final requests = <String>[];

  @override
  Future<ByteData> load(String key) {
    requests.add(key);
    return rootBundle.load(key);
  }
}
