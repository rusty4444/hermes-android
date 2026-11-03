import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mtls_fixture.dart';

// Public throwaway fixture, generated once with macOS LibreSSL:
// openssl rsa -in test/fixtures/mtls-client-key.pem -aes256 \
//   -passout env:QUALITY_PEM_PHRASE -out <fixture>
// OpenSSL 3 also needs -traditional. No CLI is required to run these tests.
const _phrase = ' exact fixture password\t ';
const _keyPath = 'test/fixtures/mtls-client-key-traditional.pem';

class _Credentials implements CredentialStore {
  final Map<String, String> values;
  final _cache = <String, String>{};

  _Credentials(this.values);

  @override
  String? readCached(String key) => _cache[key];

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
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _cache.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late ClientCertificateService certificates;
  late SharedPreferences preferences;
  late Map<String, String> physicalCredentials;
  late ConnectionManager manager;
  late MutualTlsFixture server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    physicalCredentials = <String, String>{};
    support = await Directory.systemTemp.createTemp('traditional-pem-');
    certificates = ClientCertificateService(
      supportDirectory: () async => support,
    );
    manager = ConnectionManager(
      preferences,
      credentialStore: _Credentials(physicalCredentials),
      certificateFiles: certificates,
      nativePushSupported: false,
    );
    server = MutualTlsFixture();
    await server.start((request) async {
      server.json(request, {'data': [], 'has_more': false});
      await request.response.close();
    });
    final key = await File(_keyPath).readAsString();
    // A PKCS#8 fixture would only exercise the previously working branch.
    expect(key, startsWith('-----BEGIN RSA PRIVATE KEY-----\n'));
    expect(key, contains('Proc-Type: 4,ENCRYPTED\n'));
    expect(key, isNot(contains('BEGIN ENCRYPTED PRIVATE KEY')));
  });

  tearDown(() async {
    await server.close();
    if (await support.exists()) await support.delete(recursive: true);
  });

  SavedConnection connection(ClientCertificateConfig identity) =>
      SavedConnection(
        id: 'traditional-fixture',
        label: 'fixture',
        host: '127.0.0.1',
        port: server.server.port,
        useHttps: true,
        apiKey: 'synthetic-api',
        clientCertificate: identity,
      );

  Future<SavedConnection> physicallyReload() async {
    await preferences.reload();
    // Reopen with an empty credential cache, not the importing manager's state.
    final restarted = ConnectionManager(
      preferences,
      credentialStore: _Credentials(physicalCredentials),
      certificateFiles: certificates,
      nativePushSupported: false,
    );
    final restored = (await restarted.loadConnectionsWithSecrets()).single;
    expect(restored.clientCertificate!.privateKeyPassword, _phrase);
    expect(
      preferences.getStringList('saved_connections')!.single,
      isNot(contains('private_key_password')),
    );
    expect(
      jsonDecode(physicalCredentials.values.single)['client_key_password'],
      _phrase,
    );
    return restored;
  }

  Future<void> verifiedFetch(SavedConnection saved) =>
      withLoopbackTrust(() async {
        final before = server.requests.length;
        final client = ApiClient(
          baseUrl: saved.baseUrl,
          apiKey: saved.apiKey,
          clientCertificate: saved.clientCertificate,
        );
        try {
          expect(await client.getSessions(), isEmpty);
          expect(server.requests, hasLength(before + 1));
          expect(server.anonymousRequests, 0);
        } finally {
          client.close();
        }
      });

  test(
    'traditional PEM import retains exact phrase through secure reload and HTTPS',
    () async {
      final imported = await certificates.importPemPair(
        certificateBytes: await File(
          loopbackIdentity.certificatePemPath,
        ).readAsBytes(),
        privateKeyBytes: await File(_keyPath).readAsBytes(),
        password: _phrase,
        label: 'traditional RSA',
      );
      expect(imported.privateKeyPassword, _phrase);
      final committed = await certificates.commit(imported);
      await manager.importConnections([
        connection(committed),
      ], replaceExisting: false);
      await verifiedFetch(await physicallyReload());
    },
  );

  for (final mode in ConfigImportMode.values) {
    test(
      'traditional PEM encrypted backup $mode retains exact phrase after same-ID secure reload and HTTPS',
      () async {
        // Seed the known-valid identity without depending on importPemPair, so
        // this case independently regresses restore's encryption classification.
        final directory = await Directory(
          '${support.path}/client-certs/original',
        ).create(recursive: true);
        final chain = await File(
          loopbackIdentity.certificatePemPath,
        ).copy('${directory.path}/certificate.pem');
        final key = await File(
          _keyPath,
        ).copy('${directory.path}/private-key.pem');
        final original = ClientCertificateConfig(
          label: 'traditional RSA',
          certificatePemPath: chain.path,
          privateKeyPemPath: key.path,
          privateKeyPassword: _phrase,
        );
        await manager.importConnections([
          connection(original),
        ], replaceExisting: false);
        await verifiedFetch(await physicallyReload());
        final backups = ConfigBackupService(
          connectionManager: manager,
          preferences: preferences,
          certificates: certificates,
        );
        final backup = await backups.export(appVersion: 'test');
        final encoded = await ConfigBackupCodec.encrypt(
          backup,
          passphrase: 'synthetic-backup-password',
          iterations: 10,
        );
        final decoded = await ConfigBackupCodec.decrypt(
          encoded,
          passphrase: 'synthetic-backup-password',
        );
        expect(decoded.clientCertificates.values.single.password, _phrase);
        final result = await backups.import(decoded, mode: mode);
        expect(result.connectionsUpdated, 1);
        final restored = await physicallyReload();
        expect(restored.id, connection(original).id);
        expect(
          File(restored.clientCertificate!.certificatePemPath).existsSync(),
          isTrue,
        );
        expect(
          File(restored.clientCertificate!.privateKeyPemPath).existsSync(),
          isTrue,
        );
        expect(File(original.privateKeyPemPath).existsSync(), isFalse);
        await verifiedFetch(restored);
        expect(server.requests, hasLength(2));
      },
    );
  }
}
