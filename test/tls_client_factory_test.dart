import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/tls_client_factory.dart';

void main() {
  const factory = TlsClientFactory();

  const validConfig = ClientCertificateConfig(
    label: 'fixture',
    certificatePemPath: 'test/fixtures/client-cert.pem',
    privateKeyPemPath: 'test/fixtures/client-key.pem',
  );

  test('disabled certificate leaves the platform trust context in place', () {
    final seenContexts = <SecurityContext>[];
    final factory = TlsClientFactory(
      httpClientBuilder: (context) {
        seenContexts.add(context);
        return HttpClient();
      },
    );

    expect(factory.securityContextFor(null), isNull);

    final client = factory.createHttpClient(null);
    addTearDown(client.close);
    expect(seenContexts, hasLength(1));
    expect(seenContexts.single, same(SecurityContext.defaultContext));
    expect(client.idleTimeout, Duration.zero);
  });

  test('enabled certificate produces a context used by the HTTP client', () {
    final seenContexts = <SecurityContext>[];
    final factory = TlsClientFactory(
      httpClientBuilder: (context) {
        seenContexts.add(context);
        return HttpClient();
      },
    );

    final context = factory.securityContextFor(validConfig);
    expect(context, isNotNull);
    expect(context, isNot(same(SecurityContext.defaultContext)));

    final client = factory.createHttpClient(validConfig);
    addTearDown(client.close);
    expect(seenContexts, hasLength(1));
    expect(seenContexts.single, isNot(same(SecurityContext.defaultContext)));
    expect(client.idleTimeout, Duration.zero);
  });

  test('a missing key path throws instead of falling back', () {
    const broken = ClientCertificateConfig(
      label: 'broken',
      certificatePemPath: 'test/fixtures/client-cert.pem',
      privateKeyPemPath: 'test/fixtures/does-not-exist.pem',
    );

    expect(
      () => factory.securityContextFor(broken),
      throwsA(isA<TlsClientConfigurationException>()),
    );
    expect(
      () => factory.createHttpClient(broken),
      throwsA(isA<TlsClientConfigurationException>()),
    );
    expect(
      () => factory.createRestClient(broken),
      throwsA(isA<TlsClientConfigurationException>()),
    );
  });

  test('a missing certificate chain path throws instead of falling back', () {
    const broken = ClientCertificateConfig(
      label: 'broken',
      certificatePemPath: 'test/fixtures/does-not-exist.pem',
      privateKeyPemPath: 'test/fixtures/client-key.pem',
    );

    expect(
      () => factory.securityContextFor(broken),
      throwsA(isA<TlsClientConfigurationException>()),
    );
  });
}
