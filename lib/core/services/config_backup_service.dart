// ignore_for_file: prefer_initializing_formals

import 'package:shared_preferences/shared_preferences.dart';

import 'config_backup.dart';
import 'connection_manager.dart';

/// How an imported backup is applied to the connections already on the device.
enum ConfigImportMode {
  /// Connections present in the backup are added or updated by id; anything
  /// else already on the device is kept.
  merge,

  /// The device ends up with exactly the connections in the backup.
  replace,
}

class ConfigImportResult {
  final int connectionsAdded;
  final int connectionsUpdated;
  final int connectionsRemoved;
  final int preferencesApplied;
  final int preferencesSkipped;

  const ConfigImportResult({
    required this.connectionsAdded,
    required this.connectionsUpdated,
    required this.connectionsRemoved,
    required this.preferencesApplied,
    required this.preferencesSkipped,
  });

  String get summary {
    final parts = <String>[];
    if (connectionsAdded > 0) parts.add('$connectionsAdded added');
    if (connectionsUpdated > 0) parts.add('$connectionsUpdated updated');
    if (connectionsRemoved > 0) parts.add('$connectionsRemoved removed');
    final connections = parts.isEmpty
        ? 'No connection changes'
        : 'Connections: ${parts.join(', ')}';
    return '$connections · $preferencesApplied settings restored';
  }
}

/// Builds and applies configuration backups.
///
/// Only keys this app actually owns are exported and imported. Everything else
/// in `SharedPreferences` — plugin caches, the turn journal, the raw connection
/// list, transient UI state — is deliberately excluded, so an imported file can
/// never overwrite storage the backup format does not understand.
class ConfigBackupService {
  /// Exact preference keys that are safe to carry between devices.
  static const Set<String> exactPreferenceKeys = <String>{
    'theme_mode',
    'verbose_mode',
    'chat_tool_activity_visibility',
    'chat_reasoning_visibility',
    'voice_name',
    'voice_locale',
    'app_text_size_preference',
  };

  /// Prefixes for per-connection and per-chat preferences, which are keyed by
  /// ids that the backup restores alongside them.
  static const List<String> preferenceKeyPrefixes = <String>[
    'session_search.',
    'chat_model_override.',
    'excluded_session_sources_',
    'chat_spaces_v1_',
  ];

  final ConnectionManager _connectionManager;
  final SharedPreferences _preferences;

  ConfigBackupService({
    required ConnectionManager connectionManager,
    required SharedPreferences preferences,
  }) : _connectionManager = connectionManager,
       _preferences = preferences;

  static bool isBackedUpKey(String key) {
    if (exactPreferenceKeys.contains(key)) return true;
    return preferenceKeyPrefixes.any(key.startsWith);
  }

  Future<ConfigBackup> export({required String appVersion}) async {
    final connections = await _connectionManager.loadConnectionsWithSecrets();

    final preferences = <String, Object>{};
    for (final key in _preferences.getKeys()) {
      if (!isBackedUpKey(key)) continue;
      final value = _preferences.get(key);
      if (value == null) continue;
      if (value is bool || value is int || value is double || value is String) {
        preferences[key] = value;
      } else if (value is List<String>) {
        preferences[key] = List<String>.of(value);
      } else if (value is List) {
        preferences[key] = value.map((item) => item.toString()).toList();
      }
    }

    return ConfigBackup(
      createdAt: DateTime.now().toUtc(),
      appVersion: appVersion,
      connections: connections,
      preferences: preferences,
    );
  }

  Future<ConfigImportResult> import(
    ConfigBackup backup, {
    required ConfigImportMode mode,
  }) async {
    final existingIds = _connectionManager
        .getConnections()
        .map((connection) => connection.id)
        .toSet();

    var added = 0;
    var updated = 0;
    for (final connection in backup.connections) {
      if (existingIds.contains(connection.id)) {
        updated++;
      } else {
        added++;
      }
    }
    final removed = mode == ConfigImportMode.replace
        ? existingIds
              .difference(
                backup.connections.map((connection) => connection.id).toSet(),
              )
              .length
        : 0;

    try {
      await _connectionManager.importConnections(
        backup.connections,
        replaceExisting: mode == ConfigImportMode.replace,
      );
    } on CredentialStorageException catch (error) {
      throw ConfigBackupException(error.message);
    }

    var applied = 0;
    var skipped = 0;
    for (final entry in backup.preferences.entries) {
      if (!isBackedUpKey(entry.key)) {
        skipped++;
        continue;
      }
      final value = entry.value;
      if (value is bool) {
        await _preferences.setBool(entry.key, value);
      } else if (value is int) {
        await _preferences.setInt(entry.key, value);
      } else if (value is double) {
        await _preferences.setDouble(entry.key, value);
      } else if (value is String) {
        await _preferences.setString(entry.key, value);
      } else if (value is List<String>) {
        await _preferences.setStringList(entry.key, value);
      } else {
        skipped++;
        continue;
      }
      applied++;
    }

    return ConfigImportResult(
      connectionsAdded: added,
      connectionsUpdated: updated,
      connectionsRemoved: removed,
      preferencesApplied: applied,
      preferencesSkipped: skipped,
    );
  }
}
