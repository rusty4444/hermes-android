// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/client_certificate.dart';
import '../models/connection.dart';
import '../models/session.dart';
import '../utils/android_prompt_context.dart';
import 'client_certificate_service.dart';
import 'connection_mutation_barrier.dart';
import 'tls_client_factory.dart';

// Re-export for convenience
export '../models/connection.dart';
export '../models/session.dart';

/// Injectable secret storage boundary used by [ConnectionManager].
///
/// The production implementation is backed by Android Keystore through
/// `flutter_secure_storage`; tests use a deterministic in-memory fake.
abstract interface class CredentialStore {
  /// Last read-back only; callers needing authority must await [read].
  String? readCached(String key);

  /// Read physical storage and refresh the cache, including removal on null.
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureCredentialStore implements CredentialStore {
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateWithBackup: true,
    storageNamespace: 'hermes_android_connections',
  );

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = <String, String>{};

  FlutterSecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage(aOptions: _androidOptions);

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<String?> read(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
    _cache.remove(key);
  }
}

class CredentialStorageException implements Exception {
  final String message;

  const CredentialStorageException(this.message);

  @override
  String toString() => message;
}

class _ConnectionCredentials {
  final String apiKey;
  final String? dashboardPassword;

  /// Password for an encrypted PEM client key. Persisted here (the platform
  /// secure store) rather than in the connection metadata preferences.
  final String? clientKeyPassword;

  const _ConnectionCredentials({
    required this.apiKey,
    required this.dashboardPassword,
    this.clientKeyPassword,
  });

  bool get isEmpty =>
      apiKey.isEmpty && dashboardPassword == null && clientKeyPassword == null;

  String encode() => jsonEncode(<String, String>{
    if (apiKey.isNotEmpty) 'api_key': apiKey,
    'dashboard_password': ?dashboardPassword,
    'client_key_password': ?clientKeyPassword,
  });

  static _ConnectionCredentials decode(String encoded) {
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      final apiKey = map['api_key'];
      final dashboardPassword = map['dashboard_password'];
      final clientKeyPassword = map['client_key_password'];
      if (apiKey != null && apiKey is! String ||
          dashboardPassword != null && dashboardPassword is! String ||
          clientKeyPassword != null && clientKeyPassword is! String) {
        throw const FormatException();
      }
      final password = (dashboardPassword as String?)?.trim();
      return _ConnectionCredentials(
        apiKey: (apiKey as String?) ?? '',
        dashboardPassword: password == null || password.isEmpty
            ? null
            : password,
        clientKeyPassword: clientKeyPassword as String?,
      );
    } catch (_) {
      throw const CredentialStorageException(
        'Stored connection credentials could not be read safely.',
      );
    }
  }

  static _ConnectionCredentials fromConnection(SavedConnection connection) {
    final password = connection.dashboardPassword?.trim();

    return _ConnectionCredentials(
      apiKey: connection.apiKey,
      dashboardPassword: password == null || password.isEmpty ? null : password,
      clientKeyPassword: connection.clientCertificate?.privateKeyPassword,
    );
  }
}

/// Manages non-secret connection metadata in SharedPreferences and credentials
/// in a platform secure store.
class ConnectionManager {
  static const String _key = 'saved_connections';
  static const String _credentialKeyPrefix = 'connection_credentials_v1.';
  static const Uuid _uuid = Uuid();
  static final CredentialStore _sharedCredentialStore =
      FlutterSecureCredentialStore();
  static const _pushChannel = MethodChannel(
    'com.hermesagent.hermes_android/mobile_push',
  );
  // Only finished transactions enter this outbox. An uncertain END reply must
  // stay retryable by a replacement manager, not strand this native lease until
  // process death. Retrying END never restores consent or releases a sibling.
  static final _pendingPushMutationEnds = <String, Map<String, dynamic>>{};
  // saved_connections is one physical value across managers/store wrappers.
  // Share ownership before reading a baseline, never secrets between stores.
  static Future<void>? _savedListTail;

  final SharedPreferences prefs;
  final CredentialStore _credentialStore;
  final bool _nativePushSupported;
  final ClientCertificateFileStore _certificateFiles;

  ConnectionManager(
    this.prefs, {
    CredentialStore? credentialStore,
    ClientCertificateFileStore? certificateFiles,
    bool? nativePushSupported,
  }) : _credentialStore = credentialStore ?? _sharedCredentialStore,
       _certificateFiles = certificateFiles ?? ClientCertificateService(),
       _nativePushSupported =
           nativePushSupported ?? (!kIsWeb && Platform.isAndroid);

  static Future<ConnectionManager> create(
    SharedPreferences prefs, {
    CredentialStore? credentialStore,
    ClientCertificateFileStore? certificateFiles,
  }) async {
    final manager = ConnectionManager(
      prefs,
      credentialStore: credentialStore,
      certificateFiles: certificateFiles,
    );
    await manager.initialize();
    return manager;
  }

  /// Migrates legacy plaintext credentials before the first UI is rendered.
  ///
  /// Every legacy credential bundle is written and read back first. The
  /// SharedPreferences list is sanitized only after all read-backs match, so a
  /// partial secure-store failure leaves every legacy profile retryable.
  Future<void> initialize() => _withSavedListTransaction([], () async {
    final maps = _readConnectionMaps();
    final connections = _connectionsFromMaps(maps);
    final hasLegacyFields = maps.any(
      (map) =>
          map.containsKey('api_key') ||
          map.containsKey('dashboard_password') ||
          _hasLegacyCertificatePassword(map),
    );

    Future<void> migrateAndHydrate() async {
      try {
        for (final connection in connections) {
          final legacy = _ConnectionCredentials.fromConnection(connection);
          if (!legacy.isEmpty) {
            // An earlier release already moved API/dashboard credentials into the
            // secure store while leaving only the PEM password in preferences.
            // Secure values win over stale legacy fields on a migration retry.
            final encoded = await _credentialStore.read(
              _credentialKey(connection.id),
            );
            final existing = encoded == null
                ? const _ConnectionCredentials(
                    apiKey: '',
                    dashboardPassword: null,
                  )
                : _ConnectionCredentials.decode(encoded);
            await _writeAndVerifyCredentials(
              connection.id,
              _ConnectionCredentials(
                apiKey: existing.apiKey.isEmpty
                    ? legacy.apiKey
                    : existing.apiKey,
                dashboardPassword:
                    existing.dashboardPassword ?? legacy.dashboardPassword,
                clientKeyPassword:
                    existing.clientKeyPassword ?? legacy.clientKeyPassword,
              ),
            );
          }
        }

        for (final connection in connections) {
          final encoded = await _credentialStore.read(
            _credentialKey(connection.id),
          );
          if (encoded != null) {
            _ConnectionCredentials.decode(encoded);
          }
        }

        if (hasLegacyFields) {
          await _saveAll(connections);
        }
      } on CredentialStorageException {
        rethrow;
      } catch (_) {
        throw const CredentialStorageException(
          'Connection credentials could not be migrated safely.',
        );
      }
    }

    if (hasLegacyFields) {
      await _withConnectionMutation(
        connections.map((c) => c.id),
        migrateAndHydrate,
      );
    } else {
      await migrateAndHydrate();
    }
  });

  /// Synchronous UI projection. Credentials are only as fresh as this store's
  /// last read-back; mutations/export/push must refresh before using authority.
  List<SavedConnection> getConnections() {
    return _connectionsFromMaps(
      _readConnectionMaps(),
    ).map(_hydrateFromCachedCredentials).toList();
  }

  /// Returns every saved connection with its secrets read back from the secure
  /// store, rather than from the in-memory cache used by [getConnections].
  ///
  /// Config export needs this: a freshly launched app has an empty credential
  /// cache, so [getConnections] alone would hand back connections with blank
  /// API keys and silently produce a useless backup.
  Future<List<SavedConnection>> loadConnectionsWithSecrets() =>
      _withSavedListTransaction([], _loadConnectionsWithSecrets);

  Future<List<SavedConnection>> _loadConnectionsWithSecrets() async {
    final connections = _connectionsFromMaps(_readConnectionMaps());
    final hydrated = <SavedConnection>[];
    for (final connection in connections) {
      final encoded = await _readEncodedCredentials(connection.id);
      if (encoded == null) {
        hydrated.add(connection);
        continue;
      }
      final credentials = _ConnectionCredentials.decode(encoded);
      hydrated.add(_applyCredentials(connection, credentials));
    }
    return hydrated;
  }

  Future<String?> _readEncodedCredentials(String connectionId) async {
    try {
      return await _credentialStore.read(_credentialKey(connectionId));
    } catch (_) {
      // Provider errors may contain secrets; never attach them or use the cache.
      throw const CredentialStorageException(
        'Connection credentials could not be read safely.',
      );
    }
  }

  /// Refresh this store's cache without waiting for unrelated transactions.
  /// Push must not mistake another wrapper's cold cache for revoked consent.
  /// Callers fence the asynchronous read with the per-ID mutation epoch.
  Future<void> refreshConnectionCredentials(String id) async {
    try {
      final encoded = await _credentialStore.read(_credentialKey(id));
      if (encoded != null) _ConnectionCredentials.decode(encoded);
    } catch (_) {
      throw const CredentialStorageException(
        'Connection credentials could not be read safely.',
      );
    }
  }

  /// After native engine recovery, refresh metadata as well as secrets before
  /// granting fresh push consent. A surviving isolate's owned list transaction
  /// already protects its metadata projection; do not wait behind an unrelated
  /// held mutation or reload over that transaction's optimistic cache.
  Future<void> refreshMobilePushBinding(String id) {
    if (_savedListTail != null) return refreshConnectionCredentials(id);
    return _withSavedListTransaction(
      [],
      () => refreshConnectionCredentials(id),
    );
  }

