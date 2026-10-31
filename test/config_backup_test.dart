import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/config_backup.dart';

void main() {
  // Test-only KDF cost. Production uses ConfigBackupCodec.defaultIterations.
  const int fastIterations = 1000;

  ConfigBackup sampleBackup() {
    return ConfigBackup(
      createdAt: DateTime.utc(2026, 8, 28, 9, 30),
      appVersion: '2.0.1+2131',
      connections: [
        SavedConnection(
          id: 'conn-1',
          label: 'Miniserver',
          host: 'carlos-miniserver.ts.net',
          port: 8642,
          apiKey: 'sk-secret-key',
          useHttps: true,
          dashboardPortOverride: 9119,
          dashboardUsername: 'carlos',
          dashboardPassword: 'dash-secret',
          gatewayProfile: 'carlos-work',
        ),
      ],
      preferences: const <String, Object>{
        'theme_mode': 'dark',
        'verbose_mode': true,
        'app_text_size_preference': 1.15,
        'session_search.conn-1.mode': 'ai',
        'excluded_session_sources_conn-1': <String>['discord', 'local'],
        'some_counter': 7,
      },
    );
  }

  group('ConfigBackup serialization', () {
    test('round-trips connections including secrets', () {
      final restored = ConfigBackup.fromJson(sampleBackup().toJson());

      expect(restored.connections, hasLength(1));
      final conn = restored.connections.single;
      expect(conn.id, 'conn-1');
      expect(conn.label, 'Miniserver');
      expect(conn.host, 'carlos-miniserver.ts.net');
      expect(conn.port, 8642);
      expect(conn.useHttps, isTrue);
      expect(conn.apiKey, 'sk-secret-key');
      expect(conn.dashboardUsername, 'carlos');
      expect(conn.dashboardPassword, 'dash-secret');
      expect(conn.dashboardPortOverride, 9119);
      expect(conn.gatewayProfile, 'carlos-work');
    });

    test('round-trips preference values without losing their types', () {
      final restored = ConfigBackup.fromJson(sampleBackup().toJson());

      expect(restored.preferences['theme_mode'], isA<String>());
      expect(restored.preferences['verbose_mode'], isA<bool>());
      expect(restored.preferences['app_text_size_preference'], isA<double>());
      expect(restored.preferences['app_text_size_preference'], 1.15);
      // int must not degrade into double across the JSON boundary.
      expect(restored.preferences['some_counter'], isA<int>());
      expect(restored.preferences['some_counter'], 7);
      expect(
        restored.preferences['excluded_session_sources_conn-1'],
        isA<List<String>>(),
      );
      expect(restored.preferences['excluded_session_sources_conn-1'], [
        'discord',
        'local',
      ]);
    });

    test('round-trips client certificate identities', () {
      final backup = ConfigBackup(
        createdAt: DateTime.utc(2026),
        appVersion: 'test',
        connections: [
          SavedConnection(
            id: 'mtls',
            label: 'mTLS',
            host: 'host',
            port: 443,
            apiKey: 'key',
            useHttps: true,
          ),
        ],
        clientCertificates: const <String, ClientCertificateBackup>{
          'mtls': ClientCertificateBackup(
            label: 'proxy.p12',
            certificatePem:
                '-----BEGIN CERTIFICATE-----\nAAA\n-----END CERTIFICATE-----',
            privateKeyPem:
                '-----BEGIN PRIVATE KEY-----\nBBB\n-----END PRIVATE KEY-----',
            password: 'key-password',
          ),
        },
        preferences: const <String, Object>{},
      );

      final restored = ConfigBackup.fromJson(backup.toJson());

      expect(restored.clientCertificates, hasLength(1));
      final identity = restored.clientCertificates['mtls']!;
      expect(identity.label, 'proxy.p12');
      expect(identity.certificatePem, contains('BEGIN CERTIFICATE'));
      expect(identity.privateKeyPem, contains('BEGIN PRIVATE KEY'));
      expect(identity.password, 'key-password');
    });

    test('encrypts bundled client key material', () async {
      final backup = ConfigBackup(
        createdAt: DateTime.utc(2026),
        appVersion: 'test',
        connections: const <SavedConnection>[],
        clientCertificates: const <String, ClientCertificateBackup>{
          'mtls': ClientCertificateBackup(
            label: 'proxy.p12',
            certificatePem: 'unique-certificate-marker',
            privateKeyPem: 'unique-private-key-marker',
          ),
        },
        preferences: const <String, Object>{},
      );

      final armored = await ConfigBackupCodec.encrypt(
        backup,
        passphrase: 'correct horse battery staple',
        iterations: fastIterations,
      );

      expect(armored, isNot(contains('unique-certificate-marker')));
      expect(armored, isNot(contains('unique-private-key-marker')));
    });

    test('rejects a payload whose format marker is wrong', () {
      final json = sampleBackup().toJson();
      json['format'] = 'something-else';

      expect(
        () => ConfigBackup.fromJson(json),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test('rejects a payload from a newer, unknown backup version', () {
      final json = sampleBackup().toJson();
      json['version'] = ConfigBackup.currentVersion + 1;

      expect(
        () => ConfigBackup.fromJson(json),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test(
      'rejects a structurally corrupt payload instead of half-importing',
      () {
        final json = sampleBackup().toJson();
        json['connections'] = <dynamic>['not-a-map'];

        expect(
          () => ConfigBackup.fromJson(json),
          throwsA(isA<ConfigBackupException>()),
        );
      },
    );
  });

  group('ConfigBackupCodec', () {
    test('encrypts to an envelope that leaks no secret in cleartext', () async {
      final armored = await ConfigBackupCodec.encrypt(
        sampleBackup(),
        passphrase: 'correct horse battery staple',
        iterations: fastIterations,
      );

      expect(armored, isNot(contains('sk-secret-key')));
      expect(armored, isNot(contains('dash-secret')));
      expect(armored, isNot(contains('carlos-miniserver')));

      final envelope = jsonDecode(armored) as Map<String, dynamic>;
      expect(envelope['format'], ConfigBackupCodec.envelopeFormat);
      expect(envelope['kdf'], isA<Map<String, dynamic>>());
      expect(envelope['cipher'], isA<Map<String, dynamic>>());
    });

    test(
      'decrypts back to the original backup with the right passphrase',
      () async {
        final armored = await ConfigBackupCodec.encrypt(
          sampleBackup(),
          passphrase: 'correct horse battery staple',
          iterations: fastIterations,
        );

        final restored = await ConfigBackupCodec.decrypt(
          armored,
          passphrase: 'correct horse battery staple',
        );

        expect(restored.connections.single.apiKey, 'sk-secret-key');
        expect(restored.connections.single.dashboardPassword, 'dash-secret');
        expect(restored.preferences['verbose_mode'], true);
        expect(restored.appVersion, '2.0.1+2131');
      },
    );

    test('fails closed on a wrong passphrase', () async {
      final armored = await ConfigBackupCodec.encrypt(
        sampleBackup(),
        passphrase: 'correct horse battery staple',
        iterations: fastIterations,
      );

      expect(
        () => ConfigBackupCodec.decrypt(armored, passphrase: 'wrong'),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test('fails closed when the ciphertext has been tampered with', () async {
      final armored = await ConfigBackupCodec.encrypt(
        sampleBackup(),
        passphrase: 'pass',
        iterations: fastIterations,
      );
      final envelope = jsonDecode(armored) as Map<String, dynamic>;
      final cipher = envelope['cipher'] as Map<String, dynamic>;
      final bytes = base64Decode(cipher['ciphertext'] as String);
      bytes[0] = bytes[0] ^ 0xFF;
      cipher['ciphertext'] = base64Encode(bytes);

      expect(
        () =>
            ConfigBackupCodec.decrypt(jsonEncode(envelope), passphrase: 'pass'),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test('uses a fresh salt and nonce for every export', () async {
      final first =
          jsonDecode(
                await ConfigBackupCodec.encrypt(
                  sampleBackup(),
                  passphrase: 'pass',
                  iterations: fastIterations,
                ),
              )
              as Map<String, dynamic>;
      final second =
          jsonDecode(
                await ConfigBackupCodec.encrypt(
                  sampleBackup(),
                  passphrase: 'pass',
                  iterations: fastIterations,
                ),
              )
              as Map<String, dynamic>;

      expect(
        (first['kdf'] as Map)['salt'],
        isNot((second['kdf'] as Map)['salt']),
      );
      expect(
        (first['cipher'] as Map)['nonce'],
        isNot((second['cipher'] as Map)['nonce']),
      );
    });

    test('rejects an empty passphrase rather than encrypting weakly', () {
      expect(
        () => ConfigBackupCodec.encrypt(
          sampleBackup(),
          passphrase: '   ',
          iterations: fastIterations,
        ),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test('rejects a file that is not a Hermes backup envelope', () {
      expect(
        () =>
            ConfigBackupCodec.decrypt('{"hello":"world"}', passphrase: 'pass'),
        throwsA(isA<ConfigBackupException>()),
      );
      expect(
        () => ConfigBackupCodec.decrypt('not json at all', passphrase: 'pass'),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test('honours the iteration count recorded in the envelope', () async {
      final armored = await ConfigBackupCodec.encrypt(
        sampleBackup(),
        passphrase: 'pass',
        iterations: fastIterations,
      );
      final envelope = jsonDecode(armored) as Map<String, dynamic>;
      expect((envelope['kdf'] as Map)['iterations'], fastIterations);

      // Tampering with the cost parameter must not silently produce a
      // different key that decrypts anyway.
      (envelope['kdf'] as Map)['iterations'] = fastIterations + 1;
      expect(
        () =>
            ConfigBackupCodec.decrypt(jsonEncode(envelope), passphrase: 'pass'),
        throwsA(isA<ConfigBackupException>()),
      );
    });

    test('refuses an absurd iteration count from an untrusted file', () {
      expect(
        () => ConfigBackupCodec.decrypt(
          jsonEncode(<String, dynamic>{
            'format': ConfigBackupCodec.envelopeFormat,
            'version': 1,
            'kdf': <String, dynamic>{
              'algorithm': 'pbkdf2-hmac-sha256',
              'iterations': 100000000,
              'salt': base64Encode(List<int>.filled(16, 1)),
            },
            'cipher': <String, dynamic>{
              'algorithm': 'aes-256-gcm',
              'nonce': base64Encode(List<int>.filled(12, 2)),
              'ciphertext': base64Encode(List<int>.filled(8, 3)),
              'mac': base64Encode(List<int>.filled(16, 4)),
            },
          }),
          passphrase: 'pass',
        ),
        throwsA(isA<ConfigBackupException>()),
      );
    });
  });
}
