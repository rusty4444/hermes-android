// A chat parked on a Hermes `clarify` shows its question card again when the
// app attaches later: a client that connects after the question was asked gets
// no live `clarify` frame, only `open_requests` in the `session.resume` reply.
// The fixture is the real shape of that reply (Hermes 0.23, session authority).
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

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'test/fixtures/nextgen_resume_with_clarify.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

/// Loopback gateway: `session.resume` answers with [resumes] in order (the last
/// one repeats); `session.events.since` is refused like an older gateway.
Future<HttpServer> _server(List<Map<String, dynamic>> resumes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var resumed = 0;
  server.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    ws.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'gateway.ready',
          'payload': {'replay_epoch': 'e1', 'session_authority': true},
        },
      }),
    );
    ws.listen((raw) {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      final method = frame['method'];
      final id = frame['id'];
      if (method == 'session.resume') {
        final result =
            resumes[resumed < resumes.length ? resumed : resumes.length - 1];
        resumed++;
        ws.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
      } else if (method == 'session.events.since') {
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': 4000, 'message': 'unsupported'},
          }),
        );
      } else if (id != null) {
        ws.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': {}}));
      }
    });
  });
  return server;
}

/// A gateway whose socket is a real [WsClient] feeding [acceptServerRequest]
/// the way the app wires it.
class _LiveGateway extends NextGenGateway {
  _LiveGateway(super.connection, this.ws, {super.dashboard}) {
    readyFrame = const {'replay_epoch': 'e1'};
    ws.onServerRequest = acceptServerRequest;
  }

  final WsClient ws;

  @override
  WsClient? get socket => ws;

  @override
  Future<WsClient> connected({
    Duration timeout = const Duration(seconds: 20),
  }) async => ws;

  @override
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await ws.send(method, params, timeout: timeout);
    final result = response['result'];
    if (response['error'] != null) throw StateError('${response['error']}');
    return Map<String, dynamic>.from(result as Map);
  }
}

Future<({NgChatController chat, NextGenGateway gateway})> _open(
  HttpServer server,
  void Function(void Function()) addTeardown,
) async {
  final ws = WsClient('http://127.0.0.1:${server.port}');
  final httpClient = MockClient(
    (request) async => http.Response(
      jsonEncode({'messages': const <Object>[]}),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );
  final gateway = _LiveGateway(
    _connection(),
    ws,
    dashboard: DashboardClient(
      host: '10.0.0.5',
      proxied: true,
      httpClient: httpClient,
    ),
  );
  // The handler must be wired before connect so the gateway is told this
  // client answers server requests.
  await ws.connect().timeout(const Duration(seconds: 5));
  await ws.waitForGatewayReady().timeout(const Duration(seconds: 5));
  final chat = NgChatController(
    gateway,
    sessionId: _fixture()['session_id'] as String,
  );
  addTeardown(() {
    chat.dispose();
    gateway.dispose();
    ws.close();
    httpClient.close();
  });
  return (chat: chat, gateway: gateway);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('opening a chat parked on a clarify shows its five questions', () async {
    final server = await _server([_fixture()]);
    addTearDown(() => server.close(force: true));
    final o = await _open(server, addTearDown);

    await o.chat.open();

    final request = o.chat.request;
    expect(request, isNotNull);
    expect(request!.kind, NgRequestKind.clarify);
    expect(request.questions, hasLength(5));
    expect(request.questions.first.qid, 'q0');
    expect(o.gateway.needsYou, {_fixture()['session_id']});
  });

  test('a chat that missed the question shows it after a resync', () async {
    final quiet = _fixture()
      ..['running'] = false
      ..['open_requests'] = const <Object>[];
    final server = await _server([quiet, _fixture()]);
    addTearDown(() => server.close(force: true));
    final o = await _open(server, addTearDown);
    await o.chat.open();
    expect(o.chat.request, isNull);

    o.chat.resync();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (o.chat.request == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(o.chat.request, isNotNull);
    expect(o.chat.request!.questions, hasLength(5));
  });
}
