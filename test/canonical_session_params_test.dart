// Regression for #291: Hermes 0.23+ gateways route session RPCs through the
// canonical session authority, whose params models are extra="forbid".
// `session.create` with the legacy `source: 'desktop'` and `session.resume`
// with the legacy-only `inline_images` key are refused with invalid_params,
// which broke sending ("Not sent: invalid_params") and live updates
// ("Live updates are unavailable") on v4.0.8.
//
// The wire fakes below enforce the real canonical contract:
// CanonicalCreateParams.source is Literal['cli','tui','gui','acp','tool',
// 'oneshot'] and CanonicalResumeParams has no inline_images field. Legacy
// gateways (no session_authority in gateway.ready) keep the desktop hint and
// inline_images.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _canonicalSources = {'cli', 'tui', 'gui', 'acp', 'tool', 'oneshot'};

SavedConnection _connection() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
  dashboardProxied: true,
);

/// Loopback gateway that records session.create / session.resume params and,
/// when [authority] is set, refuses the legacy-only shapes exactly like the
/// canonical params models do.
Future<HttpServer> _gatewayServer({
  required bool authority,
  required List<Map<String, dynamic>> recorded,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'gateway.ready',
          'payload': {
            'change_events': true,
            'heartbeat': true,
            'replay_epoch': 'test-epoch',
            if (authority) 'session_authority': true,
          },
        },
      }),
    );
    ws.listen((raw) {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      final method = frame['method'];
      if (method != 'session.create' && method != 'session.resume') return;
      final params = Map<String, dynamic>.from(frame['params'] as Map);
      recorded.add({'method': method, ...params});
      final id = frame['id'];
      void refuse(String message) {
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': 4000, 'message': 'Invalid params: $message'},
          }),
        );
      }

      if (method == 'session.create') {
        if (authority && !_canonicalSources.contains(params['source'])) {
          refuse(
            "source: Input should be 'cli', 'tui', 'gui', 'acp', 'tool' or "
            "'oneshot'",
          );
          return;
        }
        // Full extra=forbid parity for the keys the app may send.
        const allowed = {
          'source',
          'cwd',
          'model',
          'provider',
          'reasoning',
          'profile',
        };
        if (authority) {
          for (final key in params.keys) {
            if (!allowed.contains(key)) {
              refuse('$key: Extra inputs are not permitted');
              return;
            }
          }
        }
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'session_id': 'rt-new',
              'stored_session_id': 'stored-new',
              'message_count': 0,
              'messages': const <Object>[],
            },
          }),
        );
        return;
      }
      if (authority && params.containsKey('inline_images')) {
        refuse('inline_images: Extra inputs are not permitted');
        return;
      }
      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'session_id': 'rt-1',
            'running': false,
            'inflight': null,
            'open_requests': const <Object>[],
          },
        }),
      );
    });
  });
  return server;
}

class _RecordedCall {
  final String method;
  final Map<String, dynamic> params;
  const _RecordedCall(this.method, this.params);
}

class _FakeGateway extends NextGenGateway {
  _FakeGateway(
    super.connection, {
    super.dashboard,
    required this.onCall,
    Map<String, dynamic>? ready,
    this.liveSocket,
  }) {
    readyFrame = ready;
  }

  final Future<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic> params,
  )
  onCall;

  final List<_RecordedCall> calls = [];
  final WsClient? liveSocket;
  final WsClient _dummySocket = WsClient('http://10.0.0.5:9119');

  @override
  WsClient? get socket => liveSocket ?? _dummySocket;

  @override
  Future<WsClient> connected({
    Duration timeout = const Duration(seconds: 20),
  }) async => liveSocket ?? _dummySocket;

  @override
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    calls.add(_RecordedCall(method, Map<String, dynamic>.from(params)));
    return onCall(method, params);
  }
}

/// NextGen fake that enforces the canonical contract on the recorded calls.
Future<Map<String, dynamic>> _strictCall(
  String method,
  Map<String, dynamic> params,
) async {
  if (method == 'session.create') {
    if (!_canonicalSources.contains(params['source'])) {
      throw JsonRpcError(
        'session.create',
        "Invalid params: source: Input should be 'cli', 'tui', 'gui', 'acp', "
            "'tool' or 'oneshot'",
        code: 4000,
      );
    }
    return {
      'session_id': 'rt-new',
      'stored_session_id': 'stored-new',
      'revision': 1,
      'execution_generation': 0,
      'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
    };
  }
  if (method == 'session.resume') {
    if (params.containsKey('inline_images')) {
      throw JsonRpcError(
        'session.resume',
        'Invalid params: inline_images: Extra inputs are not permitted',
        code: 4000,
      );
    }
    return {
      'session_id': 'rt-1',
      'revision': 4,
      'execution_generation': 2,
      'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
    };
  }
  if (method == 'prompt.submit') return {'status': 'started'};
  return const {};
}

