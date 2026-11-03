import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';

void main() {
  for (final warmSocket in [false, true]) {
    for (final create in [false, true]) {
      test(
        'L1 shared ${create ? 'create' : 'resume'} completion after observer close '
        '(warm socket=$warmSocket) cannot resurrect the old owner',
        () async {
          final gateway = await _Gateway.start();
          final old = gateway.client();
          final current = gateway.client();
          addTearDown(() async {
            old.close();
            current.close();
            await gateway.close();
          });
          if (warmSocket) {
            await old.ensureSession('warm');
            await gateway.take('session.resume');
          }
          final heldMethod = create ? 'session.create' : 'session.resume';
          if (create) gateway.missing.add('local');
          gateway.held.add(heldMethod);
          var bindings = 0;
          var creations = 0;
          old.setSessionBoundListener((local, stored) {
            if (local != 'local') return;
            bindings++;
            old.close();
            old.close();
          }, onCreated: (_, _) => creations++);
          final first = _outcome(old.ensureSession('local'));
          final second = _outcome(old.ensureSession('local'));
          final held = await gateway.take(heldMethod);
          gateway.held.remove(heldMethod);
          held.replyDefault();
          final outcomes = await Future.wait([first, second]);

          // Both callers are real consumers of the same transport future.
          // The first observer closes synchronously, before the second await
          // continuation consumes the already-successful socket response.
          expect(old.storedSessionKeyFor('local'), isNull);
          expect(bindings, 1);
          expect(creations, create ? 1 : 0);
          expect(outcomes, everyElement(isA<StateError>()));
          expect(
            gateway
                .calls(heldMethod, socket: held.socket)
                .where((rpc) => create || rpc.params['session_id'] == 'local'),
            hasLength(1),
          );

          final currentBindings = <String>[];
          current.setSessionBoundListener((_, stored) {
            currentBindings.add(stored);
          });
          await current.ensureSession('local');
          final key = current.storedSessionKeyFor('local');
          expect(key, isNotNull);
          old.close();
          await current.renameSession(sessionId: 'local', title: 'Still owned');
          expect(current.storedSessionKeyFor('local'), key);
          expect(currentBindings, [key]);
        },
      );
    }
  }

  test('L1 close before a held resume reply rejects the pending RPC', () async {
    final gateway = await _Gateway.start();
    final client = gateway.client();
    addTearDown(() async {
      client.close();
      await gateway.close();
    });
    gateway.held.add('session.resume');
    var callbacks = 0;
    client.setSessionBoundListener((_, _) => callbacks++);
    final pending = _outcome(client.ensureSession('local'));
    await gateway.take('session.resume');
    client.close();
    expect(await pending, anyOf(isA<JsonRpcError>(), isA<StateError>()));
    expect(client.storedSessionKeyFor('local'), isNull);
    expect(callbacks, 0);
    expect(gateway.calls('session.create'), isEmpty);
  });

  test(
    'L1 deferred failure cannot notify a listener installed after close',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(() async {
        client.close();
        await gateway.close();
      });
      gateway.held.add('session.resume');
      var lateEvents = 0;
      final closed = Completer<void>();
      client.setSessionBoundListener((_, _) {
        scheduleMicrotask(() {
          client.close();
          // A retained consumer may register while its teardown is unwinding.
          client.setAsyncEventListener((_, _) => lateEvents++);
          closed.complete();
        });
      });
      final pending = _outcome(client.ensureSession('local'));
      (await gateway.take('session.resume')).reply({
        'session_id': 'runtime-local',
        'running': false,
        'status': 'error',
        'inflight': {'status': 'error', 'error': 'Detached failure'},
      });
      await pending;
      await closed.future.timeout(_deadline);
      expect(client.storedSessionKeyFor('local'), isNull);
      expect(lateEvents, 0);
    },
  );

  test(
    'L1 close from empty-create proof prevents the binding callback',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(() async {
        client.close();
        await gateway.close();
      });
      gateway.missing.add('local');
      var creations = 0;
      var bindings = 0;
      client.setSessionBoundListener(
        (_, _) => bindings++,
        onCreated: (_, _) {
          creations++;
          client.close();
        },
      );
      final result = await _outcome(client.ensureSession('local'));
      expect(creations, 1);
      expect(bindings, 0);
      expect(client.storedSessionKeyFor('local'), isNull);
      expect(result, isA<StateError>());
    },
  );

  test(
    'L1 rejecting binding after close cannot roll back into cleared maps',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(() async {
        client.close();
        await gateway.close();
      });
      client.bindStoredSession('local', 'stored');
      client.setSessionBoundListener((_, _) {
        client.close();
        throw StateError('Owner rejected binding while being disposed');
      });
      await expectLater(client.ensureSession('local'), throwsStateError);
      expect(client.storedSessionKeyFor('local'), isNull);
    },
  );

  test(
    'L1 resume acceptance callback cannot close then republish binding',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(() async {
        client.close();
        await gateway.close();
      });
      var bindings = 0;
      client.setSessionBoundListener((_, _) => bindings++);
      final result = await _outcome(
        client.resumeSubmittedSession(
          localSessionId: 'local',
          storedSessionId: 'stored',
          acceptsResult: () {
            client.close();
            return true;
          },
        ),
      );
      expect(client.storedSessionKeyFor('local'), isNull);
      expect(bindings, 0);
      expect(result, isA<StateError>());
    },
  );

  test(
    'L1 request admission closing the owner cannot retain a new approval',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(() async {
        client.close();
        await gateway.close();
      });
      await client.ensureSession('local');
      final admitted = Completer<void>();
      var events = 0;
      client.setAsyncEventListener(
        (_, _) => events++,
        acceptsSession: (_) {
          client.close();
          admitted.complete();
          return true;
        },
      );
      gateway.request('approval-after-close', 'approval', {
        'session_id': 'runtime-local',
        'choices': ['once', 'deny'],
      });
      await admitted.future.timeout(_deadline);
      expect(client.ownsApprovalRequest('local'), isFalse);
      expect(client.storedSessionKeyFor('local'), isNull);
      expect(events, 0);
    },
  );

  test(
    'L1 closing during replay stops sibling callbacks and retained requests',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      final events = _Events(client);
      addTearDown(() async {
        client.close();
        await events.close();
        await gateway.close();
      });
      await client.ensureSession('local');
      final first = await _clarify(gateway, events, 'first');
      final second = await _clarify(gateway, events, 'second');
      var replays = 0;
      client.setAsyncEventListener((_, _) {
        replays++;
        client.close();
      });
      client.replayServerRequestsForSession('local');
      expect(replays, 1);
      expect(client.ownsServerRequest(first, 'clarify'), isFalse);
      expect(client.ownsServerRequest(second, 'clarify'), isFalse);
    },
  );

  test(
    'L1 closed client refuses new bindings and session work without RPC',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(gateway.close);
      await client.ensureSession('local');
      client.close();
      final before = gateway.requests.length;
      expect(
        () => client.bindStoredSession('late', 'stored'),
        throwsStateError,
      );
      await expectLater(
        client.ensureSession('late', workingDirectory: '/must/not/be/retained'),
        throwsStateError,
      );
      expect(client.storedSessionKeyFor('late'), isNull);
      expect(gateway.requests, hasLength(before));
      client.close();
    },
  );

  for (final retirement in ['disconnect', 'cancel', 'settle']) {
    test(
      'L4 $retirement rejects a forgotten clarify key without RPC or resend',
      () async {
        final gateway = await _Gateway.start();
        final client = gateway.client();
        final events = _Events(client);
        addTearDown(() async {
          client.close();
          await events.close();
          await gateway.close();
        });
        client.setReconnectAllowed(false);
        await client.ensureSession('local');
        final oldKey = await _clarify(gateway, events, 'reused');
        if (retirement == 'disconnect') {
          final disconnected = Completer<void>();
          client.setConnectionListener((state) {
            if (state == DesktopConnectionState.disconnected) {
              disconnected.complete();
            }
          });
          await gateway.sockets.last.close();
          await disconnected.future.timeout(_deadline);
          await client.ensureSession('local');
        } else if (retirement == 'cancel') {
          final cancelled = events.take('request.cancel');
          gateway.event('request.cancel', {'id': 'reused'});
          await cancelled;
        } else {
          client.forgetSettledServerRequestsForSession('local');
        }
        final currentKey = await _clarify(gateway, events, 'reused');
        expect(currentKey, isNot(oldKey));
        final before = gateway.requests.length;
        final stale = await _outcome(
          client.respondToClarify(
            requestId: oldKey,
            questionId: 'q1',
            answer: 'Stale answer must stay local',
          ),
        );
        expect(gateway.calls('clarify.respond'), isEmpty);
        expect(stale, isA<StateError>());
        expect(gateway.requests, hasLength(before));
        expect(client.ownsServerRequest(currentKey, 'clarify'), isTrue);
        expect(gateway.calls('prompt.submit'), isEmpty);

        await client.respondToClarify(
          requestId: currentKey,
          questionId: 'q1',
          answer: 'Current answer',
        );
        final lock = await gateway.take('clarify.lock');
        expect(lock.params, {
          'request_id': 'reused',
          'question_id': 'q1',
          'answer': 'Current answer',
        });
        expect(client.ownsServerRequest(currentKey, 'clarify'), isFalse);
      },
    );
  }

  test(
    'L4 another owner cannot send a local clarify key on its live socket',
    () async {
      final gateway = await _Gateway.start();
      final old = gateway.client();
      final current = gateway.client();
      final oldEvents = _Events(old);
      final currentEvents = _Events(current);
      addTearDown(() async {
        old.close();
        current.close();
        await oldEvents.close();
        await currentEvents.close();
        await gateway.close();
      });
      await old.ensureSession('local');
      final staleKey = await _clarify(gateway, oldEvents, 'reused');
      old.close();
      await current.ensureSession('local');
      final liveKey = await _clarify(gateway, currentEvents, 'reused');
      final before = gateway.requests.length;
      final stale = await _outcome(
        current.respondToClarify(
          requestId: staleKey,
          answer: 'Never sent',
          questionId: 'q1',
        ),
      );
      expect(gateway.calls('clarify.respond'), isEmpty);
      expect(stale, isA<StateError>());
      expect(gateway.requests, hasLength(before));
      expect(current.ownsServerRequest(liveKey, 'clarify'), isTrue);
      await current.respondToClarify(
        requestId: liveKey,
        answer: 'Live',
        questionId: 'q1',
      );
      expect(
        (await gateway.take('clarify.lock')).params['request_id'],
        'reused',
      );
    },
  );

  test(
    'L4 held lock cannot republish a cancelled request over its replacement',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      final events = _Events(client);
      addTearDown(() async {
        client.close();
        await events.close();
        await gateway.close();
      });
      await client.ensureSession('local');
      final oldKey = await _clarify(gateway, events, 'reused', batch: true);
      gateway.held.add('clarify.lock');
      final oldAnswer = _outcome(
        client.respondToClarify(
          requestId: oldKey,
          answer: 'Old answer',
          questionId: 'q1',
        ),
      );
      final held = await gateway.take('clarify.lock');
      final cancelled = events.take('request.cancel');
      gateway.event('request.cancel', {'id': 'reused'});
      await cancelled;
      final currentKey = await _clarify(gateway, events, 'reused');
      held.reply({
        'status': 'ok',
        'remaining': ['q2'],
      });
      expect(await oldAnswer, isA<StateError>());
      expect(client.ownsServerRequest(oldKey, 'clarify'), isFalse);
      expect(client.ownsServerRequest(currentKey, 'clarify'), isTrue);
      expect(
        events.seen.where((event) => event.type == 'clarify.remaining'),
        isEmpty,
      );
      gateway.held.remove('clarify.lock');
      await client.respondToClarify(
        requestId: currentKey,
        answer: 'New answer',
        questionId: 'q1',
      );
      expect(
        (await gateway.take('clarify.lock')).params['answer'],
        'New answer',
      );
      expect(gateway.calls('clarify.respond'), isEmpty);
      expect(gateway.calls('prompt.submit'), isEmpty);
    },
  );

  test(
    'L4 live batch preserves partial replay and expires without fallback',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      final events = _Events(client);
      addTearDown(() async {
        client.close();
        await events.close();
        await gateway.close();
      });
      await client.ensureSession('local');
      final key = await _clarify(gateway, events, 'batch', batch: true);
      gateway.held.add('clarify.lock');
      final partial = client.respondToClarify(
        requestId: key,
        answer: 'One',
        questionId: 'q1',
      );
      (await gateway.take('clarify.lock')).reply({
        'status': 'ok',
        'remaining': ['q2'],
      });
      await partial;
      expect(client.ownsServerRequest(key, 'clarify'), isTrue);
      final replay = events.take('clarify.request');
      client.replayServerRequestsForSession('local');
      expect((await replay).data['questions'], [
        {'qid': 'q2', 'question': 'Second question?'},
      ]);
      final finalAnswer = client.respondToClarify(
        requestId: key,
        answer: 'Two',
        questionId: 'q2',
      );
      (await gateway.take('clarify.lock')).reply({'status': 'expired'});
      await finalAnswer;
      expect(client.ownsServerRequest(key, 'clarify'), isFalse);
      await expectLater(
        client.respondToClarify(
          requestId: key,
          answer: 'Stale retry',
          questionId: 'q2',
        ),
        throwsStateError,
      );
      expect(
        gateway.calls('clarify.lock').map((rpc) => rpc.params['request_id']),
        ['batch', 'batch'],
      );
      expect(gateway.calls('clarify.respond'), isEmpty);
    },
  );

  test('L4 genuine legacy clarify IDs keep their wire fallback', () async {
    final gateway = await _Gateway.start();
    final client = gateway.client();
    addTearDown(() async {
      client.close();
      await gateway.close();
    });
    await client.ensureSession('local');
    await client.respondToClarify(
      requestId: 'legacy-wire-id',
      answer: 'Legacy answer',
      questionId: 'q1',
    );
    expect((await gateway.take('clarify.respond')).params, {
      'request_id': 'legacy-wire-id',
      'answer': 'Legacy answer',
      'question_id': 'q1',
    });
    expect(gateway.calls('clarify.lock'), isEmpty);
  });

  test(
    'L9 rejected rebind leaves a new chat eligible for its original fallback',
    () async {
      final gateway = await _Gateway.start();
      final client = gateway.client();
      addTearDown(() async {
        client.close();
        await gateway.close();
      });
      client.setReconnectAllowed(false);
      gateway.missing.add('local');
      await client.ensureSession('local', workingDirectory: '/srv/original');
      expect(client.storedSessionKeyFor('local'), 'stored-created-1');
      expect(
        () => client.bindStoredSession('local', 'unrelated'),
        throwsStateError,
      );
      expect(client.storedSessionKeyFor('local'), 'stored-created-1');
      gateway.missing.add('stored-created-1');
      final disconnected = Completer<void>();
      client.setConnectionListener((state) {
        if (state == DesktopConnectionState.disconnected) {
          disconnected.complete();
        }
      });
      await gateway.sockets.last.close();
      await disconnected.future.timeout(_deadline);
      await client.ensureSession('local');
      expect(client.storedSessionKeyFor('local'), 'stored-created-2');
      expect(gateway.calls('session.create').map((r) => r.params), [
        {'source': 'desktop', 'cwd': '/srv/original'},
        {'source': 'desktop', 'cwd': '/srv/original'},
      ]);
    },
  );

  test('L9 accepted idempotent durable binding remains resume-only', () async {
    final gateway = await _Gateway.start();
    final client = gateway.client();
    addTearDown(() async {
      client.close();
      await gateway.close();
    });
    client.bindStoredSession('local', 'stored');
    client.bindStoredSession('local', 'stored');
    expect(() => client.bindStoredSession('local', 'other'), throwsStateError);
    gateway.missing.add('stored');
    await expectLater(
      client.ensureSession('local'),
      throwsA(isA<JsonRpcError>()),
    );
    expect(client.storedSessionKeyFor('local'), 'stored');
    expect(gateway.calls('session.create'), isEmpty);
  });
}

