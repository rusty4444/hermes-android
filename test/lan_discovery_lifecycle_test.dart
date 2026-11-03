import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/lan_discovery_service.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;

class SilentClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}

void main() {
  testWidgets('sheet disposal cancels work and ignores late completion', (
    tester,
  ) async {
    final clients = <SilentClient>[];
    final service = LanDiscoveryService(
      resolveAddresses: () async => [InternetAddress('192.168.1.5')],
      concurrency: 2,
      clientFactory: () {
        final client = SilentClient();
        clients.add(client);
        return client;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LanDiscoverySheet(service: service)),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(clients, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(clients.every((c) => c.closed), isTrue);
    expect(clients, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  test(
    'selected HTTPS IPv6 endpoint remains valid through saved transports',
    () {
      const server = DiscoveredHermesServer(
        host: 'fd00::1234',
        port: 8642,
        useHttps: true,
        label: 'Hermes',
      );
      expect(server.connectionUrl, 'https://[fd00::1234]:8642');
      final normalized = SavedConnection.normalizeHostAndPort(
        server.connectionUrl,
        server.port,
      );
      expect(normalized.useHttps, isTrue);
      final conn = SavedConnection(
        id: 'test',
        label: 'test',
        host: normalized.host,
        port: normalized.port,
        useHttps: normalized.useHttps,
        apiKey: '',
      );
      expect(conn.baseUrl, server.connectionUrl);
      expect(Uri.parse(conn.baseUrl).host, 'fd00::1234');
      final dashboard = DashboardClient(
        host: normalized.host,
        port: normalized.port,
        useHttps: normalized.useHttps,
        httpClient: SilentClient(),
      );
      expect(dashboard.baseUrl, server.connectionUrl);
      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(conn),
        server.connectionUrl,
      );
    },
  );
}