MockClient _mockHttp() => MockClient((request) async {
  if (request.url.path.contains('/messages')) {
    return http.Response(
      jsonEncode({'messages': const <Object>[]}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response(
    jsonEncode({'model': 'gpt-5-mini', 'provider': 'openai'}),
    200,
    headers: {'content-type': 'application/json'},
  );
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('readyFrameHasSessionAuthority wire shape (#291)', () {
    test('reads the flag from params.payload like the real gateway', () {
      expect(
        WsClient.readyFrameHasSessionAuthority(const {
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        }),
        isTrue,
      );
    });
    test('a flat top-level flag is not the wire shape and must not match', () {
      expect(
        WsClient.readyFrameHasSessionAuthority(const {
          'session_authority': true,
        }),
        isFalse,
      );
      expect(
        WsClient.readyFrameHasSessionAuthority(const {
          'params': {'type': 'gateway.ready', 'session_authority': true},
        }),
        isFalse,
      );
    });
    test('legacy and absent frames report no authority', () {
      expect(WsClient.readyFrameHasSessionAuthority(null), isFalse);
      expect(
        WsClient.readyFrameHasSessionAuthority(const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'replay_epoch': 'e1'},
          },
        }),
        isFalse,
      );
    });
  });

  group('WsClient canonical session params (#291)', () {
    test(
      'createSession uses a canonical source on authority gateways',
      () async {
        final recorded = <Map<String, dynamic>>[];
        final server = await _gatewayServer(
          authority: true,
          recorded: recorded,
        );
        addTearDown(() => server.close(force: true));
        final client = WsClient('http://127.0.0.1:${server.port}');
        addTearDown(client.close);
        await client.connect().timeout(const Duration(seconds: 5));
        await client.waitForGatewayReady().timeout(const Duration(seconds: 5));

        final created = await client.createSession();
        expect(created.runtimeSessionId, 'rt-new');
        expect(created.storedSessionId, 'stored-new');
        final create = recorded.singleWhere(
          (p) => p['method'] == 'session.create',
        );
        expect(create['source'], 'gui');
      },
    );

    test(
      'resumeSessionDetails omits inline_images on authority gateways',
      () async {
        final recorded = <Map<String, dynamic>>[];
        final server = await _gatewayServer(
          authority: true,
          recorded: recorded,
        );
        addTearDown(() => server.close(force: true));
        final client = WsClient('http://127.0.0.1:${server.port}');
        addTearDown(client.close);
        await client.connect().timeout(const Duration(seconds: 5));
        await client.waitForGatewayReady().timeout(const Duration(seconds: 5));

        final resumed = await client.resumeSessionDetails('stored-1');
        expect(resumed.runtimeSessionId, 'rt-1');
        final resume = recorded.singleWhere(
          (p) => p['method'] == 'session.resume',
        );
        expect(resume.containsKey('inline_images'), isFalse);
        expect(resume['session_id'], 'stored-1');
      },
    );

    test('legacy gateways keep the desktop hint and inline_images', () async {
      final recorded = <Map<String, dynamic>>[];
      final server = await _gatewayServer(authority: false, recorded: recorded);
      addTearDown(() => server.close(force: true));
      final client = WsClient('http://127.0.0.1:${server.port}');
      addTearDown(client.close);
      await client.connect().timeout(const Duration(seconds: 5));
      await client.waitForGatewayReady().timeout(const Duration(seconds: 5));

      await client.createSession();
      await client.resumeSessionDetails('stored-1');
      final create = recorded.singleWhere(
        (p) => p['method'] == 'session.create',
      );
      final resume = recorded.singleWhere(
        (p) => p['method'] == 'session.resume',
      );
      expect(create['source'], 'desktop');
      expect(resume['source'], 'desktop');
      expect(resume['inline_images'], false);
    });
  });

  group('NextGen canonical session params (#291)', () {
    test(
      'new chat creates with a canonical source on authority gateways',
      () async {
        final gateway = _FakeGateway(
          _connection(),
          ready: const {
            'params': {
              'type': 'gateway.ready',
              'payload': {'session_authority': true},
            },
          },
          onCall: _strictCall,
        );
        final chat = NgChatController(gateway);
        addTearDown(() {
          chat.dispose();
          gateway.dispose();
        });

        final sent = await chat.send('Hello');
        expect(sent, isTrue);
        final create = gateway.calls.singleWhere(
          (c) => c.method == 'session.create',
        );
        expect(create.params['source'], 'gui');
      },
    );

    test(
      'opening a chat resumes without inline_images on authority gateways',
      () async {
        final httpClient = _mockHttp();
        final dashboard = DashboardClient(
          host: '10.0.0.5',
          proxied: true,
          httpClient: httpClient,
        );
        final gateway = _FakeGateway(
          _connection(),
          dashboard: dashboard,
          ready: const {
            'params': {
              'type': 'gateway.ready',
              'payload': {'session_authority': true},
            },
          },
          onCall: _strictCall,
        );
        final chat = NgChatController(gateway, sessionId: 'stored-1');
        addTearDown(() {
          chat.dispose();
          gateway.dispose();
          httpClient.close();
        });

        await chat.open();
        expect(chat.error, isNull);
        expect(chat.runtimeId, 'rt-1');
        final resume = gateway.calls.singleWhere(
          (c) => c.method == 'session.resume',
        );
        expect(resume.params.containsKey('inline_images'), isFalse);
        expect(resume.params['session_id'], 'stored-1');
      },
    );

    test(
      'catch-up resync resumes without inline_images on authority gateways',
      () async {
        final recorded = <Map<String, dynamic>>[];
        final server = await _gatewayServer(
          authority: true,
          recorded: recorded,
        );
        addTearDown(() => server.close(force: true));
        final liveSocket = WsClient('http://127.0.0.1:${server.port}');
        addTearDown(liveSocket.close);
        await liveSocket.connect().timeout(const Duration(seconds: 5));
        await liveSocket.waitForGatewayReady().timeout(
          const Duration(seconds: 5),
        );

        final httpClient = _mockHttp();
        final dashboard = DashboardClient(
          host: '10.0.0.5',
          proxied: true,
          httpClient: httpClient,
        );
        final gateway = _FakeGateway(
          _connection(),
          dashboard: dashboard,
          liveSocket: liveSocket,
          ready: const {
            'params': {
              'type': 'gateway.ready',
              'payload': {'session_authority': true},
            },
          },
          onCall: _strictCall,
        );
        final chat = NgChatController(gateway, sessionId: 'stored-1');
        addTearDown(() {
          chat.dispose();
          gateway.dispose();
          httpClient.close();
        });

        await chat.open();
        expect(chat.runtimeId, 'rt-1');
        chat.resync();
        // The catch-up runs unawaited; wait for its resume to land.
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (gateway.calls.where((c) => c.method == 'session.resume').length <
                2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final resumes = gateway.calls
            .where((c) => c.method == 'session.resume')
            .toList();
        expect(resumes, hasLength(2));
        for (final r in resumes) {
          expect(r.params.containsKey('inline_images'), isFalse);
          expect(r.params['session_id'], 'stored-1');
        }
      },
    );

    test(
      'legacy gateways keep desktop create and inline_images resume',
      () async {
        final httpClient = _mockHttp();
        final dashboard = DashboardClient(
          host: '10.0.0.5',
          proxied: true,
          httpClient: httpClient,
        );
        final gateway = _FakeGateway(
          _connection(),
          dashboard: dashboard,
          ready: const {'replay_epoch': 'e1'},
          onCall: (method, params) async {
            if (method == 'session.create') {
              return {
                'session_id': 'rt-new',
                'stored_session_id': 'stored-new',
                'revision': 1,
                'execution_generation': 0,
                'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
              };
            }
            if (method == 'session.resume') {
              return {
                'session_id': 'rt-1',
                'revision': 4,
                'execution_generation': 2,
                'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
              };
            }
            if (method == 'prompt.submit') return {'status': 'started'};
            return const {};
          },
        );
        final chat = NgChatController(gateway, sessionId: 'stored-1');
        addTearDown(() {
          chat.dispose();
          gateway.dispose();
          httpClient.close();
        });

        await chat.open();
        expect(chat.error, isNull);
        final resume = gateway.calls.singleWhere(
          (c) => c.method == 'session.resume',
        );
        expect(resume.params['source'], 'desktop');
        expect(resume.params['inline_images'], false);

        final fresh = NgChatController(gateway);
        addTearDown(fresh.dispose);
        final sent = await fresh.send('Hello');
        expect(sent, isTrue);
        final create = gateway.calls.singleWhere(
          (c) => c.method == 'session.create',
        );
        expect(create.params['source'], 'desktop');
      },
    );
  });
}