const _deadline = Duration(seconds: 5);

Future<Object?> _outcome<T>(Future<T> future) =>
    future.then<Object?>((_) => null, onError: (Object error) => error);

Future<String> _clarify(
  _Gateway gateway,
  _Events events,
  String id, {
  bool batch = false,
}) async {
  final received = events.take('clarify.request');
  gateway.request(id, 'clarify', {
    'session_id': 'runtime-local',
    'questions': [
      {'qid': 'q1', 'question': 'Proceed?'},
      if (batch) {'qid': 'q2', 'question': 'Second question?'},
    ],
  });
  return (await received).data['request_id'] as String;
}

class _Events {
  _Events(DesktopGatewayClient client) {
    client.setAsyncEventListener((_, event) {
      seen.add(event);
      _events.add(event);
    });
  }

  final seen = <StreamEvent>[];
  final _events = StreamController<StreamEvent>.broadcast(sync: true);

  Future<StreamEvent> take(String type) => _events.stream
      .firstWhere((event) => event.type == type)
      .timeout(_deadline);

  Future<void> close() => _events.close();
}

/// Real loopback HTTP ticket mint + WebSocket JSON-RPC. Only reply release is
/// controlled: no replacement transport, private-state access or timing sleeps.
class _Gateway {
  _Gateway(this.server);

