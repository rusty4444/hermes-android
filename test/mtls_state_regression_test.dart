import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The existing plugin's platform seam injects physical write/ACK failures.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/mtls_fixture.dart';

class _Credentials implements CredentialStore {
  final values = <String, String>{};
  final cache = <String, String>{};
  int writes = 0;
  int? failWrite;
  bool failVerification = false;
  bool failNextRead = false;
  bool _justWrote = false;

  @override
  String? readCached(String key) => cache[key];

  @override
  Future<String?> read(String key) async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('synthetic prerequisite storage read failure');
    }
    if (_justWrote && failVerification) {
      _justWrote = false;
      failVerification = false;
      throw StateError('synthetic storage verification failure');
    }
    _justWrote = false;
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
    if (++writes == failWrite) throw StateError('synthetic write failure');
    values[key] = value;
    _justWrote = true;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    cache.remove(key);
  }
}

class _FailOnceMetadataStore extends InMemorySharedPreferencesStore {
  _FailOnceMetadataStore() : super.empty();
  bool failMetadata = false;
  bool returnFalse = false;
  bool failRollback = false;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.saved_connections' && failRollback && !failMetadata) {
      throw StateError('synthetic permanent metadata rollback failure');
    }
    if (key == 'flutter.saved_connections' && failMetadata) {
      failMetadata = false;
      // A failed acknowledgement may follow an actual physical write.
      await super.setValue(type, key, value);
      if (returnFalse) return false;
      throw StateError('synthetic metadata acknowledgement failure');
    }
    return super.setValue(type, key, value);
  }
}

const _certificate = ClientCertificateConfig(
  label: 'fixture',
  certificatePemPath: 'test/fixtures/client-cert.pem',
  privateKeyPemPath: 'test/fixtures/client-key-encrypted.pem',
  privateKeyPassword: '  key password \t',
);

SavedConnection _connection([ClientCertificateConfig? certificate]) =>
    SavedConnection(
      id: 'same-id',
      label: 'mTLS',
      host: 'hermes.example',
      port: 443,
      useHttps: true,
      apiKey: 'synthetic-api',
      dashboardPassword: 'synthetic-dashboard',
      clientCertificate: certificate,
    );

