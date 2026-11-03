import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';

/// The single certificate picker sniffs the picked bytes instead of asking
/// the user which format they hold: a PKCS#12 container, one PEM document
/// with both halves, or the certificate and key as separate files.
void main() {
  late Directory support;
  late ClientCertificateService service;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('hermes-identity-test');
    service = ClientCertificateService(supportDirectory: () async => support);
  });

  tearDown(() async {
    if (support.existsSync()) await support.delete(recursive: true);
  });

  Future<List<int>> fixture(String name) =>
      File('test/fixtures/$name').readAsBytes();

  test('a PKCS#12 container imports on its own', () async {
    final config = await service.importIdentityDocument(
      bytes: await fixture('client-test.p12'),
      password: 'test-password',
      label: 'fixture-client.p12',
    );

    expect(config, isNotNull);
    expect(config!.privateKeyPassword, isNull);
    expect(
      await File(config.certificatePemPath).readAsString(),
      contains('-----BEGIN CERTIFICATE-----'),
    );
    expect(
      await File(config.privateKeyPemPath).readAsString(),
      contains('-----BEGIN PRIVATE KEY-----'),
    );
  });

  test('a combined PEM document imports on its own', () async {
    final combined = [
      utf8.decode(await fixture('mtls-client-cert.pem')),
      utf8.decode(await fixture('mtls-client-key.pem')),
    ].join('\n');

    final config = await service.importIdentityDocument(
      bytes: utf8.encode(combined),
      label: 'combined.pem',
    );

    expect(config, isNotNull);
    expect(
      await File(config!.certificatePemPath).readAsString(),
      contains('-----BEGIN CERTIFICATE-----'),
    );
    expect(
      await File(config.privateKeyPemPath).readAsString(),
      contains('-----BEGIN PRIVATE KEY-----'),
    );
  });

  test('split PEM halves import across two picks in either order', () async {
    final certificateBytes = await fixture('mtls-client-cert.pem');
    final keyBytes = await fixture('mtls-client-key.pem');

    // Certificate first, then the key.
    final staged = await service.importIdentityDocument(
      bytes: certificateBytes,
      label: 'client-cert.pem',
    );
    expect(staged, isNull);
    final certFirst = await service.importIdentityDocument(
      bytes: keyBytes,
      label: 'client-key.pem',
      stagedCertificateBytes: certificateBytes,
      stagedCertificateName: 'client-cert.pem',
    );
    expect(certFirst, isNotNull);
    expect(certFirst!.label, 'client-cert.pem');

    // Key first, then the certificate.
    final stagedKey = await service.importIdentityDocument(
      bytes: keyBytes,
      label: 'client-key.pem',
    );
    expect(stagedKey, isNull);
    final keyFirst = await service.importIdentityDocument(
      bytes: certificateBytes,
      label: 'client-cert.pem',
      stagedPrivateKeyBytes: keyBytes,
    );
    expect(keyFirst, isNotNull);
    expect(keyFirst!.label, 'client-cert.pem');
    expect(
      await File(keyFirst.privateKeyPemPath).readAsString(),
      contains('-----BEGIN PRIVATE KEY-----'),
    );
  });

  test('a lone certificate stages while garbage is rejected', () async {
    final staged = await service.importIdentityDocument(
      bytes: await fixture('mtls-client-cert.pem'),
      label: 'client-cert.pem',
    );
    expect(staged, isNull);

    await expectLater(
      service.importIdentityDocument(
        bytes: utf8.encode('definitely not a certificate'),
        label: 'notes.txt',
      ),
      throwsA(
        isA<ClientCertificateImportException>().having(
          (e) => e.message,
          'message',
          contains('not a certificate'),
        ),
      ),
    );
  });

  test('a wrong PKCS#12 password still reports a wrong password', () async {
    await expectLater(
      service.importIdentityDocument(
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
  });

  // Picking the file first and typing the password second is the natural
  // order, so an empty password on a protected container must be reported as
  // "needs a password" (and retryable), not as a corrupt file.
  test(
    'an empty password on a protected PKCS#12 asks for the password',
    () async {
      await expectLater(
        service.importIdentityDocument(
          bytes: await fixture('client-test.p12'),
          password: '',
          label: 'fixture-client.p12',
        ),
        throwsA(
          isA<ClientCertificateImportException>()
              .having(
                (e) => e.message,
                'message',
                contains('needs its password'),
              )
              .having((e) => e.passwordRelated, 'passwordRelated', isTrue),
        ),
      );
    },
  );

  test('a wrong password is flagged as password-related', () async {
    await expectLater(
      service.importIdentityDocument(
        bytes: await fixture('client-test.p12'),
        password: 'wrong-password',
        label: 'fixture-client.p12',
      ),
      throwsA(
        isA<ClientCertificateImportException>().having(
          (e) => e.passwordRelated,
          'passwordRelated',
          isTrue,
        ),
      ),
    );
  });

  test('an unreadable file is not flagged as password-related', () async {
    await expectLater(
      service.importIdentityDocument(
        bytes: utf8.encode('not a certificate'),
        label: 'notes.txt',
      ),
      throwsA(
        isA<ClientCertificateImportException>().having(
          (e) => e.passwordRelated,
          'passwordRelated',
          isFalse,
        ),
      ),
    );
  });
}
