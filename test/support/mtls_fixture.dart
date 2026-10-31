import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes_android/core/models/client_certificate.dart';

const loopbackIdentity = ClientCertificateConfig(
  label: 'throwaway loopback identity',
  certificatePemPath: 'test/fixtures/mtls-client-cert.pem',
  privateKeyPemPath: 'test/fixtures/mtls-client-key.pem',
);

/// Adds only this fixture's CA, without bypassing certificate verification or
/// changing any global/default production trust context.
class _LoopbackTrust extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final isolated =
        context == null || identical(context, SecurityContext.defaultContext)
        ? SecurityContext(withTrustedRoots: true)
        : context;
    isolated.setTrustedCertificates('test/fixtures/mtls-ca-cert.pem');
    return super.createHttpClient(isolated);
  }
}

Future<T> withLoopbackTrust<T>(Future<T> Function() action) =>
    HttpOverrides.runWithHttpOverrides(action, _LoopbackTrust());

class _PlatformTrust extends HttpOverrides {}

/// Real sockets with unchanged platform trust, bypassing flutter_test's HTTP
/// mock without adding the fixture CA.
Future<T> withPlatformTrust<T>(Future<T> Function() action) =>
    HttpOverrides.runWithHttpOverrides(action, _PlatformTrust());

/// HTTP handlers run only after a verified client certificate is presented.
/// An anonymous client with valid server trust gets an explicit 403, so negative
/// tests cannot accidentally pass because the server's certificate was rejected.
class MutualTlsFixture {
  late final HttpServer server;
  final requests = <HttpRequest>[];
  final sockets = <WebSocket>[];
  final rpcRequests = <Map<String, dynamic>>[];
  int anonymousRequests = 0;

  Future<void> start(
    FutureOr<void> Function(HttpRequest request) answer,
  ) async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/mtls-server-cert.pem')
      ..usePrivateKey('test/fixtures/mtls-server-key.pem')
      ..setClientAuthorities('test/fixtures/mtls-ca-cert.pem')
      ..setTrustedCertificates('test/fixtures/mtls-ca-cert.pem');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
      requestClientCertificate: true,
    );
    server.listen((request) async {
      if (request.certificate == null) {
        anonymousRequests++;
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      requests.add(request);
      await answer(request);
    });
  }

  String get origin => 'https://127.0.0.1:${server.port}';

  void json(HttpRequest request, Object body) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
