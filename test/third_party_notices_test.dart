import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _graphifyNotice = '''<!--
Graphify viewer template: Copyright (c) 2026 Safi Shamsi (MIT).
Complete permission/warranty text: ../third_party/licenses/graphify-MIT.txt
Pinned source and scope: ../third_party/NOTICE.md
-->
''';

void main() {
  test('retains exact upstream licence and NOTICE bytes', () {
    const hashes = <String, String>{
      'third_party/licenses/graphify-MIT.txt':
          '36ecff6bbb97aca1be64e95f42538cf796adde5864edac583e620643c096931a',
      'third_party/licenses/hermes-agent-MIT.txt':
          '821556e6336796450ab852d375117b48a4887e71d255794fd6318d99982a5ab6',
      'third_party/licenses/flutter-BSD-3-Clause.txt':
          'a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20',
      'third_party/licenses/Apache-2.0.txt':
          'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
      'third_party/licenses/gradle-NOTICE.txt':
          'd3d569a7f18525b229a7daa4926faf3e0566371f66686b157d62cdf7b3a0b3b3',
    };
    for (final entry in hashes.entries) {
      expect(
        sha256.convert(File(entry.key).readAsBytesSync()).toString(),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('notice repair preserves copied payloads and existing licences', () {
    const hashes = <String, String>{
      'LICENSE':
          '63a8c9d5b5485c845090d15933956f537ecedb0fb0af25abb5c5a4c9d6428567',
      'assets/fonts/OFL.txt':
          'f5a242cf68ad6ebd0603b3359a74c593ca080318a681035be5296ba2c6b04ae6',
      'third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt':
          '620e35bd6e6066ee0376391296ff595459584fe135853d8f60434d38693f06cb',
      'test/fixtures/internal_background_messages.json':
          '2fc48814c1cd7b62e9c07fce9356b97163fe63d39ff6de2be04acf7f9411d04a',
      'ios/Runner/AppDelegate.swift':
          '451c6d9ba0a2b3ff43092ea349c60fa79a91f1158b915eb29dbdd357cb95d7b8',
    };
    for (final entry in hashes.entries) {
      expect(
        sha256.convert(File(entry.key).readAsBytesSync()).toString(),
        entry.value,
        reason: entry.key,
      );
    }
    final html = File('graphify-out/graph.html').readAsStringSync();
    expect(html.startsWith('<!DOCTYPE html>\n$_graphifyNotice'), isTrue);
    expect(
      sha256
          .convert(utf8.encode(html.replaceFirst(_graphifyNotice, '')))
          .toString(),
      'cbc504a7a703007d342f5b878fdf685fef04c5c1284f46bc1d06f336994cf05f',
      reason: 'Only a non-executing provenance comment may change the viewer.',
    );
  });

  test('inventory pins each notice to its source-only or build-material scope', () {
    final inventory = File('third_party/NOTICE.md').readAsStringSync();
    const scopes = <String, List<String>>{
      'Graphify viewer template — source material': [
        'graphify-out/graph.html',
        'b6ffdbb8dd8eeec73f02d939f43e3320db06b461/graphify/export.py',
        'Copyright (c) 2026 Safi Shamsi',
        'licenses/graphify-MIT.txt',
        '36ecff6bbb97aca1be64e95f42538cf796adde5864edac583e620643c096931a',
        'not an application runtime asset',
      ],
      'Hermes Agent message templates — source material': [
        'test/fixtures/internal_background_messages.json',
        'bf0203a794a07aac3ff764972ab9087baa4e4f4e/hermes_cli/goals.py',
        'bf0203a794a07aac3ff764972ab9087baa4e4f4e/agent/context_compressor.py',
        'Copyright (c) 2025 Nous Research',
        'licenses/hermes-agent-MIT.txt',
        '821556e6336796450ab852d375117b48a4887e71d255794fd6318d99982a5ab6',
        'not application runtime assets',
      ],
      'Flutter iOS scaffold — source material': [
        'ios/Runner/AppDelegate.swift',
        '559ffa3f75e7402d65a8def9c28389a9b2e6fe42/packages/flutter_tools/templates/app/ios.tmpl/Runner/AppDelegate.swift',
        'Copyright 2014 The Flutter Authors',
        'licenses/flutter-BSD-3-Clause.txt',
        'a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20',
        'not compiled into the Android application',
      ],
      'Gradle wrapper — Library build material': [
        'd618c7aceb5c9f139c8c21c2ae6116a7e44e1d2d/gradlew',
        'Copyright © 2015-2021 the original authors.',
        'Copyright 2015 the original author or authors.',
        'e996d452d2645e70c01c11143ca2d3742734a28da2bf61f25c82bdc288c9e637',
        '1ef1b260d39daacbf9357f9d8594a8a743e2152e/gradle/wrapper/gradle-wrapper.jar',
        'licenses/Apache-2.0.txt',
        'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
        'licenses/gradle-NOTICE.txt',
        'd3d569a7f18525b229a7daa4926faf3e0566371f66686b157d62cdf7b3a0b3b3',
        'LGPL-2.1-or-later',
        'not executed by the application',
      ],
    };
    for (final scope in scopes.entries) {
      final section = inventory
          .split('## ${scope.key}\n')
          .last
          .split('\n## ')
          .first;
      expect(inventory, contains('## ${scope.key}\n'));
      for (final value in scope.value) {
        expect(section, contains(value), reason: scope.key);
      }
    }
    final capture = File(
      'tools/capture_internal_message_fixture.py',
    ).readAsStringSync();
    expect(capture, contains('third_party/NOTICE.md'));
    expect(capture, contains('third_party/licenses/hermes-agent-MIT.txt'));
  });
}
