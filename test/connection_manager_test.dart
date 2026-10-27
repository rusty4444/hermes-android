import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';

/// Case-insensitive request header lookup — package:http normalises header
/// names when sending, so tests should not assume a particular casing.
String? _header(http.BaseRequest request, String name) {
  final lower = name.toLowerCase();
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

const _raceKey = 'race-test-key';

class _BlockingStreamingClient extends http.BaseClient {
  bool cancelled = false;
  late final StreamController<List<int>> controller =
      StreamController<List<int>>(onCancel: () => cancelled = true);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(controller.stream, 200);
  }

  @override
  void close() {
    if (!controller.isClosed) controller.close();
  }
}

class _PreHeaderHangingClient extends http.BaseClient {
  final Completer<void> requestStarted = Completer<void>();
  final Completer<void> releaseRequest = Completer<void>();
  http.BaseRequest? request;
  bool abortObserved = false;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    if (!requestStarted.isCompleted) requestStarted.complete();
    if (request is http.AbortableRequest && request.abortTrigger != null) {
      await Future.any<void>([
        request.abortTrigger!.then((_) {
          abortObserved = true;
          throw http.RequestAbortedException(request.url);
        }),
        releaseRequest.future,
      ]);
    } else {
      await releaseRequest.future;
    }
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() {
    closed = true;
    if (!releaseRequest.isCompleted) releaseRequest.complete();
  }
}

/// Returns a FRESH stream controller per request so a test can keep the
/// first response's stream alive while a second send starts.
class _MultiStreamingClient extends http.BaseClient {
  final List<StreamController<List<int>>> controllers = [];

  StreamController<List<int>> get latest => controllers.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    controllers.add(controller);
    return http.StreamedResponse(controller.stream, 200);
  }

  @override
  void close() {
    for (final c in controllers) {
      if (!c.isClosed) c.close();
    }
  }
}

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = <String, String>{};
  final Map<String, String> _cache = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

enum _PromptDisconnectPoint {
  beforeAck,
  afterAckBeforeFirstDelta,
  midStreamAfterTwoDeltas,
}

Future<void> _expectFailClosedPromptDisconnect(
  _PromptDisconnectPoint point, {
  required int expectedDeltaCount,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <Map<String, dynamic>>[];
  final events = <StreamEvent>[];
  final socketClosed = Completer<void>();
  var connectionCount = 0;
  final socketSubscription = server.transform(WebSocketTransformer()).listen((
    socket,
  ) {
    connectionCount += 1;
    socket.listen(
      (raw) {
        final request = jsonDecode(raw as String) as Map<String, dynamic>;
        if (request['method'] == 'config.get') {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {'config': <String, dynamic>{}},
            }),
          );
          return;
        }
        if (request['method'] != 'prompt.submit') return;
        requests.add(request);

        if (point == _PromptDisconnectPoint.beforeAck) {
          unawaited(
            socket.close(
              WebSocketStatus.goingAway,
              'fixture disconnect before ack',
            ),
          );
          return;
        }

        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            'result': {'accepted': true},
          }),
        );
        if (point == _PromptDisconnectPoint.afterAckBeforeFirstDelta) {
          unawaited(
            socket.close(
              WebSocketStatus.goingAway,
              'fixture disconnect after ack',
            ),
          );
          return;
        }

        for (var index = 0; index < 2; index += 1) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'message.delta',
                'sid': 'disconnect-session',
                'payload': {'text': 'delta-${index + 1}'},
              },
            }),
          );
        }
        unawaited(
          socket.close(
            WebSocketStatus.goingAway,
            'fixture disconnect mid-stream',
          ),
        );
      },
      onError: (Object error) {
        if (!socketClosed.isCompleted) socketClosed.completeError(error);
      },
      onDone: () {
        if (!socketClosed.isCompleted) socketClosed.complete();
      },
    );
  });
  final client = WsClient('http://127.0.0.1:${server.port}');

  try {
    await client.connect().timeout(const Duration(seconds: 5));
    Object? surfacedError;
    var sentCount = 0;
    try {
      await client.submitPrompt(
        'Synthetic disconnect prompt',
        sessionId: 'disconnect-session',
        onEvent: events.add,
        onSent: () => sentCount += 1,
        timeout: const Duration(seconds: 5),
      );
    } catch (error) {
      surfacedError = error;
    }
    await socketClosed.future.timeout(const Duration(seconds: 5));

    expect(surfacedError, isA<Exception>());
    expect(surfacedError, isA<JsonRpcError>());
    expect(
      surfacedError.toString(),
      'JsonRpcError(prompt.submit): Desktop gateway connection closed',
    );
    expect((surfacedError as JsonRpcError).reason, 'connection_closed');
    expect(connectionCount, 1);
    expect(sentCount, 1);
    expect(requests, hasLength(1));
    expect(requests.single['params'], {
      'session_id': 'disconnect-session',
      'text': AndroidPromptContext.forModel('Synthetic disconnect prompt'),
      'title_preview': 'Synthetic disconnect prompt',
    });
    expect(
      events.where((event) => event.type == 'message.delta'),
      hasLength(expectedDeltaCount),
    );
    expect(events.where((event) => event.type == 'turn.end'), isEmpty);
    expect(events.where((event) => event.type == 'turn.error'), isEmpty);
    expect(events.where((event) => event.isComplete), isEmpty);
  } finally {
    client.close();
    await socketSubscription.cancel();
    await server.close(force: true);
  }
}

Map<String, dynamic> _archivedRow(String id) => {
  'id': id,
  'title': 'Archived $id',
  'model': 'gpt-oss-20b',
  'source': 'gateway',
  'message_count': 2,
  'preview': 'archived preview',
  'started_at': 1750000000,
  'last_active': 1750000000,
  'archived': true,
};

