import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FaultInjectingCredentialStore implements CredentialStore {
  final Map<String, String> values = <String, String>{};
  final Map<String, String> _cache = <String, String>{};

  int reads = 0;
  int writes = 0;
  int deletes = 0;
  int? failReadNumber;
  bool failNextRead = false;

  @override
  Future<void> delete(String key) async {
    deletes += 1;
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    reads += 1;
    if (failNextRead || reads == failReadNumber) {
      failNextRead = false;
      _cache.remove(key);
      return null;
    }

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
    writes += 1;
    values[key] = value;
  }
}

String _legacyConnection({
  required String id,
  required String label,
  required String host,
  String apiKey = '',
  String? dashboardPassword,
  int port = 8642,
  String? gatewayPrefix,
}) {
  return jsonEncode(<String, Object?>{
    'id': id,
    'label': label,
    'host': host,
    'port': port,
    'api_key': apiKey,
    'use_https': false,
    'gateway_prefix': gatewayPrefix,
    'dashboard_username': dashboardPassword == null ? null : 'operator',
    'dashboard_password': dashboardPassword,
  });
}

List<Map<String, dynamic>> _storedMetadata(SharedPreferences prefs) {
  return (prefs.getStringList('saved_connections') ?? const <String>[])
      .map((value) => jsonDecode(value) as Map<String, dynamic>)
      .toList();
}