  /// Exact persisted metadata shape for native admission. Re-serializing the
  /// model would add defaults absent in older saved lists. Never copy secrets.
  Map<String, dynamic>? mobilePushConsentMetadata(String id) {
    final rows = _readConnectionMaps().where((row) => row['id'] == id).toList();
    if (rows.length != 1) return null;
    return Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(rows.single)
        ..remove('api_key')
        ..remove('dashboard_password'),
    );
  }

  /// Writes a whole set of connections at once, preserving their ids.
  ///
  /// Every credential bundle is written and verified before the metadata list
  /// is committed, matching the fail-closed contract of the single-connection
  /// paths. When [replaceExisting] is true, connections absent from [incoming]
  /// are removed along with their credentials.
  Future<void> importConnections(
    List<SavedConnection> incoming, {
    required bool replaceExisting,
  }) {
    final ordered = List<SavedConnection>.of(incoming);
    return _withSavedListTransaction(ordered.map((c) => c.id), () async {
      final current = await _loadConnectionsWithSecrets();
      final previousMetadata = prefs.getStringList(_key);

      final List<SavedConnection> next;
      final removed = <SavedConnection>[];
      if (replaceExisting) {
        final keep = ordered.map((connection) => connection.id).toSet();
        removed.addAll(
          current.where((connection) => !keep.contains(connection.id)),
        );
        next = ordered;
      } else {
        final incomingIds = ordered.map((connection) => connection.id).toSet();
        next = <SavedConnection>[
          ...ordered,
          ...current.where(
            (connection) => !incomingIds.contains(connection.id),
          ),
        ];
      }

      await _withConnectionMutation(
        [...ordered, ...removed].map((connection) => connection.id),
        () async {
          final previousCredentials = <String, String?>{};
          final attemptedIds = <String>{};
          var metadataAttempted = false;
          // Capture every physical bundle before the first write, including absent
          // entries. Restoring raw bundles preserves all secrets and exact bytes.
          for (final connection in [...ordered, ...removed]) {
            if (previousCredentials.containsKey(connection.id)) continue;
            final encoded = await _readEncodedCredentials(connection.id);
            if (encoded != null) _ConnectionCredentials.decode(encoded);
            previousCredentials[connection.id] = encoded;
          }
          try {
            for (final connection in ordered) {
              attemptedIds.add(
                connection.id,
              ); // a failed ACK may follow a real write
              await _writeAndVerifyCredentials(
                connection.id,
                _ConnectionCredentials.fromConnection(connection),
              );
            }
            for (final connection in removed) {
              attemptedIds.add(connection.id);
              await _writeAndVerifyCredentials(
                connection.id,
                const _ConnectionCredentials(
                  apiKey: '',
                  dashboardPassword: null,
                ),
              );
            }
            metadataAttempted = true;
            await _saveAll(next);
          } catch (_) {
            var restored = true;
            for (final id in attemptedIds.toList().reversed) {
              try {
                await _writeAndVerifyEncodedCredentials(
                  id,
                  previousCredentials[id],
                );
              } catch (_) {
                restored = false;
              }
            }
            if (metadataAttempted) {
              try {
                final saved = previousMetadata == null
                    ? await prefs.remove(_key)
                    : await prefs.setStringList(_key, previousMetadata);
                if (!saved) restored = false;
              } catch (_) {
                restored = false;
              }
            }
            throw CredentialStorageException(
              restored
                  ? 'Connection import could not be saved safely. Previous configuration was preserved.'
                  : 'Connection import failed and the previous configuration could not be fully restored. Retry after checking secure storage.',
            );
          }
        },
      );
      await _deleteUnreferencedCertificates(current, next);
    });
  }

  Future<void> saveConnection(
    String label,
    String host,
    int? port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
    String? gatewayProfile,
    ClientCertificateConfig? clientCertificate,
  }) => _withSavedListTransaction([], () async {
    final normalized = SavedConnection.normalizeHostAndPort(host, port);
    final profile = gatewayProfile?.trim();
    final conn = SavedConnection(
      id: _uuid.v4(),
      label: label,
      host: normalized.host,
      port: normalized.port,
      apiKey: apiKey,
      useHttps: normalized.useHttps,
      gatewayPrefix: gatewayPrefix,
      dashboardPrefix: dashboardPrefix,
      dashboardProxied: dashboardProxied,
      desktopGatewayUrl: desktopGatewayUrl?.trim(),
      dashboardPortOverride: dashboardPort,
      dashboardUsername: dashboardUsername,
      dashboardPassword: dashboardPassword,
      gatewayProfile: profile == null || profile.isEmpty ? null : profile,
      clientCertificate: clientCertificate,
    );
    final current = await _loadConnectionsWithSecrets();
    final previousConnections = List<SavedConnection>.of(current);
    current.insert(0, conn);
    await _commitCredentialAndMetadata(
      connectionId: conn.id,
      previousCredentials: const _ConnectionCredentials(
        apiKey: '',
        dashboardPassword: null,
      ),
      nextCredentials: _ConnectionCredentials.fromConnection(conn),
      connections: current,
      previousConnections: previousConnections,
    );
  });

  /// Updates all editable fields on an existing connection while preserving its
  /// id and list position. Empty optional strings clear their saved values.
  Future<void> updateConnection(
    String connId,
    String label,
    String host,
    int? port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
    String? gatewayProfile,
    ClientCertificateConfig? clientCertificate,
    bool clearClientCertificate = false,
  }) => _withSavedListTransaction([connId], () async {
    final current = await _loadConnectionsWithSecrets();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;

    final previousCredentials = _ConnectionCredentials.fromConnection(
      current[idx],
    );
    final previousConnections = List<SavedConnection>.of(current);

    final normalized = SavedConnection.normalizeHostAndPort(host, port);
    final gateway = gatewayPrefix?.trim();
    final dashboard = dashboardPrefix?.trim();
    final dashUser = dashboardUsername?.trim();
    final dashPass = dashboardPassword?.trim();
    final desktopGateway = desktopGatewayUrl?.trim();
    final profile = gatewayProfile?.trim();

    current[idx] = current[idx].copyWith(
      label: label,
      host: normalized.host,
      port: normalized.port,
      apiKey: apiKey,
      useHttps: normalized.useHttps,
      gatewayPrefix: gateway == null || gateway.isEmpty ? null : gateway,
      clearGatewayPrefix: gateway != null && gateway.isEmpty,
      dashboardPrefix: dashboard == null || dashboard.isEmpty
          ? null
          : dashboard,
      clearDashboardPrefix: dashboard != null && dashboard.isEmpty,
      dashboardProxied: dashboardProxied,
      desktopGatewayUrl: desktopGateway == null || desktopGateway.isEmpty
          ? null
          : desktopGateway,
      clearDesktopGatewayUrl: desktopGateway != null && desktopGateway.isEmpty,
      dashboardPortOverride: dashboardPort,
      clearDashboardPort: dashboardPort == null,
      dashboardUsername: dashUser == null || dashUser.isEmpty ? null : dashUser,
      clearDashboardUsername: dashUser != null && dashUser.isEmpty,
      dashboardPassword: dashPass == null || dashPass.isEmpty ? null : dashPass,
      clearDashboardPassword: dashPass != null && dashPass.isEmpty,
      gatewayProfile: profile == null || profile.isEmpty ? null : profile,
      clearGatewayProfile: profile != null && profile.isEmpty,
      clientCertificate: clientCertificate,
      clearClientCertificate: clearClientCertificate,
    );
    await _commitCredentialAndMetadata(
      connectionId: connId,
      previousCredentials: previousCredentials,
      nextCredentials: _ConnectionCredentials.fromConnection(current[idx]),
      connections: current,
      previousConnections: previousConnections,
    );
  });

  /// Updates the dashboard port + basic-auth credentials on an existing
  /// connection. Empty strings clear the corresponding field.
  Future<void> updateDashboardAuth(
    String connId, {
    int? dashboardPort,
    required String username,
    required String password,
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool? dashboardProxied,
  }) => _withSavedListTransaction([connId], () async {
    final current = await _loadConnectionsWithSecrets();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;
    final previousCredentials = _ConnectionCredentials.fromConnection(
      current[idx],
    );
    final previousConnections = List<SavedConnection>.of(current);
    final u = username.trim();
    final p = password.trim();
    final gateway = gatewayPrefix?.trim();
    final dashboard = dashboardPrefix?.trim();
    current[idx] = current[idx].copyWith(
      gatewayPrefix: gateway == null || gateway.isEmpty ? null : gateway,
      clearGatewayPrefix: gateway != null && gateway.isEmpty,
      dashboardPrefix: dashboard == null || dashboard.isEmpty
          ? null
          : dashboard,
      clearDashboardPrefix: dashboard != null && dashboard.isEmpty,
      dashboardProxied: dashboardProxied,
      dashboardPortOverride: dashboardPort,
      clearDashboardPort: dashboardPort == null,
      dashboardUsername: u.isEmpty ? null : u,
      clearDashboardUsername: u.isEmpty,
      dashboardPassword: p.isEmpty ? null : p,
      clearDashboardPassword: p.isEmpty,
    );
    await _commitCredentialAndMetadata(
      connectionId: connId,
      previousCredentials: previousCredentials,
      nextCredentials: _ConnectionCredentials.fromConnection(current[idx]),
      connections: current,
      previousConnections: previousConnections,
    );
  });

  Future<void> updateApiKey(String connId, String apiKey) =>
      _withSavedListTransaction([connId], () async {
        final current = await _loadConnectionsWithSecrets();
        final idx = current.indexWhere((c) => c.id == connId);
        if (idx < 0) return;
        final previousCredentials = _ConnectionCredentials.fromConnection(
          current[idx],
        );
        final previousConnections = List<SavedConnection>.of(current);
        current[idx] = current[idx].copyWith(apiKey: apiKey);
        await _commitCredentialAndMetadata(
          connectionId: connId,
          previousCredentials: previousCredentials,
          nextCredentials: _ConnectionCredentials.fromConnection(current[idx]),
          connections: current,
          previousConnections: previousConnections,
        );
      });

  Future<void> deleteConnection(String id) =>
      _withSavedListTransaction([id], () async {
        final current = await _loadConnectionsWithSecrets();
        final index = current.indexWhere((connection) => connection.id == id);
        if (index < 0) return;
        final previousCredentials = _ConnectionCredentials.fromConnection(
          current[index],
        );
        final previousConnections = List<SavedConnection>.of(current);
        current.removeWhere((c) => c.id == id);
        await _commitCredentialAndMetadata(
          connectionId: id,
          previousCredentials: previousCredentials,
          nextCredentials: const _ConnectionCredentials(
            apiKey: '',
            dashboardPassword: null,
          ),
          connections: current,
          previousConnections: previousConnections,
        );
      });

  /// Resets metadata and every identifiable credential bundle, including corrupt
  /// bundles/legacy rows. Native consent is independent of damaged metadata.
  /// Keep the list owner and revocation lease through verified removal/rollback;
  /// never delete credentials or certificate files on an optimistic cache change.
  Future<void> resetConnections() => _withSavedListTransaction([], () async {
    final previous = prefs.get(_key);
    final ids = <String>{};
    var hadCertificate = false;
    // Decode IDs individually: one corrupt row (or unrelated field) must not
    // orphan the recoverable siblings. Unrecoverable IDs cannot be guessed.
    if (previous is List) {
      for (final raw in previous.whereType<String>()) {
        try {
          final row = jsonDecode(raw);
          if (row is Map && row['client_certificate'] is Map) {
            hadCertificate = true;
          }
          if (row is Map &&
              row['id'] is String &&
              (row['id'] as String).isNotEmpty) {
            ids.add(row['id'] as String);
          }
        } catch (_) {
          // The sealed native binding may still identify the affected account.
        }
      }
    }
    if (_nativePushSupported) {
      try {
        final state = await _pushChannel.invokeMapMethod<String, dynamic>(
          'snapshot',
        );
        final bound = state?['connection'];
        if (bound is String && bound.isNotEmpty) ids.add(bound);
      } catch (_) {
        throw const CredentialStorageException(
          'Native push consent could not be read safely. Retry the connection reset.',
        );
      }
    }
    await _withConnectionMutation(ids, () async {
      // Preserve raw bytes, not decoded secrets: reset must also recover from a
      // corrupt bundle, and a failed cleanup must be able to restore it exactly.
      final previousCredentials = <String, String?>{};
      for (final id in ids) {
        previousCredentials[id] = await _readEncodedCredentials(id);
      }
      final attemptedIds = <String>[];
      try {
        if (!await prefs.remove(_key)) {
          throw const CredentialStorageException(
            'Saved connections could not be reset safely.',
          );
        }
        await prefs.reload();
        if (prefs.containsKey(_key)) {
          throw const CredentialStorageException(
            'Saved connections could not be reset safely.',
          );
        }
        for (final id in ids) {
          // A failed acknowledgement may follow a physical delete.
          attemptedIds.add(id);
          await _writeAndVerifyEncodedCredentials(id, null);
        }
      } catch (_) {
        var restored = true;
        for (final id in attemptedIds.reversed) {
          try {
            await _writeAndVerifyEncodedCredentials(
              id,
              previousCredentials[id],
            );
          } catch (_) {
            restored = false;
          }
        }
        try {
          await _restoreMetadata(previous);
          if (jsonEncode(prefs.get(_key)) != jsonEncode(previous)) {
            restored = false;
          }
        } catch (_) {
          restored = false;
        }
        // Provider exceptions can contain credentials. Report only the verified
        // rollback disposition, never the original exception or raw bundle.
        throw CredentialStorageException(
          restored
              ? 'Saved connections could not be reset safely. Previous configuration was preserved.'
              : 'Connection reset failed and the previous configuration could not be fully restored. Retry after checking secure storage.',
        );
      }
    });
    // Metadata removal and native cleanup are confirmed while the shared list
    // owner is still held. File leases protect identities in live editors.
    if (hadCertificate) {
      try {
        await _certificateFiles.deleteUnreferenced(const <String>[]);
      } catch (_) {
        // Optional collection never turns a committed reset into a failed save.
      }
    }
  });

  Future<T> _withSavedListTransaction<T>(
    Iterable<String> pendingIds,
    Future<T> Function() action,
  ) {
    // Fence queued targeted edits synchronously, including initially-off starts.
    // Import removals are discovered only after owning the current list.
    final lease = ConnectionMutationBarrier.begin(pendingIds);
    final previous = _savedListTail;
    final completed = Completer<void>();
    final tail = completed.future;
    _savedListTail = tail;
    Future<T> perform() async {
      try {
        if (previous != null) await previous;
        try {
          await prefs.reload();
        } catch (_) {
          throw const CredentialStorageException(
            'Saved connection metadata could not be read safely.',
          );
        }
        return await action();
      } finally {
        lease.release();
        // A completed Future must not retain its disposed fake-async zone.
        if (identical(_savedListTail, tail)) _savedListTail = null;
        completed.complete();
      }
    }

    return perform();
  }

  List<Map<String, dynamic>> _readConnectionMaps() {
    try {
      final jsonList = prefs.getStringList(_key) ?? const <String>[];
      return jsonList
          .map((json) => jsonDecode(json) as Map<String, dynamic>)
          .toList();
    } catch (_) {
      throw const CredentialStorageException(
        'Saved connection metadata could not be read safely.',
      );
    }
  }

  List<SavedConnection> _connectionsFromMaps(List<Map<String, dynamic>> maps) {
    try {
      return maps.map(SavedConnection.fromMap).toList();
    } catch (_) {
      throw const CredentialStorageException(
        'Saved connection metadata could not be read safely.',
      );
    }
  }

  SavedConnection _hydrateFromCachedCredentials(SavedConnection connection) {
    final encoded = _credentialStore.readCached(_credentialKey(connection.id));
    if (encoded == null) return connection;
    return _applyCredentials(
      connection,
      _ConnectionCredentials.decode(encoded),
    );
  }

  /// Attaches secrets held in the secure store to [connection].
  ///
  /// The client-key password is runtime-only for [ClientCertificateConfig]'s
  /// serializer, so it must be re-attached on every read.
  SavedConnection _applyCredentials(
    SavedConnection connection,
    _ConnectionCredentials credentials,
  ) {
    final certificate = connection.clientCertificate;
    return connection.copyWith(
      apiKey: credentials.apiKey,
      dashboardPassword: credentials.dashboardPassword,
      clearDashboardPassword: credentials.dashboardPassword == null,
      clientCertificate: certificate?.copyWith(
        privateKeyPassword: credentials.clientKeyPassword,
        clearPrivateKeyPassword: credentials.clientKeyPassword == null,
      ),
    );
  }

  /// Own the full mutation, not just a one-shot invalidation while consent may
  /// still be off. Begin synchronously before any await; release only after the
  /// transaction/rollback and the matching native lease have settled. The
  /// injected platform boundary lets host tests exercise the actual IPC.
  Future<void> _withConnectionMutation(
    Iterable<String> connections,
    Future<void> Function() action,
  ) async {
    final lease = ConnectionMutationBarrier.begin(connections);
    final args = {
      'connections': lease.connections.toList(),
      'mutation': _uuid.v4(),
    };
    final native = _nativePushSupported;
    try {
      if (native) {
        try {
          await finishPendingMobilePushChanges();
          await _pushChannel.invokeMethod<void>('beginConnectionChange', args);
        } catch (_) {
          throw const CredentialStorageException(
            'Native push consent could not be invalidated safely. Retry the connection change.',
          );
        }
      }
      await action();
    } finally {
      try {
        // Idempotent even if begin's reply was lost after native revocation.
        if (native) {
          try {
            await _finishMobilePushChange(args);
          } catch (_) {
            throw const CredentialStorageException(
              'Native push account change could not be completed safely. Retry the connection change.',
            );
          }
        }
      } finally {
        lease.release();
      }
    }
  }

  /// Complete only terminal native leases whose acknowledgement was lost.
  /// Called before fresh consent as well as before another account transaction.
  Future<void> finishPendingMobilePushChanges() async {
    if (!_nativePushSupported) return;
    for (final args in _pendingPushMutationEnds.values.toList()) {
      await _finishMobilePushChange(args);
    }
  }

  static Future<void> _finishMobilePushChange(Map<String, dynamic> args) async {
    final mutation = args['mutation'] as String;
    _pendingPushMutationEnds[mutation] = args;
    await _pushChannel.invokeMethod<void>('endConnectionChange', args);
    _pendingPushMutationEnds.remove(mutation);
  }

  Future<void> _commitCredentialAndMetadata({
    required String connectionId,
    required _ConnectionCredentials previousCredentials,
    required _ConnectionCredentials nextCredentials,
    required List<SavedConnection> connections,
    required List<SavedConnection> previousConnections,
  }) async {
    await _withConnectionMutation([connectionId], () async {
      try {
        await _writeAndVerifyCredentials(connectionId, nextCredentials);
        await _saveAll(connections);
      } catch (_) {
        try {
          await _writeAndVerifyCredentials(connectionId, previousCredentials);
        } catch (_) {
          // Never attach platform errors: they may include storage secrets.
        }
        throw const CredentialStorageException(
          'Connection credentials could not be saved safely.',
        );
      }
    });
    // Only now that the metadata is committed is an old identity provably
    // unreferenced. A failed save above leaves every existing key file in
    // place, preserving the still-referenced identity.
    await _deleteUnreferencedCertificates(previousConnections, connections);
  }

  /// Reconciles released editor/import files against physical saved metadata.
  ///
  /// Share the list owner with account writes, including the reference read and
  /// collection. A failed save may have committed; unknown reachability must
  /// retain files. This best-effort cleanup never replaces the mutation error.
  Future<void> cleanupUnreferencedCertificates() async {
    try {
      await _withSavedListTransaction([], () async {
        final connections = _connectionsFromMaps(_readConnectionMaps());
        await _certificateFiles.deleteUnreferenced(
          _certificateDirectories(connections),
        );
      });
    } catch (_) {
      // Retry collection after a later successful physical metadata read.
    }
  }

  /// Removes certificate/key files no longer referenced by any connection.
  ///
  /// Runs only after a successful commit and is best-effort: storage cleanup
  /// must never turn a saved connection into a reported failure.
  Future<void> _deleteUnreferencedCertificates(
    List<SavedConnection> before,
    List<SavedConnection> after,
  ) async {
    final beforeDirs = _certificateDirectories(before);
    final afterDirs = _certificateDirectories(after);
    if (beforeDirs.length == afterDirs.length &&
        beforeDirs.containsAll(afterDirs)) {
      return;
    }
    try {
      await _certificateFiles.deleteUnreferenced(afterDirs);
    } catch (_) {
      // Leftover files are harmless; the connection change already succeeded.
    }
  }

  static Set<String> _certificateDirectories(
    List<SavedConnection> connections,
  ) {
    return <String>{
      for (final connection in connections)
        if (connection.clientCertificate case final certificate?)
          certificate.directoryPath,
    };
  }

  static bool _hasLegacyCertificatePassword(Map<String, dynamic> map) {
    final certificate = map['client_certificate'];
    if (certificate is! Map) return false;
    return certificate.containsKey('private_key_password');
  }

  Future<void> _writeAndVerifyCredentials(
    String connectionId,
    _ConnectionCredentials credentials,
  ) => _writeAndVerifyEncodedCredentials(
    connectionId,
    credentials.isEmpty ? null : credentials.encode(),
  );

  Future<void> _writeAndVerifyEncodedCredentials(
    String connectionId,
    String? encoded,
  ) async {
    final key = _credentialKey(connectionId);
    if (encoded == null) {
      await _credentialStore.delete(key);
      final readBack = await _credentialStore.read(key);
      if (readBack != null) {
        throw const CredentialStorageException(
          'Connection credentials could not be cleared safely.',
        );
      }
      return;
    }

    await _credentialStore.write(key, encoded);
    final readBack = await _credentialStore.read(key);
    if (readBack != encoded) {
      throw const CredentialStorageException(
        'Connection credentials could not be verified safely.',
      );
    }
  }

  Future<void> _saveAll(List<SavedConnection> list) async {
    final previous = prefs.getStringList(_key);
    try {
      final saved = await prefs.setStringList(
        _key,
        list.map((connection) => jsonEncode(connection.toMap())).toList(),
      );
      if (!saved) {
        throw const CredentialStorageException(
          'Connection metadata could not be saved safely.',
        );
      }
    } catch (_) {
      await _restoreMetadata(previous);
      throw const CredentialStorageException(
        'Connection metadata could not be saved safely.',
      );
    }
  }

  Future<void> _restoreMetadata(Object? previous) async {
    try {
      switch (previous) {
        case null:
          await prefs.remove(_key);
        case List<String>():
          await prefs.setStringList(_key, previous);
        case String():
          await prefs.setString(_key, previous);
        case bool():
          await prefs.setBool(_key, previous);
        case int():
          await prefs.setInt(_key, previous);
        case double():
          await prefs.setDouble(_key, previous);
      }
    } catch (_) {
      // Reload after rollback/ACK loss: optimistic metadata is not authority.
    }
    await prefs.reload();
  }

  static String _credentialKey(String connectionId) {
    final encodedId = base64Url
        .encode(utf8.encode(connectionId))
        .replaceAll('=', '');
    return '$_credentialKeyPrefix$encodedId';
  }
}

