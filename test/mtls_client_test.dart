import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mtls_client.dart';

class _FakeMtlsTransport implements MtlsTransport, MtlsWebSocketTransport {
  final StreamController<MtlsResponseEvent> controller =
      StreamController<MtlsResponseEvent>.broadcast();
  final List<MtlsRequest> requests = [];
  final List<String> cancelled = [];
  bool autoComplete = true;
  bool autoRespondWebSocket = false;
  bool emitWebSocketClose = true;
  Completer<MtlsResponseHead>? delayedResponseHead;
  Completer<void>? delayedWebSocketStart;
  String Function(MtlsRequest request)? responseBodyForRequest;
  String? webSocketId;
  String? webSocketAlias;
  Uri? webSocketUrl;
  final List<String> webSocketMessages = [];
  int webSocketStarts = 0;
  bool webSocketClosed = false;

  @override
  Stream<MtlsResponseEvent> get events => controller.stream;

  @override
  Future<bool> cancelRequest(String requestId) async {
    cancelled.add(requestId);
    final delayed = delayedResponseHead;
    if (delayed != null && !delayed.isCompleted) {
      delayed.completeError(StateError('cancelled'));
    }
    return true;
  }

  @override
  Future<MtlsCertificate?> chooseCertificate({
    String? host,
    int? port,
    String? alias,
  }) async {
    return const MtlsCertificate(alias: 'chosen', label: 'Chosen certificate');
  }

  @override
  Future<MtlsCertificate?> describeCertificate(String alias) async {
    return MtlsCertificate(alias: alias, label: 'Remembered certificate');
  }

  @override
  Future<MtlsResponseHead> startRequest(MtlsRequest request) async {
    requests.add(request);
    final delayed = delayedResponseHead;
    if (delayed != null) return delayed.future;
    if (autoComplete) {
      final responseBody =
          responseBodyForRequest?.call(request) ?? '{"ok":true}';
      scheduleMicrotask(() {
        controller.add(
          MtlsDataEvent(
            request.requestId,
            Uint8List.fromList(utf8.encode(responseBody)),
          ),
        );
        controller.add(MtlsDoneEvent(request.requestId));
      });
    }
    return const MtlsResponseHead(
      statusCode: 200,
      reasonPhrase: 'OK',
      contentLength: null,
      headers: {'content-type': 'application/json'},
    );
  }

  @override
  Future<void> startWebSocket({
    required String socketId,
    required String alias,
    required Uri url,
  }) async {
    webSocketId = socketId;
    webSocketAlias = alias;
    webSocketUrl = url;
    webSocketStarts++;
    final delayed = delayedWebSocketStart;
    if (delayed != null) await delayed.future;
    if (autoRespondWebSocket) {
      scheduleMicrotask(() {
        controller.add(
          MtlsWebSocketDataEvent(
            socketId,
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'gateway.ready',
                'data': {'methods': <String>[]},
              },
            }),
          ),
        );
      });
    }
  }

  @override
  Future<void> sendWebSocket({
    required String socketId,
    required String data,
  }) async {
    webSocketMessages.add(data);
    if (autoRespondWebSocket) {
      final request = jsonDecode(data) as Map<String, dynamic>;
      scheduleMicrotask(() {
        controller.add(
          MtlsWebSocketDataEvent(
            socketId,
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'session_id':
                    (request['params'] as Map<String, dynamic>)['session_id'],
              },
            }),
          ),
        );
      });
    }
  }

  @override
  Future<void> closeWebSocket({
    required String socketId,
    int code = 1000,
    String reason = '',
  }) async {
    webSocketClosed = true;
    if (emitWebSocketClose) {
      scheduleMicrotask(() {
        controller.add(
          MtlsWebSocketClosedEvent(socketId, code: code, reason: reason),
        );
      });
    }
  }

  Future<void> dispose() => controller.close();
}

SavedConnection _connection({
  bool mtlsEnabled = true,
  String? alias = 'client-cert',
}) {
  return SavedConnection(
    id: 'connection-id',
    label: 'Gateway',
    host: 'gateway.example.com',
    port: 443,
    apiKey: 'synthetic-api-key',
    useHttps: true,
    mtlsEnabled: mtlsEnabled,
    mtlsCertificateAlias: alias,
  );
}

