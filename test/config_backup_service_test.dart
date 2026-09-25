import 'package:flutter_test/flutter_test.dart';
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
buildService(Map<String, Object> initialPrefs) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final manager = await ConnectionManager.create(
    prefs,
    credentialStore: _MemoryCredentialStore(),
  );
  return (
    ConfigBackupService(connectionManager: manager, preferences: prefs),
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
        'verbose_mode': true,
        'chat_tool_activity_visibility': 'hidden',
        'chat_reasoning_visibility': 'collapsed',
        'app_text_size_preference': 1.15,
        'voice_name': 'fr-CH-x-fra',
        'session_search.abc.mode': 'ai',
      });

      final backup = await service.export(appVersion: 'test');

      expect(backup.preferences['theme_mode'], 'dark');
      expect(backup.preferences['verbose_mode'], true);
      expect(backup.preferences['chat_tool_activity_visibility'], 'hidden');
      expect(backup.preferences['chat_reasoning_visibility'], 'collapsed');
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
      expect(targetPrefs.getBool('verbose_mode'), true);

      final restored = await targetManager.loadConnectionsWithSecrets();
      expect(restored, hasLength(1));
      expect(restored.single.apiKey, 'sk-live-key');
      expect(restored.single.dashboardPassword, 'dash-pass');
      expect(restored.single.host, 'carlos-miniserver.ts.net');
      expect(restored.single.useHttps, isTrue);
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
  });
}