  final HttpServer server;
  final sockets = <WebSocket>[];
  final requests = <_Rpc>[];
  final missing = <String>{};
  final held = <String>{};
  final _received = StreamController<_Rpc>.broadcast(sync: true);
  final _taken = <String, int>{};
  var creates = 0;

  static Future<_Gateway> start() async {
    final gateway = _Gateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen(gateway._http);
    return gateway;
  }

  DesktopGatewayClient client() => DesktopGatewayClient.fromConnection(
    SavedConnection(
      id: 'lifecycle-fixture',
      label: 'Fixture',
      host: '127.0.0.1',
      port: server.port,
      apiKey: 'fixture',
      dashboardPortOverride: server.port,
      dashboardProxied: true,
      desktopGatewayUrl: 'http://127.0.0.1:${server.port}',
    ),
  );

  Iterable<_Rpc> calls(String method, {WebSocket? socket}) => requests.where(
    (rpc) =>
        rpc.method == method &&
        (socket == null || identical(rpc.socket, socket)),
  );

  Future<_Rpc> take(String method) async {
    final index = _taken[method] ?? 0;
    _taken[method] = index + 1;
    final existing = calls(method).toList();
    if (existing.length > index) return existing[index];
    return _received.stream
        .firstWhere((rpc) => rpc.method == method)
        .timeout(_deadline);
  }