String? _header(Map<String, String> headers, String name) {
  final lowerName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerName) return entry.value;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('waits for the native event stream before starting a request', () async {
    const channel = MethodChannel('com.hermesagent.hermes_android/mtls');
    final calls = <String>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'startRequest') {
            return <String, Object?>{
              'statusCode': 200,
              'reasonPhrase': 'OK',
              'contentLength': 0,
              'headers': <String, String>{},
            };
          }
          return null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await MethodChannelMtlsTransport.instance.startRequest(
      MtlsRequest(
        requestId: 'request-id',
        alias: 'client-cert',
        method: 'GET',
        url: Uri.parse('https://gateway.example.com/api/sessions'),
        headers: const {},
        body: null,
      ),
    );

    expect(calls, ['waitUntilEventStreamReady', 'startRequest']);
  });

  test('factory routes enabled connections through native mTLS transport', () {
    final transport = _FakeMtlsTransport();
    addTearDown(transport.dispose);

    final enabled = GatewayHttpClientFactory.create(
      _connection(),
      mtlsTransport: transport,
    );
    final disabled = GatewayHttpClientFactory.create(
      _connection(mtlsEnabled: false, alias: null),
      mtlsTransport: transport,
    );

    expect(enabled, isA<MtlsHttpClient>());
    expect(disabled, isNot(isA<MtlsHttpClient>()));
    enabled.close();
    disabled.close();
  });

  test('Gateway API keys are rejected over cleartext HTTP', () {
    final connection = _connection(
      mtlsEnabled: false,
      alias: null,
    ).copyWith(useHttps: false, port: 80);

    expect(() => ApiClient.fromConnection(connection), throwsArgumentError);
  });

  test('unauthenticated Gateway connections may use local HTTP', () {
    final connection = _connection(
      mtlsEnabled: false,
      alias: null,
    ).copyWith(host: '127.0.0.1', port: 8642, apiKey: '', useHttps: false);

    final client = ApiClient.fromConnection(connection);
    client.close();
  });

  test('dashboard password authentication is rejected over HTTP', () {
    final connection = _connection(mtlsEnabled: false, alias: null).copyWith(
      dashboardUrl: 'http://dashboard.example.com:9119',
      dashboardUsername: 'user',
      dashboardPassword: 'password',
    );

    expect(
      () => DashboardClient.fromConnection(connection),
      throwsArgumentError,
    );
  });

  test('open dashboards may use local HTTP', () {
    final connection = _connection(mtlsEnabled: false, alias: null).copyWith(
      dashboardUrl: 'http://127.0.0.1:9119',
      clearDashboardUsername: true,
      clearDashboardPassword: true,
    );

    final client = DashboardClient.fromConnection(connection);
    client.close();
  });

  test(
    'forwards API key, request body, and streamed native response',
    () async {
      final transport = _FakeMtlsTransport();
      addTearDown(transport.dispose);
      final client = ApiClient.fromConnection(
        _connection(),
        mtlsTransport: transport,
      );
      addTearDown(client.close);

      final response = await client.apiPost(
        'api/example',
        body: {'message': 'hello'},
      );

      expect(response, {'ok': true});
      expect(transport.requests, hasLength(1));
      final request = transport.requests.single;
      expect(request.alias, 'client-cert');
      expect(
        request.url,
        Uri.parse('https://gateway.example.com:443/api/example'),
      );
      expect(
        _header(request.headers, 'Authorization'),
        contains('synthetic-api-key'),
      );
      expect(utf8.decode(request.body!), contains('"message":"hello"'));
    },
  );

  test('routes a separate dashboard URL through native mTLS', () async {
    final transport = _FakeMtlsTransport();
    final connection = _connection().copyWith(
      dashboardUrl: 'https://dashboard.example.com:8443',
      dashboardProxied: true,
    );
    final client = DashboardClient.fromConnection(
      connection,
      mtlsTransport: transport,
    );
    addTearDown(() async {
      client.close();
      await Future<void>.delayed(Duration.zero);
      await transport.dispose();
    });

    expect(await client.getModelInfo(), {'ok': true});
    expect(transport.requests, hasLength(1));
    expect(
      transport.requests.single.url,
      Uri.parse('https://dashboard.example.com:8443/api/model/info'),
    );
    expect(transport.requests.single.alias, 'client-cert');
  });

  test('combines a separate dashboard URL and port for native mTLS', () async {
    final transport = _FakeMtlsTransport();
    addTearDown(transport.dispose);
    final connection = _connection().copyWith(
      dashboardUrl: 'https://dashboard.example.com',
      dashboardPortOverride: 42848,
      dashboardProxied: true,
    );
    final client = DashboardClient.fromConnection(
      connection,
      mtlsTransport: transport,
    );
    addTearDown(client.close);

    expect(await client.getModelInfo(), {'ok': true});
    expect(
      transport.requests.single.url,
      Uri.parse('https://dashboard.example.com:42848/api/model/info'),
    );
    expect(transport.requests.single.alias, 'client-cert');
  });

  test('sends and receives Desktop Gateway WebSocket data with mTLS', () async {
    final transport = _FakeMtlsTransport();
    addTearDown(transport.dispose);
    final channel = MtlsWebSocketChannel.connect(
      Uri.parse('wss://desktop.example.com:42848/api/ws?ticket=one-use'),
      alias: 'client-cert',
      transport: transport,
    );

    await channel.ready;
    expect(transport.webSocketAlias, 'client-cert');
    expect(
      transport.webSocketUrl,
      Uri.parse('wss://desktop.example.com:42848/api/ws?ticket=one-use'),
    );

    await channel.sink.addStream(Stream.value('{"jsonrpc":"2.0"}'));
    expect(transport.webSocketMessages, ['{"jsonrpc":"2.0"}']);

    final response = channel.stream.first;
    transport.controller.add(
      MtlsWebSocketDataEvent(transport.webSocketId!, '{"result":"ok"}'),
    );
    expect(await response, '{"result":"ok"}');

    final closed = channel.sink.close();
    await closed;
    expect(transport.webSocketClosed, isTrue);
  });

  test(
    'closing an mTLS WebSocket does not wait for a stalled connect',
    () async {
      final delayedStart = Completer<void>();
      final transport = _FakeMtlsTransport()
        ..delayedWebSocketStart = delayedStart
        ..emitWebSocketClose = false;
      addTearDown(transport.dispose);
      final channel = MtlsWebSocketChannel.connect(
        Uri.parse('wss://desktop.example.com:42848/api/ws'),
        alias: 'client-cert',
        transport: transport,
      );
      channel.ready.ignore();
      while (transport.webSocketId == null) {
        await Future<void>.delayed(Duration.zero);
      }

      await channel.sink.close().timeout(const Duration(seconds: 1));

      expect(transport.webSocketClosed, isTrue);
      delayedStart.complete();
    },
  );

  test('open Desktop Gateway uses its SPA token with native mTLS', () async {
    final transport = _FakeMtlsTransport()
      ..autoRespondWebSocket = true
      ..responseBodyForRequest = (_) =>
          '<script>window.__HERMES_SESSION_TOKEN__="spa-token";</script>';
    final connection = _connection().copyWith(
      desktopGatewayUrl: 'https://desktop.example.com:42848',
    );
    final client = DesktopGatewayClient.fromConnection(
      connection,
      mtlsTransport: transport,
      mtlsWebSocketTransport: transport,
    );
    addTearDown(() async {
      client.close();
      await Future<void>.delayed(Duration.zero);
      await transport.dispose();
    });

    await client.ensureSession('mobile-session');

    expect(transport.requests, hasLength(1));
    expect(
      transport.requests.single.url,
      Uri.parse('https://desktop.example.com:42848/'),
    );
    expect(transport.requests.single.alias, 'client-cert');
    expect(
      transport.webSocketUrl,
      Uri.parse('wss://desktop.example.com:42848/api/ws?token=spa-token'),
    );
    expect(transport.webSocketAlias, 'client-cert');
  });

  test(
    'routes Desktop Gateway ticket and socket through native mTLS',
    () async {
      final transport = _FakeMtlsTransport()
        ..autoRespondWebSocket = true
        ..responseBodyForRequest = (request) {
          if (request.url.path.endsWith('/api/auth/ws-ticket')) {
            return '{"ticket":"one-use"}';
          }
          return '{"ok":true}';
        };
      final connection = _connection().copyWith(
        desktopGatewayUrl: 'https://desktop.example.com:42848',
        dashboardProxied: true,
      );
      final client = DesktopGatewayClient.fromConnection(
        connection,
        mtlsTransport: transport,
        mtlsWebSocketTransport: transport,
      );
      addTearDown(() async {
        client.close();
        await Future<void>.delayed(Duration.zero);
        await transport.dispose();
      });

      await Future.wait([
        client.ensureSession('mobile-session'),
        client.ensureSession('second-session'),
      ]);

      expect(transport.requests, hasLength(1));
      expect(transport.webSocketStarts, 1);
      expect(
        transport.requests.single.url,
        Uri.parse('https://desktop.example.com:42848/api/auth/ws-ticket'),
      );
      expect(transport.requests.single.alias, 'client-cert');
      expect(
        transport.webSocketUrl,
        Uri.parse('wss://desktop.example.com:42848/api/ws?ticket=one-use'),
      );
      expect(transport.webSocketAlias, 'client-cert');
      expect(transport.webSocketMessages, hasLength(2));
      expect(
        transport.webSocketMessages.map(
          (message) => jsonDecode(message)['method'],
        ),
        everyElement('session.resume'),
      );
    },
  );

  test('closing Desktop Gateway during connect cannot resurrect it', () async {
    final transport = _FakeMtlsTransport()
      ..delayedResponseHead = Completer<MtlsResponseHead>();
    final connection = _connection().copyWith(
      desktopGatewayUrl: 'https://desktop.example.com:42848',
      dashboardProxied: true,
    );
    final client = DesktopGatewayClient.fromConnection(
      connection,
      mtlsTransport: transport,
      mtlsWebSocketTransport: transport,
    );
    final connecting = client.ensureSession('mobile-session');
    while (transport.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }

    client.close();

    await expectLater(connecting, throwsA(anything));
    expect(transport.webSocketStarts, 0);
    await transport.dispose();
  });

  test('Desktop Gateway rejects a cleartext URL without mTLS', () {
    final connection = _connection(
      mtlsEnabled: false,
      alias: null,
    ).copyWith(desktopGatewayUrl: 'http://desktop.example.com:42848');

    expect(
      () => DesktopGatewayClient.fromConnection(connection),
      throwsArgumentError,
    );
  });

  test('rejects cleartext requests before invoking native transport', () async {
    final transport = _FakeMtlsTransport();
    addTearDown(transport.dispose);
    final client = MtlsHttpClient(alias: 'client-cert', transport: transport);
    addTearDown(client.close);

    await expectLater(
      client.get(Uri.parse('http://gateway.example.com/health')),
      throwsArgumentError,
    );
    expect(transport.requests, isEmpty);
  });

  test('cancelling an SSE response cancels the native request', () async {
    final transport = _FakeMtlsTransport()..autoComplete = false;
    addTearDown(transport.dispose);
    final api = ApiClient.fromConnection(
      _connection(),
      mtlsTransport: transport,
    );
    final gateway = GatewayChatClient(api);
    addTearDown(gateway.abort);

    final sending = gateway.sendMessageStreaming(
      message: 'hello',
      sessionId: 'session-id',
      onToken: (_) {},
      onDone: () {},
      onError: (_) {},
    );
    while (transport.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(await gateway.cancelActiveMessage(), isTrue);
    await sending;
    expect(transport.cancelled, [transport.requests.single.requestId]);
  });

  test('cancels native SSE while response headers are pending', () async {
    final transport = _FakeMtlsTransport()
      ..autoComplete = false
      ..delayedResponseHead = Completer<MtlsResponseHead>();
    addTearDown(transport.dispose);
    final api = ApiClient.fromConnection(
      _connection(),
      mtlsTransport: transport,
    );
    final gateway = GatewayChatClient(api);
    addTearDown(gateway.abort);

    final sending = gateway.sendMessageStreaming(
      message: 'hello',
      sessionId: 'session-id',
      onToken: (_) {},
      onDone: () {},
      onError: (_) {},
    );
    while (transport.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(await gateway.cancelActiveMessage(), isTrue);
    await sending;
    expect(transport.cancelled, [transport.requests.single.requestId]);
  });

  test('missing alias fails requests closed', () async {
    final client = GatewayHttpClientFactory.create(
      _connection(alias: null),
      mtlsTransport: _FakeMtlsTransport(),
    );
    addTearDown(client.close);

    await expectLater(
      client.get(Uri.parse('https://gateway.example.com/health')),
      throwsStateError,
    );
  });
}
