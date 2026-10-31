import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = <String, String>{};
  final Map<String, String> _cache = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Future<(ConfigBackupService, ConnectionManager, SharedPreferences)>
buildService(
  Map<String, Object> initialPrefs, {
  ClientCertificateService? certificates,
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final manager = await ConnectionManager.create(
    prefs,
    credentialStore: _MemoryCredentialStore(),
    certificateFiles: certificates,
  );
  return (
    ConfigBackupService(
      connectionManager: manager,
      preferences: prefs,
      certificates: certificates,
    ),
    manager,
    prefs,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigBackupService.export', () {
    test('captures every saved connection with its secrets', () async {
      final (service, manager, _) = await buildService(<String, Object>{});
      await manager.saveConnection(
        'Miniserver',
        'https://carlos-miniserver.ts.net',
        8642,
        'sk-live-key',
        dashboardUsername: 'carlos',
        dashboardPassword: 'dash-pass',
        dashboardPort: 9119,
      );

      final backup = await service.export(appVersion: '2.0.1+2131');

      expect(backup.connections, hasLength(1));
      expect(backup.connections.single.label, 'Miniserver');
      expect(backup.connections.single.apiKey, 'sk-live-key');
      expect(backup.connections.single.dashboardPassword, 'dash-pass');
      expect(backup.appVersion, '2.0.1+2131');
    });

    test('captures user preferences that belong in a backup', () async {
      final (service, _, _) = await buildService(<String, Object>{
        'theme_mode': 'dark',
        'theme_palette': 'purple',
        'verbose_mode': true,
        'app_text_size_preference': 1.15,
        'voice_name': 'fr-CH-x-fra',
        'session_search.abc.mode': 'ai',
      });

      final backup = await service.export(appVersion: 'test');

      expect(backup.preferences['theme_mode'], 'dark');
      expect(backup.preferences['theme_palette'], 'purple');
      expect(backup.preferences['verbose_mode'], true);
      expect(backup.preferences['app_text_size_preference'], 1.15);
      expect(backup.preferences['voice_name'], 'fr-CH-x-fra');
      expect(backup.preferences['session_search.abc.mode'], 'ai');
    });

    test('never exports the raw connection list or transient state', () async {
      final (service, manager, prefs) = await buildService(<String, Object>{
        'last_connection_id': 'conn-9',
        'gateway_turn_journal_v2': 'huge-blob',
        'flutter.some_plugin_cache': 'noise',
      });
      await manager.saveConnection('L', 'host', 8642, 'k');

      final backup = await service.export(appVersion: 'test');

      // saved_connections is rebuilt from `connections`; re-importing the raw
      // list would resurrect stale metadata alongside it.
      expect(backup.preferences.containsKey('saved_connections'), isFalse);
      expect(backup.preferences.containsKey('last_connection_id'), isFalse);
      expect(
        backup.preferences.containsKey('gateway_turn_journal_v2'),
        isFalse,
      );
      expect(prefs.getStringList('saved_connections'), isNotNull);
    });
  });

  group('ConfigBackupService.import', () {
    test('restores connections and preferences onto a blank install', () async {
      final (source, sourceManager, _) = await buildService(<String, Object>{
        'theme_mode': 'dark',
        'theme_palette': 'purple',
        'verbose_mode': true,
      });
      await sourceManager.saveConnection(
        'Miniserver',
        'https://carlos-miniserver.ts.net',
        8642,
        'sk-live-key',
        dashboardUsername: 'carlos',
        dashboardPassword: 'dash-pass',
      );
      final backup = await source.export(appVersion: 'test');

      final (target, targetManager, targetPrefs) = await buildService(
        <String, Object>{},
      );
      final result = await target.import(backup, mode: ConfigImportMode.merge);

      expect(result.connectionsAdded, 1);
      expect(result.connectionsUpdated, 0);
      expect(targetPrefs.getString('theme_mode'), 'dark');
      expect(targetPrefs.getString('theme_palette'), 'purple');
      expect(targetPrefs.getBool('verbose_mode'), true);

      final restored = await targetManager.loadConnectionsWithSecrets();
      expect(restored, hasLength(1));
      expect(restored.single.apiKey, 'sk-live-key');
      expect(restored.single.dashboardPassword, 'dash-pass');
      expect(restored.single.host, 'carlos-miniserver.ts.net');
      expect(restored.single.useHttps, isTrue);
    });

    test('import re-broadcasts a restored chat density', () async {
      final (source, sourceManager, _) = await buildService(<String, Object>{
        ChatDensity.preferenceKey: 'compact',
      });
      await sourceManager.saveConnection('Restored host', 'host', 8642, 'key');
      final backup = await source.export(appVersion: 'test');

      // The device was on the default before the import.
      chatDensitySelection.value = ChatDensity.comfortable;
      final (target, _, targetPrefs) = await buildService(<String, Object>{});

      await target.import(backup, mode: ConfigImportMode.merge);

      expect(targetPrefs.getString(ChatDensity.preferenceKey), 'compact');
      expect(chatDensitySelection.value, ChatDensity.compact);
    });

    test('merge updates a connection already present by id', () async {
      final (source, sourceManager, _) = await buildService(<String, Object>{});
      await sourceManager.saveConnection('New label', 'host', 8642, 'new-key');
      final backup = await source.export(appVersion: 'test');
      final importedId = backup.connections.single.id;

      final (target, targetManager, _) = await buildService(<String, Object>{});
      await targetManager.saveConnection('Old label', 'host', 8642, 'old-key');
      // Force an id collision the way a re-import onto the same device would.
      final existing = targetManager.getConnections().single;
      await targetManager.deleteConnection(existing.id);
      await targetManager.importConnections([
        backup.connections.single.copyWith(label: 'Old label', apiKey: 'old'),
      ], replaceExisting: false);

      final result = await target.import(backup, mode: ConfigImportMode.merge);

      expect(result.connectionsAdded, 0);
      expect(result.connectionsUpdated, 1);
      final restored = await targetManager.loadConnectionsWithSecrets();
      expect(restored, hasLength(1));
      expect(restored.single.id, importedId);
      expect(restored.single.label, 'New label');
      expect(restored.single.apiKey, 'new-key');
    });

    test('merge keeps connections that are not in the backup', () async {
      final (source, sourceManager, _) = await buildService(<String, Object>{});
      await sourceManager.saveConnection('Imported', 'a', 8642, 'k1');
      final backup = await source.export(appVersion: 'test');

      final (target, targetManager, _) = await buildService(<String, Object>{});
      await targetManager.saveConnection('Local only', 'b', 8642, 'k2');

      await target.import(backup, mode: ConfigImportMode.merge);

      final labels = targetManager
          .getConnections()
          .map((connection) => connection.label)
          .toList();
      expect(labels, containsAll(<String>['Imported', 'Local only']));
      expect(labels, hasLength(2));
    });

    test('replace drops connections that are not in the backup', () async {
      final (source, sourceManager, _) = await buildService(<String, Object>{});
      await sourceManager.saveConnection('Imported', 'a', 8642, 'k1');
      final backup = await source.export(appVersion: 'test');

      final (target, targetManager, _) = await buildService(<String, Object>{});
      await targetManager.saveConnection('Local only', 'b', 8642, 'k2');

      final result = await target.import(
        backup,
        mode: ConfigImportMode.replace,
      );

      expect(result.connectionsRemoved, 1);
      final restored = await targetManager.loadConnectionsWithSecrets();
      expect(restored, hasLength(1));
      expect(restored.single.label, 'Imported');
      expect(restored.single.apiKey, 'k1');
    });

    test('never writes a preference key the app does not own', () async {
      final backup = ConfigBackup(
        createdAt: DateTime.utc(2026),
        appVersion: 'test',
        connections: const <SavedConnection>[],
        preferences: const <String, Object>{
          'theme_mode': 'dark',
          'saved_connections': 'hostile',
          'gateway_turn_journal_v2': 'hostile',
          'totally_unknown_key': 'hostile',
        },
      );

      final (service, _, prefs) = await buildService(<String, Object>{});
      final result = await service.import(backup, mode: ConfigImportMode.merge);

      expect(prefs.getString('theme_mode'), 'dark');
      // saved_connections is owned by ConnectionManager. It may legitimately be
      // rewritten by the import, but never with the hostile payload.
      expect(prefs.get('saved_connections'), isNot(contains('hostile')));
      expect(prefs.get('gateway_turn_journal_v2'), isNull);
      expect(prefs.get('totally_unknown_key'), isNull);
      expect(result.preferencesSkipped, 3);
      expect(result.preferencesApplied, 1);
    });

    test('survives a full export → import → export round trip', () async {
      final (source, sourceManager, _) = await buildService(<String, Object>{
        'theme_mode': 'dark',
        'app_text_size_preference': 1.15,
      });
      await sourceManager.saveConnection(
        'Miniserver',
        'https://host.ts.net',
        8642,
        'sk-key',
        dashboardPassword: 'dash',
      );
      final original = await source.export(appVersion: 'test');

      final (target, _, _) = await buildService(<String, Object>{});
      await target.import(original, mode: ConfigImportMode.replace);
      final reexported = await target.export(appVersion: 'test');

      expect(reexported.connections.single.apiKey, 'sk-key');
      expect(reexported.connections.single.dashboardPassword, 'dash');
      expect(reexported.connections.single.id, original.connections.single.id);
      expect(reexported.preferences['theme_mode'], 'dark');
      expect(reexported.preferences['app_text_size_preference'], 1.15);
    });

    test('preserves an mTLS identity through export → import', () async {
      final sourceSupport = await Directory.systemTemp.createTemp(
        'hermes-backup-source',
      );
      final targetSupport = await Directory.systemTemp.createTemp(
        'hermes-backup-target',
      );
      addTearDown(() async {
        if (sourceSupport.existsSync()) {
          await sourceSupport.delete(recursive: true);
        }
        if (targetSupport.existsSync()) {
          await targetSupport.delete(recursive: true);
        }
      });
      final sourceCertificates = ClientCertificateService(
        supportDirectory: () async => sourceSupport,
      );
      final targetCertificates = ClientCertificateService(
        supportDirectory: () async => targetSupport,
      );

      final (source, sourceManager, _) = await buildService(
        <String, Object>{},
        certificates: sourceCertificates,
      );
      final identity = await sourceCertificates.commit(
        await sourceCertificates.importPkcs12(
          bytes: await File('test/fixtures/client-test.p12').readAsBytes(),
          password: 'test-password',
          label: 'proxy.p12',
        ),
      );
      await sourceManager.saveConnection(
        'mTLS proxy',
        'https://host.ts.net',
        443,
        'sk-key',
        clientCertificate: identity,
      );

      final backup = await source.export(appVersion: 'test');
      expect(backup.clientCertificates, hasLength(1));
      final bundled = backup.clientCertificates.values.single;
      expect(bundled.label, 'proxy.p12');
      expect(bundled.certificatePem, contains('BEGIN CERTIFICATE'));
      expect(bundled.privateKeyPem, contains('PRIVATE KEY'));
      // The throwaway container password has no remaining use.
      expect(bundled.password, isNull);

      final (target, targetManager, _) = await buildService(
        <String, Object>{},
        certificates: targetCertificates,
      );
      await target.import(backup, mode: ConfigImportMode.replace);

      final restored =
          (await targetManager.loadConnectionsWithSecrets()).single;
      final restoredCertificate = restored.clientCertificate;
      expect(restoredCertificate, isNotNull);
      expect(restoredCertificate!.label, 'proxy.p12');
      expect(
        restoredCertificate.certificatePemPath,
        startsWith(targetSupport.path),
      );
      expect(
        restoredCertificate.privateKeyPemPath,
        startsWith(targetSupport.path),
      );
      expect(File(restoredCertificate.certificatePemPath).existsSync(), isTrue);
      expect(File(restoredCertificate.privateKeyPemPath).existsSync(), isTrue);

      // Re-exporting the restored profile keeps the identity available.
      final reexported = await target.export(appVersion: 'test');
      expect(reexported.clientCertificates, hasLength(1));
    });

    test(
      'merge-import on the same device restores mTLS instead of dropping it',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'hermes-backup-merge',
        );
        addTearDown(() async {
          if (support.existsSync()) await support.delete(recursive: true);
        });
        final certificates = ClientCertificateService(
          supportDirectory: () async => support,
        );

        final (service, manager, _) = await buildService(
          <String, Object>{},
          certificates: certificates,
        );
        final identity = await certificates.commit(
          await certificates.importPkcs12(
            bytes: await File('test/fixtures/client-test.p12').readAsBytes(),
            password: 'test-password',
            label: 'proxy.p12',
          ),
        );
        await manager.saveConnection(
          'mTLS proxy',
          'https://host.ts.net',
          443,
          'sk-key',
          clientCertificate: identity,
        );
        final backup = await service.export(appVersion: 'test');
        final id = backup.connections.single.id;

        // Simulate a same-id profile already on the device without the identity.
        await manager.updateConnection(
          id,
          'mTLS proxy',
          'https://host.ts.net',
          443,
          'sk-key',
          clearClientCertificate: true,
        );
        expect(manager.getConnections().single.clientCertificate, isNull);

        await service.import(backup, mode: ConfigImportMode.merge);

        final restored = manager.getConnections().single;
        expect(restored.id, id);
        expect(restored.clientCertificate, isNotNull);
        expect(
          File(restored.clientCertificate!.certificatePemPath).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'rejects a backup that claims a certificate it does not carry',
      () async {
        final backup = ConfigBackup(
          createdAt: DateTime.utc(2026),
          appVersion: 'test',
          connections: [
            SavedConnection(
              id: 'conn-1',
              label: 'mTLS',
              host: 'host',
              port: 443,
              apiKey: 'key',
              useHttps: true,
              clientCertificate: const ClientCertificateConfig(
                label: 'missing',
                certificatePemPath: '/tmp/certificate.pem',
                privateKeyPemPath: '/tmp/private-key.pem',
              ),
            ),
          ],
          preferences: const <String, Object>{},
        );
        final json = backup.toJson();
        expect(
          () => ConfigBackup.fromJson(json),
          throwsA(
            isA<ConfigBackupException>().having(
              (e) => e.message,
              'message',
              contains('complete restore is not possible'),
            ),
          ),
        );
      },
    );
  });
}
