// Keepalive contract tests: the Android client must hold the Desktop
// gateway socket open without user interaction, mirroring the desktop
// client's heartbeat (apps/shared/src/json-rpc-channel.ts) which the
// gateway answers on its WS reader thread (tui_gateway/ws.py
// `gateway.ping`). Lives in its own file because real local WS traffic
// cannot share a suite with TestWidgetsFlutterBinding (see
// desktop_gateway_auto_title_bridge_test.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';

const _fixtureKey = 'fixture-key';

void main() {
  test('WsClient sends gateway.ping heartbeats on the interval', () async {
    final gateway = await _KeepAliveFakeGateway.start();
    addTearDown(gateway.stop);
    final client = WsClient(
      'http://127.0.0.1:${gateway.port}',
      token: _fixtureKey,
      heartbeatInterval: const Duration(milliseconds: 100),
      heartbeatDeadline: const Duration(seconds: 5),
    );
    addTearDown(client.close);
    await client.connect().timeout(const Duration(seconds: 5));

    await _waitFor(() => gateway.pingCount >= 2, timeout: const Duration(seconds: 3));
    expect(client.isConnected, isTrue);
    // Heartbeats must not leak into the request-response pending map: a
    // normal RPC still completes normally while pings flow.
    final response = await client
        .send('session.resume', {'session_id': 'x'})
        .timeout(const Duration(seconds: 2));
    expect(response['error'], isNull);
  });

  test('WsClient tears down a half-open socket at the deadline', () async {
    final gateway = await _KeepAliveFakeGateway.start();
    addTearDown(gateway.stop);
    final client = WsClient(
      'http://127.0.0.1:${gateway.port}',
      token: _fixtureKey,
      heartbeatInterval: const Duration(milliseconds: 100),
      heartbeatDeadline: const Duration(milliseconds: 400),
    );
    addTearDown(client.close);
    await client.connect().timeout(const Duration(seconds: 5));
    await _waitFor(() => gateway.pingCount >= 1, timeout: const Duration(seconds: 2));

    // Simulate the half-open case: the gateway stops answering anything.
    gateway.silencePings = true;
    await _waitFor(() => !client.isConnected, timeout: const Duration(seconds: 3));
    expect(client.isConnected, isFalse);
  });

  test('DesktopGatewayClient auto-reconnects after the socket drops', () async {
    final gateway = await _KeepAliveFakeGateway.start();
    addTearDown(gateway.stop);
    final client = DesktopGatewayClient.fromConnection(
      SavedConnection(
        id: 'conn-keepalive',
        label: 'Local fake',
        // Distinct host alias: a same-host override falls back to the
        // dashboard port and bypasses the fake entirely.
        host: 'localhost',
        port: gateway.port,
        apiKey: _fixtureKey,
        useHttps: false,
        desktopGatewayUrl: 'http://127.0.0.1:${gateway.port}',
        dashboardUsername: 'u',
        dashboardPassword: 'p',
      ),
    );
    addTearDown(client.close);

    await client.ensureSession('mob-ka');
    expect(gateway.connectionCount, 1);

    // Server drops the socket (gateway restart / NAT eviction).
    await gateway.dropSocket();

    // The client must reopen WITHOUT any explicit call from the UI.
    await _waitFor(() => gateway.connectionCount >= 2, timeout: const Duration(seconds: 8));

    // Rebind-on-reconnect: the fresh socket must resume the stored key
    // proactively — no explicit call — so a reply that completed detached
    // during the outage is addressable immediately.
    await _waitFor(
      () => gateway.resumedStoredIds.contains('stored-ka-1'),
      timeout: const Duration(seconds: 5),
    );

    // And the stored session binding must survive: the next use resumes
    // the same stored key rather than minting a fresh session.
    await client.ensureSession('mob-ka');
    expect(gateway.resumedStoredIds, contains('stored-ka-1'));
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _KeepAliveFakeGateway {
  _KeepAliveFakeGateway(this._server);

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  int pingCount = 0;
  int connectionCount = 0;
  bool silencePings = false;
  final List<String> resumedStoredIds = [];

  int get port => _server.port;

  static Future<_KeepAliveFakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gw = _KeepAliveFakeGateway(server);
    server.listen((httpReq) async {
      if (httpReq.method == 'POST' &&
          httpReq.uri.path == '/auth/password-login') {
        httpReq.response
          ..statusCode = 200
          ..headers.set('set-cookie', 'hermes_session_at=TOK123; Path=/')
          ..write('{"ok":true}');
        await httpReq.response.close();
        return;
      }
      if (httpReq.method == 'POST' &&
          httpReq.uri.path == '/api/auth/ws-ticket') {
        httpReq.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"ticket":"TICKET-1"}');
        await httpReq.response.close();
        return;
      }
      if (httpReq.uri.path == '/api/ws') {
        final socket = await WebSocketTransformer.upgrade(httpReq);
        gw._sockets.add(socket);
        gw.connectionCount++;
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {'type': 'gateway.ready', 'payload': {}},
          }),
        );
        socket.listen((raw) {
          final request = jsonDecode(raw as String) as Map<String, dynamic>;
          final id = request['id'];
          final method = request['method'];
          if (method == 'gateway.ping') {
            gw.pingCount++;
            if (!gw.silencePings) {
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': id,
                  'result': {'ok': true},
                }),
              );
            }
            return;
          }
          switch (method) {
            case 'session.resume':
              final requested =
                  (request['params']?['session_id'] ?? '').toString();
              gw.resumedStoredIds.add(requested);
              if (requested == 'mob-ka') {
                // First touch: the mobile id is not a stored key yet —
                // exactly the new-chat path that mints stored-ka-1 below.
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': id,
                    'error': {
                      'code': 4007,
                      'message': 'session not found',
                    },
                  }),
                );
              } else {
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': id,
                    'result': {'session_id': 'gw-runtime-1'},
                  }),
                );
              }
            case 'session.create':
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': id,
                  'result': {
                    'session_id': 'gw-runtime-1',
                    'stored_session_id': 'stored-ka-1',
                  },
                }),
              );
            default:
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': id,
                  'error': {'code': 1, 'message': 'not needed for this test'},
                }),
              );
          }
        });
        return;
      }
      httpReq.response.statusCode = 404;
      await httpReq.response.close();
    });
    return gw;
  }

  Future<void> dropSocket() async {
    final sockets = List<WebSocket>.from(_sockets);
    _sockets.clear();
    for (final ws in sockets) {
      await ws.close(WebSocketStatus.goingAway, 'fixture drop');
    }
  }

  Future<void> stop() async {
    for (final ws in _sockets) {
      await ws.close();
    }
    _sockets.clear();
    await _server.close(force: true);
  }
}
