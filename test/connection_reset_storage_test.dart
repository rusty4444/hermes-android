import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _sensitive = 'SYNTHETIC-PROVIDER-DETAILS';

String _key(String id) =>
    'connection_credentials_v1.${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';

class _Secrets implements CredentialStore {
  final values = <String, String>{};
  final cache = <String, String>{};
  final deleted = <String>[];
  Future<void> Function(String)? beforeDelete;
  int? failDeleteAt;
  bool failRead = false;
  bool ignoreDelete = false;
  bool failRollback = false;

  @override
  String? readCached(String key) => cache[key];
  @override
  Future<String?> read(String key) async {
    if (failRead) {
      throw PlatformException(code: 'unavailable', details: _sensitive);
    }
    final value = values[key];
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    if (failRollback) {
      throw PlatformException(code: 'write', details: _sensitive);
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleted.add(key);
    await beforeDelete?.call(key);
    if (!ignoreDelete) values.remove(key);
    if (deleted.length == failDeleteAt) {
      throw PlatformException(code: 'lost-delete-ack', details: _sensitive);
    }
  }
}

class _Metadata extends InMemorySharedPreferencesStore {
  _Metadata(super.data) : super.withData();
  String? failure;
  bool usedFailure = false;
  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.saved_connections' && !usedFailure && failure != null) {
      usedFailure = true;
      if (failure == 'lost ACK') {
        await super.remove(key);
        throw PlatformException(code: 'remove', details: _sensitive);
      }
      if (failure == 'false') return false;
      if (failure == 'lying success') return true;
    }
    return super.remove(key);
  }
}

