import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/tls_client_factory.dart';

void main() {
  late Directory support;
  late ClientCertificateService service;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('pem-import-regression-');
    service = ClientCertificateService(supportDirectory: () async => support);
  });
  tearDown(() async => support.delete(recursive: true));

  List<int> fixture(String name) =>
      File('test/fixtures/$name').readAsBytesSync();
  final retryable = throwsA(
    isA<ClientCertificateImportException>().having(
      (e) => e.passwordRelated,
      'passwordRelated',
      isTrue,
    ),
  );

  for (final key in [
    (
      name: 'client-key-encrypted.pem',
      cert: 'client-cert.pem',
      phrase: 'key-password',
    ),
    (
      name: 'mtls-client-key-traditional.pem',
      cert: 'mtls-client-cert.pem',
      phrase: ' exact fixture password\t ',
    ),
    (
      name: 'mtls-client-key-whitespace.pem',
      cert: 'mtls-client-cert.pem',
      phrase: '  key password \t',
    ),
  ]) {
    for (final mode in ['combined', 'certificate-first', 'key-first', 'pair']) {
      test(
        '${key.name} $mode prompts and retries the exact password',
        () async {
          final cert = fixture(key.cert);
          final privateKey = fixture(key.name);
          Future<ClientCertificateConfig?> attempt(String? password) {
            if (mode == 'pair') {
              return service.importPemPair(
                certificateBytes: cert,
                privateKeyBytes: privateKey,
                password: password,
                label: 'pair',
              );
            }
            return service.importIdentityDocument(
              bytes: mode == 'combined'
                  ? [...cert, 10, ...privateKey]
                  : mode == 'certificate-first'
                  ? privateKey
                  : cert,
              stagedCertificateBytes: mode == 'certificate-first' ? cert : null,
              stagedPrivateKeyBytes: mode == 'key-first' ? privateKey : null,
              password: password,
              label: mode,
            );
          }

          if (mode != 'combined' && mode != 'pair') {
            expect(
              await service.importIdentityDocument(
                bytes: mode == 'certificate-first' ? cert : privateKey,
                label: 'first half',
              ),
              isNull,
            );
          }
          await expectLater(attempt(null), retryable);
          await expectLater(attempt('wrong'), retryable);
          if (key.phrase != key.phrase.trim()) {
            await expectLater(attempt(key.phrase.trim()), retryable);
          }
          // Failed attempts must not leave any private key on disk.
          expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
          final config = (await attempt(key.phrase))!;
          expect(config.privateKeyPassword, key.phrase);
          expect(
            const TlsClientFactory().securityContextFor(config),
            isNotNull,
          );
        },
      );
    }
  }

  for (final mode in ['combined', 'certificate-first', 'key-first']) {
    test('$mode preserves every certificate and a parseable chain', () async {
      final leaf = utf8.decode(fixture('mtls-client-cert.pem')).trim();
      final ca = utf8.decode(fixture('mtls-ca-cert.pem')).trim();
      final cert = utf8.encode('$leaf\n$ca');
      final key = fixture('mtls-client-key.pem');
      final config = (await service.importIdentityDocument(
        bytes: mode == 'combined'
            ? [...cert, 10, ...key]
            : mode == 'certificate-first'
            ? key
            : cert,
        stagedCertificateBytes: mode == 'certificate-first' ? cert : null,
        stagedPrivateKeyBytes: mode == 'key-first' ? key : null,
        label: mode,
      ))!;
      expect(
        await File(config.certificatePemPath).readAsString(),
        '$leaf\n$ca',
      );
      expect(const TlsClientFactory().securityContextFor(config), isNotNull);
    });
  }

  test(
    'successful retry remains owned until cancellation releases its files',
    () async {
      final owner = ClientCertificateFileLease();
      final config = await owner.run(
        () => service.importPemPair(
          certificateBytes: fixture('mtls-client-cert.pem'),
          privateKeyBytes: fixture('mtls-client-key-traditional.pem'),
          password: ' exact fixture password\t ',
          label: 'owned retry',
        ),
      );
      final collector = ClientCertificateService(
        supportDirectory: () async => support,
      );
      await collector.cleanupStaging();
      expect(File(config.privateKeyPemPath).existsSync(), isTrue);
      await owner.close();
      await collector.cleanupStaging();
      expect(File(config.privateKeyPemPath).existsSync(), isFalse);
    },
  );
}
