import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/models/connection.dart';

void main() {
  const config = ClientCertificateConfig(
    label: 'Hermes proxy',
    certificatePemPath: '/data/app/client-certs/a/certificate.pem',
    privateKeyPemPath: '/data/app/client-certs/a/private-key.pem',
    privateKeyPassword: 'secret',
  );

  group('ClientCertificateConfig', () {
    test('never serializes the private-key password', () {
      final json = config.toJson();

      expect(json.containsKey('private_key_password'), isFalse);
      expect(json.values, isNot(contains('secret')));
      expect(json['label'], 'Hermes proxy');
      expect(json['certificate_pem_path'], config.certificatePemPath);
      expect(json['private_key_pem_path'], config.privateKeyPemPath);
    });

    test('fromJson still accepts a legacy plaintext password for migration', () {
      final restored = ClientCertificateConfig.fromJson({
        ...config.toJson(),
        'private_key_password': 'legacy-secret',
      });

      // Readable so ConnectionManager can move it into the secure store; it is
      // never written back out by toJson.
      expect(restored.privateKeyPassword, 'legacy-secret');
      expect(restored.toJson().containsKey('private_key_password'), isFalse);
    });

    test('fromJson treats a blank legacy password as absent', () {
      final restored = ClientCertificateConfig.fromJson({
        ...config.toJson(),
        'private_key_password': '',
      });

      expect(restored.privateKeyPassword, isNull);
    });

    test('copyWith replaces only the requested fields', () {
      final updated = config.copyWith(label: 'Renamed');

      expect(updated.label, 'Renamed');
      expect(updated.certificatePemPath, config.certificatePemPath);
      expect(updated.privateKeyPemPath, config.privateKeyPemPath);
      expect(updated.privateKeyPassword, config.privateKeyPassword);
    });

    test('copyWith can clear the private-key password', () {
      final cleared = config.copyWith(clearPrivateKeyPassword: true);

      expect(cleared.privateKeyPassword, isNull);
      expect(cleared.certificatePemPath, config.certificatePemPath);
    });

    test('equality includes every field', () {
      expect(
        config,
        const ClientCertificateConfig(
          label: 'Hermes proxy',
          certificatePemPath: '/data/app/client-certs/a/certificate.pem',
          privateKeyPemPath: '/data/app/client-certs/a/private-key.pem',
          privateKeyPassword: 'secret',
        ),
      );
      expect(config, isNot(config.copyWith(label: 'Other')));
      expect(config, isNot(config.copyWith(privateKeyPassword: 'other')));
      expect(
        config,
        isNot(config.copyWith(certificatePemPath: '/other/certificate.pem')),
      );
    });
  });

  test(
    'SavedConnection persists the certificate metadata without a password',
    () {
      final connection = SavedConnection(
        id: 'conn-1',
        label: 'mTLS proxy',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
        clientCertificate: config,
      );

      final map = connection.toMap();
      final restored = SavedConnection.fromMap(map);

      expect(
        restored.clientCertificate,
        config.copyWith(clearPrivateKeyPassword: true),
      );
      expect(restored.clientCertificate!.privateKeyPassword, isNull);
      expect(
        map['client_certificate'] as Map<String, dynamic>,
        isNot(contains('private_key_password')),
      );
      expect(
        connection.toMap()['client_certificate'],
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test('SavedConnection.copyWith can clear the client certificate', () {
    final connection = SavedConnection(
      id: 'conn-1',
      label: 'mTLS proxy',
      host: 'hermes.example.com',
      port: 443,
      apiKey: 'key',
      useHttps: true,
      clientCertificate: config,
    );

    expect(connection.copyWith(label: 'Renamed').clientCertificate, config);
    expect(
      connection.copyWith(clearClientCertificate: true).clientCertificate,
      isNull,
    );
  });
}