void main() {
  group('SavedConnection', () {
    test('normalizes bare HTTP gateway hosts with fallback port', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        '192.168.1.50',
        8642,
      );

      expect(normalized.host, '192.168.1.50');
      expect(normalized.port, 8642);
      expect(normalized.useHttps, isFalse);
    });

    test('normalizes HTTPS URLs without an explicit port to 443', () {
      // null = the Port field was left blank, i.e. no port supplied.
      final normalized = SavedConnection.normalizeHostAndPort(
        'https://hermes.example.com',
        null,
      );

      expect(normalized.host, 'hermes.example.com');
      expect(normalized.port, 443);
      expect(normalized.useHttps, isTrue);
    });

    test('honours an explicit 8642 on an HTTPS host instead of 443', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        'https://hermes.example.com',
        8642,
      );

      expect(normalized.host, 'hermes.example.com');
      expect(normalized.port, 8642);
      expect(normalized.useHttps, isTrue);
    });

    test('infers 8642 for HTTP when no port is supplied', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        'hermes.example.com',
        null,
      );

      expect(normalized.host, 'hermes.example.com');
      expect(normalized.port, 8642);
      expect(normalized.useHttps, isFalse);
    });

    test('a port inside the URL still wins over the Port field', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        'https://hermes.example.com:9443',
        8642,
      );

      expect(normalized.port, 9443);
      expect(normalized.useHttps, isTrue);
    });

    test('normalizes HTTPS URLs with a custom fallback port', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        'https://hermes.example.com',
        8443,
      );

      expect(normalized.host, 'hermes.example.com');
      expect(normalized.port, 8443);
      expect(normalized.useHttps, isTrue);
    });

    test('serializes HTTPS flag and remains backward compatible', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Remote',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
      );

      expect(SavedConnection.fromMap(conn.toMap()).useHttps, isTrue);
      expect(
        SavedConnection.fromMap({
          'id': '2',
          'label': 'Old',
          'host': '192.168.1.50',
          'port': 8642,
          'api_key': 'key',
        }).useHttps,
        isFalse,
      );
    });

    test('uses dashboard port 9119 for local gateway connections', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
      );

      expect(conn.dashboardPort, 9119);
      expect(
        DashboardClient(host: conn.host, port: conn.dashboardPort).baseUrl,
        'http://192.168.1.50:9119',
      );
    });

    test('uses the HTTPS proxy port for dashboard calls over HTTPS', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Remote',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
      );

      expect(conn.dashboardPort, 443);
      expect(
        DashboardClient(
          host: conn.host,
          port: conn.dashboardPort,
          useHttps: conn.useHttps,
        ).baseUrl,
        'https://hermes.example.com:443',
      );
    });

    test('explicit dashboard port override wins over topology default', () {
      final local = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
        dashboardPortOverride: 30433,
      );
      expect(local.dashboardPort, 30433);

      final https = SavedConnection(
        id: '2',
        label: 'Remote',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
        dashboardPortOverride: 8443,
      );
      expect(https.dashboardPort, 8443);
    });

    test('serializes dashboard metadata without plaintext credentials', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
        dashboardPortOverride: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );

      final map = conn.toMap();
      final restored = SavedConnection.fromMap(map);
      expect(map, isNot(contains('api_key')));
      expect(map, isNot(contains('dashboard_password')));
      expect(restored.dashboardPortOverride, 30433);
      expect(restored.dashboardUsername, 'misha');
      expect(restored.apiKey, isEmpty);
      expect(restored.dashboardPassword, isNull);
      expect(restored.dashboardPort, 30433);
    });

    test('fromMap is backward compatible with maps lacking dashboard keys', () {
      final restored = SavedConnection.fromMap({
        'id': '2',
        'label': 'Old',
        'host': '192.168.1.50',
        'port': 8642,
        'api_key': 'key',
      });
      expect(restored.dashboardPortOverride, isNull);
      expect(restored.dashboardUsername, isNull);
      expect(restored.dashboardPassword, isNull);
      expect(restored.dashboardPort, 9119);
    });

    test('round-trips the Hermes profile and clears it via copyWith', () {
      final conn = SavedConnection(
        id: '4',
        label: 'Sol',
        host: 'hermes.example.com',
        port: 8642,
        apiKey: 'key',
        gatewayProfile: 'sol',
      );
      final restored = SavedConnection.fromMap(conn.toMap());
      expect(conn.toMap()['gateway_profile'], 'sol');
      expect(restored.gatewayProfile, 'sol');
      expect(
        SavedConnection.fromMap({
          'id': '5',
          'label': 'Blank',
          'host': 'hermes.example.com',
          'port': 8642,
          'gateway_profile': '  ',
        }).gatewayProfile,
        isNull,
      );
      expect(conn.copyWith(label: 'Still Sol').gatewayProfile, 'sol');
      expect(conn.copyWith(clearGatewayProfile: true).gatewayProfile, isNull);
    });

    test('fromMap normalises blank credentials to null', () {
      final restored = SavedConnection.fromMap({
        'id': '3',
        'label': 'Blank',
        'host': '192.168.1.50',
        'port': 8642,
        'api_key': 'key',
        'dashboard_username': '   ',
        'dashboard_password': '',
      });
      expect(restored.dashboardUsername, isNull);
      expect(restored.dashboardPassword, isNull);
    });

    test('copyWith preserves unset fields and clears via flags', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
        gatewayPrefix: '/profile/peter',
        dashboardPrefix: '/dashboard',
        dashboardProxied: true,
        dashboardPortOverride: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );

      final keyOnly = conn.copyWith(apiKey: 'new-key');
      expect(keyOnly.apiKey, 'new-key');
      expect(keyOnly.gatewayPrefix, '/profile/peter');
      expect(keyOnly.dashboardPrefix, '/dashboard');
      expect(keyOnly.dashboardProxied, isTrue);
      expect(keyOnly.dashboardPortOverride, 30433);
      expect(keyOnly.dashboardUsername, 'misha');
      expect(keyOnly.dashboardPassword, 'secret');

      final cleared = conn.copyWith(
        clearGatewayPrefix: true,
        clearDashboardPrefix: true,
        clearDashboardPort: true,
        clearDashboardUsername: true,
        clearDashboardPassword: true,
      );
      expect(cleared.gatewayPrefix, isNull);
      expect(cleared.dashboardPrefix, isNull);
      expect(cleared.dashboardProxied, isTrue);
      expect(cleared.dashboardPortOverride, isNull);
      expect(cleared.dashboardUsername, isNull);
      expect(cleared.dashboardPassword, isNull);
      // Identity and unrelated fields are retained.
      expect(cleared.id, '1');
      expect(cleared.apiKey, 'key');
    });
  });

  group('ApiClient', () {
    test('healthCheck verifies an authenticated endpoint', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'valid-key',
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer valid-key');
          if (request.url.path == '/health') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/sessions') {
            return http.Response('{"object":"list","data":[]}', 200);
          }
          return http.Response('not found', 404);
        }),
      );

      expect(await client.healthCheck(), isTrue);
      client.close();
    });

    test('healthCheck rejects invalid API keys', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'bad-key',
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/sessions') {
            return http.Response('unauthorized', 401);
          }
          return http.Response('not found', 404);
        }),
      );

      expect(await client.healthCheck(), isFalse);
      client.close();
    });

    test(
      'checkHealth reports the failing prefixed endpoint and status',
      () async {
        final client = ApiClient(
          baseUrl: 'https://hermes.example',
          pathPrefix: '/hermes',
          apiKey: 'prefixed-test-key',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/hermes/health');
            return http.Response('not found', 404);
          }),
        );

        final result = await client.checkHealth();

        expect(result.isHealthy, isFalse);
        expect(result.statusCode, 404);
        expect(result.endpoint.path, '/hermes/health');
        expect(
          result.userMessage(apiKeyProvided: true),
          allOf(contains('HTTP 404'), contains('reverse-proxy routes')),
        );
        client.close();
      },
    );

    test(
      'checkHealth attributes auth failures to the sessions endpoint',
      () async {
        final client = ApiClient(
          baseUrl: 'http://hermes.local:8642',
          apiKey: 'invalid-test-key',
          httpClient: MockClient((request) async {
            if (request.url.path == '/health') return http.Response('{}', 200);
            return http.Response('unauthorized', 401);
          }),
        );

        final result = await client.checkHealth();

        expect(result.isHealthy, isFalse);
        expect(result.statusCode, 401);
        expect(result.endpoint.path, '/api/sessions');
        expect(
          result.userMessage(apiKeyProvided: true),
          contains('API key was rejected'),
        );
        client.close();
      },
    );

    test('loads and changes a session model through the API Server', () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'valid-key',
        pathPrefix: '/gateway',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.host, 'hermes.local');
          expect(request.url.port, 8642);
          expect(request.headers['authorization'], 'Bearer valid-key');
          if (request.method == 'GET' &&
              request.url.path == '/gateway/api/sessions/mob-123') {
            return http.Response(
              jsonEncode({
                'object': 'hermes.session',
                'session': {'id': 'mob-123', 'model': 'old-model'},
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/gateway/api/model/options') {
            return http.Response(
              jsonEncode({
                'model': 'profile-default',
                'provider': 'nous',
                'providers': [
                  {
                    'slug': 'nous',
                    'models': ['old-model', 'new-model'],
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/gateway/api/sessions/mob-123/model') {
            expect(jsonDecode(request.body), {
              'provider': 'nous',
              'model': 'new-model',
              'require_model_lock': true,
            });
            return http.Response(
              jsonEncode({
                'object': 'hermes.session.model_lock',
                'session_id': 'mob-123',
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final session = await client.getSession('mob-123');
      final options = await client.getModelOptions();
      await client.setSessionModel(
        sessionId: 'mob-123',
        provider: 'nous',
        model: 'new-model',
      );

      expect(session['model'], 'old-model');
      expect(options['provider'], 'nous');
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'GET /gateway/api/sessions/mob-123',
          'GET /gateway/api/model/options',
          'POST /gateway/api/sessions/mob-123/model',
        ],
      );
      client.close();
    });

    test('rejects a malformed single-session response', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'valid-key',
        httpClient: MockClient(
          (_) async => http.Response('{"object":"hermes.session"}', 200),
        ),
      );

      await expectLater(
        client.getSession('mob-123'),
        throwsA(isA<FormatException>()),
      );
      client.close();
    });

    test('deleteSession deletes a remote Hermes session', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'valid-key',
        httpClient: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/sessions/mob-123');
          expect(request.headers['authorization'], 'Bearer valid-key');
          return http.Response('{"object":"hermes.session.deleted"}', 200);
        }),
      );

      await client.deleteSession('mob-123');
      client.close();
    });

    test('deleteSession treats already-missing sessions as synced', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'valid-key',
        httpClient: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/sessions/mob-absent');
          return http.Response('not found', 404);
        }),
      );

      await client.deleteSession('mob-absent');
      client.close();
    });
  });

  group('GatewayChatClient', () {
    test('appends latest user message to existing history exactly once', () {
      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: 'new question',
        history: [
          {'role': 'user', 'content': 'old question'},
          {'role': 'assistant', 'content': 'old answer'},
        ],
      );

      expect(messages, [
        {'role': 'user', 'content': 'old question'},
        {'role': 'assistant', 'content': 'old answer'},
        {
          'role': 'user',
          'content': AndroidPromptContext.forModel('new question'),
        },
      ]);
    });

    test(
      'does not duplicate latest user message already present in history',
      () {
        final messages = GatewayChatClient.buildChatCompletionMessages(
          message: 'new question',
          history: [
            {'role': 'user', 'content': 'old question'},
            {'role': 'assistant', 'content': 'old answer'},
            {'role': 'user', 'content': 'new question'},
          ],
        );

        expect(
          messages.where(
            (m) =>
                m['content'] == AndroidPromptContext.forModel('new question'),
          ),
          hasLength(1),
        );
        expect(messages.last, {
          'role': 'user',
          'content': AndroidPromptContext.forModel('new question'),
        });
      },
    );

    test('builds an OpenAI image_url content part for an attached image', () {
      const dataUrl = 'data:image/jpeg;base64,aGVybWVz';

      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: 'What is in this image?',
        imageDataUrl: dataUrl,
      );

      expect(messages, [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': AndroidPromptContext.forModel('What is in this image?'),
            },
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ]);
    });

    test('preserves multimodal history when sending a later message', () {
      final previousImageMessage = {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Earlier image'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,cHJldmlvdXM='},
          },
        ],
      };

      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: 'Describe it further.',
        history: [previousImageMessage],
      );

      expect(messages.first, previousImageMessage);
      expect(messages.last, {
        'role': 'user',
        'content': AndroidPromptContext.forModel('Describe it further.'),
      });
    });

    test('parses normal chat completion SSE token frames', () {
      final token = GatewayChatClient.parseSseFrame(
        'data: {"choices":[{"delta":{"content":"hello"}}]}',
      );

      expect(token, 'hello');
    });

    test('parses Hermes tool progress SSE frames via callback', () {
      Map<String, dynamic>? progress;
      final token = GatewayChatClient.parseSseFrame(
        'event: hermes.tool.progress\n'
        'data: {"tool":"read_file","toolCallId":"call_1","status":"running"}',
        onToolProgress: (p) => progress = p,
      );

      expect(token, isNull);
      expect(progress, isNotNull);
      expect(progress!['tool'], 'read_file');
      expect(progress!['toolCallId'], 'call_1');
      expect(progress!['status'], 'running');
    });

    test(
      'cancels the active SSE request without reporting completion',
      () async {
        final transport = _BlockingStreamingClient();
        final api = ApiClient(
          baseUrl: 'http://hermes.local:8642',
          apiKey: 'valid-key',
          httpClient: transport,
        );
        final gateway = GatewayChatClient(api);
        final firstToken = Completer<void>();
        var done = false;
        String? error;

        final sending = gateway.sendMessageStreaming(
          message: 'slow response',
          sessionId: 'mob-stop-test',
          onToken: (token) {
            if (!firstToken.isCompleted) firstToken.complete();
          },
          onDone: () => done = true,
          onError: (value) => error = value,
        );
        transport.controller.add(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
          ),
        );
        await firstToken.future;

        expect(await gateway.cancelActiveMessage(), isTrue);
        await sending;

        expect(transport.cancelled, isTrue);
        expect(done, isFalse);
        expect(error, isNull);
        api.close();
      },
    );

    test(
      'cancels promptly while SSE response headers are still pending',
      () async {
        final transport = _PreHeaderHangingClient();
        final api = ApiClient(
          baseUrl: 'http://hermes.local:8642',
          apiKey: _raceKey,
          httpClient: transport,
        );
        final gateway = GatewayChatClient(api);
        var done = false;
        String? error;

        final sending = gateway.sendMessageStreaming(
          message: 'waiting for headers',
          sessionId: 'mob-pre-header-cancel',
          onToken: (_) {},
          onDone: () => done = true,
          onError: (value) => error = value,
        );
        await transport.requestStarted.future;

        expect(await gateway.cancelActiveMessage(), isTrue);
        Object? settleFailure;
        try {
          await sending.timeout(const Duration(milliseconds: 250));
        } catch (failure) {
          settleFailure = failure;
        }
        if (!transport.releaseRequest.isCompleted) {
          transport.releaseRequest.complete();
        }
        await sending;

        expect(transport.request, isA<http.AbortableRequest>());
        expect(transport.abortObserved, isTrue);
        expect(
          settleFailure,
          isNull,
          reason: 'cancellation must not wait for response headers',
        );
        expect(
          transport.closed,
          isFalse,
          reason: 'cancelling one send must keep the shared client usable',
        );
        expect(done, isFalse);
        expect(error, isNull);
        api.close();
      },
    );

    test('cancel-then-resend never reports the cancelled turn as done and '
        'never leaks its tokens into the new stream', () async {
      final transport = _MultiStreamingClient();
      final api = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: _raceKey,
        httpClient: transport,
      );
      final gateway = GatewayChatClient(api);
      final firstToken = Completer<void>();
      var firstDone = false;
      var secondDone = false;
      final firstTokens = <String>[];
      final secondTokens = <String>[];

      final firstSending = gateway.sendMessageStreaming(
        message: 'first',
        sessionId: 'mob-race-1',
        onToken: (t) {
          firstTokens.add(t);
          if (!firstToken.isCompleted) firstToken.complete();
        },
        onDone: () => firstDone = true,
        onError: (_) {},
      );
      transport.controllers.first.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"one"}}]}\n\n'),
      );
      await firstToken.future;

      // Cancel the first, then IMMEDIATELY start a second send — the
      // old shared-flag design reset _activeStreamCancelled=false in
      // the second call before the first call's post-await check ran,
      // so the cancelled first turn reported onDone.
      expect(await gateway.cancelActiveMessage(), isTrue);
      final secondSending = gateway.sendMessageStreaming(
        message: 'second',
        sessionId: 'mob-race-2',
        onToken: secondTokens.add,
        onDone: () => secondDone = true,
        onError: (_) {},
      );
      // Let the first call unwind fully with the second already active.
      await firstSending;
      expect(
        firstDone,
        isFalse,
        reason: 'a cancelled turn must never report completion',
      );

      // The orphaned first stream pushing late tokens must not reach
      // any callback: the first stream's controller is still open but
      // its subscription was cancelled; the second stream gets its own.
      transport.latest.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"two"}}]}\n\n'),
      );
      await pumpEventQueue();
      expect(secondTokens, ['two']);
      expect(firstTokens, [
        'one',
      ], reason: 'first stream delivered nothing after cancellation');

      // Second stream completes with explicit successful protocol evidence.
      transport.latest.add(
        utf8.encode(
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
        ),
      );
      await transport.latest.close();
      await secondSending;
      expect(secondDone, isTrue);
      api.close();
    });
  });

  group('Desktop gateway URL derivation', () {
    test('derives the Desktop gateway from dashboard details by default', () {
      final connection = SavedConnection(
        id: 'miniserver',
        label: 'Miniserver',
        host: 'carlos-miniserver.taild544f6.ts.net',
        port: 8642,
        apiKey: 'test-key',
        dashboardPortOverride: 9119,
        dashboardUsername: 'carlos',
        dashboardPassword: 'secret',
      );

      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
        'http://carlos-miniserver.taild544f6.ts.net:9119',
      );
    });

    test(
      'ignores a redundant same-host override and derives dashboard port',
      () {
        final connection = SavedConnection(
          id: 'miniserver',
          label: 'Miniserver',
          host: 'carlos-miniserver.taild544f6.ts.net',
          port: 8642,
          apiKey: 'test-key',
          dashboardPortOverride: 9119,
          desktopGatewayUrl: 'https://carlos-miniserver.taild544f6.ts.net',
        );

        expect(
          DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
          'http://carlos-miniserver.taild544f6.ts.net:9119',
        );
      },
    );

    test('preserves an explicit Desktop gateway override', () {
      final connection = SavedConnection(
        id: 'remote',
        label: 'Remote',
        host: 'api.example.test',
        port: 8642,
        apiKey: 'test-key',
        useHttps: true,
        dashboardPortOverride: 9119,
        desktopGatewayUrl: 'https://desktop.example.test/gateway',
      );

      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
        'https://desktop.example.test:443/gateway',
      );
    });

    test('includes the dashboard path prefix in the derived URL', () {
      final connection = SavedConnection(
        id: 'proxied',
        label: 'Proxied',
        host: 'hermes.example.test',
        port: 443,
        apiKey: 'test-key',
        useHttps: true,
        dashboardPrefix: 'dashboard',
      );

      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
        'https://hermes.example.test:443/dashboard',
      );
    });
  });

  group('DashboardClient', () {
    test('wraps cron job updates for dashboard endpoint', () {
      final updates = {'name': 'Daily', 'no_agent': true};

      expect(DashboardClient.buildCronUpdateBody(updates), {
        'updates': updates,
      });
    });

    test('scopes every cron operation to the connection profile', () async {
      final requests = <http.Request>[];
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        proxied: true,
        gatewayProfile: 'research',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/cron/jobs') {
            if (request.method == 'GET') return http.Response('[]', 200);
            return http.Response('{"id":"job-1"}', 200);
          }
          if (request.url.path.endsWith('/runs')) {
            return http.Response('{"runs":[],"limit":20}', 200);
          }
          return http.Response('{}', 200);
        }),
      );

      await client.getCronJobs();
      await client.getCronJobRuns('job-1');
      await client.createJob(
        name: 'Scoped job',
        prompt: 'Do scoped work',
        schedule: '0 9 * * *',
      );
      await client.updateJob('job-1', {'name': 'Updated'});
      await client.setJobPaused('job-1', paused: true);
      await client.setJobPaused('job-1', paused: false);
      await client.triggerJob('job-1');
      await client.deleteJob('job-1');

      expect(requests, hasLength(8));
      for (final request in requests) {
        expect(
          request.url.queryParameters['profile'],
          'research',
          reason:
              '${request.method} ${request.url.path} must stay profile-scoped',
        );
      }
      expect(requests[1].url.queryParameters['limit'], '20');
      expect(jsonDecode(requests[2].body), {
        'prompt': 'Do scoped work',
        'schedule': '0 9 * * *',
        'name': 'Scoped job',
        'deliver': 'local',
      });
      expect(jsonDecode(requests[3].body), {
        'updates': {'name': 'Updated'},
      });
      expect(requests[4].url.path, '/api/cron/jobs/job-1/pause');
      expect(requests[5].url.path, '/api/cron/jobs/job-1/resume');
      expect(requests[6].url.path, '/api/cron/jobs/job-1/trigger');
      expect(requests[7].method, 'DELETE');
      client.close();
    });

    test('updateJob times out when response headers never arrive', () async {
      final never = Completer<http.Response>();
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        proxied: true,
        httpClient: MockClient((_) => never.future),
      );

      await expectLater(
        client.updateJob('job-1', {
          'name': 'Still bounded',
        }, timeout: const Duration(milliseconds: 25)),
        throwsA(isA<TimeoutException>()),
      );
      client.close();
    });

    test('getCronJobRuns parses the dashboard runs envelope', () async {
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          if (request.url.path == '/api/cron/jobs/nightly%20report/runs') {
            expect(request.url.queryParameters['limit'], '20');
            return http.Response(
              jsonEncode({
                'runs': [
                  {
                    'id': 'cron_nightly_1750000000',
                    'title': 'Nightly report run',
                    'model': 'claude-opus-5',
                    'source': 'cron',
                    'message_count': 4,
                    'started_at': 1750000000,
                    'last_active': 1750000123,
                    'preview': 'Report generated',
                    'ended_at': 1750000123,
                  },
                ],
                'limit': 20,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final runs = await client.getCronJobRuns('nightly report');

      expect(runs, hasLength(1));
      expect(runs.single.id, 'cron_nightly_1750000000');
      expect(runs.single.source, 'cron');
      expect(runs.single.isActive, isFalse);
      expect(runs.single.lastActive, 1750000123);
      client.close();
    });

    test('getArchivedSessions dedupes repeated pins and proves exhaustion '
        'independently of total', () async {
      // 150 archived window rows + one back-filled pin. Even an accurate
      // total is not exhaustion authority: require the terminal end probe.
      final requestedOffsets = <String>[];
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          if (request.url.path == '/api/sessions' &&
              request.url.queryParameters['archived'] == 'only') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            requestedOffsets.add(request.url.queryParameters['offset']!);
            final limit = int.parse(request.url.queryParameters['limit']!);
            final rows = [
              for (var i = offset; i < offset + limit && i < 150; i++)
                _archivedRow('a$i'),
            ];
            // The pin repeats on every page (back-fill semantics).
            final withPin = [
              {..._archivedRow('pin-x'), 'pinned': true},
              if (!rows.any((r) => r['id'] == 'pin-x')) ...rows,
            ];
            return http.Response(
              jsonEncode({
                'sessions': withPin,
                'total': 151,
                'limit': limit,
                'offset': offset,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final sessions = await client.getArchivedSessions(pageSize: 100);

      expect(requestedOffsets, ['0', '100', '200']);
      // 150 window rows + 1 pin, deduped — never the inflated 153.
      expect(sessions, hasLength(151));
      final ids = sessions.map((s) => s.id).toSet();
      expect(ids.length, 151, reason: 'no duplicate ids');
      expect(ids.contains('pin-x'), isTrue);
      expect(ids.contains('a149'), isTrue);
      client.close();
    });

    test('getArchivedSessions keeps paging past a full pin-only window '
        'with an underreported total', () async {
      // A complete OFFSET window consists of 100 already back-filled pins.
      // This replaces the old fixture's impossible 100-row hole with only two
      // unmarked pins. A real pin window must consume its disjoint pin bound.
      final requestedOffsets = <String>[];
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          if (request.url.path == '/api/sessions' &&
              request.url.queryParameters['archived'] == 'only') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            requestedOffsets.add(request.url.queryParameters['offset']!);
            final limit = int.parse(request.url.queryParameters['limit']!);
            final pins = [
              for (var i = 100; i < 200; i++)
                {..._archivedRow('a$i'), 'pinned': true},
            ];
            final windowRows = [
              for (var i = offset; i < offset + limit && i < 210; i++)
                if (offset != 100) _archivedRow('a$i'),
              // The window at offset 100 is a pure repeat: only the
              // pins, zero fresh rows, while a200+ still sit ahead.
            ];
            return http.Response(
              jsonEncode({
                'sessions': [...pins, ...windowRows],
                'total': 1,
                'limit': limit,
                'offset': offset,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final sessions = await client.getArchivedSessions(pageSize: 100);

      expect(requestedOffsets, ['0', '100', '200', '300', '400']);
      expect(sessions, hasLength(210));
      expect(sessions.map((s) => s.id).toSet(), hasLength(210));
      expect(sessions.map((s) => s.id), contains('a209'));
      client.close();
    });

    test('getArchivedSessions without a total falls back to the pin-bound '
        'proof and walks past a pin-only window', () async {
      // The fallback branch (non-standard router that omits `total`):
      // termination is the k-consecutive-zero-new-pages rule bounded by
      // the max pins seen on any page. Reviewer shape at pageSize 2:
      // window rows a0..a5 with a2,a3 pinned; the offset-2 window is
      // pure pin repeats (zero new) while a4,a5 sit at offset 4.
      // required = 2 ~/ 2 + 1 = 2 consecutive zero-new pages.
      final requestedOffsets = <String>[];
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          if (request.url.path == '/api/sessions' &&
              request.url.queryParameters['archived'] == 'only') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            requestedOffsets.add(request.url.queryParameters['offset']!);
            final limit = int.parse(request.url.queryParameters['limit']!);
            final window = [
              for (var i = offset; i < offset + limit && i < 6; i++)
                _archivedRow('a$i'),
            ];
            // Pins (a2, a3) back-filled on EVERY page.
            final pins = [_archivedRow('a2'), _archivedRow('a3')]
              ..forEach((p) => p['pinned'] = true);
            final withPins = [
              ...window,
              for (final p in pins)
                if (!window.any((r) => r['id'] == p['id'])) p,
            ];
            // NO 'total' key — forces the client-side proof branch.
            return http.Response(
              jsonEncode({
                'sessions': withPins,
                'limit': limit,
                'offset': offset,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final sessions = await client.getArchivedSessions(pageSize: 2);

      // The zero-new window at offset 2 did NOT end the walk: a4/a5
      // were reached. (A mutant that required only ONE zero-new page —
      // e.g. flipping the pinBound==0 ternary or dropping the +1 —
      // stops at offset 4 and loses them.)
      expect(requestedOffsets, contains('4'));
      final ids = sessions.map((s) => s.id).toSet();
      expect(ids, containsAll(<String>['a0', 'a1', 'a2', 'a3', 'a4', 'a5']));
      expect(ids.length, 6, reason: 'pins deduped');
      client.close();
    });

    test('getArchivedSessions probes the end even when the total matches '
        'an exact page boundary', () async {
      final requestedOffsets = <String>[];
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          if (request.url.path == '/api/sessions' &&
              request.url.queryParameters['archived'] == 'only') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            requestedOffsets.add(request.url.queryParameters['offset']!);
            final limit = int.parse(request.url.queryParameters['limit']!);
            final rows = [
              for (var i = offset; i < offset + limit && i < 200; i++)
                _archivedRow('a$i'),
            ];
            return http.Response(
              jsonEncode({
                'sessions': rows,
                'total': 200,
                'limit': limit,
                'offset': offset,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final sessions = await client.getArchivedSessions(pageSize: 100);

      expect(
        requestedOffsets,
        ['0', '100', '200'],
        reason: 'only the zero-new offset window proves exhaustion',
      );
      expect(sessions, hasLength(200));
      client.close();
    });

    test('getArchivedSessions throws rather than present a cap-truncated '
        'archive as complete', () async {
      // A store that never ends: every page carries fresh rows. The
      // maxPages cap must surface an error, not a silent partial list.
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          if (request.url.path == '/api/sessions') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            final limit = int.parse(request.url.queryParameters['limit']!);
            return http.Response(
              jsonEncode({
                'sessions': [
                  for (var i = offset; i < offset + limit; i++)
                    _archivedRow('endless$i'),
                ],
                'total': 999999,
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      expect(
        client.getArchivedSessions(pageSize: 100, maxPages: 3),
        throwsStateError,
      );
      client.close();
    });

    test('getCronJobRuns returns empty for a job with no runs', () async {
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
              },
            );
          }
          return http.Response('{"runs": [], "limit": 20}', 200);
        }),
      );

      expect(await client.getCronJobRuns('fresh-job'), isEmpty);
      client.close();
    });

    test(
      'logs in and authenticates /api calls with the session cookie',
      () async {
        var loginCalls = 0;
        final client = DashboardClient(
          host: 'hermes.local',
          port: 30433,
          username: 'misha',
          password: 'secret',
          httpClient: MockClient((request) async {
            if (request.url.path == '/auth/password-login') {
              loginCalls++;
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'provider': 'basic',
                'username': 'misha',
                'password': 'secret',
              });
              return http.Response(
                '{"ok":true}',
                200,
                headers: {
                  'set-cookie':
                      'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
                },
              );
            }
            if (request.url.path == '/api/model/info') {
              // Cookie auth, not the insecure token header.
              expect(_header(request, 'cookie'), 'hermes_session_at=TOK123');
              expect(_header(request, 'x-hermes-session-token'), isNull);
              return http.Response('{"model":"hermes-agent"}', 200);
            }
            return http.Response('not found', 404);
          }),
        );

        final info = await client.getModelInfo();
        expect(info['model'], 'hermes-agent');

        // A second call reuses the cached cookie (no re-login).
        await client.getModelInfo();
        expect(loginCalls, 1);
        client.close();
      },
    );

    test('falls back to homepage token scrape when no credentials', () async {
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        httpClient: MockClient((request) async {
          if (request.url.path == '/') {
            return http.Response(
              '<script>window.__HERMES_SESSION_TOKEN__="SPA_TOK";</script>',
              200,
            );
          }
          if (request.url.path == '/api/model/info') {
            expect(_header(request, 'x-hermes-session-token'), 'SPA_TOK');
            expect(_header(request, 'cookie'), isNull);
            return http.Response('{"model":"hermes-agent"}', 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final info = await client.getModelInfo();
      expect(info['model'], 'hermes-agent');
      client.close();
    });

    test('re-authenticates once on a 401 from an /api call', () async {
      var apiCalls = 0;
      var loginCalls = 0;
      final client = DashboardClient(
        host: 'hermes.local',
        port: 30433,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            loginCalls++;
            final cookie = 'hermes_session_at=TOK$loginCalls';
            return http.Response(
              '{"ok":true}',
              200,
              headers: {'set-cookie': '$cookie; Path=/'},
            );
          }
          if (request.url.path == '/api/model/info') {
            apiCalls++;
            // First attempt: stale cookie → 401. Retry: succeeds.
            if (apiCalls == 1) return http.Response('unauthorized', 401);
            expect(_header(request, 'cookie'), 'hermes_session_at=TOK2');
            return http.Response('{"model":"hermes-agent"}', 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final info = await client.getModelInfo();
      expect(info['model'], 'hermes-agent');
      expect(apiCalls, 2);
      expect(loginCalls, 2);
      client.close();
    });

    test(
      'concurrent stale 401 responses share one replacement login',
      () async {
        var loginCalls = 0;
        var staleApiCalls = 0;
        var apiCalls = 0;
        final bothStaleRequestsStarted = Completer<void>();
        final releaseReplacementLogin = Completer<void>();
        final client = DashboardClient(
          host: 'hermes.local',
          port: 30433,
          username: 'misha',
          password: 'secret',
          httpClient: MockClient((request) async {
            if (request.url.path == '/auth/password-login') {
              loginCalls++;
              if (loginCalls == 2) {
                Future<void>.delayed(const Duration(milliseconds: 25), () {
                  if (!releaseReplacementLogin.isCompleted) {
                    releaseReplacementLogin.complete();
                  }
                });
                await releaseReplacementLogin.future;
              }
              return http.Response(
                '{"ok":true}',
                200,
                headers: {
                  'set-cookie':
                      'hermes_session_at=TOK$loginCalls; Path=/; HttpOnly',
                },
              );
            }
            if (request.url.path.startsWith('/api/')) {
              apiCalls++;
              if (_header(request, 'cookie') == 'hermes_session_at=TOK1') {
                staleApiCalls++;
                if (staleApiCalls == 2 &&
                    !bothStaleRequestsStarted.isCompleted) {
                  bothStaleRequestsStarted.complete();
                }
                await bothStaleRequestsStarted.future;
                return http.Response('unauthorized', 401);
              }
              return http.Response('{"ok":true}', 200);
            }
            return http.Response('not found', 404);
          }),
        );

        final results = await Future.wait([
          client.apiGet('first'),
          client.apiGet('second'),
        ]);

        expect(results, everyElement({'ok': true}));
        expect(staleApiCalls, 2);
        expect(apiCalls, 4, reason: 'each request retries at most once');
        expect(
          loginCalls,
          2,
          reason: 'initial login plus one shared replacement login',
        );
        client.close();
      },
    );

    test('surfaces invalid dashboard credentials', () async {
      final client = DashboardClient(
        host: 'hermes.local',
        port: 30433,
        username: 'misha',
        password: 'wrong',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response('{"detail":"Invalid credentials"}', 401);
          }
          return http.Response('not found', 404);
        }),
      );

      expect(client.getModelInfo(), throwsA(isA<Exception>()));
      client.close();
    });

    test(
      'mints a WebSocket ticket with the dashboard session cookie',
      () async {
        final client = DashboardClient(
          host: 'desktop.hermes.local',
          port: 443,
          useHttps: true,
          username: 'misha',
          password: 'secret',
          httpClient: MockClient((request) async {
            if (request.url.path == '/auth/password-login') {
              return http.Response(
                '{"ok":true}',
                200,
                headers: {'set-cookie': 'hermes_session_at=TOK123; Path=/'},
              );
            }
            if (request.url.path == '/api/auth/ws-ticket') {
              expect(request.method, 'POST');
              expect(_header(request, 'cookie'), 'hermes_session_at=TOK123');
              return http.Response('{"ticket":"ONE_TIME_TICKET"}', 200);
            }
            return http.Response('not found', 404);
          }),
        );

        await expectLater(
          client.mintWebSocketTicket(),
          completion('ONE_TIME_TICKET'),
        );
        client.close();
      },
    );
  });

  group('ConnectionManager', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('saveConnection persists dashboard port and credentials', () async {
      final prefs = await SharedPreferences.getInstance();
      final mgr = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await mgr.saveConnection(
        'Home',
        '192.168.1.50',
        8642,
        'key',
        dashboardPort: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );

      final conn = mgr.getConnections().single;
      expect(conn.dashboardPortOverride, 30433);
      expect(conn.dashboardUsername, 'misha');
      expect(conn.dashboardPassword, 'secret');
    });

    test('updateDashboardAuth sets then clears fields', () async {
      final prefs = await SharedPreferences.getInstance();
      final mgr = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await mgr.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final id = mgr.getConnections().single.id;

      await mgr.updateDashboardAuth(
        id,
        gatewayPrefix: '/profile/peter',
        dashboardPrefix: '/dashboard',
        dashboardProxied: true,
        dashboardPort: 30433,
        username: 'misha',
        password: 'secret',
      );
      var conn = mgr.getConnections().single;
      expect(conn.gatewayPrefix, '/profile/peter');
      expect(conn.dashboardPrefix, '/dashboard');
      expect(conn.dashboardProxied, isTrue);
      expect(conn.dashboardPortOverride, 30433);
      expect(conn.dashboardUsername, 'misha');
      expect(conn.dashboardPassword, 'secret');

      // Blank values clear the corresponding fields.
      await mgr.updateDashboardAuth(
        id,
        gatewayPrefix: '',
        dashboardPrefix: '',
        dashboardProxied: false,
        username: '',
        password: '',
      );
      conn = mgr.getConnections().single;
      expect(conn.gatewayPrefix, isNull);
      expect(conn.dashboardPrefix, isNull);
      expect(conn.dashboardProxied, isFalse);
      expect(conn.dashboardPortOverride, isNull);
      expect(conn.dashboardUsername, isNull);
      expect(conn.dashboardPassword, isNull);
    });

    test('updateApiKey preserves dashboard credentials', () async {
      final prefs = await SharedPreferences.getInstance();
      final mgr = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await mgr.saveConnection(
        'Home',
        '192.168.1.50',
        8642,
        'key',
        dashboardPort: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );
      final id = mgr.getConnections().single.id;

      await mgr.updateApiKey(id, 'new-key');
      final conn = mgr.getConnections().single;
      expect(conn.apiKey, 'new-key');
      expect(conn.dashboardPortOverride, 30433);
      expect(conn.dashboardUsername, 'misha');
      expect(conn.dashboardPassword, 'secret');
    });

    test(
      'updateConnection edits host, port, key, and clears optional fields',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final mgr = await ConnectionManager.create(
          prefs,
          credentialStore: _MemoryCredentialStore(),
        );
        await mgr.saveConnection(
          'Home',
          '192.168.1.50',
          8642,
          'key',
          gatewayPrefix: '/old-gateway',
          dashboardPrefix: '/old-dashboard',
          dashboardProxied: true,
          dashboardPort: 30433,
          dashboardUsername: 'misha',
          dashboardPassword: 'secret',
        );
        final id = mgr.getConnections().single.id;

        await mgr.updateConnection(
          id,
          'Moved',
          'https://hermes.example.com',
          null,
          'new-key',
          gatewayPrefix: '',
          dashboardPrefix: '',
          dashboardProxied: false,
          dashboardUsername: '',
          dashboardPassword: '',
        );

        final conn = mgr.getConnections().single;
        expect(conn.id, id);
        expect(conn.label, 'Moved');
        expect(conn.host, 'hermes.example.com');
        expect(conn.port, 443);
        expect(conn.useHttps, isTrue);
        expect(conn.apiKey, 'new-key');
        expect(conn.gatewayPrefix, isNull);
        expect(conn.dashboardPrefix, isNull);
        expect(conn.dashboardProxied, isFalse);
        expect(conn.dashboardPortOverride, isNull);
        expect(conn.dashboardUsername, isNull);
        expect(conn.dashboardPassword, isNull);
      },
    );

    test(
      'saveConnection keeps an explicit 8642 for an HTTPS host (issue #110)',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final mgr = await ConnectionManager.create(
          prefs,
          credentialStore: _MemoryCredentialStore(),
        );
        await mgr.saveConnection(
          'kodi',
          'https://home-kodi.example.ts.net',
          8642,
          'key',
        );

        final conn = mgr.getConnections().single;
        expect(conn.port, 8642);
        expect(conn.useHttps, isTrue);
        expect(conn.baseUrl, 'https://home-kodi.example.ts.net:8642');
      },
    );

    test(
      'saveConnection infers 443 for HTTPS when the Port field is blank',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final mgr = await ConnectionManager.create(
          prefs,
          credentialStore: _MemoryCredentialStore(),
        );
        await mgr.saveConnection(
          'proxy',
          'https://hermes.example.com',
          null,
          'key',
        );

        final conn = mgr.getConnections().single;
        expect(conn.port, 443);
        expect(conn.useHttps, isTrue);
      },
    );
  });

  group('Path prefix support', () {
    test('joinBaseUrl without prefix returns baseUrl unchanged', () {
      expect(
        SavedConnection.joinBaseUrl('https://hermes.example.com:443', ''),
        'https://hermes.example.com:443',
      );
    });

    test('joinBaseUrl appends prefix between base and API path', () {
      expect(
        SavedConnection.joinBaseUrl(
          'https://hermes.example.com:443',
          '/profile/peter',
        ),
        'https://hermes.example.com:443/profile/peter',
      );
    });

    test('ApiClient pathPrefix is prepended to baseUrl', () {
      final client = ApiClient(
        baseUrl: 'https://hermes.example.com:443',
        apiKey: 'key',
        pathPrefix: '/profile/peter',
      );
      expect(client.baseUrl, 'https://hermes.example.com:443/profile/peter');
      client.close();
    });

    test('DashboardClient uses pathPrefix', () {
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        pathPrefix: '/dashboard',
      );
      expect(client.baseUrl, 'https://hermes.example.com:443/dashboard');
      client.close();
    });

    test('DashboardClient proxied sends no auth headers', () async {
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        pathPrefix: '/dashboard',
        proxied: true,
        httpClient: MockClient((request) async {
          expect(
            request.headers.containsKey('x-hermes-session-token'),
            isFalse,
          );
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response('{"data": {}}', 200);
        }),
      );
      await client.apiGet('model/info');
      client.close();
    });

    test(
      'DashboardClient proxied ignores credentials, sends clean headers',
      () async {
        final client = DashboardClient(
          host: 'hermes.example.com',
          port: 443,
          useHttps: true,
          pathPrefix: '/dashboard',
          proxied: true,
          username: 'user',
          password: 'pass',
          httpClient: MockClient((request) async {
            expect(
              request.headers.containsKey('x-hermes-session-token'),
              isFalse,
            );
            expect(request.headers.containsKey('cookie'), isFalse);
            return http.Response('{"data": {}}', 200);
          }),
        );
        await client.apiGet('model/info');
        client.close();
      },
    );

    test('SavedConnection serializes gateway and dashboard prefixes', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Proxy',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
        gatewayPrefix: '/profile/peter',
        dashboardPrefix: '/dashboard',
        dashboardProxied: true,
      );
      final map = conn.toMap();
      expect(map['gateway_prefix'], '/profile/peter');
      expect(map['dashboard_prefix'], '/dashboard');
      expect(map['dashboard_proxied'], true);
    });

    test('SavedConnection preserves an optional Desktop gateway URL', () {
      final conn = SavedConnection(
        id: '1',
        label: 'ATLAS',
        host: 'hermes-api.example.lan',
        port: 443,
        apiKey: 'key',
        useHttps: true,
        desktopGatewayUrl: 'https://hermes-desktop.example.lan',
      );

      final restored = SavedConnection.fromMap(conn.toMap());
      expect(restored.desktopGatewayUrl, 'https://hermes-desktop.example.lan');
    });
  });

  group('Desktop gateway WebSocket URL', () {
    test('uses a ticket for a secured Desktop gateway', () {
      expect(
        WsClient.buildWebSocketUrl(
          'https://hermes-desktop.example.lan',
          ticket: 'one time+ticket',
        ),
        'wss://hermes-desktop.example.lan/api/ws?ticket=one+time%2Bticket',
      );
    });

    test('keeps legacy token support for insecure gateways', () {
      expect(
        WsClient.buildWebSocketUrl('http://hermes.local:9119', token: 'spa'),
        'ws://hermes.local:9119/api/ws?token=spa',
      );
    });

    test('withProfile adds the profile to params, blank sends nothing', () {
      expect(WsClient.withProfile({'session_id': 'abc'}, 'sol'), {
        'session_id': 'abc',
        'profile': 'sol',
      });
      expect(WsClient.withProfile({'session_id': 'abc'}, '   '), {
        'session_id': 'abc',
      });
      expect(WsClient.withProfile({'session_id': 'abc'}, null), {
        'session_id': 'abc',
      });
      expect(
        WsClient.withProfile({'session_id': 'abc', 'profile': 'kael'}, 'sol'),
        {'session_id': 'abc', 'profile': 'kael'},
      );
    });

    test(
      'sends the Hermes profile in every JSON-RPC payload, not the URL',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requestUris = <Uri>[];
        final frames = <Map<String, dynamic>>[];
        final socketSubscription = server.listen((request) async {
          requestUris.add(request.uri);
          final socket = await WebSocketTransformer.upgrade(request);
          socket.listen((message) {
            final frame = jsonDecode(message as String) as Map<String, dynamic>;
            frames.add(frame);
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': frame['id'],
                'result': {'session_id': 'abc', 'stored_session_id': 'abc'},
              }),
            );
          });
        });
        final client = WsClient(
          'http://127.0.0.1:${server.port}',
          token: 'spa',
          profile: 'sol',
        );
        try {
          await client.connect();
          await client.resumeSession('abc');
          await client.createSession();
          await client.send('config.get', {'key': 'model'});

          expect(requestUris, hasLength(1));
          expect(requestUris.single.path, '/api/ws');
          expect(requestUris.single.queryParameters, {'token': 'spa'});
          expect(frames.map((f) => f['method']), [
            'session.resume',
            'session.create',
            'config.get',
          ]);
          for (final frame in frames) {
            expect(
              (frame['params'] as Map<String, dynamic>)['profile'],
              'sol',
              reason: '${frame['method']} must carry the profile',
            );
          }
          expect(frames.first['params'], {
            'session_id': 'abc',
            'source': 'desktop',
            'omit_messages': true,
            'defer_history': true,
            'inline_images': false,
            'profile': 'sol',
          });
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test(
      'pins an immutable gateway.ready received before its waiter',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final callbackFrames = <Map<String, dynamic>>[];
        final applicationEvents = <StreamEvent>[];
        final readyFrame = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': 'gateway.ready',
            'payload': {
              'capabilities': ['turn.resume', 'turn.recover'],
              'limits': {
                'recovery': {'max_attempts': 2},
              },
            },
          },
        };
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              socket.add(jsonEncode(readyFrame));
            });
        final client = WsClient('http://127.0.0.1:${server.port}')
          ..onGatewayReady = callbackFrames.add
          ..onStreamEvent = applicationEvents.add;

        try {
          await client.connect();
          final frame = await client.waitForGatewayReady();

          expect(frame, readyFrame);
          expect(callbackFrames, hasLength(1));
          expect(applicationEvents, isEmpty);
          expect(
            () => (frame['params'] as Map<String, dynamic>)['type'] = 'drift',
            throwsUnsupportedError,
          );
          final payload =
              (frame['params'] as Map<String, dynamic>)['payload']
                  as Map<String, dynamic>;
          final limits = payload['limits'] as Map<String, dynamic>;
          expect(
            () => (limits['recovery'] as Map<String, dynamic>)['max_attempts'] =
                99,
            throwsUnsupportedError,
          );
          expect(
            () => (payload['capabilities'] as List<dynamic>).add('unsafe'),
            throwsUnsupportedError,
          );
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test('delivers gateway.ready to a waiter registered first', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final socketSeen = Completer<WebSocket>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socketSeen.complete(socket);
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        final readyFuture = client.waitForGatewayReady();
        final socket = await socketSeen.future;
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'type': 'gateway.ready',
              'payload': {'generation': 1},
            },
          }),
        );

        final frame = await readyFuture.timeout(const Duration(seconds: 5));
        expect((frame['params'] as Map<String, dynamic>)['payload'], {
          'generation': 1,
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('fails a gateway.ready waiter when the socket closes first', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            Timer(const Duration(milliseconds: 50), () {
              unawaited(socket.close(WebSocketStatus.goingAway, 'no ready'));
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await expectLater(
          client.waitForGatewayReady(timeout: const Duration(seconds: 5)),
          throwsA(
            isA<JsonRpcError>()
                .having((error) => error.method, 'method', 'gateway.ready')
                .having((error) => error.reason, 'reason', 'connection_closed'),
          ),
        );
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test(
      'invalidates buffered frames from a closed socket across reconnect',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final firstSocketSeen = Completer<WebSocket>();
        final secondSocketSeen = Completer<WebSocket>();
        var connectionCount = 0;
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              connectionCount += 1;
              socket.listen((_) {});
              if (connectionCount == 1) {
                firstSocketSeen.complete(socket);
              } else {
                secondSocketSeen.complete(socket);
              }
            });
        final readyGenerations = <int>[];
        final eventTexts = <String>[];
        final newEventSeen = Completer<void>();
        final connectionChanges = <bool>[];
        final client = WsClient('http://127.0.0.1:${server.port}')
          ..onGatewayReady = (frame) {
            final params = frame['params'] as Map<String, dynamic>;
            final payload = params['payload'] as Map<String, dynamic>;
            readyGenerations.add(payload['generation'] as int);
          }
          ..onStreamEvent = (event) {
            eventTexts.add(event.data['text'] as String);
            if (event.data['text'] == 'new' && !newEventSeen.isCompleted) {
              newEventSeen.complete();
            }
          }
          ..onConnectionChanged = connectionChanges.add;

        try {
          await client.connect();
          final firstSocket = await firstSocketSeen.future;
          firstSocket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'gateway.ready',
                'payload': {'generation': 1},
              },
            }),
          );
          firstSocket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'message.delta',
                'session_id': 'old-session',
                'payload': {'text': 'old'},
              },
            }),
          );
          client.close();

          await client.connect();
          final secondSocket = await secondSocketSeen.future;
          secondSocket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'gateway.ready',
                'payload': {'generation': 2},
              },
            }),
          );
          secondSocket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'message.delta',
                'session_id': 'new-session',
                'payload': {'text': 'new'},
              },
            }),
          );

          final ready = await client.waitForGatewayReady();
          await newEventSeen.future.timeout(const Duration(seconds: 5));
          expect(
            ((ready['params'] as Map<String, dynamic>)['payload']
                as Map<String, dynamic>)['generation'],
            2,
          );
          expect(readyGenerations, [2]);
          expect(eventTexts, ['new']);
          expect(connectionChanges, [true, false, true]);
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test('isolates throwing connected and disconnected observers', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSocketClosed = Completer<void>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen(
              (_) {},
              onDone: () {
                if (!serverSocketClosed.isCompleted) {
                  serverSocketClosed.complete();
                }
              },
            );
          });
      final connectionChanges = <bool>[];
      final client = WsClient('http://127.0.0.1:${server.port}')
        ..onConnectionChanged = (connected) {
          connectionChanges.add(connected);
          throw StateError('synthetic connection observer failure');
        };

      try {
        await client.connect();
        expect(client.isConnected, isTrue);
        expect(() => client.close(), returnsNormally);
        await serverSocketClosed.future.timeout(const Duration(seconds: 5));
        expect(client.isConnected, isFalse);
        expect(connectionChanges, [true, false]);
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test(
      'terminalizes every session despite throwing global and turn observers',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              socket.listen((raw) {
                final request =
                    jsonDecode(raw as String) as Map<String, dynamic>;
                if (request['method'] == 'config.get') {
                  socket.add(
                    jsonEncode({
                      'jsonrpc': '2.0',
                      'id': request['id'],
                      'result': {'config': <String, dynamic>{}},
                    }),
                  );
                  return;
                }
                requests.add(request);
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': request['id'],
                    'result': {'accepted': true},
                  }),
                );
                if (requests.length == 2) {
                  socket.add(
                    jsonEncode({
                      'jsonrpc': '2.0',
                      'method': 'event',
                      'params': {
                        'type': 'message.delta',
                        'session_id': 'shared-session',
                        'payload': {'text': 'delta'},
                      },
                    }),
                  );
                  socket.add(
                    jsonEncode({
                      'jsonrpc': '2.0',
                      'method': 'event',
                      'params': {
                        'type': 'turn.end',
                        'session_id': 'shared-session',
                        'payload': {'status': 'complete'},
                      },
                    }),
                  );
                }
              });
            });
        final globalTypes = <String>[];
        final firstTypes = <String>[];
        final secondTypes = <String>[];
        final client = WsClient('http://127.0.0.1:${server.port}')
          ..onStreamEvent = (event) {
            globalTypes.add(event.type);
            throw StateError('synthetic global observer failure');
          };

        try {
          await client.connect();
          final first = client.submitPrompt(
            'first',
            sessionId: 'shared-session',
            onEvent: (event) {
              firstTypes.add(event.type);
              throw StateError('synthetic first session observer failure');
            },
            timeout: const Duration(seconds: 5),
          );
          final second = client.submitPrompt(
            'second',
            sessionId: 'shared-session',
            onEvent: (event) {
              secondTypes.add(event.type);
              if (event.isComplete) {
                throw StateError('synthetic terminal observer failure');
              }
            },
            timeout: const Duration(seconds: 5),
          );

          await Future.wait([
            first,
            second,
          ]).timeout(const Duration(seconds: 5));
          expect(requests, hasLength(2));
          expect(globalTypes, ['message.delta', 'turn.end']);
          expect(firstTypes, ['message.delta', 'turn.end']);
          expect(secondTypes, ['message.delta', 'turn.end']);
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test('completes and cleans a stream before its observer throws', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              requests.add(request);
              if (request['method'] == 'fixture.stream') {
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': request['id'],
                    'method': 'done',
                    'params': {'status': 'complete'},
                    'result': {'accepted': true},
                  }),
                );
              } else {
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': request['id'],
                    'result': {'status': 'interrupted'},
                  }),
                );
              }
            });
          });
      var streamCallbackCount = 0;
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        final response = await client.sendStreaming(
          'fixture.stream',
          const {},
          onEvent: (_) {
            streamCallbackCount += 1;
            throw StateError('synthetic stream observer failure');
          },
          timeout: const Duration(seconds: 5),
        );
        expect(response['result'], {'accepted': true});
        expect(streamCallbackCount, 1);

        await client.interruptSession('after-stream');
        expect(requests.map((request) => request['method']), [
          'fixture.stream',
          'session.interrupt',
        ]);
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test(
      'ignores an exact ready duplicate and closes on ready drift',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final callbackFrames = <Map<String, dynamic>>[];
        final applicationEvents = <StreamEvent>[];
        final connectionChanges = <bool>[];
        final disconnected = Completer<void>();
        final serverSocketClosed = Completer<void>();
        final firstFrame = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': 'gateway.ready',
            'payload': {
              'capabilities': ['turn.resume'],
            },
          },
        };
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              socket.listen(
                (_) {},
                onDone: () {
                  if (!serverSocketClosed.isCompleted) {
                    serverSocketClosed.complete();
                  }
                },
              );
              socket.add(jsonEncode(firstFrame));
              socket.add(jsonEncode(firstFrame));
              Timer(const Duration(milliseconds: 100), () {
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'method': 'event',
                    'params': {
                      'type': 'gateway.ready',
                      'payload': {
                        'capabilities': ['turn.resume', 'unexpected'],
                      },
                    },
                  }),
                );
              });
            });
        final client = WsClient('http://127.0.0.1:${server.port}')
          ..onGatewayReady = callbackFrames.add
          ..onStreamEvent = applicationEvents.add
          ..onConnectionChanged = (connected) {
            connectionChanges.add(connected);
            if (!connected && !disconnected.isCompleted) {
              disconnected.complete();
              throw StateError('synthetic observer failure');
            }
          };

        try {
          await client.connect();
          expect(await client.waitForGatewayReady(), firstFrame);
          await disconnected.future.timeout(const Duration(seconds: 5));
          await serverSocketClosed.future.timeout(const Duration(seconds: 5));

          expect(callbackFrames, hasLength(1));
          expect(applicationEvents, isEmpty);
          expect(connectionChanges, [true, false]);
          await expectLater(
            client.waitForGatewayReady(),
            throwsA(
              isA<JsonRpcError>().having(
                (error) => error.reason,
                'reason',
                'gateway_ready_drift',
              ),
            ),
          );
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test(
      'parses complete gateway error metadata without resubmitting',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requestCount = 0;
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              socket.listen((raw) {
                final request =
                    jsonDecode(raw as String) as Map<String, dynamic>;
                requestCount += 1;
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': request['id'],
                    'error': {
                      'message': 'Synthetic denial',
                      'code': -32091,
                      'data': {
                        'reason': 'fixture_denied',
                        'safe_to_resubmit': true,
                        'nested': {
                          'attempts': [1, 2],
                        },
                      },
                    },
                  }),
                );
              });
            });
        final client = WsClient('http://127.0.0.1:${server.port}');

        try {
          await client.connect();
          JsonRpcError? surfaced;
          try {
            await client.interruptSession('fixture-session');
          } on JsonRpcError catch (error) {
            surfaced = error;
          }

          expect(surfaced, isNotNull);
          expect(surfaced!.message, 'Synthetic denial');
          expect(surfaced.code, -32091);
          expect(surfaced.reason, 'fixture_denied');
          expect(surfaced.safeToResubmit, isTrue);
          expect(surfaced.data['nested'], {
            'attempts': [1, 2],
          });
          expect(
            () =>
                ((surfaced!.data['nested'] as Map<String, dynamic>)['attempts']
                        as List<dynamic>)
                    .add(3),
            throwsUnsupportedError,
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(requestCount, 1);
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test('treats safe_to_resubmit as exact boolean metadata only', () {
      final falseError = JsonRpcError.fromGateway('fixture', {
        'data': {'safe_to_resubmit': false},
      }, fallbackMessage: 'fallback');
      final missingError = JsonRpcError.fromGateway(
        'fixture',
        const {},
        fallbackMessage: 'fallback',
      );
      final wrongTypeError = JsonRpcError.fromGateway('fixture', {
        'data': {'safe_to_resubmit': 'true'},
      }, fallbackMessage: 'fallback');

      expect(falseError.safeToResubmit, isFalse);
      expect(missingError.safeToResubmit, isFalse);
      expect(wrongTypeError.safeToResubmit, isFalse);
    });

    test(
      'removes timeout listeners across reconnect and consecutive submits',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requestCount = 0;
        var connectionCount = 0;
        final secondAck = Completer<void>();
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              connectionCount += 1;
              socket.listen((raw) {
                final request =
                    jsonDecode(raw as String) as Map<String, dynamic>;
                requestCount += 1;
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': request['id'],
                    'result': {'accepted': true},
                  }),
                );
                if (requestCount == 2 && !secondAck.isCompleted) {
                  secondAck.complete();
                }
              });
            });
        final connectionChanges = <bool>[];
        final client = WsClient('http://127.0.0.1:${server.port}')
          ..onConnectionChanged = connectionChanges.add;

        try {
          await client.connect();
          await expectLater(
            client.submitPrompt(
              'timeout fixture',
              sessionId: 'timeout-session',
              onEvent: (_) {},
              timeout: const Duration(milliseconds: 100),
            ),
            throwsA(
              isA<JsonRpcError>()
                  .having((error) => error.method, 'method', 'prompt.submit')
                  .having((error) => error.message, 'message', 'Timeout'),
            ),
          );

          client.close();
          await client.connect();
          final secondSubmit = client.submitPrompt(
            'close fixture',
            sessionId: 'close-session',
            onEvent: (_) {},
            timeout: const Duration(seconds: 5),
          );
          final secondExpectation = expectLater(
            secondSubmit,
            throwsA(
              isA<JsonRpcError>()
                  .having((error) => error.method, 'method', 'prompt.submit')
                  .having(
                    (error) => error.reason,
                    'reason',
                    'connection_closed',
                  ),
            ),
          );
          await secondAck.future.timeout(const Duration(seconds: 5));
          client.close();
          client.close();
          await secondExpectation;

          expect(requestCount, 2);
          expect(connectionCount, 2);
          expect(connectionChanges, [true, false, true, false]);
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test('fails closed when the socket closes before prompt ACK', () async {
      await _expectFailClosedPromptDisconnect(
        _PromptDisconnectPoint.beforeAck,
        expectedDeltaCount: 0,
      );
    });

    test(
      'fails closed when the socket closes after ACK before first delta',
      () async {
        await _expectFailClosedPromptDisconnect(
          _PromptDisconnectPoint.afterAckBeforeFirstDelta,
          expectedDeltaCount: 0,
        );
      },
    );

    test(
      'fails closed after two deltas without reconnect or resubmit',
      () async {
        await _expectFailClosedPromptDisconnect(
          _PromptDisconnectPoint.midStreamAfterTwoDeltas,
          expectedDeltaCount: 2,
        );
      },
    );

    test('sends the official session.interrupt JSON-RPC method', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'status': 'interrupted'},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.interruptSession('gateway-session-123');
        final request = await requestSeen.future;

        expect(request['method'], 'session.interrupt');
        expect(request['params'], {'session_id': 'gateway-session-123'});
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('file.attach sends only stock FileAttachParams wire keys', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {
                    'attached': true,
                    'name': 'fixture.txt',
                    'ref_text': '@file:fixture.txt',
                  },
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.attachFile(
          sessionId: 'gateway-session-123',
          name: 'fixture.txt',
          dataUrl: 'data:application/octet-stream;base64,ZmFrZQ==',
        );
        final request = await requestSeen.future;

        // Stock Hermes FileAttachParams is extra="forbid"; sending
        // source_channel/source_profile (fixture-only keys) makes every
        // attach fail with "Extra inputs are not permitted".
        expect(request['method'], 'file.attach');
        expect(request['params'], {
          'session_id': 'gateway-session-123',
          'name': 'fixture.txt',
          'path': '',
          'data_url': 'data:application/octet-stream;base64,ZmFrZQ==',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('sends the official session.resume JSON-RPC method', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {
                    'session_id': 'runtime-123',
                    'running': false,
                    'status': 'idle',
                    'inflight': {
                      'status': 'error',
                      'error': 'Provider unavailable',
                      'recoverable': true,
                    },
                  },
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        final resumed = await client.resumeSessionDetails('stored-123');
        expect(resumed.runtimeSessionId, 'runtime-123');
        expect(resumed.running, isFalse);
        expect(resumed.status, 'idle');
        expect(resumed.inflight, {
          'status': 'error',
          'error': 'Provider unavailable',
          'recoverable': true,
        });
        final request = await requestSeen.future;
        expect(request['method'], 'session.resume');
        expect(request['params'], {
          'session_id': 'stored-123',
          'source': 'desktop',
          'omit_messages': true,
          'defer_history': true,
          'inline_images': false,
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test(
      'creates a Project session with cwd and no client session id',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requestSeen = Completer<Map<String, dynamic>>();
        final socketSubscription = server
            .transform(WebSocketTransformer())
            .listen((socket) {
              socket.listen((raw) {
                final request =
                    jsonDecode(raw as String) as Map<String, dynamic>;
                requestSeen.complete(request);
                socket.add(
                  jsonEncode({
                    'jsonrpc': '2.0',
                    'id': request['id'],
                    'result': {
                      'session_id': 'runtime-created',
                      'stored_session_id': 'stored-created',
                    },
                  }),
                );
              });
            });
        final client = WsClient('http://127.0.0.1:${server.port}');

        try {
          await client.connect();
          final created = await client.createSession(
            workingDirectory: ' /srv/projects/hermes-android ',
          );
          expect(created.runtimeSessionId, 'runtime-created');
          expect(created.storedSessionId, 'stored-created');
          final request = await requestSeen.future;
          expect(request['method'], 'session.create');
          expect(request['params'], {
            'source': 'desktop',
            'cwd': '/srv/projects/hermes-android',
          });
          expect(request['params'], isNot(contains('session_id')));
        } finally {
          client.close();
          await socketSubscription.cancel();
          await server.close(force: true);
        }
      },
    );

    test('sends official session.title and session.branch frames', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              requests.add(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': request['method'] == 'session.branch'
                      ? {'session_id': 'branch-runtime', 'title': 'Copy'}
                      : {'ok': true},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.setSessionTitle('runtime-123', 'Renamed');
        final branch = await client.branchSession('runtime-123', name: 'Copy');
        expect(branch['session_id'], 'branch-runtime');
        expect(requests[0]['method'], 'session.title');
        expect(requests[0]['params'], {
          'session_id': 'runtime-123',
          'title': 'Renamed',
        });
        expect(requests[1]['method'], 'session.branch');
        expect(requests[1]['params'], {
          'session_id': 'runtime-123',
          'name': 'Copy',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    group('DesktopGatewayClient session binding', () {
      // The fixture mimics a secured Desktop gateway: the HTTP endpoint mints
      // a WebSocket ticket, and each upgraded socket speaks the JSON-RPC
      // session contract. session.resume is accepted only when the fixture
      // has been told the stored identity exists; otherwise it rejects with
      // 4007 so the client falls back to session.create with cwd. One fresh
      // fixture per test keeps late async socket callbacks from leaking into
      // the next test.
      //
      // TestWidgetsFlutterBinding (initialised by other tests in this file)
      // replaces HttpClient with a mock that answers every request with 400.
      // These tests talk to a real loopback server, so clear the global
      // override for the duration of the group and restore it afterwards.
      late _ProjectGatewayFixture fixture;
      HttpOverrides? savedHttpOverrides;

      Future<void> expectSoon(
        bool Function() condition, {
        String reason = 'condition',
      }) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for $reason');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      DesktopGatewayClient buildClient() {
        final connection = SavedConnection(
          id: 'conn-project',
          label: 'Project gateway',
          host: '127.0.0.1',
          port: 8642,
          apiKey: 'project-key',
          dashboardPortOverride: fixture.server.port,
          dashboardProxied: true,
          desktopGatewayUrl: 'http://127.0.0.1:${fixture.server.port}',
        );
        return DesktopGatewayClient.fromConnection(connection);
      }

      setUp(() async {
        savedHttpOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        fixture = _ProjectGatewayFixture();
        await fixture.start();
      });

      tearDown(() async {
        await fixture.stop();
        HttpOverrides.global = savedHttpOverrides;
      });

      test('a send that reconnects after the socket drops still binds the '
          'session to the Project working directory', () async {
        final client = buildClient();
        addTearDown(client.close);

        await client.ensureSession(
          'mobile-project',
          workingDirectory: '/srv/projects/hermes-android',
        );
        await expectSoon(
          () => fixture.openSockets.length == 1,
          reason: 'first WebSocket connection',
        );

        // Simulate a gateway restart that lost the stored identity: the
        // reconnect resume fails, so the next send must create the session
        // again in the remembered Project working directory.
        final states = <DesktopConnectionState>[];
        client.setConnectionListener(states.add);
        await fixture.openSockets.single.close();
        await expectSoon(
          () => states.contains(DesktopConnectionState.disconnected),
          reason: 'client observing the dropped socket',
        );
        await client
            .submitPrompt(
              sessionId: 'mobile-project',
              text: 'hello',
              onEvent: (_) {},
              onSent: () {},
            )
            .then<void>((_) {}, onError: (_) {});

        final createCalls = fixture.requests
            .where((request) => request['method'] == 'session.create')
            .toList();
        await expectSoon(
          () => createCalls.length == 2,
          reason: 'reconnect session.create with the remembered cwd',
        );
        expect(createCalls[1]['params'], {
          'source': 'desktop',
          'cwd': '/srv/projects/hermes-android',
        });
        expect(createCalls[1]['params'], isNot(contains('session_id')));
      });

      test('a lazy stock-gateway submit publishes its durable binding before '
          'the prompt completes', () async {
        final client = buildClient();
        addTearDown(client.close);
        final bindings = <(String, String)>[];
        client.setSessionBoundListener((localSessionId, storedSessionId) {
          bindings.add((localSessionId, storedSessionId));
        });

        await client
            .submitPrompt(
              sessionId: 'mobile-draft',
              text: 'Create the durable chat lazily',
              onEvent: (_) {},
              onSent: () {},
            )
            .then<void>((_) {}, onError: (_) {});

        expect(bindings, [('mobile-draft', 'stored-project')]);
        expect(client.storedSessionKeyFor('mobile-draft'), 'stored-project');
        final methods = fixture.requests
            .map((request) => request['method'])
            .toList();
        expect(
          methods,
          containsAllInOrder([
            'session.resume',
            'session.create',
            'prompt.submit',
          ]),
        );
      });

      test(
        'a reconnect after disconnect resumes the stored identity instead of '
        'creating a second session',
        () async {
          final client = buildClient();
          addTearDown(client.close);

          await client.ensureSession(
            'mobile-project',
            workingDirectory: '/srv/projects/hermes-android',
          );
          await expectSoon(
            () => fixture.openSockets.length == 1,
            reason: 'first WebSocket connection',
          );
          // The first socket rejected session.resume (unknown identity) and
          // the client then created a session, minting the stored identity.
          await expectSoon(
            () => fixture.knownStoredIds.contains('stored-project'),
            reason: 'session.create minting the stored identity',
          );
          // The fixture now knows the stored identity, so the reconnect must
          // resume instead of creating a second session.
          fixture.resumeKnownIds.add('stored-project');

          // Drop the live socket; the client must reconnect and resume with
          // the stored identity instead of creating a second session.
          final states = <DesktopConnectionState>[];
          client.setConnectionListener(states.add);
          await fixture.openSockets.single.close();
          await expectSoon(
            () => states.contains(DesktopConnectionState.disconnected),
            reason: 'client observing the dropped socket',
          );
          await client.ensureSession('mobile-project');
          await expectSoon(
            () => fixture.openSockets.length == 1,
            reason: 'reconnect WebSocket connection replacing the dropped one',
          );

          final createCalls = fixture.requests
              .where((request) => request['method'] == 'session.create')
              .toList();
          final resumeCalls = fixture.requests
              .where((request) => request['method'] == 'session.resume')
              .toList();
          expect(createCalls, hasLength(1));
          expect(createCalls.single['params'], {
            'source': 'desktop',
            'cwd': '/srv/projects/hermes-android',
          });
          expect(resumeCalls, hasLength(2));
          expect(resumeCalls.first['params'], {
            'session_id': 'mobile-project',
            'source': 'desktop',
            'omit_messages': true,
            'defer_history': true,
            'inline_images': false,
          });
          expect(resumeCalls.last['params'], {
            'session_id': 'stored-project',
            'source': 'desktop',
            'omit_messages': true,
            'defer_history': true,
            'inline_images': false,
          });
        },
      );

      test(
        'a retained resume failure emits one terminal async event',
        () async {
          final client = buildClient();
          addTearDown(client.close);

          await client.ensureSession(
            'mobile-project',
            workingDirectory: '/srv/projects/hermes-android',
          );
          await expectSoon(
            () => fixture.knownStoredIds.contains('stored-project'),
            reason: 'session.create minting the stored identity',
          );
          fixture
            ..resumeKnownIds.add('stored-project')
            ..resumeInflight = {
              'status': 'error',
              'error': 'Provider unavailable',
              'recoverable': true,
            };

          final events = <StreamEvent>[];
          final states = <DesktopConnectionState>[];
          client
            ..setAsyncEventListener((mobileSessionId, event) {
              expect(mobileSessionId, 'mobile-project');
              events.add(event);
            })
            ..setConnectionListener(states.add);

          await fixture.openSockets.single.close();
          await expectSoon(
            () => states.contains(DesktopConnectionState.disconnected),
            reason: 'client observing the dropped socket',
          );
          await client.ensureSession('mobile-project');
          await expectSoon(
            () => events.any((event) => event.type == 'turn.error'),
            reason: 'retained terminal failure delivery',
          );

          final failures = events
              .where((event) => event.type == 'turn.error')
              .toList();
          expect(failures, hasLength(1));
          expect(failures.single.isComplete, isTrue);
          expect(failures.single.data['message'], 'Provider unavailable');
          expect(failures.single.data['status'], 'error');
        },
      );
    });

    test('reads and writes session-scoped reasoning effort', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              requests.add(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': request['method'] == 'config.get'
                      ? {'key': 'reasoning', 'value': 'high'}
                      : {'key': 'reasoning', 'value': 'xhigh'},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        expect(await client.getSessionReasoning('runtime-123'), 'high');
        await client.setSessionReasoning(
          sessionId: 'runtime-123',
          effort: 'xhigh',
        );

        expect(requests[0], {
          'jsonrpc': '2.0',
          'id': requests[0]['id'],
          'method': 'config.get',
          'params': {'session_id': 'runtime-123', 'key': 'reasoning'},
        });
        expect(requests[1], {
          'jsonrpc': '2.0',
          'id': requests[1]['id'],
          'method': 'config.set',
          'params': {
            'session_id': 'runtime-123',
            'key': 'reasoning',
            'value': 'xhigh',
          },
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('rejects invalid reasoning effort before sending it', () async {
      final client = WsClient('http://127.0.0.1:1');

      expect(
        () => client.setSessionReasoning(
          sessionId: 'runtime-123',
          effort: 'impossible',
        ),
        throwsArgumentError,
      );
    });

    test('sends the official approval.respond JSON-RPC method', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'resolved': true},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.respondToApproval(
          sessionId: 'gateway-session-123',
          choice: 'session',
        );
        final request = await requestSeen.future;

        expect(request['method'], 'approval.respond');
        expect(request['params'], {
          'session_id': 'gateway-session-123',
          'choice': 'session',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('sends the official sudo.respond JSON-RPC method', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'status': 'ok'},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.respondToSudo(
          requestId: 'sudo-request-123',
          password: 'synthetic-password',
        );
        final request = await requestSeen.future;

        expect(request['method'], 'sudo.respond');
        expect(request['params'], {
          'request_id': 'sudo-request-123',
          'password': 'synthetic-password',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('sends the official secret.respond JSON-RPC method', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'status': 'ok'},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.respondToSecret(
          requestId: 'secret-request-123',
          value: 'synthetic-secret',
        );
        final request = await requestSeen.future;

        expect(request['method'], 'secret.respond');
        expect(request['params'], {
          'request_id': 'secret-request-123',
          'value': 'synthetic-secret',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('sends the official clarify.respond JSON-RPC method', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'status': 'expired'},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.respondToClarify(
          requestId: 'clarify-request-123',
          questionId: 'q1',
          answer: 'Balanced',
        );
        final request = await requestSeen.future;

        expect(request['method'], 'clarify.respond');
        expect(request['params'], {
          'request_id': 'clarify-request-123',
          'question_id': 'q1',
          'answer': 'Balanced',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('locks batch clarify answers with clarify.lock', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestSeen = Completer<Map<String, dynamic>>();
      final socketSubscription = server
          .transform(WebSocketTransformer())
          .listen((socket) {
            socket.listen((raw) {
              final request = jsonDecode(raw as String) as Map<String, dynamic>;
              if (!requestSeen.isCompleted) requestSeen.complete(request);
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': request['id'],
                  'result': {'status': 'ok', 'remaining': <String>[]},
                }),
              );
            });
          });
      final client = WsClient('http://127.0.0.1:${server.port}');

      try {
        await client.connect();
        await client.respondToClarify(
          requestId: 'clarify-request-123',
          questionId: 'q1',
          answer: 'Balanced',
          lockAnswer: true,
        );
        final request = await requestSeen.future;

        expect(request['method'], 'clarify.lock');
        expect(request['params'], {
          'request_id': 'clarify-request-123',
          'question_id': 'q1',
          'answer': 'Balanced',
        });
      } finally {
        client.close();
        await socketSubscription.cancel();
        await server.close(force: true);
      }
    });

    test('rejects an invalid approval choice before sending it', () async {
      final client = WsClient('http://127.0.0.1:1');

      expect(
        () => client.respondToApproval(
          sessionId: 'gateway-session-123',
          choice: 'unsafe',
        ),
        throwsArgumentError,
      );
    });

    test('unwraps a gateway event into its session payload', () {
      final event = WsClient.parseGatewayEvent({
        'type': 'message.delta',
        'sid': 'session-123',
        'payload': {'text': 'Hello'},
      });

      expect(event, isNotNull);
      expect(event!.type, 'message.delta');
      expect(event.data, {'text': 'Hello', 'session_id': 'session-123'});
      expect(event.isComplete, isFalse);
    });

    test('unwraps the real gateway session_id event field', () {
      final event = WsClient.parseGatewayEvent({
        'type': 'message.delta',
        'session_id': 'gateway-session-123',
        'payload': {'text': 'Hello'},
      });

      expect(event, isNotNull);
      expect(event!.data, {
        'text': 'Hello',
        'session_id': 'gateway-session-123',
      });
    });

    test('snapshots exact typed event envelope convenience fields', () {
      final params = <String, dynamic>{
        'type': 'message.delta',
        'session_id': 'gateway-session-123',
        'turn_id': 'turn-456',
        'seq': 7,
        'message_id': 'message-789',
        'payload': {
          'text': 'Hello',
          'nested': {
            'parts': ['one', 'two'],
          },
        },
      };
      final event = WsClient.parseGatewayEvent(params);

      expect(event, isNotNull);
      expect(event!.sessionId, 'gateway-session-123');
      expect(event.turnId, 'turn-456');
      expect(event.seq, 7);
      expect(event.messageId, 'message-789');
      expect(event.envelope, params);

      (params['payload'] as Map<String, dynamic>)['text'] = 'mutated source';
      params['turn_id'] = 'mutated source';
      expect(event.data['text'], 'Hello');
      expect(event.turnId, 'turn-456');
      expect(event.envelope['turn_id'], 'turn-456');
      expect(
        () =>
            ((event.data['nested'] as Map<String, dynamic>)['parts']
                    as List<dynamic>)
                .add('three'),
        throwsUnsupportedError,
      );
      expect(() => event.envelope['seq'] = 8, throwsUnsupportedError);
    });

    test('does not normalize wrong envelope field types', () {
      final event = WsClient.parseGatewayEvent({
        'type': 'message.delta',
        'session_id': 123,
        'sid': false,
        'turn_id': 456,
        'seq': '7',
        'message_id': 789,
        'payload': {'text': 'Hello'},
      });

      expect(event, isNotNull);
      expect(event!.sessionId, isNull);
      expect(event.turnId, isNull);
      expect(event.seq, isNull);
      expect(event.messageId, isNull);
      expect(event.data.containsKey('session_id'), isFalse);
    });

    test('rejects untrimmed control or overbound envelope IDs', () {
      final invalidIds = <String>[
        ' leading',
        'trailing ',
        'line\nbreak',
        'delete\u007fcontrol',
        'c1\u0085control',
        List<String>.filled(257, 'x').join(),
      ];

      for (final invalidId in invalidIds) {
        final event = WsClient.parseGatewayEvent({
          'type': 'message.delta',
          'session_id': invalidId,
          'sid': false,
          'turn_id': invalidId,
          'seq': 1,
          'message_id': invalidId,
          'payload': {'text': 'Hello'},
        });

        expect(event, isNotNull, reason: invalidId);
        expect(event!.sessionId, isNull, reason: invalidId);
        expect(event.turnId, isNull, reason: invalidId);
        expect(event.messageId, isNull, reason: invalidId);
        expect(
          event.data.containsKey('session_id'),
          isFalse,
          reason: invalidId,
        );
      }

      final boundaryId = List<String>.filled(256, 'x').join();
      final boundaryEvent = WsClient.parseGatewayEvent({
        'type': 'message.delta',
        'session_id': boundaryId,
        'turn_id': boundaryId,
        'seq': 1,
        'message_id': boundaryId,
        'payload': const <String, dynamic>{},
      });
      expect(boundaryEvent?.sessionId, boundaryId);
      expect(boundaryEvent?.turnId, boundaryId);
      expect(boundaryEvent?.messageId, boundaryId);
    });

    test('accepts only an exact positive integer event sequence', () {
      for (final invalidSeq in <Object?>[0, -1, 1.0, '1', true, null]) {
        final event = WsClient.parseGatewayEvent({
          'type': 'message.delta',
          'session_id': 'session-123',
          'seq': invalidSeq,
          'payload': const <String, dynamic>{},
        });
        expect(event?.seq, isNull, reason: '$invalidSeq');
      }

      expect(
        WsClient.parseGatewayEvent({
          'type': 'message.delta',
          'session_id': 'session-123',
          'seq': 1,
          'payload': const <String, dynamic>{},
        })?.seq,
        1,
      );
    });

    test('marks a gateway turn error as terminal', () {
      final event = WsClient.parseGatewayEvent({
        'type': 'turn.error',
        'sid': 'session-123',
        'payload': {'message': 'failed'},
      });

      expect(event?.isComplete, isTrue);
    });

    test('marks the real gateway message.complete event as terminal', () {
      final event = WsClient.parseGatewayEvent({
        'type': 'message.complete',
        'sid': 'session-123',
        'payload': {'text': 'Done', 'status': 'complete'},
      });

      expect(event?.isComplete, isTrue);
    });

    test('marks the real gateway error event as terminal', () {
      final event = WsClient.parseGatewayEvent({
        'type': 'error',
        'sid': 'session-123',
        'payload': {'message': 'failed'},
      });

      expect(event?.isComplete, isTrue);
    });

    test('omits bare custom provider from an early session model switch', () {
      expect(
        WsClient.buildSessionModelValue(
          provider: 'custom',
          model: 'hermes-android-fixture',
        ),
        'hermes-android-fixture --session',
      );
      expect(
        WsClient.buildSessionModelValue(
          provider: 'anthropic',
          model: 'claude-sonnet-4.6',
        ),
        'claude-sonnet-4.6 --provider anthropic --session',
      );
    });
  });
}

/// Minimal secured Desktop gateway fixture: mints WebSocket tickets over HTTP
/// and speaks the JSON-RPC session contract on each upgraded socket.
class _ProjectGatewayFixture {
  late final HttpServer server;
  final requests = <Map<String, dynamic>>[];
  final openSockets = <WebSocket>[];
  final perSocketRequests = <List<Map<String, dynamic>>>[];
  final knownStoredIds = <String>{};
  final resumeKnownIds = <String>{};
  Map<String, dynamic>? resumeInflight;
  var ticketCount = 0;

  void safeAdd(WebSocket socket, Map<String, dynamic> frame) {
    // Tests close sockets while the fixture may still be answering an earlier
    // frame; a write to a closed sink is a fixture artefact, not client
    // behaviour.
    try {
      socket.add(jsonEncode(frame));
    } on StateError {
      // Socket already closed.
    }
  }

  void handleSocket(WebSocket socket) {
    final requestsForSocket = <Map<String, dynamic>>[];
    openSockets.add(socket);
    perSocketRequests.add(requestsForSocket);
    socket.listen(
      (raw) {
        final request = jsonDecode(raw as String) as Map<String, dynamic>;
        requestsForSocket.add(request);
        requests.add(request);
        final params = request['params'] as Map<String, dynamic>?;
        if (request['method'] == 'session.resume') {
          if (resumeKnownIds.contains(params?['session_id'])) {
            safeAdd(socket, {
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': {
                'session_id': 'runtime-resumed',
                'running': false,
                'status': resumeInflight == null ? 'idle' : 'working',
                'inflight': ?resumeInflight,
              },
            });
          } else {
            safeAdd(socket, {
              'jsonrpc': '2.0',
              'id': request['id'],
              'error': {'code': 4007, 'message': 'session not found'},
            });
          }
          return;
        }
        if (request['method'] == 'session.create') {
          knownStoredIds.add('stored-project');
          safeAdd(socket, {
            'jsonrpc': '2.0',
            'id': request['id'],
            'result': {
              'session_id': 'runtime-project',
              'stored_session_id': 'stored-project',
            },
          });
          return;
        }
        if (request['method'] == 'prompt.submit') {
          // Fail the turn fast: this fixture only asserts the session
          // lifecycle wire contract, not streaming turn delivery.
          safeAdd(socket, {
            'jsonrpc': '2.0',
            'id': request['id'],
            'error': {'code': 4005, 'message': 'fixture turns off'},
          });
          return;
        }
        safeAdd(socket, {
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': {'ok': true},
        });
      },
      onDone: () {
        openSockets.remove(socket);
        perSocketRequests.remove(requestsForSocket);
      },
    );
  }

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.uri.path == '/api/auth/ws-ticket') {
          ticketCount += 1;
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'ticket': 'TICKET_$ticketCount'}));
          await request.response.close();
        } else if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          handleSocket(socket);
        } else {
          request.response
            ..statusCode = 404
            ..write('not found');
          await request.response.close();
        }
      } catch (_) {
        // A fixture request that cannot be answered must not take down the
        // whole test suite; the failing assertion will surface the cause.
      }
    });
  }

  Future<void> stop() async {
    for (final socket in List<WebSocket>.from(openSockets)) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
