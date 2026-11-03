import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mtls_fixture.dart';

class _Secrets implements CredentialStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('synthetic credential write failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _NoFileWork extends ClientCertificateService {
  _NoFileWork()
    : super(
        supportDirectory: () async {
          throw StateError('certificate-free import requested a platform path');
        },
      );

  int collections = 0;
  int restores = 0;

  @override
  Future<void> deleteUnreferenced(Iterable<String> references) async {
    collections++;
    await super.deleteUnreferenced(references);
  }

  @override
  Future<ClientCertificateConfig> restore({
    required String certificatePem,
    required String privateKeyPem,
    required String label,
    String? password,
  }) async {
    restores++;
    throw StateError('certificate-free import attempted materialization');
  }
}

class _ObservedFiles extends ClientCertificateService {
  _ObservedFiles(Directory support, {this.failRestoreAt, this.onFailure})
    : super(supportDirectory: () async => support);

  final int? failRestoreAt;
  final Future<void> Function()? onFailure;
  final materialized = <ClientCertificateConfig>[];
  int collections = 0;

  @override
  Future<ClientCertificateConfig> restore({
    required String certificatePem,
    required String privateKeyPem,
    required String label,
    String? password,
  }) async {
    final config = await super.restore(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      label: label,
      password: password,
    );
    materialized.add(config);
    if (materialized.length == failRestoreAt) {
      // Leave an actual partial directory, and fail before returning a config
      // to the backup owner. Cleanup cannot rely on the returned-config list.
      await File(config.privateKeyPemPath).delete();
      await onFailure?.call();
      throw const ClientCertificateImportException(
        'Synthetic restore failure.',
      );
    }
    return config;
  }

  @override
  Future<void> deleteUnreferenced(Iterable<String> references) async {
    collections++;
    await super.deleteUnreferenced(references);
  }
}

SavedConnection _account(String id, {ClientCertificateConfig? identity}) =>
    SavedConnection(
      id: id,
      label: id,
      host: '127.0.0.1',
      port: 443,
      apiKey: 'synthetic-api',
      useHttps: true,
      clientCertificate: identity,
    );

Future<ClientCertificateConfig> _identity(
  ClientCertificateService files,
) async => files.commit(
  await files.importPemPair(
    certificateBytes: await File(
      loopbackIdentity.certificatePemPath,
    ).readAsBytes(),
    privateKeyBytes: await File(
      loopbackIdentity.privateKeyPemPath,
    ).readAsBytes(),
    label: 'existing',
  ),
);

Future<ConfigBackup> _backup(
  List<SavedConnection> accounts, {
  bool certificates = true,
}) async {
  final pair = certificates
      ? ClientCertificateBackup(
          label: 'bundled',
          certificatePem: await File(
            loopbackIdentity.certificatePemPath,
          ).readAsString(),
          privateKeyPem: await File(
            loopbackIdentity.privateKeyPemPath,
          ).readAsString(),
        )
      : null;
  return ConfigBackup(
    createdAt: DateTime.utc(2026),
    appVersion: 'certificate-cleanup-test',
    connections: accounts,
    clientCertificates: {
      if (pair != null)
        for (final account in accounts) account.id: pair,
    },
    preferences: const {'theme_mode': 'dark'},
  );
}