class ApiHealthCheckResult {
  final bool isHealthy;
  final Uri endpoint;
  final int? statusCode;

  const ApiHealthCheckResult._({
    required this.isHealthy,
    required this.endpoint,
    this.statusCode,
  });

  const ApiHealthCheckResult.success(Uri endpoint)
    : this._(isHealthy: true, endpoint: endpoint);

  const ApiHealthCheckResult.httpFailure(Uri endpoint, int statusCode)
    : this._(isHealthy: false, endpoint: endpoint, statusCode: statusCode);

  const ApiHealthCheckResult.networkFailure(Uri endpoint)
    : this._(isHealthy: false, endpoint: endpoint);

  String userMessage({required bool apiKeyProvided}) {
    if (isHealthy) return '';
    if (statusCode == 401 || statusCode == 403) {
      return apiKeyProvided
          ? 'API key was rejected by $endpoint (HTTP $statusCode).'
          : 'Server requires an API key. Enter your API_SERVER_KEY.';
    }
    if (statusCode == 404) {
      return 'Gateway endpoint $endpoint returned HTTP 404. Check the Gateway '
          'path prefix and reverse-proxy routes.';
    }
    if (statusCode case final code?) {
      return 'Gateway endpoint $endpoint returned HTTP $code.';
    }
    return 'Cannot reach Gateway endpoint $endpoint.';
  }
}

