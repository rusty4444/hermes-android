// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_alias_authority_wire_test.dart
// Base 4a53e32 blob f158bd50c74c11e13e574a07170610299fe43442; SHA256 2b5a78af681c84f15c39987f78f5a19703722499d0eb4aa4a9d5ae3327ee1474.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Independent HTTP/WS fixture. The encoded empty-create result is captured at
// allocation, before another client writes the durable conversation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previous);

  for (final sourceKnown in [false, true]) {
    test(
      'SPEC newer canonical history wins delayed empty proof; source known=$sourceKnown',
      () async {
        final f = await _Wire.start();
        final c = GatewayTurnApplicationController();
        addTearDown(() async {
          await c.close();
          await f.close();
        });
        final s = c.normalSessionFor(f.connection);
        await s.ready;
        final local = s.chatFor('local', title: 'Local');
        if (sourceKnown) {
          local.observeHistory([_row(37, 'Older source context')]);
        }
        final sending = _send(local, 'Current prompt');
        sending.ignore();
        await f.created.future;
        f.rows.addAll([
          _row(98, 'Other client question', role: 'user'),
          _row(99, 'Other client answer'),
        ]);
        final canonical = s.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Canonical',
        );
        final routeHistory = ApiClient(
          baseUrl: f.connection.baseUrl,
          apiKey: 'fixture',
        );
        canonical.observeHistory(
          await routeHistory.getMessages('stored', limit: 50, latest: true),
        );
        routeHistory.close();
        f.releaseCreate();
        await f.untilPrompts(1);
        final receipts = await s.pendingStore.load(s.scope);
        debugPrint(
          'CANONICAL_FLOOR sourceKnown=$sourceKnown floor=${local.snapshot.rowFloor} history=${local.snapshot.historyRows} receipt=${receipts.single.rowFloor}',
        );
        expect(
          local.snapshot.rowFloor,
          99,
          reason:
              'a later canonical read supersedes allocation-time empty proof before emission',
        );
        expect(receipts.single.rowFloor, 99);
        expect(local.snapshot.historyRows.map((r) => r['id']), contains(99));
        await c.close();
        await sending;
      },
    );
  }

  test(
    'SPEC lagged old history must not erase current received reply after coalescing',
    () async {
      final f = await _Wire.start();
      final c = GatewayTurnApplicationController();
      addTearDown(() async {
        await c.close();
        await f.close();
      });
      final s = c.normalSessionFor(f.connection);
      await s.ready;
      final local = s.chatFor('local', title: 'Local');
      final sending = _send(local, 'New prompt');
      sending.ignore();
      await f.created.future;
      f.rows.addAll([
        _row(98, 'Other old question', role: 'user'),
        _row(99, 'Other old answer'),
      ]);
      final canonical = s.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      final routeHistory = ApiClient(
        baseUrl: f.connection.baseUrl,
        apiKey: 'fixture',
      );
      canonical.observeHistory(
        await routeHistory.getMessages('stored', limit: 50, latest: true),
      );
      routeHistory.close();
      f.releaseCreate();
      await f.untilPrompts(1);
      final getsBeforeCompletion = f.gets;
      f.event('reasoning.delta', {
        'text': 'Current exposed reasoning',
      }, turn: 'wire-1');
      f.event('tool.start', {
        'tool': 'read_file',
        'tool_id': 'current-tool',
      }, turn: 'wire-1');
      f.finish('New received answer', persist: false);
      await sending;
      await _until(
        () => !local.snapshot.hasActiveTurn && f.gets > getsBeforeCompletion,
      );
      await pumpEventQueue();
      debugPrint(
        'LAGGED_CANONICAL phase=${local.phase} floor=${local.snapshot.rowFloor} display=${local.snapshot.displayRows} history=${local.snapshot.historyRows}',
      );
      expect(
        local.snapshot.displayRows.any(
          (r) => r['content'] == 'New received answer',
        ),
        isTrue,
        reason:
            'row 99 predates this send and cannot replace received current output',
      );
      expect(await s.pendingStore.load(s.scope), isEmpty);
      expect(f.prompts, hasLength(1));
      expect(local.snapshot.tools.single.toolId, 'current-tool');
      expect(
        local.snapshot.displayRows.last['_gateway_reasoning'],
        'Current exposed reasoning',
      );
      expect(local.snapshot.timeline.runs, isNotEmpty);
      // A later canonical response does not prove any parent received match.
      local.observeHistory([
        ...f.rows,
        _row(100, 'New prompt', role: 'user'),
        _row(101, 'Canonical new answer'),
      ]);
      expect(
        local.snapshot.historyRows.last['content'],
        'Canonical new answer',
      );
      expect(local.snapshot.displayRows.last['content'], 'New received answer');
      expect(local.snapshot.tools.single.toolId, 'current-tool');
      expect(local.snapshot.timeline.runs, isNotEmpty);
    },
  );

  test(
    'SPEC settled canonical has no admission; pending original continues exactly once',
    () async {
      final f = await _Wire.start();
      final c = GatewayTurnApplicationController();
      addTearDown(() async {
        await c.close();
        await f.close();
      });
      final s = c.normalSessionFor(f.connection);
      await s.ready;
      final local = s.chatFor('local', title: 'Local');
      Object? error;
      final sending = _send(local, 'Original pending').then<void>(
        (_) {},
        onError: (Object e) {
          error = e;
        },
      );
      await f.created.future;
      final canonical = s.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      final canonicalSend = _send(canonical, 'Earlier canonical turn');
      canonicalSend.ignore();
      await f.untilPrompts(1);
      f.finish('Earlier canonical answer');
      await canonicalSend;
      await _until(() => !canonical.snapshot.hasActiveTurn);
      await _until(() => canonical.snapshot.historyRows.isNotEmpty);
      final prior = canonical.turnId;
      f.releaseCreate();
      await _until(() => error != null || f.prompts.length == 2);
      debugPrint(
        'SETTLED_CANONICAL error=$error oldTurn=$prior current=${local.turnId} prompts=${f.prompts.map((p) => p['text']).toList()} phase=${local.phase}',
      );
      expect(
        error,
        isNull,
        reason:
            'completed turnId is historical identity, not current admission',
      );
      expect(f.prompts.map((p) => p['text']), [
        'Earlier canonical turn',
        'Original pending',
      ]);
      f.event('message.start', {}, turn: 'wire-1');
      f.event('turn.end', {}, turn: 'wire-1');
      await pumpEventQueue();
      expect(local.snapshot.hasActiveTurn, isTrue);
      f.finish('Original final');
      await sending;
    },
  );

  for (final proof in [true, false]) {
    test(
      'SPEC control local 404 proof=$proof does not invent an unknown baseline',
      () async {
        final f = await _Wire.start();
        f.emptyProof = proof;
        f.historyStatus = 404;
        final c = GatewayTurnApplicationController();
        addTearDown(() async {
          await c.close();
          await f.close();
        });
        final s = c.normalSessionFor(f.connection);
        await s.ready;
        final local = s.chatFor('local', title: 'Local');
        final flight = _send(local, 'Single send');
        flight.ignore();
        await f.created.future;
        f.releaseCreate();
        await f.untilPrompts(1);
        expect(local.snapshot.rowFloor, proof ? 0 : null);
        expect(
          (await s.pendingStore.load(s.scope)).single.rowFloor,
          proof ? 0 : null,
        );
        expect(f.prompts.single['text'], 'Single send');
        await c.close();
        await flight;
      },
    );
  }

  test(
    'SPEC control eager binding adopts canonical history and transferred unsubscribe',
    () async {
      final f = await _Wire.start();
      final c = GatewayTurnApplicationController();
      addTearDown(() async {
        await c.close();
        await f.close();
      });
      final s = c.normalSessionFor(f.connection);
      await s.ready;
      final local = s.chatFor('local', title: 'Local');
      final ensuring = s.client!.ensureSession('local');
      ensuring.ignore();
      await f.created.future;
      final canonical = s.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      f.rows.add(_row(99, 'Canonical context'));
      final routeHistory = ApiClient(
        baseUrl: f.connection.baseUrl,
        apiKey: 'fixture',
      );
      canonical.observeHistory(
        await routeHistory.getMessages('stored', limit: 50, latest: true),
      );
      routeHistory.close();
      var callbacks = 0;
      final token = canonical.subscribe((_) => callbacks++);
      f.releaseCreate();
      await ensuring;
      // Let the deferred publication callback finish before unsubscribing.
      await pumpEventQueue();
      canonical.unsubscribe(token);
      final before = callbacks;
      final flight = _send(canonical, 'Retained canonical reference');
      flight.ignore();
      await f.untilPrompts(1);
      expect(local.snapshot.rowFloor, 99);
      expect(callbacks, before);
      await c.close();
      await flight;
    },
  );

  test(
    'SPEC control canonical active admission rejects local before wire and old reference retries',
    () async {
      final f = await _Wire.start();
      final c = GatewayTurnApplicationController();
      addTearDown(() async {
        await c.close();
        await f.close();
      });
      final s = c.normalSessionFor(f.connection);
      await s.ready;
      final local = s.chatFor('local', title: 'Local');
      Object? rejection;
      final flight = _send(local, 'Never emitted').then<void>(
        (_) {},
        onError: (Object e) {
          rejection = e;
        },
      );
      await f.created.future;
      final canonical = s.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      final reservation = canonical.reserve()!;
      var rejectedCallbacks = 0;
      local.subscribe((snap) {
        if (snap.phase == NormalGatewayTurnPhase.failed) {
          rejectedCallbacks++;
          expect(local.reserve(), isNull);
        }
      });
      f.releaseCreate();
      await flight;
      expect(rejection, isA<StateError>());
      await pumpEventQueue();
      expect(rejectedCallbacks, 1);
      expect(f.prompts, isEmpty);
      canonical.cancelPreparation(reservation);
      final retry = _send(local, 'Explicit retained-reference retry');
      retry.ignore();
      await f.untilPrompts(1);
      f.finish('Retry reply');
      await retry;
      await _until(() => !local.snapshot.hasActiveTurn);
      expect(f.prompts.single['text'], 'Explicit retained-reference retry');
      expect(await s.pendingStore.load(s.scope), isEmpty);
    },
  );

  test(
    'SPEC idle canonical child observer survives convergence and repeated parent hydration',
    () async {
      final f = await _Wire.start();
      final c = GatewayTurnApplicationController();
      addTearDown(() async {
        await c.close();
        await f.close();
      });
      final s = c.normalSessionFor(f.connection);
      await s.ready;
      final local = s.chatFor('local', title: 'Local');
      final ensuring = s.client!.ensureSession('local');
      ensuring.ignore();
      await f.created.future;
      final canonical = s.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      // Observe through the actual canonical stock runtime while the original
      // local create reply is still held. No parent prompt is required.
      await s.client!.ensureSession('stored');
      f.event(
        'subagent.progress',
        _childEvent('running', 'Original child goal').data,
      );
      await _until(() => canonical.snapshot.subagents.length == 1);
      f.releaseCreate();
      await ensuring;
      canonical.observeHistory([_row(5, 'Hydrated parent')]);
      debugPrint(
        'CHILD_AFTER_COALESCE agents=${canonical.snapshot.subagents.length}',
      );
      expect(
        canonical.snapshot.subagents,
        hasLength(1),
        reason: 'retained observer may be mounted without a parent turn',
      );
      f.event('subagent.progress', _childEvent('completed', null).data);
      await _until(
        () => local.snapshot.subagents.any((a) => a.status == 'completed'),
      );
      canonical.observeHistory([_row(5, 'Hydrated parent')]);
      expect(local.snapshot.subagents, hasLength(1));
      expect(local.snapshot.subagents.single.goal, 'Original child goal');
      expect(local.snapshot.subagents.single.status, 'completed');
    },
  );
}

