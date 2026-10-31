import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';

void main() {
  late Directory support;
  late ClientCertificateService service;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('hermes-client-cert-test');
    service = ClientCertificateService(supportDirectory: () async => support);
  });

  tearDown(() async {
    if (support.existsSync()) await support.delete(recursive: true);
  });

  Future<List<int>> fixture(String name) =>
      File('test/fixtures/$name').readAsBytes();

  test('importPemPair stages both PEM files under app support', () async {
    final config = await service.importPemPair(
      certificateBytes: await fixture('client-cert.pem'),
      privateKeyBytes: await fixture('client-key.pem'),
      label: 'fixture-client.pem',
    );

    expect(config.label, 'fixture-client.pem');
    expect(config.privateKeyPassword, isNull);
    expect(config.certificatePemPath, startsWith(support.path));
    expect(config.privateKeyPemPath, startsWith(support.path));
    expect(config.certificatePemPath, endsWith('certificate.pem'));
    expect(config.privateKeyPemPath, endsWith('private-key.pem'));
    expect(await service.isStaged(config), isTrue);
    expect(config.directoryPath, contains('.staging'));

    final certificateFile = File(config.certificatePemPath);
    final privateKeyFile = File(config.privateKeyPemPath);
    expect(certificateFile.existsSync(), isTrue);
    expect(privateKeyFile.existsSync(), isTrue);
    expect(
      await certificateFile.readAsString(),
      contains('-----BEGIN CERTIFICATE-----'),
    );
    expect(
      await privateKeyFile.readAsString(),
      contains('-----BEGIN PRIVATE KEY-----'),
    );
  });

  test('importPemPair drops a password for an unencrypted key', () async {
    final config = await service.importPemPair(
      certificateBytes: await fixture('client-cert.pem'),
      privateKeyBytes: await fixture('client-key.pem'),
      password: 'key-password',
      label: 'fixture-client.pem',
    );

    // Storing a password that nothing needs would be a needless secret.
    expect(config.privateKeyPassword, isNull);
  });

  test('importPemPair keeps the password for an encrypted key', () async {
    final config = await service.importPemPair(
      certificateBytes: await fixture('client-cert.pem'),
      privateKeyBytes: await fixture('client-key-encrypted.pem'),
      password: 'key-password',
      label: 'fixture-client.pem',
    );

    expect(config.privateKeyPassword, 'key-password');
  });

  test('commit moves a staged import into permanent storage', () async {
    final staged = await service.importPemPair(
      certificateBytes: await fixture('client-cert.pem'),
      privateKeyBytes: await fixture('client-key.pem'),
      label: 'fixture-client.pem',
    );
    final stagedDirectory = staged.directoryPath;

    final committed = await service.commit(staged);

    expect(await service.isStaged(committed), isFalse);
    expect(committed.directoryPath, isNot(stagedDirectory));
    expect(Directory(stagedDirectory).existsSync(), isFalse);
    expect(File(committed.certificatePemPath).existsSync(), isTrue);
    expect(File(committed.privateKeyPemPath).existsSync(), isTrue);
    // Committing twice is a no-op, not a second move.
    expect(await service.commit(committed), committed);
  });

  test(
    'discard removes a staged import and leaves committed ones alone',
    () async {
      final staged = await service.importPemPair(
        certificateBytes: await fixture('client-cert.pem'),
        privateKeyBytes: await fixture('client-key.pem'),
        label: 'staged',
      );
      await service.discard(staged);
      expect(File(staged.certificatePemPath).existsSync(), isFalse);

      final committed = await service.commit(
        await service.importPemPair(
          certificateBytes: await fixture('client-cert.pem'),
          privateKeyBytes: await fixture('client-key.pem'),
          label: 'committed',
        ),
      );
      await service.discard(committed);
      expect(File(committed.certificatePemPath).existsSync(), isTrue);
    },
  );

  test('deleteUnreferenced removes abandoned identities and staging', () async {
    final keep = await service.commit(
      await service.importPemPair(
        certificateBytes: await fixture('client-cert.pem'),
        privateKeyBytes: await fixture('client-key.pem'),
        label: 'keep',
      ),
    );
    final drop = await service.commit(
      await service.importPemPair(
        certificateBytes: await fixture('client-cert.pem'),
        privateKeyBytes: await fixture('client-key.pem'),
        label: 'drop',
      ),
    );
    final staged = await service.importPemPair(
      certificateBytes: await fixture('client-cert.pem'),
      privateKeyBytes: await fixture('client-key.pem'),
      label: 'abandoned',
    );

    await service.deleteUnreferenced([keep.directoryPath]);

    expect(File(keep.certificatePemPath).existsSync(), isTrue);
    expect(File(drop.certificatePemPath).existsSync(), isFalse);
    expect(File(staged.certificatePemPath).existsSync(), isFalse);
  });

  test('importPemPair rejects a non-PEM certificate', () async {
    await expectLater(
      service.importPemPair(
        certificateBytes: 'not a certificate'.codeUnits,
        privateKeyBytes: await fixture('client-key.pem'),
        label: 'broken.pem',
      ),
      throwsA(
        isA<ClientCertificateImportException>().having(
          (e) => e.message,
          'message',
          contains('not a PEM certificate'),
        ),
      ),
    );
  });

  test('importPkcs12 writes the leaf certificate plus its CA chain', () async {
    final config = await service.importPkcs12(
      bytes: await fixture('client-test.p12'),
      password: 'test-password',
      label: 'fixture-client.p12',
    );

    expect(config.label, 'fixture-client.p12');
    final certificatePem = await File(config.certificatePemPath).readAsString();
    final privateKeyPem = await File(config.privateKeyPemPath).readAsString();
    // The fixture contains a leaf certificate and its CA certificate.
    expect(
      '-----BEGIN CERTIFICATE-----'.allMatches(certificatePem),
      hasLength(2),
    );
    expect(certificatePem, startsWith('-----BEGIN CERTIFICATE-----'));
    expect(privateKeyPem, contains('-----BEGIN PRIVATE KEY-----'));
  });

  test('importPkcs12 does not retain the container password', () async {
    final config = await service.importPkcs12(
      bytes: await fixture('client-test.p12'),
      password: 'test-password',
      label: 'fixture-client.p12',
    );

    // The extracted key is unencrypted, so the container password has no
    // remaining use and must not be persisted.
    expect(config.privateKeyPassword, isNull);
  });

  test(
    'importPkcs12 reports a wrong password as a user-facing error',
    () async {
      await expectLater(
        service.importPkcs12(
          bytes: await fixture('client-test.p12'),
          password: 'wrong-password',
          label: 'fixture-client.p12',
        ),
        throwsA(
          isA<ClientCertificateImportException>().having(
            (e) => e.message,
            'message',
            contains('password is incorrect'),
          ),
        ),
      );
    },
  );

  test(
    'importPkcs12 reports an unreadable file as a user-facing error',
    () async {
      await expectLater(
        service.importPkcs12(
          bytes: 'not a p12'.codeUnits,
          password: null,
          label: 'broken.p12',
        ),
        throwsA(
          isA<ClientCertificateImportException>().having(
            (e) => e.message,
            'message',
            contains('not a readable PKCS#12'),
          ),
        ),
      );
    },
  );
}