ConnectionManager _manager(
  SharedPreferences prefs,
  _Secrets secrets,
  ClientCertificateService files,
) => ConnectionManager(
  prefs,
  credentialStore: secrets,
  certificateFiles: files,
  nativePushSupported: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in ConfigImportMode.values) {
    for (final hasConnections in [false, true]) {
      testWidgets(
        'certificate-free $mode connections=$hasConnections needs no file work',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final files = _NoFileWork();
          final manager = _manager(prefs, _Secrets(), files);
          final backup = ConfigBackup(
            createdAt: DateTime.utc(2026),
            appVersion: 'certificate-free',
            connections: [if (hasConnections) _account('ordinary')],
            preferences: const {'theme_mode': 'dark'},
          );
          // Deliberately unchanged fake-async await, as in the real theme suite.
          final result = await ConfigBackupService(
            connectionManager: manager,
            preferences: prefs,
            certificates: files,
          ).import(backup, mode: mode);
          expect(result.connectionsAdded, hasConnections ? 1 : 0);
          expect(prefs.getString('theme_mode'), 'dark');
          expect(files.restores, 0);
          expect(files.collections, 0);
        },
      );
    }
  }

  test('failed certificate-free import also needs no file work', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final files = _NoFileWork();
    final secrets = _Secrets()..failWrites = true;
    final manager = _manager(prefs, secrets, files);
    final backup = await _backup([_account('ordinary')], certificates: false);
    await expectLater(
      ConfigBackupService(
        connectionManager: manager,
        preferences: prefs,
        certificates: files,
      ).import(backup, mode: ConfigImportMode.merge),
      throwsA(isA<ConfigBackupException>()),
    );
    expect(files.restores, 0);
    expect(files.collections, 0);
    await prefs.reload();
    expect(await manager.loadConnectionsWithSecrets(), isEmpty);
    expect(prefs.getString('theme_mode'), isNull);
  });

  for (final mode in ConfigImportMode.values) {
    test(
      'certificate-free $mode still collects the old removed identity',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'backup-old-certificate-',
        );
        addTearDown(() => support.delete(recursive: true));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final files = _ObservedFiles(support);
        final manager = _manager(prefs, _Secrets(), files);
        final identity = await _identity(files);
        final old = _account('old', identity: identity);
        await manager.importConnections([old], replaceExisting: false);
        final beforeCollections = files.collections;
        final backup = await _backup([
          _account(mode == ConfigImportMode.merge ? old.id : 'new'),
        ], certificates: false);
        await ConfigBackupService(
          connectionManager: manager,
          preferences: prefs,
          certificates: files,
        ).import(backup, mode: mode);
        expect(files.materialized, isEmpty);
        expect(files.collections, beforeCollections + 1);
        expect(Directory(identity.directoryPath).existsSync(), isFalse);
        await prefs.reload();
        final saved = (await manager.loadConnectionsWithSecrets()).single;
        expect(saved.clientCertificate, isNull);
        expect(saved.id, mode == ConfigImportMode.merge ? 'old' : 'new');
      },
    );
  }

  for (final failAt in [1, 2]) {
    test(
      'restore failure at identity $failAt collects partial and earlier materialization',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'backup-partial-restore-',
        );
        addTearDown(() => support.delete(recursive: true));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final files = _ObservedFiles(support, failRestoreAt: failAt);
        final manager = _manager(prefs, _Secrets(), files);
        final original = await _identity(files);
        await manager.importConnections([
          _account('existing', identity: original),
        ], replaceExisting: false);
        final beforeCollections = files.collections;
        await expectLater(
          ConfigBackupService(
            connectionManager: manager,
            preferences: prefs,
            certificates: files,
          ).import(
            await _backup([_account('one'), _account('two')]),
            mode: ConfigImportMode.replace,
          ),
          throwsA(
            isA<ConfigBackupException>().having(
              (error) => error.message,
              'message',
              'Synthetic restore failure.',
            ),
          ),
        );
        expect(files.materialized, hasLength(failAt));
        expect(files.collections, beforeCollections + 1);
        for (final identity in files.materialized) {
          expect(Directory(identity.directoryPath).existsSync(), isFalse);
        }
        expect(File(original.certificatePemPath).existsSync(), isTrue);
        expect(File(original.privateKeyPemPath).existsSync(), isTrue);
        await prefs.reload();
        final saved = (await manager.loadConnectionsWithSecrets()).single;
        expect(saved.id, 'existing');
        expect(saved.clientCertificate, original);
        expect(prefs.getString('theme_mode'), isNull);
      },
    );
  }

  test(
    'partial restore with unknown physical references is retained until a known read',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'backup-unknown-restore-',
      );
      addTearDown(() => support.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final files = _ObservedFiles(
        support,
        failRestoreAt: 1,
        onFailure: () async {
          await prefs.setStringList('saved_connections', ['{invalid-metadata']);
        },
      );
      final manager = _manager(prefs, _Secrets(), files);
      await expectLater(
        ConfigBackupService(
          connectionManager: manager,
          preferences: prefs,
          certificates: files,
        ).import(
          await _backup([_account('one')]),
          mode: ConfigImportMode.merge,
        ),
        throwsA(isA<ConfigBackupException>()),
      );
      final partial = files.materialized.single;
      expect(File(partial.certificatePemPath).existsSync(), isTrue);
      expect(File(partial.privateKeyPemPath).existsSync(), isFalse);
      await prefs.setStringList('saved_connections', []);
      await manager.cleanupUnreferencedCertificates();
      expect(Directory(partial.directoryPath).existsSync(), isFalse);
    },
  );

  test(
    'restored identity is collected after an uncommitted credential failure',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'backup-credential-failure-',
      );
      addTearDown(() => support.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final files = _ObservedFiles(support);
      final secrets = _Secrets()..failWrites = true;
      final manager = _manager(prefs, secrets, files);
      await expectLater(
        ConfigBackupService(
          connectionManager: manager,
          preferences: prefs,
          certificates: files,
        ).import(
          await _backup([_account('one')]),
          mode: ConfigImportMode.merge,
        ),
        throwsA(isA<ConfigBackupException>()),
      );
      final restored = files.materialized.single;
      expect(Directory(restored.directoryPath).existsSync(), isFalse);
      await prefs.reload();
      expect(await manager.loadConnectionsWithSecrets(), isEmpty);
      expect(prefs.getString('theme_mode'), isNull);
    },
  );
}