String _credentialKey(String id) =>
    'connection_credentials_v1.${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final failVerification in [false, true]) {
    test(
      'legacy key migration merges secure bundle, failure=$failVerification, '
      'and retries without losing other secrets',
      () async {
        final map = _connection(_certificate).toMap();
        (map['client_certificate'] as Map)['private_key_password'] =
            _certificate.privateKeyPassword;
        final originalMetadata = [jsonEncode(map)];
        SharedPreferences.setMockInitialValues({
          'saved_connections': originalMetadata,
        });
        final prefs = await SharedPreferences.getInstance();
        final store = _Credentials();
        final key = _credentialKey('same-id');
        store.values[key] = jsonEncode({
          'api_key': 'existing-api',
          'dashboard_password': 'existing-dashboard',
        });
        store.failVerification = failVerification;
        final manager = ConnectionManager(prefs, credentialStore: store);
        if (failVerification) {
          await expectLater(
            manager.initialize(),
            throwsA(isA<CredentialStorageException>()),
          );
          expect(prefs.getStringList('saved_connections'), originalMetadata);
          expect(jsonDecode(store.values[key]!)['api_key'], 'existing-api');
          expect(
            jsonDecode(store.values[key]!)['dashboard_password'],
            'existing-dashboard',
          );
        }
        await manager.initialize();
        final saved = (await manager.loadConnectionsWithSecrets()).single;
        expect(saved.apiKey, 'existing-api');
        expect(saved.dashboardPassword, 'existing-dashboard');
        expect(
          saved.clientCertificate!.privateKeyPassword,
          _certificate.privateKeyPassword,
        );
        expect(
          prefs.getStringList('saved_connections')!.single,
          isNot(contains('private_key_password')),
        );
        final writes = store.writes;
        await manager.initialize();
        expect(store.writes, writes);
      },
    );
  }

  test(
    'exact whitespace key password survives save, reload and backup JSON',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = _Credentials();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      await manager.saveConnection(
        'mTLS',
        'https://hermes.example',
        443,
        'api',
        clientCertificate: _certificate,
      );
      final reloaded = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      expect(
        reloaded.getConnections().single.clientCertificate!.privateKeyPassword,
        _certificate.privateKeyPassword,
      );
      final backup = ClientCertificateBackup.fromJson({
        'label': 'fixture',
        'certificate_pem': 'cert',
        'private_key_pem': 'key',
        'private_key_password': _certificate.privateKeyPassword,
      });
      expect(backup.password, _certificate.privateKeyPassword);
      expect(
        ClientCertificateBackup.fromJson(backup.toJson()).password,
        _certificate.privateKeyPassword,
      );
    },
  );

  for (final failure in [
    'prior credential read',
    'later credential',
    'verification',
    'metadata throw',
    'metadata false',
  ]) {
    test('same-ID import rolls back credentials and metadata after '
        '$failure '
        'failure and retries', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final platform = _FailOnceMetadataStore();
      final originalPlatform = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalPlatform,
      );
      final store = _Credentials();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      await manager.importConnections([
        _connection(_certificate),
      ], replaceExisting: false);
      final originalMetadata = prefs.getStringList('saved_connections');
      final originalCredentials = Map<String, String>.of(store.values);
      final replacement = _connection(
        _certificate.copyWith(privateKeyPassword: 'replacement-password'),
      );
      if (failure.startsWith('metadata')) {
        platform.failMetadata = true;
        platform.returnFalse = failure == 'metadata false';
      } else if (failure == 'verification') {
        store.failVerification = true;
      } else if (failure == 'prior credential read') {
        store.failNextRead = true;
      } else {
        store.failWrite = store.writes + 2;
      }
      final incoming = [
        replacement,
        SavedConnection(
          id: 'new-id',
          label: 'new',
          host: 'hermes.example',
          port: 443,
          apiKey: 'synthetic-new-api',
        ),
      ];
      await expectLater(
        manager.importConnections(incoming, replaceExisting: false),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(store.values, originalCredentials);
      expect(prefs.getStringList('saved_connections'), originalMetadata);
      await prefs.reload();
      expect(prefs.getStringList('saved_connections'), originalMetadata);
      final restored = (await manager.loadConnectionsWithSecrets()).single;
      expect(restored.clientCertificate, _certificate);
      expect(restored.apiKey, 'synthetic-api');
      store.failWrite = null;
      await manager.importConnections(incoming, replaceExisting: false);
      expect(
        (await manager.loadConnectionsWithSecrets())
            .first
            .clientCertificate!
            .privateKeyPassword,
        'replacement-password',
      );
    });
  }

  test('certificate addition, rotation, password change and removal retire '
      'stock owners; unchanged identity retains them', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = GatewayTurnApplicationController();
    addTearDown(controller.close);
    NormalGatewayApplicationSession session(SavedConnection c) =>
        controller.normalSessionFor(
          c,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {},
        );
    final rotatedChain = _certificate.copyWith(
      certificatePemPath: 'rotated-cert.pem',
    );
    final rotatedKey = rotatedChain.copyWith(
      privateKeyPemPath: 'rotated-key.pem',
    );
    final rotatedPassword = rotatedKey.copyWith(
      privateKeyPassword: 'rotated password',
    );
    final configurations = [
      _connection(),
      _connection(_certificate),
      _connection(rotatedChain),
      _connection(rotatedKey),
      _connection(rotatedPassword),
      _connection(rotatedPassword.copyWith(clearPrivateKeyPassword: true)),
      _connection(),
    ];
    var previous = session(configurations.first);
    await previous.ready;
    for (final connection in configurations.skip(1)) {
      final current = session(connection);
      await current.ready;
      expect(identical(current, previous), isFalse);
      expect(() => previous.chatFor('stale', title: 'stale'), throwsStateError);
      expect(identical(session(connection), current), isTrue);
      previous = current;
    }
  });

  test(
    'migration does not replace newer secure fields with stale plaintext',
    () async {
      final map = _connection(_certificate).toMap()
        ..['api_key'] = 'stale-api'
        ..['dashboard_password'] = 'stale-dashboard';
      (map['client_certificate'] as Map)['private_key_password'] = 'stale-key';
      SharedPreferences.setMockInitialValues({
        'saved_connections': [jsonEncode(map)],
      });
      final store = _Credentials();
      store.values[_credentialKey('same-id')] = jsonEncode({
        'api_key': 'current-api',
        'dashboard_password': 'current-dashboard',
        'client_key_password': _certificate.privateKeyPassword,
      });
      final manager = await ConnectionManager.create(
        await SharedPreferences.getInstance(),
        credentialStore: store,
      );
      final restored = (await manager.loadConnectionsWithSecrets()).single;
      expect(restored.apiKey, 'current-api');
      expect(restored.dashboardPassword, 'current-dashboard');
      expect(
        restored.clientCertificate!.privateKeyPassword,
        _certificate.privateKeyPassword,
      );
    },
  );

  test(
    'non-mTLS connections keep existing receipt scope and push authority binding',
    () async {
      SharedPreferences.setMockInitialValues({});
      final c = _connection();
      final legacyCredentialDigest = sha256
          .convert(utf8.encode('${c.apiKey}\u0000${c.dashboardPassword ?? ''}'))
          .toString();
      final legacyScope = sha256
          .convert(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'id': c.id,
                'host': c.host,
                'port': c.port,
                'https': c.useHttps,
                'gateway_prefix': c.gatewayPrefix,
                'profile': c.gatewayProfile,
                'desktop_gateway_url': c.desktopGatewayUrl,
                'dashboard_username': c.dashboardUsername,
                'dashboard_prefix': c.dashboardPrefix,
                'dashboard_port': c.dashboardPort,
                'dashboard_proxied': c.dashboardProxied,
                'credential_digest': legacyCredentialDigest,
              }),
            ),
          )
          .toString();
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(
        c,
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {},
      );
      await session.ready;
      expect(session.scope, legacyScope);
      final legacyBinding = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                ...c.toMap(),
                'api_key': c.apiKey,
                'dashboard_password': c.dashboardPassword,
              }),
            ),
          )
          .toString();
      expect(MobilePushService.binding(c), legacyBinding);
    },
  );

  test('push authority binding includes the exact encrypted-key password', () {
    final original = MobilePushService.binding(_connection(_certificate));
    expect(MobilePushService.binding(_connection(_certificate)), original);
    expect(
      MobilePushService.binding(
        _connection(
          _certificate.copyWith(
            privateKeyPassword: _certificate.privateKeyPassword!.trim(),
          ),
        ),
      ),
      isNot(original),
    );
    expect(original, isNot(contains(_certificate.privateKeyPassword!)));
  });

  test(
    'encrypted whitespace passphrase survives encrypted backup restore and real TLS',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'mtls-whitespace-backup-',
      );
      addTearDown(() => support.delete(recursive: true));
      final certificates = ClientCertificateService(
        supportDirectory: () async => support,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _Credentials(),
        certificateFiles: certificates,
      );
      final identity = await certificates.commit(
        await certificates.importPemPair(
          certificateBytes: await File(
            loopbackIdentity.certificatePemPath,
          ).readAsBytes(),
          privateKeyBytes: await File(
            'test/fixtures/mtls-client-key-whitespace.pem',
          ).readAsBytes(),
          password: _certificate.privateKeyPassword,
          label: 'encrypted fixture',
        ),
      );
      await manager.importConnections([
        _connection(identity),
      ], replaceExisting: false);
      final service = ConfigBackupService(
        connectionManager: manager,
        preferences: prefs,
        certificates: certificates,
      );
      final before = await service.export(appVersion: 'test');
      final encoded = await ConfigBackupCodec.encrypt(
        before,
        passphrase: 'synthetic-backup-password',
      );
      final backup = await ConfigBackupCodec.decrypt(
        encoded,
        passphrase: 'synthetic-backup-password',
      );
      expect(
        backup.clientCertificates.values.single.password,
        _certificate.privateKeyPassword,
      );
      await service.import(backup, mode: ConfigImportMode.replace);
      final restored = (await manager.loadConnectionsWithSecrets()).single;
      expect(
        restored.clientCertificate!.privateKeyPassword,
        _certificate.privateKeyPassword,
      );
      expect(File(identity.privateKeyPemPath).existsSync(), isFalse);
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        fixture.json(request, {'data': [], 'has_more': false});
        await request.response.close();
      });
      addTearDown(fixture.close);
      await withLoopbackTrust(() async {
        final client = ApiClient(
          baseUrl: fixture.origin,
          apiKey: 'fixture',
          clientCertificate: restored.clientCertificate,
        );
        addTearDown(client.close);
        expect(await client.getSessions(), isEmpty);
        expect(fixture.requests, hasLength(1));
        expect(fixture.anonymousRequests, 0);
      });
    },
  );

  for (final failure in [
    'prior credential read',
    'later credential',
    'verification',
    'metadata throw',
    'metadata false',
  ]) {
    for (final mode in ConfigImportMode.values) {
      test(
        'backup $mode import restores old key files, metadata and secure bundles after $failure',
        () async {
          final support = await Directory.systemTemp.createTemp(
            'mtls-import-rollback-',
          );
          addTearDown(() => support.delete(recursive: true));
          final certificates = ClientCertificateService(
            supportDirectory: () async => support,
          );
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final platform = _FailOnceMetadataStore();
          final originalPlatform = SharedPreferencesStorePlatform.instance;
          SharedPreferencesStorePlatform.instance = platform;
          addTearDown(
            () => SharedPreferencesStorePlatform.instance = originalPlatform,
          );
          final store = _Credentials();
          final manager = await ConnectionManager.create(
            prefs,
            credentialStore: store,
            certificateFiles: certificates,
          );
          final identity = await certificates.commit(
            await certificates.importPemPair(
              certificateBytes: await File(
                loopbackIdentity.certificatePemPath,
              ).readAsBytes(),
              privateKeyBytes: await File(
                'test/fixtures/mtls-client-key-whitespace.pem',
              ).readAsBytes(),
              password: _certificate.privateKeyPassword,
              label: 'original',
            ),
          );
          final obsolete = SavedConnection(
            id: 'obsolete',
            label: 'obsolete',
            host: 'unused.example',
            port: 443,
            apiKey: 'obsolete-api',
          );
          await manager.importConnections([
            _connection(identity),
            obsolete,
          ], replaceExisting: false);
          final metadataBefore = prefs.getStringList('saved_connections');
          final secretsBefore = Map<String, String>.of(store.values);
          final service = ConfigBackupService(
            connectionManager: manager,
            preferences: prefs,
            certificates: certificates,
          );
          final originalBackup = await service.export(appVersion: 'test');
          final incoming = ConfigBackup(
            createdAt: originalBackup.createdAt,
            appVersion: 'test',
            connections: [
              _connection().copyWith(
                apiKey: 'replacement-api',
                dashboardPassword: 'replacement-dashboard',
              ),
              SavedConnection(
                id: 'new-id',
                label: 'new',
                host: 'unused.example',
                port: 443,
                apiKey: 'new-api',
              ),
            ],
            preferences: {},
            clientCertificates: {
              'same-id': ClientCertificateBackup(
                label: 'replacement',
                certificatePem: await File(
                  loopbackIdentity.certificatePemPath,
                ).readAsString(),
                privateKeyPem: await File(
                  'test/fixtures/mtls-client-key.pem',
                ).readAsString(),
              ),
            },
          );
          if (failure.startsWith('metadata')) {
            platform.failMetadata = true;
            platform.returnFalse = failure == 'metadata false';
          } else if (failure == 'verification') {
            store.failVerification = true;
          } else if (failure == 'prior credential read') {
            store.failNextRead = true;
          } else {
            store.failWrite = store.writes + 2;
          }
          await expectLater(
            service.import(incoming, mode: mode),
            throwsA(isA<ConfigBackupException>()),
          );
          expect(store.values, secretsBefore);
          await prefs.reload();
          expect(prefs.getStringList('saved_connections'), metadataBefore);
          final restarted = await ConnectionManager.create(
            prefs,
            credentialStore: store,
            certificateFiles: certificates,
          );
          expect(restarted.getConnections().first.clientCertificate, identity);
          expect(File(identity.privateKeyPemPath).existsSync(), isTrue);
          final dirs = await Directory(
            '${support.path}/client-certs',
          ).list().toList();
          expect(
            dirs.whereType<Directory>().where(
              (d) => !d.path.endsWith('.staging'),
            ),
            hasLength(1),
          );
          store.failWrite = null;
          await service.import(incoming, mode: mode);
          final afterRetry = await manager.loadConnectionsWithSecrets();
          expect(afterRetry.first.apiKey, 'replacement-api');
          expect(
            afterRetry.first.clientCertificate!.privateKeyPassword,
            isNull,
          );
          expect(File(identity.privateKeyPemPath).existsSync(), isFalse);
          expect(
            afterRetry.any((c) => c.id == 'obsolete'),
            mode == ConfigImportMode.merge,
          );
        },
      );
    }
  }

  test(
    'a permanent rollback outage cannot delete a still-referenced replacement key',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'mtls-import-outage-',
      );
      addTearDown(() => support.delete(recursive: true));
      final certificates = ClientCertificateService(
        supportDirectory: () async => support,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final platform = _FailOnceMetadataStore();
      final originalPlatform = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalPlatform,
      );
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _Credentials(),
        certificateFiles: certificates,
      );
      await manager.importConnections([_connection()], replaceExisting: false);
      final service = ConfigBackupService(
        connectionManager: manager,
        preferences: prefs,
        certificates: certificates,
      );
      final backup = ConfigBackup(
        createdAt: DateTime.utc(2026),
        appVersion: 'test',
        connections: [_connection()],
        preferences: {},
        clientCertificates: {
          'same-id': ClientCertificateBackup(
            label: 'replacement',
            certificatePem: await File(
              loopbackIdentity.certificatePemPath,
            ).readAsString(),
            privateKeyPem: await File(
              loopbackIdentity.privateKeyPemPath,
            ).readAsString(),
          ),
        },
      );
      platform.failMetadata = true;
      platform.failRollback = true;
      await expectLater(
        service.import(backup, mode: ConfigImportMode.merge),
        throwsA(
          isA<ConfigBackupException>().having(
            (e) => e.message,
            'message',
            contains('could not be fully restored'),
          ),
        ),
      );
      await prefs.reload();
      final referenced = manager.getConnections().single.clientCertificate!;
      expect(File(referenced.certificatePemPath).existsSync(), isTrue);
      expect(File(referenced.privateKeyPemPath).existsSync(), isTrue);
    },
  );
}