/// One page of the gateway's session list with its paging signal.
class SessionListPage {
  final List<Session> sessions;
  final bool hasMore;

  const SessionListPage({required this.sessions, required this.hasMore});
}

/// HTTP client for the Hermes Gateway API Server (port 8642).
///
/// Uses Bearer token auth. Same pattern as hermes-desktop.
class ApiClient {
  final http.Client _http;
  final String baseUrl;
  final String _apiKey;

  /// How long a single request may take before the UI may surface an error.
  ///
  /// A gateway on a dead keep-alive socket can otherwise hang forever while
  /// the server already answered or closed the connection; every read path
  /// uses this bound so the user always gets a loadable error state.
  static const Duration requestTimeout = Duration(seconds: 20);

  // Keep the public parameter name `apiKey` while storing it privately.
  ApiClient({
    required String baseUrl,
    required String apiKey,
    String pathPrefix = '',
    ClientCertificateConfig? clientCertificate,
    http.Client? httpClient,
  }) : _apiKey = apiKey,
       baseUrl = SavedConnection.joinBaseUrl(baseUrl, pathPrefix),
       _http = httpClient ?? _freshClient(clientCertificate);

  /// Builds a client that does not pool keep-alive sockets.
  ///
  /// dart:io's pooled connections go stale silently (the server closed an
  /// idle connection; the client only notices on the *next* request, which
  /// then hangs). Home/tablet/LAN gateways are cheap to reconnect to, so a
  /// fresh TCP connection per request is a fair price for never wedging the
  /// session list on a stale socket.
  static http.Client _freshClient(ClientCertificateConfig? clientCertificate) {
    return const TlsClientFactory().createRestClient(clientCertificate);
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
  };

  // ── Session listing ──────────────────────────────────────────────────