void _expectNoPlaintextCredentials(SharedPreferences prefs) {
  final metadata = _storedMetadata(prefs);
  for (final connection in metadata) {
    expect(connection, isNot(contains('api_key')));
    expect(connection, isNot(contains('dashboard_password')));
    expect(connection, isNot(contains('mtls_certificate_alias')));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('migrates multiple legacy profiles, preserves metadata and IDs, and '
      'removes plaintext only after verified writes', () async {
    final legacy = <String>[
      _legacyConnection(
        id: 'profile-a',
        label: 'Organizer',
        host: 'organizer.example.lan',
        apiKey: 'synthetic-api-a',
        dashboardPassword: 'synthetic-dashboard-a',
        gatewayPrefix: '/organizer',
      ),
      _legacyConnection(
        id: 'profile-b',
        label: 'Professional',
        host: 'professional.example.lan',
        apiKey: 'synthetic-api-b',
      ),
      _legacyConnection(
        id: 'profile-without-secrets',
        label: 'Old metadata only',
        host: 'old.example.lan',
      ),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_connections': legacy,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore();

    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );
    final connections = manager.getConnections();

    expect(connections.map((connection) => connection.id), <String>[
      'profile-a',
      'profile-b',
      'profile-without-secrets',
    ]);
    expect(connections[0].label, 'Organizer');
    expect(connections[0].gatewayPrefix, '/organizer');
    expect(connections[0].apiKey, 'synthetic-api-a');
    expect(connections[0].dashboardPassword, 'synthetic-dashboard-a');
    expect(connections[1].apiKey, 'synthetic-api-b');
    expect(connections[2].apiKey, isEmpty);
    expect(connections[2].dashboardPassword, isNull);
    expect(store.values, hasLength(2));
    _expectNoPlaintextCredentials(prefs);
    final sanitizedJson = prefs.getStringList('saved_connections')!.join();
    expect(sanitizedJson, isNot(contains('synthetic-api')));
    expect(sanitizedJson, isNot(contains('synthetic-dashboard')));

    // SessionListScreen creates a fresh manager synchronously. The initialized
    // store cache keeps that compatibility path hydrated without plaintext.
    final sessionListManager = ConnectionManager(prefs, credentialStore: store);
    expect(sessionListManager.getConnections()[0].apiKey, 'synthetic-api-a');

    final writesAfterMigration = store.writes;
    final reloaded = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );
    expect(reloaded.getConnections()[0].apiKey, 'synthetic-api-a');
    expect(store.writes, writesAfterMigration);
    _expectNoPlaintextCredentials(prefs);
  });

  test('removes the obsolete prefilled Desktop Gateway URL', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_connections': <String>[
        jsonEncode(<String, Object?>{
          'id': 'profile-a',
          'label': 'Gateway',
          'host': 'gateway.example.com',
          'port': 443,
          'use_https': true,
          'desktop_gateway_url': 'http://192.168.1.193/desktop',
        }),
      ],
    });
    final prefs = await SharedPreferences.getInstance();

    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: _FaultInjectingCredentialStore(),
    );

    expect(manager.getConnections().single.desktopGatewayUrl, isNull);
    expect(
      _storedMetadata(prefs).single,
      isNot(contains('desktop_gateway_url')),
    );
  });

  test('partial read-back failure retains all legacy plaintext and retry is '
      'idempotent', () async {
    final legacy = <String>[
      _legacyConnection(
        id: 'profile-a',
        label: 'A',
        host: 'a.example.lan',
        apiKey: 'synthetic-api-a',
        dashboardPassword: 'synthetic-password-a',
      ),
      _legacyConnection(
        id: 'profile-b',
        label: 'B',
        host: 'b.example.lan',
        apiKey: 'synthetic-api-b',
        dashboardPassword: 'synthetic-password-b',
      ),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'saved_connections': legacy,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore()..failReadNumber = 2;
    final manager = ConnectionManager(prefs, credentialStore: store);

    Object? migrationError;
    try {
      await manager.initialize();
    } catch (error) {
      migrationError = error;
    }
    expect(migrationError, isA<CredentialStorageException>());
    expect(migrationError.toString(), isNot(contains('synthetic-api')));
    expect(migrationError.toString(), isNot(contains('synthetic-password')));
    expect(prefs.getStringList('saved_connections'), legacy);
    expect(store.values, hasLength(2));
    expect(manager.getConnections(), hasLength(2));

    store.failReadNumber = null;
    await manager.initialize();
    _expectNoPlaintextCredentials(prefs);
    expect(manager.getConnections()[0].apiKey, 'synthetic-api-a');
    expect(manager.getConnections()[1].apiKey, 'synthetic-api-b');

    final writesAfterRetry = store.writes;
    await manager.initialize();
    expect(store.writes, writesAfterRetry);
    _expectNoPlaintextCredentials(prefs);
  });

  test('update, clear, and delete keep secure storage synchronized', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );

    await manager.saveConnection(
      'Home',
      '192.0.2.10',
      8642,
      'synthetic-api-old',
      dashboardUsername: 'operator',
      dashboardPassword: 'synthetic-password-old',
    );
    final original = manager.getConnections().single;
    expect(store.values, hasLength(1));
    _expectNoPlaintextCredentials(prefs);

    await manager.updateConnection(
      original.id,
      'Moved',
      'https://hermes.example.com',
      8642,
      'synthetic-api-new',
      dashboardUsername: 'operator',
      dashboardPassword: 'synthetic-password-new',
    );
    var updated = manager.getConnections().single;
    expect(updated.id, original.id);
    expect(updated.label, 'Moved');
    expect(updated.host, 'hermes.example.com');
    expect(updated.port, 443);
    expect(updated.apiKey, 'synthetic-api-new');
    expect(updated.dashboardPassword, 'synthetic-password-new');
    _expectNoPlaintextCredentials(prefs);

    await manager.updateApiKey(original.id, '');
    await manager.updateDashboardAuth(original.id, username: '', password: '');
    updated = manager.getConnections().single;
    expect(updated.apiKey, isEmpty);
    expect(updated.dashboardPassword, isNull);
    expect(store.values, isEmpty);
    _expectNoPlaintextCredentials(prefs);

    await manager.updateApiKey(original.id, 'synthetic-api-restored');
    expect(store.values, hasLength(1));
    await manager.deleteConnection(original.id);
    expect(manager.getConnections(), isEmpty);
    expect(_storedMetadata(prefs), isEmpty);
    expect(store.values, isEmpty);
  });

  test('failed update read-back restores the prior credentials', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _FaultInjectingCredentialStore();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: store,
    );
    await manager.saveConnection(
      'Home',
      '192.0.2.10',
      8642,
      'synthetic-api-stable',
      dashboardPassword: 'synthetic-password-stable',
    );
    final id = manager.getConnections().single.id;

    store.failNextRead = true;
    await expectLater(
      manager.updateApiKey(id, 'synthetic-api-rejected'),
      throwsA(isA<CredentialStorageException>()),
    );

    final retained = manager.getConnections().single;
    expect(retained.apiKey, 'synthetic-api-stable');
    expect(retained.dashboardPassword, 'synthetic-password-stable');
    _expectNoPlaintextCredentials(prefs);
  });

  test(
    'remembers mTLS selection securely and clears it when disabled',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = _FaultInjectingCredentialStore();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );

      await manager.saveConnection(
        'Secure gateway',
        'https://gateway.example.com',
        8642,
        'synthetic-api-key',
        mtlsEnabled: true,
        mtlsCertificateAlias: 'android-client-cert',
      );

      var connection = manager.getConnections().single;
      expect(connection.useHttps, isTrue);
      expect(connection.mtlsEnabled, isTrue);
      expect(connection.mtlsCertificateAlias, 'android-client-cert');
      final metadata = _storedMetadata(prefs).single;
      expect(metadata['mtls_enabled'], isTrue);
      expect(metadata, isNot(contains('mtls_certificate_alias')));
      expect(store.values.values.single, contains('android-client-cert'));

      final reloaded = await ConnectionManager.create(
        prefs,
        credentialStore: store,
      );
      connection = reloaded.getConnections().single;
      expect(connection.mtlsEnabled, isTrue);
      expect(connection.mtlsCertificateAlias, 'android-client-cert');

      await reloaded.updateConnection(
        connection.id,
        connection.label,
        'http://gateway.example.com',
        8642,
        connection.apiKey,
        mtlsEnabled: false,
      );
      connection = reloaded.getConnections().single;
      expect(connection.useHttps, isFalse);
      expect(connection.mtlsEnabled, isFalse);
      expect(connection.mtlsCertificateAlias, isNull);
      expect(
        store.values.values.single,
        isNot(contains('android-client-cert')),
      );
      _expectNoPlaintextCredentials(prefs);
    },
  );

  test('rejects enabled mTLS without a certificate alias', () async {
    final prefs = await SharedPreferences.getInstance();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: _FaultInjectingCredentialStore(),
    );

    await expectLater(
      manager.saveConnection(
        'Invalid',
        'https://gateway.example.com',
        8642,
        'synthetic-api-key',
        mtlsEnabled: true,
      ),
      throwsArgumentError,
    );
    await expectLater(
      manager.saveConnection(
        'Invalid',
        'http://gateway.example.com',
        8642,
        'synthetic-api-key',
        mtlsEnabled: true,
        mtlsCertificateAlias: 'android-client-cert',
      ),
      throwsArgumentError,
    );
  });
}