  Future<void> _http(HttpRequest request) async {
    if (request.uri.path == '/api/auth/ws-ticket') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ticket': 'fixture-ticket'}));
      await request.response.close();
    } else if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final frame = Map<String, dynamic>.from(
          jsonDecode(raw as String) as Map,
        );
        if (frame['method'] == null) return;
        final rpc = _Rpc(this, socket, frame);
        requests.add(rpc);
        _received.add(rpc);
        if (!held.contains(rpc.method)) rpc.replyDefault();
      });
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }

  void request(String id, String method, Map<String, dynamic> params) {
    sockets.last.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
  }

  void event(String type, Map<String, dynamic> payload) {
    sockets.last.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': type,
          'session_id': 'runtime-local',
          'payload': payload,
        },
      }),
    );
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
    await _received.close();
  }
}

class _Rpc {
  _Rpc(this.gateway, this.socket, this.frame);

  final _Gateway gateway;
  final WebSocket socket;
  final Map<String, dynamic> frame;

  @override
  String toString() => jsonEncode(frame);

  String get method => frame['method'] as String;
  Map<String, dynamic> get params =>
      Map<String, dynamic>.from(frame['params'] as Map);

  void reply(Map<String, dynamic> result) => socket.add(
    jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
  );

  void replyDefault() {
    switch (method) {
      case 'session.resume':
        final stored = params['session_id'] as String;
        if (gateway.missing.contains(stored)) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              'error': {'code': 4007, 'message': 'session not found'},
            }),
          );
        } else {
          reply({
            'session_id': 'runtime-$stored',
            'running': false,
            'status': 'idle',
          });
        }
      case 'session.create':
        final number = ++gateway.creates;
        reply({
          'session_id': 'runtime-local',
          'stored_session_id': 'stored-created-$number',
          'message_count': 0,
          'messages': <dynamic>[],
        });
      case 'clarify.lock':
        reply({'status': 'ok', 'remaining': <String>[]});
      case 'clarify.respond':
        reply({'status': 'expired'});
      default:
        reply({'ok': true});
    }
  }
}
