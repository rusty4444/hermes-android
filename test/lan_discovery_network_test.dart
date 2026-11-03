import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/lan_discovery_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// Map only synthetic private candidates to a disposable loopback listener.
// Real IOClient trust/stream/redirect behaviour remains intact; no LAN scan.
class LoopbackClient extends http.BaseClient {
  LoopbackClient(this.port, this.paths);
  final int port;
  final List<String> paths;
  final inner = IOClient();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    paths.add(request.url.path);
    return inner.send(
      http.Request(
          request.method,
          request.url.replace(host: '127.0.0.1', port: port),
        )
        ..followRedirects = request.followRedirects
        ..headers.addAll(request.headers),
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'real HTTP listener receives /health and Hermes contract is discovered',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final receivedPaths = <String>[];
      final subscription = server.listen((request) async {
        receivedPaths.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"status":"ok","platform":"hermes-agent","version":"fixture"}',
        );
        await request.response.close();
      });
      try {
        final service = LanDiscoveryService(
          maxHosts: 1,
          resolveAddresses: () async => [InternetAddress('192.168.1.5')],
          clientFactory: () => LoopbackClient(server.port, paths),
        );
        final result = await service.discover();
        expect(result.single.host, '192.168.1.1');
        expect(result.single.useHttps, isFalse);
        expect(paths, ['/health']);
        expect(receivedPaths, ['/health']);
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );

  test(
    'real TLS listener with untrusted fixture certificate is NOT discovered',
    () async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/mtls-server-cert.pem')
        ..usePrivateKey('test/fixtures/mtls-server-key.pem');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      var acceptedHttp = 0;
      final subscription = server.listen((request) async {
        acceptedHttp++;
        request.response.write('{"status":"ok","platform":"hermes-agent"}');
        await request.response.close();
      }, onError: (Object _) {});
      try {
        final paths = <String>[];
        final service = LanDiscoveryService(
          maxHosts: 1,
          resolveAddresses: () async => [InternetAddress('192.168.1.5')],
          clientFactory: () => LoopbackClient(server.port, paths),
        );
        expect(await service.discover(), isEmpty);
        expect(paths, ['/health', '/health']);
        expect(acceptedHttp, 0);
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );
}