class _Files implements ClientCertificateFileStore {
  final collections = <List<String>>[];
  bool fail = false;
  void Function()? beforeCollect;
  @override
  Future<void> deleteUnreferenced(
    Iterable<String> referencedDirectoryPaths,
  ) async {
    beforeCollect?.call();
    collections.add(referencedDirectoryPaths.toList());
    if (fail) throw StateError('optional certificate cleanup failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hermesagent.hermes_android/mobile_push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SharedPreferences prefs;
  late _Secrets secrets;
  late _Metadata metadata;
  late _Files files;
  late ConnectionManager manager;
  late List<SavedConnection> connections;
  late Map<String, Set<String>> nativeLeases;
  late List<String> methods;
  var nativeEnabled = true;
  bool failEndOnce = false;
  bool failSnapshot = false;

  ConnectionManager sibling() => ConnectionManager(
    prefs,
    credentialStore: secrets,
    certificateFiles: files,
    nativePushSupported: true,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final previous = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    connections = [
      for (final id in ['A', 'B'])
        SavedConnection(
          id: id,
          label: id,
          host: 'fixture.invalid',
          port: 8642,
          apiKey: '',
          clientCertificate: id == 'A'
              ? const ClientCertificateConfig(
                  label: 'fixture identity',
                  certificatePemPath: '/fixture-only/A/certificate.pem',
                  privateKeyPemPath: '/fixture-only/A/private-key.pem',
                )
              : null,
        ),
    ];
    metadata = _Metadata({
      'flutter.saved_connections': [
        for (final c in connections) jsonEncode(c.toMap()),
      ],
    });
    SharedPreferencesStorePlatform.instance = metadata;
    prefs = await SharedPreferences.getInstance();
    secrets = _Secrets();
    for (final c in connections) {
      secrets.values[_key(c.id)] =
          '{ "api_key": "fixture-${c.id}", "dashboard_password": "fixture-dash", "client_key_password": "fixture-pem" }';
    }
    files = _Files();
    nativeLeases = {};
    methods = [];
    nativeEnabled = true;
    failEndOnce = false;
    failSnapshot = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'snapshot') {
        if (failSnapshot) {
          throw PlatformException(code: 'snapshot', details: _sensitive);
        }
        return {'connection': 'B'};
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final token = args['mutation'] as String;
      if (call.method == 'beginConnectionChange') {
        final ids = Set<String>.from(args['connections'] as List);
        nativeLeases[token] = ids;
        if (ids.contains('B')) nativeEnabled = false;
      } else if (call.method == 'endConnectionChange') {
        nativeLeases.remove(token);
        if (failEndOnce) {
          failEndOnce = false;
          throw PlatformException(code: 'end-ack', details: _sensitive);
        }
      } else {
        throw StateError(call.method);
      }
      return null;
    });
    manager = sibling();
  });

  tearDown(() async {
    secrets.failRead = false;
    secrets.failRollback = false;
    await manager.finishPendingMobilePushChanges();
    messenger.setMockMethodCallHandler(channel, null);
    for (final c in connections) {
      expect(ConnectionMutationBarrier.isPending(c.id), isFalse);
    }
    expect(nativeLeases, isEmpty);
  });

  test(
    'reset removes every known raw bundle only after physical metadata removal (#207 L7)',
    () async {
      secrets.values[_key('A')] = 'corrupt bundle is still removable';
      secrets.beforeDelete = (_) async {
        final physical = await metadata.getAll();
        expect(physical, isNot(contains('flutter.saved_connections')));
        expect(nativeLeases.values.single, {'A', 'B'});
        expect(ConnectionMutationBarrier.isPending('A'), isTrue);
        expect(nativeEnabled, isFalse);
        expect(files.collections, isEmpty);
      };
      files.beforeCollect = () {
        expect(secrets.values, isEmpty);
        expect(prefs.containsKey('saved_connections'), isFalse);
      };
      await manager.resetConnections();
      expect(secrets.values, isEmpty);
      expect(secrets.cache, isEmpty);
      expect(secrets.deleted.toSet(), {_key('A'), _key('B')});
      expect(files.collections, [[]]);
      await sibling().initialize();
      expect(manager.getConnections(), isEmpty);
      secrets.beforeDelete = null;
      await manager.resetConnections();
      expect(secrets.values, isEmpty);
    },
  );

  test(
    'one corrupt metadata row does not hide decodable credential IDs (#207 L7)',
    () async {
      await prefs.setStringList('saved_connections', [
        'bad-json',
        jsonEncode({'id': 'A', 'host': 42}),
      ]);
      await manager.resetConnections();
      expect(
        secrets.values,
        isEmpty,
        reason: 'A from partial metadata; B from native binding',
      );
      expect(nativeEnabled, isFalse);
    },
  );

  for (final failure in ['false', 'lost ACK', 'lying success']) {
    test(
      'metadata $failure preserves credentials and files with sanitized failure (#207 L7)',
      () async {
        final before = Map<String, String>.of(secrets.values);
        final priorMetadata = prefs.getStringList('saved_connections');
        metadata.failure = failure;
        await expectLater(
          manager.resetConnections(),
          throwsA(
            isA<CredentialStorageException>().having(
              (e) => e.toString(),
              'safe message',
              isNot(contains(_sensitive)),
            ),
          ),
        );
        expect(secrets.values, before);
        expect(secrets.deleted, isEmpty);
        expect(files.collections, isEmpty);
        expect(prefs.getStringList('saved_connections'), priorMetadata);
        expect(
          nativeEnabled,
          isFalse,
          reason: 'rollback never restores push consent',
        );
        await sibling().resetConnections();
        expect(secrets.values, isEmpty);
      },
    );
  }

  for (final failAt in [1, 2]) {
    test(
      'delete $failAt lost ACK restores exact bundles and metadata before successor (#207 L7)',
      () async {
        final before = Map<String, String>.of(secrets.values);
        final priorMetadata = prefs.getStringList('saved_connections');
        secrets.failDeleteAt = failAt;
        await expectLater(
          manager.resetConnections(),
          throwsA(
            isA<CredentialStorageException>().having(
              (e) => e.toString(),
              'safe message',
              isNot(contains(_sensitive)),
            ),
          ),
        );
        expect(secrets.values, before);
        expect(prefs.getStringList('saved_connections'), priorMetadata);
        expect(files.collections, isEmpty);
        expect(nativeEnabled, isFalse);
        await sibling().updateApiKey('A', 'after-rollback');
        expect(
          (await sibling().loadConnectionsWithSecrets()).first.apiKey,
          'after-rollback',
        );
        expect(
          (await sibling().loadConnectionsWithSecrets()).last.apiKey,
          'fixture-B',
        );
      },
    );
  }

  test(
    'ignored credential delete fails read-back and restores metadata (#207 L7)',
    () async {
      secrets.ignoreDelete = true;
      await expectLater(
        manager.resetConnections(),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(prefs.getStringList('saved_connections'), hasLength(2));
      expect(secrets.values, hasLength(2));
      expect(files.collections, isEmpty);
    },
  );

  test(
    'reset owns cleanup before queued same-ID replacement (#207 L7)',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      secrets.beforeDelete = (_) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final reset = manager.resetConnections();
      // On the unfixed implementation reset never calls delete; do not hang red.
      await pumpEventQueue();
      if (!entered.isCompleted) {
        await reset;
        fail('reset never attempted credential cleanup');
      }
      var replaced = false;
      final replacement = sibling()
          .importConnections([
            connections.first.copyWith(apiKey: 'replacement-key'),
          ], replaceExisting: false)
          .then((_) => replaced = true);
      await pumpEventQueue();
      expect(replaced, isFalse);
      expect(ConnectionMutationBarrier.isPending('A'), isTrue);
      release.complete();
      await reset;
      await replacement;
      expect(
        (await sibling().loadConnectionsWithSecrets()).single.apiKey,
        'replacement-key',
      );
      expect(secrets.values, hasLength(1));
      expect(nativeEnabled, isFalse);
    },
  );

  test(
    'credential prerequisite read failure preserves configuration and is sanitized (#207 L7)',
    () async {
      final before = Map<String, String>.of(secrets.values);
      secrets.failRead = true;
      await expectLater(
        manager.resetConnections(),
        throwsA(
          isA<CredentialStorageException>().having(
            (e) => e.toString(),
            'safe message',
            isNot(contains(_sensitive)),
          ),
        ),
      );
      expect(secrets.values, before);
      expect(prefs.getStringList('saved_connections'), hasLength(2));
    },
  );

  test(
    'native snapshot read failure preserves configuration and is sanitized (#207 L7)',
    () async {
      final before = Map<String, String>.of(secrets.values);
      failSnapshot = true;
      await expectLater(
        manager.resetConnections(),
        throwsA(
          isA<CredentialStorageException>().having(
            (e) => e.toString(),
            'safe message',
            isNot(contains(_sensitive)),
          ),
        ),
      );
      expect(secrets.values, before);
      expect(prefs.getStringList('saved_connections'), hasLength(2));
      expect(methods, ['snapshot']);
    },
  );

  test(
    'failed rollback is reported honestly and retains certificate files (#207 L7)',
    () async {
      secrets.failDeleteAt = 2;
      secrets.failRollback = true;
      await expectLater(
        manager.resetConnections(),
        throwsA(
          isA<CredentialStorageException>()
              .having(
                (e) => e.toString(),
                'disposition',
                contains('could not be fully restored'),
              )
              .having(
                (e) => e.toString(),
                'safe message',
                isNot(contains(_sensitive)),
              ),
        ),
      );
      expect(files.collections, isEmpty);
      expect(nativeEnabled, isFalse);
      secrets.failRollback = false;
      await sibling().importConnections([
        connections.first.copyWith(apiKey: 'repaired-key'),
      ], replaceExisting: true);
      expect(
        (await sibling().loadConnectionsWithSecrets()).single.apiKey,
        'repaired-key',
      );
    },
  );

  test(
    'optional certificate collection failure does not fail a committed reset (#207 L7)',
    () async {
      files.fail = true;
      await manager.resetConnections();
      expect(secrets.values, isEmpty);
      expect(prefs.containsKey('saved_connections'), isFalse);
      expect(files.collections, [[]]);
    },
  );

  test(
    'lost native END ACK stays replayable without reviving consent (#207 L7)',
    () async {
      failEndOnce = true;
      await expectLater(
        manager.resetConnections(),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(secrets.values, isEmpty);
      expect(prefs.containsKey('saved_connections'), isFalse);
      await sibling().finishPendingMobilePushChanges();
      expect(methods.where((m) => m == 'endConnectionChange'), hasLength(2));
      expect(nativeEnabled, isFalse);
    },
  );
}