// Match the real child event contract without inventing transcript rows.
StreamEvent _childEvent(String status, String? goal) => StreamEvent(
  type: 'subagent.progress',
  data: {
    'subagent_id': 'child-agent',
    'child_session_id': 'child-session',
    'status': status,
    'goal': ?goal,
  },
);
Map<String, dynamic> _row(
  int id,
  String content, {
  String role = 'assistant',
}) => {'id': id, 'role': role, 'content': content};
Future<void> _send(NormalGatewayChatOwner owner, String text) =>
    owner.submitPrepared(
      reservation: owner.reserve()!,
      text: text,
      localContent: text,
    );
Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('independent fixture barrier timeout');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _Wire {
  final HttpServer server;
  final sockets = <WebSocket>[];
  final created = Completer<void>();
  final prompts = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[];
  late void Function() releaseCreate;
  var allocated = false;
  var running = false;
  var gets = 0;
  var historyStatus = 200;
  var emptyProof = true;
  var closed = false;
  _Wire(this.server);
  SavedConnection get connection => SavedConnection(
    id: 'independent-alias',
    label: 'Fixture',
    host: '127.0.0.1',
    port: server.port,
    apiKey: 'fixture',
    dashboardPortOverride: server.port,
    dashboardProxied: true,
  );
  static Future<_Wire> start() async {
    final f = _Wire(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    f.server.listen(f.handle);
    return f;
  }

  Future<void> untilPrompts(int n) => _until(() => prompts.length >= n);
  Future<void> handle(HttpRequest req) async {
    if (req.uri.path == '/api/auth/ws-ticket') {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"ticket":"fixture"}');
      await req.response.close();
      return;
    }
    if (req.uri.path.endsWith('/messages')) {
      gets++;
      req.response.statusCode = historyStatus;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'data': rows}));
      await req.response.close();
      return;
    }
    if (req.uri.path != '/api/ws') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    sockets.add(ws);
    ws.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}},
      }),
    );
    ws.listen((raw) {
      if (closed) return;
      final frame = jsonDecode(raw as String) as Map;
      final method = frame['method'];
      if (method == null) return;
      final reply = <String, dynamic>{'jsonrpc': '2.0', 'id': frame['id']};
      if (method == 'session.create') {
        allocated = true;
        reply['result'] = {
          'session_id': 'runtime',
          'stored_session_id': 'stored',
          if (emptyProof) 'message_count': 0,
          if (emptyProof) 'messages': [],
        };
        final captured = jsonEncode(reply);
        releaseCreate = () => ws.add(captured);
        created.complete();
        return;
      }
      if (method == 'session.resume') {
        if (!allocated) {
          reply['error'] = {'code': 4007, 'message': 'session not found'};
        } else {
          reply['result'] = {
            'session_id': 'runtime',
            'stored_session_id': 'stored',
            'running': running,
            'status': running
                ? 'running'
                : rows.isEmpty
                ? 'idle'
                : 'completed',
          };
        }
      } else {
        if (method == 'prompt.submit') {
          prompts.add(Map<String, dynamic>.from(frame['params'] as Map));
          running = true;
        }
        reply['result'] = {'ok': true};
      }
      ws.add(jsonEncode(reply));
    });
  }

  void event(String type, Map<String, dynamic> payload, {String? turn}) {
    final encoded = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {
        'type': type,
        'session_id': 'runtime',
        'turn_id': ?turn,
        'payload': payload,
      },
    });
    for (final ws in sockets) {
      if (ws.readyState == WebSocket.open) ws.add(encoded);
    }
  }

  void finish(String text, {bool persist = true}) {
    running = false;
    if (persist) {
      rows.addAll([
        _row(rows.length + 1, prompts.last['text'] as String, role: 'user'),
        _row(rows.length + 2, text),
      ]);
    }
    final turn = 'wire-${prompts.length}';
    event('message.start', {}, turn: turn);
    event('message.delta', {'text': text}, turn: turn);
    event('message.complete', {'text': text}, turn: turn);
    event('turn.end', {}, turn: turn);
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    for (final ws in sockets) {
      await ws.close();
    }
    await server.close(force: true);
  }
}