  /// One page of the gateway session list plus the server's paging signal.
  ///
  /// The gateway api_server caps `limit` at 200 and reports `has_more` from
  /// its recency window, so a client that never pages only ever sees the
  /// most recent page — which silently truncated the Unassigned bucket
  /// (sessions outside the first page never reached the device).
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    String? title,
    Duration timeout = requestTimeout,
  }) async {
    final uri = Uri.parse('$baseUrl/api/sessions').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (title != null && title.isNotEmpty) 'title': title,
      },
    );
    final res = await _http.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return SessionListPage(
      sessions: list
          .whereType<Map<String, dynamic>>()
          .map((s) => Session.fromJson(s))
          .toList(),
      hasMore: data['has_more'] == true,
    );
  }

  Future<List<Session>> getSessions({Duration timeout = requestTimeout}) async {
    final page = await getSessionsPage(timeout: timeout);
    return page.sessions;
  }

  /// Resolves an id or compression root to the visible canonical session.
  /// A notification or persisted Activity row may predate the current tip.
  /// [canContinue] fences each page, not just the final result. Notification
  /// navigation uses it to revoke captured credentials/consent while a request
  /// is suspended; other callers retain the original paging behaviour.
  /// [isCurrent] rechecks synchronous lifetime/configuration authority after
  /// every await, including the asynchronous continuation fence itself.
  Future<Session?> getSessionById(
    String sessionId, {
    Future<bool> Function()? canContinue,
    bool Function()? isCurrent,
  }) async {
    const pageSize = 50;
    var offset = 0;
    var pinBound = 0;
    var zeroNewPages = 0;
    final seen = <String>{};
    Session? exact;
    while (true) {
      if (canContinue != null && !await canContinue()) return null;
      if (isCurrent != null && !isCurrent()) return null;
      final result = await getSessionsPage(limit: pageSize, offset: offset);
      if (isCurrent != null && !isCurrent()) return null;
      if (canContinue != null && !await canContinue()) return null;
      if (isCurrent != null && !isCurrent()) return null;
      final continuations =
          result.sessions
              .where(
                (session) =>
                    session.lineageRootId == sessionId &&
                    session.id != sessionId,
              )
              .toList()
            ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
      if (continuations.isNotEmpty) return continuations.first;
      var newRows = 0;
      for (final session in result.sessions) {
        if (seen.add(session.id)) newRows++;
        if (session.id == sessionId) {
          exact = session;
          if (session.lineageRootId != null &&
              session.lineageRootId != sessionId) {
            return session;
          }
        }
      }
      // A pin can back-fill an obsolete root before its current tip's window.
      // Keep it as fallback, not proof that the continuation does not exist.
      // A short page/has_more=false is not proof either; use the pin bound.
      final pins = result.sessions.where((session) => session.pinned).length;
      if (pins > pinBound) pinBound = pins;
      zeroNewPages = newRows == 0 ? zeroNewPages + 1 : 0;
      if (zeroNewPages >= (pinBound == 0 ? 1 : pinBound ~/ pageSize + 1)) {
        return exact;
      }
      offset += pageSize;
    }
  }

  /// Fetches the server-authoritative metadata for one stored session.
  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final encodedId = Uri.encodeComponent(sessionId);
    final data = await apiGet('api/sessions/$encodedId');
    final session = data['session'];
    if (session is! Map) {
      throw const FormatException('Gateway returned no session metadata');
    }
    return Map<String, dynamic>.from(session);
  }

  /// Persists a title on the API server for either chat transport. Unlike a
  /// session-scoped RPC this does not resume or create a live agent session.
  /// Returns the server's saved (potentially normalised) title.
  Future<String> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be blank');
    }
    final encodedId = Uri.encodeComponent(sessionId);
    final response = await _http
        .patch(
          Uri.parse('$baseUrl/api/sessions/$encodedId'),
          headers: _headers,
          body: jsonEncode({'title': trimmed}),
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body);
    final saved = data is Map ? data['session'] : null;
    if (saved is! Map ||
        saved['id'] != sessionId ||
        saved['title'] is! String ||
        (saved['title'] as String).trim().isEmpty) {
      throw const FormatException('Gateway returned no saved session title');
    }
    return saved['title'] as String;
  }

  /// Persists a server-owned archive flag and verifies the exact target.
  /// Neither a sparse/mismatched PATCH response nor a failed read-back is
  /// reported as success; callers keep their current rows and offer retry.
  Future<bool> setSessionArchived({
    required String sessionId,
    required bool archived,
  }) async {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be blank');
    }
    final encodedId = Uri.encodeComponent(sessionId);
    final response = await _http
        .patch(
          Uri.parse('$baseUrl/api/sessions/$encodedId'),
          headers: _headers,
          body: jsonEncode({'archived': archived}),
        )
        .timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body);
    final saved = data is Map ? data['session'] : null;
    if (saved is! Map ||
        saved['id'] != sessionId ||
        saved['archived'] != archived) {
      throw const FormatException(
        'Gateway returned no confirmed archive state',
      );
    }
    final confirmed = await getSession(sessionId);
    if (confirmed['id'] != sessionId || confirmed['archived'] != archived) {
      throw const FormatException('Gateway archive read-back did not match');
    }
    return archived;
  }

  // ── Messages ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
  }) async {
    if (limit != null && limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'must not be negative');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    final query = <String, String>{
      if (limit != null) 'limit': '$limit',
      if (offset != 0) 'offset': '$offset',
      if (latest) 'order': 'latest',
    };
    final encodedId = Uri.encodeComponent(sessionId);
    final uri = Uri.parse(
      '$baseUrl/api/sessions/$encodedId/messages',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _http.get(uri, headers: _headers).timeout(requestTimeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> deleteSession(String sessionId) async {
    final encodedId = Uri.encodeComponent(sessionId);
    final res = await _http
        .delete(
          Uri.parse('$baseUrl/api/sessions/$encodedId'),
          headers: _headers,
        )
        .timeout(requestTimeout);
    // Treat a stale local row as already synced: the remote no longer has it,
    // so the UI can safely remove it from history.
    if (res.statusCode == 404) return;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // ── Models ───────────────────────────────────────────────────────────

  Future<List<String>> getModels() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/v1/models'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode != 200) {
      return ['hermes-agent'];
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => (m['id'] as String?) ?? 'hermes-agent')
        .toList();
  }

  // ── Health check ─────────────────────────────────────────────────────

  Future<ApiHealthCheckResult> checkHealth() async {
    final healthEndpoint = Uri.parse('$baseUrl/health');
    var activeEndpoint = healthEndpoint;
    try {
      final health = await _http
          .get(healthEndpoint, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (health.statusCode != 200) {
        return ApiHealthCheckResult.httpFailure(
          healthEndpoint,
          health.statusCode,
        );
      }

      // /health may be intentionally public on some deployments. Confirm that
      // the saved API key can also reach an authenticated endpoint before the
      // add/update connection dialogs accept it as valid.
      final sessionsEndpoint = Uri.parse('$baseUrl/api/sessions');
      activeEndpoint = sessionsEndpoint;
      final sessions = await _http
          .get(sessionsEndpoint, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (sessions.statusCode != 200) {
        return ApiHealthCheckResult.httpFailure(
          sessionsEndpoint,
          sessions.statusCode,
        );
      }
      return ApiHealthCheckResult.success(sessionsEndpoint);
    } catch (_) {
      return ApiHealthCheckResult.networkFailure(activeEndpoint);
    }
  }

  Future<bool> healthCheck() async => (await checkHealth()).isHealthy;

  // ── Generic HTTP helpers (for Dashboard API compatibility) ────────────

  Future<Map<String, dynamic>> apiGet(String endpoint) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/$endpoint'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> apiGetList(String endpoint) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/$endpoint'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/$endpoint'),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(requestTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> apiDelete(String endpoint) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/$endpoint'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  // ── Model selection ───────────────────────────────────────────────────

  /// Legacy Dashboard-only profile metadata endpoint.
  Future<Map<String, dynamic>> getModelInfo() => apiGet('api/model/info');

  /// Model inventory exposed by both the Dashboard and API Server.
  Future<Map<String, dynamic>> getModelOptions() => apiGet('api/model/options');

  /// Persists a model lock for one API Server session.
  Future<Map<String, dynamic>> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
    bool createSessionIfMissing = false,
  }) async {
    final body = {
      'provider': provider,
      'model': model,
      'require_model_lock': true,
    };
    if (createSessionIfMissing) {
      final response = await _http
          .post(
            Uri.parse('$baseUrl/api/sessions'),
            headers: _headers,
            body: jsonEncode({
              'id': sessionId,
              'source': 'api_server',
              ...body,
            }),
          )
          .timeout(requestTimeout);
      if (response.statusCode != 409) {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      // A turn or another client may have materialised the local draft while
      // the picker was open. Apply the lock to that existing row instead.
    }
    final encodedId = Uri.encodeComponent(sessionId);
    return apiPost('api/sessions/$encodedId/model', body: body);
  }

  // ── Dashboard-compatible helpers (may not work on the API Server) ─────

  Future<List<Map<String, dynamic>>> getSkills() async {
    final data = await apiGetList('api/skills');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => apiPost(
    'api/model/set',
    body: {'scope': scope, 'provider': provider, 'model': model},
  );

  void close() => _http.close();
}

typedef ToolProgressCallback = void Function(Map<String, dynamic> progress);

/// SSE streaming chat client for the Gateway API Server.
class GatewayChatClient {
  /// Silence bound, not a turn deadline. Raw bytes (including SSE keepalives,
  /// tool/status events and fragmented UTF-8) renew it. Stock emits keepalives
  /// every 10 seconds while working, so long tools/turns can run indefinitely.
  static const Duration streamInactivityTimeout = Duration(seconds: 60);

  final ApiClient _api;
  final String _baseUrl;

  /// Per-call stream state: each sendMessageStreaming call owns a
  /// _LiveStream, and the client keeps only the current one, which
  /// cancelActiveMessage targets. (Previously three shared fields let a
  /// second send overwrite the first's slot and let cancel-then-resend
  /// reset the cancelled flag before the cancelled stream's onDone
  /// check ran — so a cancelled turn reported success and the orphaned
  /// subscription kept pushing tokens into stale callbacks.)
  _LiveStream? _liveStream;

  GatewayChatClient(this._api) : _baseUrl = _api.baseUrl;

  /// Generate a client-side session ID: `mob-<timestamp>-<uuid>`.
  static String generateSessionId() {
    return 'mob-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4()}';
  }

  /// Build OpenAI chat-completions messages, preserving prior history and
  /// ensuring the newly typed user message is present exactly once at the end.
  static List<Map<String, dynamic>> buildChatCompletionMessages({
    required String message,
    List<Map<String, dynamic>>? history,
    String? imageDataUrl,
  }) {
    final messages = <Map<String, dynamic>>[];
    if (history != null && history.isNotEmpty) {
      for (final msg in history) {
        final role = (msg['role'] == 'agent' || msg['role'] == 'assistant')
            ? 'assistant'
            : 'user';
        final content = msg['content'];
        if (content == null || (content is String && content.isEmpty)) {
          continue;
        }
        messages.add({'role': role, 'content': content});
      }
    }

    final latest = message.trim();
    final latestContent = buildUserContent(
      message: latest,
      imageDataUrl: imageDataUrl,
    );
    final alreadyLast =
        imageDataUrl == null &&
        messages.isNotEmpty &&
        messages.last['role'] == 'user' &&
        (messages.last['content'] == latest ||
            messages.last['content'] == latestContent);
    if (alreadyLast) {
      messages[messages.length - 1] = {
        'role': 'user',
        'content': latestContent,
      };
    } else if (latest.isNotEmpty || imageDataUrl != null) {
      messages.add({'role': 'user', 'content': latestContent});
    }
    return messages;
  }

  /// Exact current-turn model content, also retained by local SSE history.
  static dynamic buildUserContent({
    required String message,
    String? imageDataUrl,
  }) {
    final latest = message.trim();
    if (imageDataUrl == null) return AndroidPromptContext.forModel(latest);
    return <Map<String, dynamic>>[
      {'type': 'text', 'text': AndroidPromptContext.forAttachment(latest)},
      {
        'type': 'image_url',
        'image_url': {'url': imageDataUrl},
      },
    ];
  }

  /// Token-only compatibility parser. Non-token, malformed and error frames
  /// return null; callers must not infer success from that. The streaming send
  /// uses [_decodeSseFrame] to retain completion and failure authority.
  static String? parseSseFrame(
    String frame, {
    ToolProgressCallback? onToolProgress,
  }) {
    final parsed = _decodeSseFrame(frame);
    if (parsed.toolProgress case final progress?) {
      onToolProgress?.call(progress);
    }
    final token = parsed.token;
    return token != null && token.isNotEmpty ? token : null;
  }

  static _SseFrame _decodeSseFrame(String frame) {
    var eventType = '';
    final dataLines = <String>[];
    for (final rawLine in frame.split('\n')) {
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    final data = dataLines.join('\n').trim();
    // event:error is authoritative even without JSON/data (or with [DONE]).
    if (eventType == 'error') {
      Object? payload;
      try {
        payload = jsonDecode(data);
      } catch (_) {
        payload = data == '[DONE]' ? null : data;
      }
      return _SseFrame(error: _streamErrorMessage(payload));
    }
    if (data.isEmpty) return const _SseFrame();
    if (data == '[DONE]') return const _SseFrame(done: true);

    final Object? parsed;
    try {
      parsed = jsonDecode(data);
    } catch (_) {
      return const _SseFrame(error: 'Gateway sent a malformed SSE frame.');
    }
    if (parsed is! Map<String, dynamic>) {
      return const _SseFrame(error: 'Gateway sent a malformed SSE frame.');
    }
    if (parsed['error'] != null || parsed['type'] == 'error') {
      return _SseFrame(error: _streamErrorMessage(parsed));
    }
    // Current Hermes annotates failed/partial completions as well as emitting
    // non-stop finish reasons. Neither can be overridden by a later [DONE].
    final hermes = parsed['hermes'];
    if (hermes is Map &&
        (hermes['completed'] == false ||
            hermes['partial'] == true ||
            hermes['failed'] == true ||
            (hermes['error'] != null && hermes['error'] != ''))) {
      return _SseFrame(error: _streamErrorMessage(hermes));
    }
    if (eventType == 'hermes.tool.progress') {
      return _SseFrame(toolProgress: parsed);
    }
    if (eventType == 'hermes.status') {
      return _SseFrame(status: parsed);
    }
    final choices = parsed['choices'];
    // Usage-only chunks and extension events do not carry completion evidence.
    if (choices == null || (choices is List && choices.isEmpty)) {
      return const _SseFrame();
    }
    if (choices is! List || choices.first is! Map) {
      return const _SseFrame(error: 'Gateway sent malformed SSE choices.');
    }
    final first = choices.first as Map;
    final finishReason = first['finish_reason'];
    if (finishReason != null && finishReason != 'stop') {
      return _SseFrame(
        error:
            'Assistant response did not finish successfully '
            '(finish_reason: $finishReason).',
      );
    }
    final delta = first['delta'];
    if (delta != null && delta is! Map) {
      return const _SseFrame(error: 'Gateway sent a malformed SSE delta.');
    }
    final content = delta is Map ? delta['content'] : null;
    if (content != null && content is! String) {
      return const _SseFrame(error: 'Gateway sent malformed SSE content.');
    }
    final reasoning = delta is Map ? delta['reasoning_content'] : null;
    if (reasoning != null && reasoning is! String) {
      return const _SseFrame(error: 'Gateway sent malformed SSE reasoning.');
    }
    return _SseFrame(
      token: content as String?,
      reasoning: reasoning as String?,
      successfulFinish: finishReason == 'stop',
      hasToolCalls:
          delta is Map &&
          (delta['tool_calls'] != null || delta['function_call'] != null),
    );
  }

  static String _streamErrorMessage(
    Object? payload, {
    String fallback = 'Assistant response did not finish successfully.',
  }) {
    if (payload is String && payload.trim().isNotEmpty) return payload;
    if (payload is Map) {
      final error = payload['error'];
      if (error != null) {
        return _streamErrorMessage(error, fallback: fallback);
      }
      final message = payload['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return fallback;
  }

  /// Send a message and stream the assistant response token-by-token.
  ///
  /// [onDone] means a successfully completed assistant reply, not socket EOF.
  /// Require non-whitespace assistant content plus a complete `stop` frame or
  /// `[DONE]`. The latter supports older OpenAI-compatible gateways omitting a
  /// finish_reason, but never completes tool-call-only, failed or partial output.
  /// A stop frame is provisional until [DONE]/clean EOF so a trailing error wins.
  /// Malformed frames, non-stop finishes and EOF without success call [onError]
  /// exactly once and mute subsequent frames. Cancellation/supersession is silent.
  Future<void> sendMessageStreaming({
    required String message,
    required String sessionId,
    String? model,
    String? provider,
    List<Map<String, dynamic>>? history,
    String? imageDataUrl,
    required void Function(String token) onToken,
    ToolProgressCallback? onToolProgress,
    void Function(String reasoning)? onReasoning,
    void Function(Map<String, dynamic> status)? onStatus,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    final messages = buildChatCompletionMessages(
      message: message,
      history: history,
      imageDataUrl: imageDataUrl,
    );

    final body = {
      'model': model ?? 'hermes-agent',
      if (provider?.trim().isNotEmpty == true) 'provider': provider!.trim(),
      'messages': messages,
      'stream': true,
    };

    final headers = {..._api._headers, 'X-Hermes-Session-Id': sessionId};
    final stream = _LiveStream();
    final previous = _liveStream;
    // A second concurrent send supersedes the first: cancel the old one
    // with its OWN state so its callbacks are muted rather than silently
    // drained into the new call's flags.
    if (previous != null) {
      previous.cancel();
    }
    _liveStream = stream;
    final completion = stream.completion;
    bool ownsStream() => !stream.cancelled && identical(_liveStream, stream);
    var callbackDelivered = false;
    void reportError(String error) {
      if (!ownsStream() || callbackDelivered) return;
      callbackDelivered = true;
      onError(error);
    }

    try {
      final request = http.AbortableRequest(
        'POST',
        Uri.parse('$_baseUrl/v1/chat/completions'),
        abortTrigger: stream.cancellation.future,
      );
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final responseFuture = _api._http.send(request);
      final response = await Future.any<http.StreamedResponse?>([
        responseFuture.then<http.StreamedResponse?>((value) => value),
        stream.cancellation.future.then<http.StreamedResponse?>((_) => null),
      ]);
      if (response == null) {
        // AbortableRequest is honoured by package:http's production clients.
        // The race above is also a safe fallback for an injected/custom client
        // that ignores it: settle this send now, then discard any late body
        // without invoking user callbacks or closing the shared ApiClient.
        unawaited(
          responseFuture.then<void>((lateResponse) {
            final subscription = lateResponse.stream.listen((_) {});
            unawaited(subscription.cancel());
          }, onError: (Object _, StackTrace _) {}),
        );
        return;
      }

      if (stream.cancelled || !identical(_liveStream, stream)) {
        final subscription = response.stream.listen((_) {});
        await subscription.cancel();
        return;
      }

      var buffer = '';
      final errorBody = StringBuffer();
      String? failure;
      var terminal = false;
      var assistantTextSeen = false;
      var successfulFinishSeen = false;
      var toolCallsSeen = false;
      void finishBody([String? error]) {
        if (terminal) return;
        terminal = true;
        failure = error;
        if (!completion.isCompleted) completion.complete();
      }

      void acceptFrame(String rawFrame) {
        final frame = _decodeSseFrame(rawFrame);
        if (frame.error case final error?) {
          finishBody(error);
          return;
        }
        if (frame.done) {
          finishBody(
            !assistantTextSeen || (toolCallsSeen && !successfulFinishSeen)
                ? 'Stream ended without a completed assistant reply.'
                : null,
          );
          return;
        }
        if (frame.toolProgress case final progress?) {
          onToolProgress?.call(progress);
        }
        // A callback can cancel, abort, or synchronously start a newer send.
        if (!ownsStream()) return;
        if (frame.status case final status?) {
          onStatus?.call(status);
        }
        if (!ownsStream()) return;
        if (frame.reasoning case final reasoning? when reasoning.isNotEmpty) {
          onReasoning?.call(reasoning);
        }
        if (!ownsStream()) return;
        toolCallsSeen |= frame.hasToolCalls;
        successfulFinishSeen |= frame.successfulFinish;
        if (frame.token case final token? when token.isNotEmpty) {
          assistantTextSeen |= token.trim().isNotEmpty;
          onToken(token);
        }
      }

      stream.subscription = response.stream
          .timeout(streamInactivityTimeout)
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              if (!ownsStream() || terminal) return;
              if (response.statusCode != 200) {
                errorBody.write(chunk);
                return;
              }
              buffer += chunk;
              // Keep delimiters buffered across TCP/UTF-8 chunks, including a
              // split between CR and LF. Never dispatch an unfinished EOF frame.
              var boundary = RegExp(r'\r?\n\r?\n').firstMatch(buffer);
              while (boundary != null && ownsStream() && !terminal) {
                final frame = buffer.substring(0, boundary.start);
                buffer = buffer.substring(boundary.end);
                try {
                  acceptFrame(frame);
                } catch (error) {
                  finishBody(error.toString());
                }
                boundary = RegExp(r'\r?\n\r?\n').firstMatch(buffer);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              finishBody(error.toString());
            },
            onDone: () {
              if (terminal) return;
              if (response.statusCode != 200) {
                Object? payload;
                try {
                  payload = jsonDecode(errorBody.toString());
                } catch (_) {
                  // A proxy may return HTML/plain text rather than JSON.
                }
                finishBody(
                  _streamErrorMessage(
                    payload,
                    fallback: 'HTTP ${response.statusCode}',
                  ),
                );
              } else {
                finishBody(
                  buffer.trim().isNotEmpty ||
                          !assistantTextSeen ||
                          !successfulFinishSeen
                      ? 'Stream ended before the assistant response completed.'
                      : null,
                );
              }
            },
            cancelOnError: true,
          );
      await completion.future;
      // A protocol terminal can arrive before transport EOF. Cancel/join the
      // body before publishing a result or letting a detached owner close it.
      await stream.cancelSubscription();
      if (!ownsStream()) return;
      if (failure != null) {
        reportError(failure!);
      } else {
        callbackDelivered = true;
        onDone();
      }
    } catch (error) {
      reportError(error.toString());
    } finally {
      await stream.cancelSubscription();
      if (!completion.isCompleted) completion.complete();
      if (identical(_liveStream, stream)) {
        _liveStream = null;
      }
      // Distinct from body/protocol termination: this also joins cancellation,
      // callback dispatch and early exits before response headers arrive.
      if (!stream.settled.isCompleted) stream.settled.complete();
    }
  }

  /// Whether a send currently owns the live SSE stream.
  bool get isStreaming => _liveStream != null;

  /// Completes once the live stream settles: done, error, cancellation, or any
  /// other exit from the send — including the failures that never open a body
  /// stream (a rejected `send()`, a non-200 reply).
  ///
  /// Lets a caller that is going away hand the connection to a detached owner.
  /// Closing the HTTP client while a turn streams aborts the request, and the
  /// API server treats that client disconnect as an agent interrupt — the turn
  /// and its tool work die server-side. A failed stream still counts as settled:
  /// the caller's only need is for the socket to be finished with.
  Future<void> whenStreamSettles() async {
    final stream = _liveStream;
    if (stream == null) return;
    await stream.settled.future;
  }

  /// Cancels the current SSE response. The Hermes API server treats the
  /// resulting client disconnect as an agent interrupt.
  Future<bool> cancelActiveMessage() async {
    final stream = _liveStream;
    if (stream == null) return false;

    stream.cancel();
    await stream.settled.future;
    return true;
  }

  void abort() {
    _liveStream?.cancel();
    // NOTE: deliberately does NOT close the shared ApiClient's HTTP
    // client — the same ApiClient instance feeds the session list and
    // health checks, and closing it killed every later HTTP call on it.
  }
}

/// Parsed frame authority, separate from the token-only public compatibility API.
class _SseFrame {
  final String? token;
  final String? reasoning;
  final Map<String, dynamic>? toolProgress;
  final Map<String, dynamic>? status;
  final String? error;
  final bool successfulFinish;
  final bool hasToolCalls;
  final bool done;

  const _SseFrame({
    this.token,
    this.reasoning,
    this.toolProgress,
    this.status,
    this.error,
    this.successfulFinish = false,
    this.hasToolCalls = false,
    this.done = false,
  });
}

/// Per-call SSE stream state owned by one sendMessageStreaming call.
class _LiveStream {
  /// Body/protocol termination wakes the send; [settled] also joins cleanup.
  final Completer<void> completion = Completer<void>();
  final Completer<void> settled = Completer<void>();
  final Completer<void> cancellation = Completer<void>();
  StreamSubscription<String>? subscription;
  Future<void>? _subscriptionCancellation;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    if (!cancellation.isCompleted) cancellation.complete();
    if (!completion.isCompleted) completion.complete();
    unawaited(cancelSubscription());
  }

  Future<void> cancelSubscription() {
    final sub = subscription;
    if (sub == null) return Future<void>.value();
    return _subscriptionCancellation ??= _joinCancellation(sub);
  }

  Future<void> _joinCancellation(StreamSubscription<String> sub) async {
    try {
      await sub.cancel();
    } catch (_) {
      // Cleanup failure must not strand detached waiters or create a second
      // terminal callback. The body outcome already owns response authority.
    }
  }
}

/// A non-200 answer from a dashboard API call, carrying the status code so
/// callers can distinguish authoritative outcomes (404 = the resource is
/// definitively absent) from unknowable ones (403/5xx/timeout = existence
/// cannot be determined). Callers that must never act on a guess — like
/// the project folder provisioner — branch on this instead of string-
/// matching a bare Exception.
class DashboardHttpException implements Exception {
  final int statusCode;
  const DashboardHttpException(this.statusCode);

  @override
  String toString() => 'HTTP $statusCode';
}

/// A bounded native preview/download exceeded its caller's memory budget.
class DownloadSizeLimitException implements Exception {
  const DownloadSizeLimitException();

  @override
  String toString() => 'DownloadSizeLimitException';
}

/// Client for the Hermes Dashboard REST API.
///
/// Three auth modes, picked by proxy configuration and supplied credentials:
///
///  * **Proxied dashboard** — when [proxied] is true, upstream infrastructure
///    injects auth and the app sends clean JSON requests with no dashboard
///    session token or cookie.
///  * **Password (gated) dashboard** — when [username] and [password] are set,
///    performs the `/auth/password-login` flow (provider `basic`) and
///    authenticates subsequent `/api/` calls with the returned
///    `hermes_session_at` session cookie. This is what hermes-desktop does and
///    is required when the dashboard runs with basic-auth.
///  * **Insecure (open) dashboard** — when no credentials are given, falls back
///    to scraping the ephemeral SPA session token from the homepage. Only works
///    on a dashboard started with `--insecure`.
///
/// Used for Dashboard-only features: cron, memory, skills, settings.
class DashboardClient {
  final http.Client _http;
  final String _baseUrl;
  final bool _proxied;
  final String? _username;
  final String? _password;
  final String? _gatewayProfile;
  String? _token;
  String? _cookie;
  int _authGeneration = 0;
  // In-flight auth requests, shared so concurrent /api calls trigger a single
  // login / token fetch instead of a thundering herd (the dashboard
  // rate-limits password logins).
  Future<String>? _cookieInFlight;
  Future<String>? _tokenInFlight;

  String get baseUrl => _baseUrl;

  /// Selected connection profile; generic API helpers deliberately do not add it.
  String? get gatewayProfile => _gatewayProfile;

  bool get _usesPasswordAuth =>
      (_username?.isNotEmpty ?? false) && (_password?.isNotEmpty ?? false);

  DashboardClient({
    required String host,
    int port = 9119,
    bool useHttps = false,
    String pathPrefix = '',
    bool proxied = false,
    String? username,
    String? password,
    String? gatewayProfile,
    ClientCertificateConfig? clientCertificate,
    TlsClientFactory tlsClientFactory = const TlsClientFactory(),
    http.Client? httpClient,
  }) : _proxied = proxied,
       _username = username,
       _password = password,
       _gatewayProfile = gatewayProfile?.trim().isEmpty == true
           ? null
           : gatewayProfile?.trim(),
       _baseUrl = SavedConnection.joinBaseUrl(
         '${useHttps ? 'https' : 'http'}://$host:$port',
         pathPrefix,
       ),
       _http =
           httpClient ?? tlsClientFactory.createRestClient(clientCertificate);

  /// Clears cached auth only when the failed request used the current auth
  /// generation. Concurrent stale 401s therefore cannot invalidate a newer
  /// replacement login started by the first failure.
  void _resetAuth({int? ifGeneration}) {
    if (ifGeneration != null && ifGeneration != _authGeneration) return;
    _authGeneration++;
    _token = null;
    _cookie = null;
    _cookieInFlight = null;
    _tokenInFlight = null;
  }

  /// Returns the session cookie, reusing a cached value or an in-flight login.
  Future<String> _getCookie() {
    final cached = _cookie;
    if (cached != null) return Future.value(cached);
    final inFlight = _cookieInFlight;
    if (inFlight != null) return inFlight;
    final generation = _authGeneration;
    final future = _login();
    _cookieInFlight = future;
    // Cache only if this login still belongs to the active generation. A stale
    // login completing after a 401 reset must not overwrite its replacement.
    future
        .then((cookie) {
          if (_authGeneration == generation &&
              identical(_cookieInFlight, future)) {
            _cookie = cookie;
          }
        })
        .whenComplete(() {
          if (identical(_cookieInFlight, future)) _cookieInFlight = null;
        })
        .ignore();
    return future;
  }

  /// Logs in against the `basic` password provider and caches the session
  /// cookie. Throws on failure (bad credentials → 401, etc.).
  Future<String> _login() async {
    final res = await _http
        .post(
          Uri.parse('$_baseUrl/auth/password-login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'provider': 'basic',
            'username': _username,
            'password': _password,
          }),
        )
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401) {
      throw Exception('Dashboard login failed: invalid username or password');
    }
    if (res.statusCode != 200) {
      throw Exception('Dashboard login failed: HTTP ${res.statusCode}');
    }
    final setCookie = res.headers['set-cookie'] ?? '';
    // The `http` package folds multiple Set-Cookie headers into one
    // comma-joined string; cookie expiry dates also contain commas, so match
    // the access-token cookie by name and take its value up to the first
    // delimiter. Handles the bare name plus the __Host-/__Secure- prefixes
    // Hermes uses on HTTPS binds.
    final match = RegExp(
      r'((?:__Host-|__Secure-)?hermes_session_at)=([^;,\s]+)',
    ).firstMatch(setCookie);
    if (match == null) {
      throw Exception('Dashboard login succeeded but no session cookie found');
    }
    return '${match.group(1)}=${match.group(2)}';
  }

  /// Returns the SPA session token, reusing a cached value or an in-flight fetch.
  Future<String> _getToken() {
    final cached = _token;
    if (cached != null) return Future.value(cached);
    final inFlight = _tokenInFlight;
    if (inFlight != null) return inFlight;
    final generation = _authGeneration;
    final future = _fetchToken();
    _tokenInFlight = future;
    future
        .then((token) {
          if (_authGeneration == generation &&
              identical(_tokenInFlight, future)) {
            _token = token;
          }
        })
        .whenComplete(() {
          if (identical(_tokenInFlight, future)) _tokenInFlight = null;
        })
        .ignore();
    return future;
  }

  Future<String> _fetchToken() async {
    final res = await _http
        .get(Uri.parse('$_baseUrl/'))
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode != 200) throw Exception('Dashboard not reachable');
    final match = RegExp(
      r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";',
    ).firstMatch(res.body);
    if (match == null) throw Exception('Session token not found');
    return match.group(1)!;
  }

  Future<Map<String, String>> _authHeaders() async {
    if (_proxied) return {'Content-Type': 'application/json'};
    if (_usesPasswordAuth) {
      return {'Cookie': await _getCookie(), 'Content-Type': 'application/json'};
    }
    return {
      'X-Hermes-Session-Token': await _getToken(),
      'Content-Type': 'application/json',
    };
  }

  /// Resolves the dashboard auth headers for a caller that issues its own
  /// requests against [baseUrl].
  ///
  /// Exposed so collaborators such as the session search client can reuse this
  /// client's cached cookie/token and its single-flight login, instead of
  /// re-implementing the auth ladder and triggering a second password login.
  Future<Map<String, String>> authHeaders() => _authHeaders();

  /// Mints the short-lived, single-use WebSocket ticket required by a secured
  /// Hermes Desktop gateway. The HTTP API cookie stays in this client; only the
  /// ticket is passed to the WebSocket URL.
  Future<String> mintWebSocketTicket({bool retried = false}) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final res = await _http
        .post(Uri.parse('$_baseUrl/api/auth/ws-ticket'), headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return mintWebSocketTicket(retried: true);
    }
    if (res.statusCode != 200) {
      throw Exception(
        'Could not mint Desktop gateway WebSocket ticket: HTTP ${res.statusCode}',
      );
    }
    final data = _decodeMapResponse(res);
    final ticket = data['ticket'] as String?;
    if (ticket == null || ticket.isEmpty) {
      throw Exception('Desktop gateway returned no WebSocket ticket');
    }
    return ticket;
  }

  Map<String, dynamic> _decodeMapResponse(http.Response res) {
    final trimmed = res.body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> apiGet(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .get(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiGet(endpoint, queryParameters: queryParameters, retried: true);
    }
    if (res.statusCode != 200) throw DashboardHttpException(res.statusCode);
    return _decodeMapResponse(res);
  }

  Future<http.Response> apiGetBytes(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
    int? maxBytes,
  }) async {
    if (maxBytes != null && maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final http.Response res;
    if (maxBytes == null) {
      res = await _http
          .get(uri, headers: headers)
          .timeout(ApiClient.requestTimeout);
    } else {
      final request = http.Request('GET', uri)..headers.addAll(headers);
      final response = await _http
          .send(request)
          .timeout(ApiClient.requestTimeout);
      // Apply the budget to the stream, not after buffering the whole file.
      // Error bodies are unnecessary; discard them before re-authentication.
      if (response.statusCode != 200) {
        final subscription = response.stream.listen((_) {});
        await subscription.cancel();
        res = http.Response('', response.statusCode, headers: response.headers);
      } else {
        if ((response.contentLength ?? 0) > maxBytes) {
          final subscription = response.stream.listen((_) {});
          await subscription.cancel();
          throw const DownloadSizeLimitException();
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          ApiClient.requestTimeout,
        )) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const DownloadSizeLimitException();
          }
          bytes.add(chunk);
        }
        res = http.Response.bytes(
          bytes.takeBytes(),
          response.statusCode,
          headers: response.headers,
        );
      }
    }
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiGetBytes(
        endpoint,
        queryParameters: queryParameters,
        retried: true,
        maxBytes: maxBytes,
      );
    }
    if (res.statusCode != 200) throw DashboardHttpException(res.statusCode);
    return res;
  }

  Future<List<dynamic>> apiGetList(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .get(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiGetList(
        endpoint,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final decoded = jsonDecode(res.body);
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List<dynamic>) {
      return decoded['data'] as List<dynamic>;
    }
    throw Exception('Expected list response');
  }

  /// Lists server-archived sessions from the dashboard's session router.
  ///
  /// The gateway api_server that serves the chat transport ignores the
  /// `archived` query param entirely (live-verified: its list never
  /// contains archived rows), so the Chats browser's Archived chip reads
  /// them from the dashboard instead — the same `archived=only` router the
  /// dashboard's own Archived view uses, and the only stock Hermes surface
  /// that enumerates archived sessions. Requires dashboard credentials on
  /// the connection; callers degrade honestly when this throws.
  ///
  /// Pages to completion: the router caps each page at 100 rows. One request
  /// would silently truncate anyone with more than one page of archived chats.
  /// [gatewayProfile] scopes the read to the connection's Hermes profile
  /// (the router opens that profile's session DB); omitting it would list
  /// the dashboard process's own default profile instead — the wrong
  /// store on a multiplexed gateway.
  ///
  /// Termination is by offset/no-progress, never by comparing the
  /// accumulated row count against `total`: the same pinned back-fill
  /// semantics as the live list can repeat rows across pages, and an
  /// inflated `all.length >= total` would stop before every offset
  /// window has been read, truncating the archive. Rows are deduplicated
  /// by session id so repeats never surface twice. [maxPages] is an optional
  /// safety cap. A progressive browser can omit it, retain successful pages,
  /// and cancel when its owner is disposed without truncating old history.
  Future<List<Session>> getArchivedSessions({
    int pageSize = 100,
    int? maxPages = 200,
    int? firstPageSize,
    String? gatewayProfile,
    void Function(List<Session>)? onProgress,
    bool Function()? shouldContinue,
    bool Function()? isCancelled,
  }) async {
    if (pageSize < 1 ||
        pageSize > 100 ||
        (maxPages != null && maxPages < 1) ||
        (firstPageSize != null && (firstPageSize < 1 || firstPageSize > 100))) {
      throw ArgumentError('Invalid archived session paging limits');
    }
    final all = <Session>[];
    final seenIds = <String>{};
    var offset = 0;
    var exhausted = false;
    // Max pins on any page bounds the pin set, and
    // k consecutive zero-new windows consume k*pageSize disjoint pins.
    var pinBound = 0;
    var zeroNewWindowRows = 0;
    for (var page = 0; maxPages == null || page < maxPages; page++) {
      if (shouldContinue?.call() == false || (isCancelled?.call() ?? false)) {
        throw StateError('Archived session read cancelled');
      }
      final limit = page == 0 ? (firstPageSize ?? pageSize) : pageSize;
      final data = await apiGet(
        'sessions',
        queryParameters: {
          'archived': 'only',
          'order': 'recent',
          'limit': '$limit',
          'offset': '$offset',
          if (gatewayProfile != null && gatewayProfile.isNotEmpty)
            'profile': gatewayProfile,
        },
      );
      if (isCancelled?.call() ?? false) {
        throw StateError('Archived session scan cancelled');
      }
      final list = data['sessions'] as List? ?? [];
      final rows = list
          .whereType<Map<String, dynamic>>()
          .map((s) => Session.fromJson(s))
          .toList();
      var newRows = 0;
      for (final row in rows) {
        if (seenIds.add(row.id)) {
          all.add(row);
          newRows++;
        }
      }
      if (shouldContinue?.call() == false || (isCancelled?.call() ?? false)) {
        throw StateError('Archived session read cancelled');
      }
      if (newRows > 0) onProgress?.call(List.unmodifiable(all));
      offset += limit;
      // Totals/has_more can under-report or change between offset windows.
      // Require the client-side proof — one zero-new page is NOT exhaustion
      // when pins exist (an all-pin window repeats seen ids while unseen rows
      // remain); k consecutive zero-new windows past the pin bound are.
      final pinsOnPage = rows.where((row) => row.pinned).length;
      if (pinsOnPage > pinBound) pinBound = pinsOnPage;
      if (rows.isEmpty || newRows == 0) {
        zeroNewWindowRows += limit;
        if (zeroNewWindowRows > pinBound) {
          exhausted = true;
          break;
        }
      } else {
        zeroNewWindowRows = 0;
      }
    }
    if (!exhausted) {
      throw StateError(
        'Archived session list exceeded the $maxPages-page cap without '
        'reaching its end; refusing to present a possibly truncated '
        'archive as complete.',
      );
    }
    return all;
  }

  Map<String, String>? _cronQuery([Map<String, String>? parameters]) {
    final profile = _gatewayProfile;
    if (profile == null) return parameters;
    return {...?parameters, 'profile': profile};
  }

  Future<List<Map<String, dynamic>>> getCronJobs() async {
    final data = await apiGetList('cron/jobs', queryParameters: _cronQuery());
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// Run sessions produced by one cron job, newest first.
  ///
  /// Mirrors the desktop's `getCronJobRuns` (apps/desktop/src/api/cron.ts):
  /// runs are ordinary sessions with id `cron_{job_id}_{timestamp}` and
  /// `source='cron'`, enumerated by the dashboard's bounded id-range scan.
  /// This is the desktop-parity home for cron output: the chat list excludes
  /// machine-source rows, so per-job runs are browsed here instead.
  Future<List<Session>> getCronJobRuns(String jobId, {int limit = 20}) async {
    final data = await apiGet(
      'cron/jobs/${Uri.encodeComponent(jobId)}/runs',
      queryParameters: _cronQuery({'limit': '$limit'}),
    );
    final list = data['runs'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((s) => Session.fromJson(s))
        .toList();
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiPost(
        endpoint,
        body: body,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<void> apiDelete(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .delete(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiDelete(
        endpoint,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> apiPut(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool retried = false,
    Duration timeout = ApiClient.requestTimeout,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiPut(
        endpoint,
        body: body,
        queryParameters: queryParameters,
        retried: true,
        timeout: timeout,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<Map<String, dynamic>> getModelInfo() => apiGet('model/info');
  Future<Map<String, dynamic>> getModelOptions() => apiGet('model/options');
  Future<List<Map<String, dynamic>>> getSkills() async {
    final data = await apiGetList('skills');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => apiPost(
    'model/set',
    body: {'scope': scope, 'provider': provider, 'model': model},
  );

  // ── Cron job management ──────────────────────────────────────────────

  Future<Map<String, dynamic>> createJob({
    required String prompt,
    required String schedule,
    String name = '',
    String deliver = 'local',
  }) => apiPost(
    'cron/jobs',
    queryParameters: _cronQuery(),
    body: {
      'prompt': prompt,
      'schedule': schedule,
      'name': name,
      'deliver': deliver,
    },
  );

  static Map<String, dynamic> buildCronUpdateBody(
    Map<String, dynamic> updates,
  ) => {'updates': updates};

  Future<Map<String, dynamic>> updateJob(
    String jobId,
    Map<String, dynamic> updates, {
    Duration timeout = ApiClient.requestTimeout,
  }) => apiPut(
    'cron/jobs/${Uri.encodeComponent(jobId)}',
    queryParameters: _cronQuery(),
    body: buildCronUpdateBody(updates),
    timeout: timeout,
  );

  Future<Map<String, dynamic>> setJobPaused(
    String jobId, {
    required bool paused,
  }) => apiPost(
    'cron/jobs/${Uri.encodeComponent(jobId)}/${paused ? 'pause' : 'resume'}',
    queryParameters: _cronQuery(),
  );

  Future<Map<String, dynamic>> triggerJob(String jobId) => apiPost(
    'cron/jobs/${Uri.encodeComponent(jobId)}/trigger',
    queryParameters: _cronQuery(),
  );

  Future<void> deleteJob(String jobId) => apiDelete(
    'cron/jobs/${Uri.encodeComponent(jobId)}',
    queryParameters: _cronQuery(),
  );

  void close() => _http.close();
}
