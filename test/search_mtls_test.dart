import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/ai_search_query_rewriter.dart';
import 'package:hermes_android/core/services/session_search_client.dart';
import 'package:hermes_android/core/services/tls_client_factory.dart';
import 'package:http/io_client.dart';

import 'support/mtls_fixture.dart';

/// A real loopback HTTPS server that only answers requests presenting a client
/// certificate signed by `mtls-ca-cert.pem`.
///
/// These tests exercise the production `TlsClientFactory` + `IOClient`
/// transport, not an injected mock: the point of the review finding was that
/// search built its own plain `http.Client()` and therefore silently omitted
/// the connection's TLS identity.
Future<HttpServer> _startMutualTlsServer({required String responseJson}) async {
  final context = SecurityContext()
    ..useCertificateChain('test/fixtures/mtls-server-cert.pem')
    ..usePrivateKey('test/fixtures/mtls-server-key.pem')
    // `setClientAuthorities` advertises the CA to the client; the same CA must
    // also be in the server's trust store to validate the presented chain.
    ..setClientAuthorities('test/fixtures/mtls-ca-cert.pem')
    ..setTrustedCertificates('test/fixtures/mtls-ca-cert.pem');
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
    requestClientCertificate: true,
  );
  server.listen((request) async {
    if (request.certificate == null) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(responseJson);
    await request.response.close();
  });
  return server;
}

TlsClientFactory _factoryTrustingServer() => const TlsClientFactory(
  trustedCertificatePaths: <String>['test/fixtures/mtls-ca-cert.pem'],
);

ClientCertificateConfig _clientCertificate() => const ClientCertificateConfig(
  label: 'fixture',
  certificatePemPath: 'test/fixtures/mtls-client-cert.pem',
  privateKeyPemPath: 'test/fixtures/mtls-client-key.pem',
);

void main() {
  test(
    'SessionSearchClient performs a certificate-enforcing mTLS request',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await _startMutualTlsServer(
        responseJson: jsonEncode({'results': []}),
      );
      try {
        final client = SessionSearchClient(
          baseUrl: 'https://127.0.0.1:${server.port}',
          headers: () async => const {'Cookie': 'session=abc'},
          clientCertificate: _clientCertificate(),
          tlsClientFactory: _factoryTrustingServer(),
        );
        addTearDown(client.close);

        // Succeeds only because the configured identity was presented.
        expect(await client.search('tls'), isEmpty);
      } finally {
        HttpOverrides.global = savedOverrides;
        await server.close(force: true);
      }
    },
  );

  test(
    'SessionSearchClient without the identity is rejected by the server',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await _startMutualTlsServer(
        responseJson: jsonEncode({'results': []}),
      );
      try {
        final context = SecurityContext(withTrustedRoots: true)
          ..setTrustedCertificates('test/fixtures/mtls-ca-cert.pem');
        final anonymous = IOClient(HttpClient(context: context));
        addTearDown(anonymous.close);
        final client = SessionSearchClient(
          baseUrl: 'https://127.0.0.1:${server.port}',
          headers: () async => const {},
          httpClient: anonymous,
        );

        await expectLater(
          client.search('tls'),
          throwsA(
            isA<SessionSearchException>().having(
              (e) => e.message,
              'message',
              contains('dashboard rejected'),
            ),
          ),
        );
      } finally {
        HttpOverrides.global = savedOverrides;
        await server.close(force: true);
      }
    },
  );

  test(
    'AiSearchQueryRewriter performs a certificate-enforcing mTLS request',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await _startMutualTlsServer(
        responseJson: jsonEncode({'query': 'rewritten query'}),
      );
      try {
        final client = AiSearchQueryRewriter(
          baseUrl: 'https://127.0.0.1:${server.port}',
          apiKey: 'key',
          clientCertificate: _clientCertificate(),
          tlsClientFactory: _factoryTrustingServer(),
        );
        addTearDown(client.close);

        expect(
          await client.rewrite(query: 'a question', provider: 'p', model: 'm'),
          'rewritten query',
        );
      } finally {
        HttpOverrides.global = savedOverrides;
        await server.close(force: true);
      }
    },
  );

  test('anonymous rewriting is rejected after server trust succeeds', () async {
    final fixture = MutualTlsFixture();
    await fixture.start((request) async {
      fixture.json(request, {'query': 'rewritten query'});
      await request.response.close();
    });
    addTearDown(fixture.close);
    await withLoopbackTrust(() async {
      final client = AiSearchQueryRewriter(
        baseUrl: fixture.origin,
        apiKey: 'fixture',
      );
      addTearDown(client.close);
      await expectLater(
        client.rewrite(query: 'question', provider: 'p', model: 'm'),
        throwsA(isA<AiSearchRewriteException>()),
      );
      expect(fixture.anonymousRequests, 1);
      expect(fixture.requests, isEmpty);
    });
  });

  test(
    'production server trust still rejects the untrusted fixture CA',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async => request.response.close());
      addTearDown(fixture.close);
      await withPlatformTrust(() async {
        final client = const TlsClientFactory().createRestClient(
          loopbackIdentity,
        );
        addTearDown(client.close);
        await expectLater(
          client.get(Uri.parse(fixture.origin)),
          throwsA(
            predicate(
              (e) => e.toString().contains('CERTIFICATE_VERIFY_FAILED'),
            ),
          ),
        );
        expect(fixture.requests, isEmpty);
        expect(fixture.anonymousRequests, 0);
      });
    },
  );

  test(
    'explicit fixture CA trust does not bypass hostname verification',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async => request.response.close());
      addTearDown(fixture.close);
      await withLoopbackTrust(() async {
        final client = const TlsClientFactory().createRestClient(
          loopbackIdentity,
        );
        addTearDown(client.close);
        await expectLater(
          client.get(Uri.parse('https://localhost:${fixture.server.port}')),
          throwsA(
            predicate(
              (e) => e.toString().contains('CERTIFICATE_VERIFY_FAILED'),
            ),
          ),
        );
        expect(fixture.requests, isEmpty);
        expect(fixture.anonymousRequests, 0);
      });
    },
  );
}
