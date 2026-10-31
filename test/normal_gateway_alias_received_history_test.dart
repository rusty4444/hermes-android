// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_alias_received_history_test.dart
// Base 4a53e32 blob 8ef1e1555fa9a3ec6fa59792fb12be487b51729e; SHA256 3e63c936b39f3215fc3b67113c75ac4220e02fda95979fac6e9c36daabc00a84.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, send, until, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previous);

  for (final history in ['known', 'empty', 'unavailable']) {
    for (final failed in [false, true]) {
      test(
        'wire settled donor $history failed=$failed stays separate from admission',
        () async {
          final f = await _Handoff.start(history: history);
          addTearDown(f.close);
          final originalTurn = f.source.turnId;
          await f.settleDonor(failed: failed);
          final donor = f.canonical.snapshot;
          final oldScope = donor.displayRows.last['_normal_projection_id'];
          f.wire.releaseCreate();
          await f.wire.untilPrompts(2);
          final current = f.source.snapshot;
          expect(current.turnId, originalTurn);
          expect(current.hasActiveTurn, isTrue);
          expect(f.canonical.snapshot.turnId, originalTurn);
          expect(_contents(current), contains('Donor answer'));
          expect(
            _contents(current).where((s) => s == 'Original prompt'),
            hasLength(1),
          );
          expect(current.tools.single.toolId, 'donor-tool');
          expect(
            current.historyRows.any((r) => r['content'] == 'Donor answer'),
            isFalse,
          );
          final currentScope =
              current.displayRows.last['_normal_projection_id'];
          f.wire.event('reasoning.delta', {
            'text': 'Current reasoning',
          }, turnId: 'wire-2');
          f.wire.event('message.delta', {
            'text': 'Current answer',
          }, turnId: 'wire-2');
          await until(
            () => _contents(f.source.snapshot).contains('Current answer'),
          );
          final timeline = f.source.snapshot.timeline;
          expect(timeline.forScope(oldScope).map((r) => r.kind), [
            ChatTimelineKind.reasoning,
            ChatTimelineKind.tool,
            ChatTimelineKind.reasoning,
            ChatTimelineKind.text,
          ]);
          expect(timeline.forScope(currentScope).map((r) => r.text), [
            'Current reasoning',
            'Current answer',
          ]);
          expect(
            timeline.forScope(currentScope).any((r) => r.activity != null),
            isFalse,
          );
          expect(
            timeline.runs.map((r) => r.id).toSet(),
            hasLength(timeline.runs.length),
          );
          expect(f.wire.prompts.map((r) => r['text']), [
            AndroidPromptContext.forModel('Donor prompt'),
            AndroidPromptContext.forModel('Original prompt'),
          ]);
          f.wire.rows
            ..clear()
            ..addAll([
              _row(98, 'Donor prompt', role: 'user'),
              _row(99, 'Canonical donor context'),
              _row(100, 'Original prompt', role: 'user'),
              _row(101, 'Canonical current answer'),
            ]);
          f.wire.historyUnavailable = false;
          f.wire.finishReceived('Current answer');
          await until(() => !f.source.snapshot.hasActiveTurn);
          await f.flights.last;
          await pumpEventQueue();
          // No stock HTTP row proves a match to any materialized donor,
          // including successful donors. Keep C and R independently complete.
          const keepDonor = true;
          expect(
            _contents(f.source.snapshot).contains('Donor answer'),
            keepDonor,
          );
          if (failed && history == 'known') {
            expect(
              f.source.snapshot.historyRows.map((row) => row['content']),
              contains('Canonical current answer'),
            );
            expect(
              _contents(f.source.snapshot).where((s) => s == 'Donor prompt'),
              hasLength(1),
            );
          }
          expect(
            _contents(
              f.source.snapshot,
            ).where((s) => s == 'Original prompt').length,
            lessThanOrEqualTo(1),
          );
        },
      );
    }
  }

  for (final width in [400.0, 1000.0]) {
    testWidgets(
      'mounted canonical received tail survives original handoff at $width',
      (tester) async {
        const picker = MethodChannel('plugins.flutter.io/image_picker');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            null,
          ),
        );
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = (await tester.runAsync(
          () => _Handoff.start(history: 'known', trackFlights: false),
        ))!;
        addTearDown(f.close);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(
              connection: f.wire.connection,
              session: const Session(
                id: 'stored',
                title: 'Canonical',
                model: 'fixture',
                source: 'test',
                messageCount: 1,
                isActive: false,
                preview: '',
                startedAt: 1,
              ),
              turnApplicationController: f.controller,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        await widgetUntil(
          tester,
          () => f.canonical.snapshot.historyRows.isNotEmpty,
        );
        final mounted = tester.state(find.byType(ChatScreen));
        send(f.canonical, 'Donor prompt').ignore();
        await widgetUntil(tester, () => f.wire.prompts.length == 1);
        f.wire.finishReceived('Donor answer');
        await widgetUntil(tester, () => !f.canonical.snapshot.hasActiveTurn);
        await widgetUntil(
          tester,
          () => find
              .text('Donor answer', findRichText: true)
              .evaluate()
              .isNotEmpty,
        );
        f.wire.releaseCreate();
        await widgetUntil(tester, () => f.wire.prompts.length == 2);
        expect(tester.state(find.byType(ChatScreen)), same(mounted));
        expect(find.text('Donor answer', findRichText: true), findsOneWidget);
        expect(_contents(f.source.snapshot), contains('Original prompt'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.close);
        await tester.pump(const Duration(seconds: 16));
      },
    );
  }

  for (final newer in ['99', 'empty', 'unidentified', 'compressed']) {
    test(
      'older physical settled GET cannot replace later accepted $newer history',
      () async {
        final f = await _Handoff.start(history: 'known');
        addTearDown(f.close);
        f.wire.holdNext = true;
        final settling = f.settleDonor();
        await f.wire.held.future;
        await settling;
        final capturedFlight = f.flights.last;
        final fresh = switch (newer) {
          '99' => [
            _row(98, 'Previous prompt', role: 'user'),
            _row(99, 'Previous answer'),
          ],
          'empty' => <Map<String, dynamic>>[],
          'unidentified' => [
            {'role': 'assistant', 'content': 'No durable identity'},
          ],
          _ => [_row(7, 'Compressed context')],
        };
        f.wire.rows
          ..clear()
          ..addAll(fresh);
        final laterApi = ApiClient(
          baseUrl: f.wire.connection.baseUrl,
          apiKey: 'fixture',
        );
        f.canonical.observeHistory(
          await laterApi.getMessages('stored', latest: true),
        );
        laterApi.close();
        f.wire.releaseHistory();
        await capturedFlight;
        await pumpEventQueue();
        expect(f.canonical.snapshot.historyRows, fresh);
        f.wire.releaseCreate();
        await f.wire.untilPrompts(2);
        final int? expected = newer == '99'
            ? 99
            : newer == 'empty'
            ? 0
            : newer == 'compressed'
            ? 7
            : null;
        expect(f.source.snapshot.rowFloor, expected);
        expect(
          (await f.session.pendingStore.load(f.session.scope)).single.rowFloor,
          expected,
        );
        if (newer == '99') {
          f.wire.finishReceived('Current answer');
          await until(() => !f.source.snapshot.hasActiveTurn);
          await f.flights.last;
          await pumpEventQueue();
          expect(_contents(f.source.snapshot), contains('Current answer'));
        }
      },
    );
  }

  for (final sourceFirst in [false, true]) {
    for (final anchorLate in [false, true]) {
      test(
        'qualified owner interval anchor sourceFirst=$sourceFirst late=$anchorLate',
        () async {
          final s = _ownerSession();
          addTearDown(s.close);
          await s.ready;
          final source = s.chatFor('local', title: 'Source');
          final canonical = s.chatFor(
            'stored',
            storedSessionId: 'stored',
            title: 'Canonical',
          );
          final first = sourceFirst ? 'local' : 'stored';
          final other = sourceFirst ? 'stored' : 'local';
          void child(String alias, String? id, String goal, {String? status}) =>
              s.receiveEvent(
                alias,
                StreamEvent(
                  type: 'subagent.progress',
                  data: {
                    'subagent_id': 'task',
                    'child_session_id': ?id,
                    'goal': goal,
                    'status': ?status,
                  },
                ),
              );
          child(first, anchorLate ? null : 'anchor', 'First');
          child(
            other,
            anchorLate ? 'anchor' : 'middle',
            'Second',
            status: 'failed',
          );
          child(first, 'latest', 'Newest');
          source.bindStoredSession('stored');
          final task = canonical.snapshot.subagents.single;
          expect(task.childSessionId, 'anchor');
          expect(task.latestChildSessionId, 'latest');
          expect(task.goal, 'Newest');
          expect(task.failed, isTrue);
          expect(task.isComplete, isTrue);
          canonical.observeHistory([_row(99, 'Parent hydration')]);
          child('local', null, 'Sparse');
          expect(canonical.snapshot.subagents.single.childSessionId, 'anchor');
        },
      );
    }
  }

  test(
    'qualified queued rejection stops a reentrant same-generation cancellation',
    () async {
      final s = _ownerSession();
      addTearDown(s.close);
      await s.ready;
      final source = s.chatFor('local', title: 'Source');
      final canonical = s.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      source.reserve();
      final reservation = canonical.reserve()!;
      source.subscribe((snap) {
        if (snap.phase == NormalGatewayTurnPhase.failed) {
          canonical.cancelPreparation(reservation);
        }
      });
      final seen = <NormalGatewayTurnPhase>[];
      source.subscribe((snap) => seen.add(snap.phase));
      source.bindStoredSession('stored');
      seen.clear();
      await pumpEventQueue();
      expect(seen, isNotEmpty);
      expect(seen, everyElement(NormalGatewayTurnPhase.idle));
    },
  );

  test(
    'wire imported tails share live projection budgets without rebasing WAL',
    () async {
      final f = await _Handoff.start(history: 'known');
      addTearDown(f.close);
      await f.settleDonor();
      f.wire.releaseCreate();
      await f.wire.untilPrompts(2);
      for (var i = 0; i < 520; i++) {
        f.wire.event('message.delta', {'text': 'x'}, turnId: 'wire-2');
        f.wire.event('reasoning.delta', {'text': 'y'}, turnId: 'wire-2');
      }
      await until(
        () =>
            f.source.snapshot.displayRows.last['_gateway_reasoning']
                ?.toString()
                .length ==
            520,
      );
      final snapshot = f.source.snapshot;
      expect(
        snapshot.timeline.runs.length,
        lessThanOrEqualTo(ChatTimeline.maxRuns),
      );
      expect(
        snapshot.timeline.runs.fold<int>(0, (sum, r) => sum + r.text.length),
        lessThanOrEqualTo(ChatTimeline.maxTextCodeUnits),
      );
      expect(snapshot.displayRows.length, lessThanOrEqualTo(256));
      expect(_contents(snapshot), isNot(contains('Donor answer')));
      expect(snapshot.tools.any((t) => t.toolId == 'donor-tool'), isFalse);
      expect(snapshot.rowFloor, 37);
      expect(
        (await f.session.pendingStore.load(f.session.scope)).single.rowFloor,
        37,
      );
    },
  );

  for (final action in [
    'new-admission',
    'unsubscribe',
    'close',
    'routine-bind',
  ]) {
    test(
      'qualified queued rejection respects scheduled epoch and $action',
      () async {
        final s = _ownerSession();
        addTearDown(s.close);
        await s.ready;
        final source = s.chatFor('local', title: 'Source');
        final canonical = s.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Canonical',
        );
        source.reserve();
        final reservation = canonical.reserve()!;
        final seen = <NormalGatewayChatSnapshot>[];
        final token = source.subscribe(seen.add);
        source.bindStoredSession('stored');
        if (action == 'new-admission') {
          canonical.cancelPreparation(reservation);
          canonical.reserve();
        } else if (action == 'unsubscribe') {
          source.unsubscribe(token);
        } else if (action == 'close') {
          await s.close();
        } else {
          s.chatFor(
            'same',
            storedSessionId: 'stored',
            title: 'Routine binding',
          );
        }
        seen.clear();
        await pumpEventQueue();
        expect(
          seen
              .where((snap) => snap.phase == NormalGatewayTurnPhase.failed)
              .length,
          action == 'routine-bind' ? 1 : 0,
        );
        if (action == 'new-admission') {
          expect(seen.every((snap) => snap.turnId == canonical.turnId), isTrue);
        }
      },
    );
  }
}

Iterable<String> _contents(NormalGatewayChatSnapshot s) =>
    s.displayRows.map((r) => r['content']?.toString() ?? '');
Map<String, dynamic> _row(int id, String text, {String role = 'assistant'}) => {
  'id': id,
  'role': role,
  'content': text,
};

NormalGatewayApplicationSession _ownerSession() =>
    NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'owner-seam',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture',
      ),
      scope: 'owner-seam',
      history: (_) async => [],
      resume: ({required localSessionId, required storedSessionId}) async =>
          const ResumedGatewaySession(
            runtimeSessionId: 'runtime',
            running: true,
          ),
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {},
    );

class _Handoff {
  _Handoff(this.wire, this.controller);
  final _HistoryServer wire;
  final GatewayTurnApplicationController controller;
  late NormalGatewayApplicationSession session;
  late NormalGatewayChatOwner source;
  late NormalGatewayChatOwner canonical;
  final flights = <Future<List<Map<String, dynamic>>>>[];
  ApiClient? api;
  Future<void>? original;
  static Future<_Handoff> start({
    required String history,
    bool trackFlights = true,
  }) async {
    final f = _Handoff(
      await _HistoryServer.start(),
      GatewayTurnApplicationController(),
    );
    f.api = ApiClient(baseUrl: f.wire.connection.baseUrl, apiKey: 'fixture');
    // The optional seam tracks, but does not reorder or synthesize, actual
    // ApiClient HTTP flights. DesktopGatewayClient still owns stock wire I/O.
    f.session = trackFlights
        ? NormalGatewayApplicationSession(
            connection: f.wire.connection,
            scope: 'received-history',
            client: DesktopGatewayClient.fromConnection(f.wire.connection),
            history: (id) {
              final flight = f.api!.getMessages(id, limit: 50, latest: true);
              f.flights.add(flight);
              return flight;
            },
          )
        : f.controller.normalSessionFor(f.wire.connection);
    await f.session.ready;
    f.source = f.session.chatFor('local', title: 'Original');
    f.original = send(f.source, 'Original prompt')..ignore();
    await f.wire.createEntered.future;
    if (history == 'known') f.wire.rows.add(_row(37, 'Old context'));
    f.wire.historyUnavailable = history == 'unavailable';
    f.canonical = f.session.chatFor(
      'stored',
      storedSessionId: 'stored',
      title: 'Canonical',
    );
    try {
      f.canonical.observeHistory(
        await f.api!.getMessages('stored', latest: true),
      );
    } catch (_) {
      expect(history, 'unavailable');
    }
    return f;
  }

  Future<void> settleDonor({bool failed = false}) async {
    final sending = send(canonical, 'Donor prompt')..ignore();
    await wire.untilPrompts(1);
    wire.event('message.start', {}, turnId: 'wire-1');
    wire.event('reasoning.delta', {'text': 'Before tool'}, turnId: 'wire-1');
    wire.event('tool.start', {
      'tool': 'read_file',
      'tool_id': 'donor-tool',
    }, turnId: 'wire-1');
    wire.event('reasoning.delta', {'text': 'After tool'}, turnId: 'wire-1');
    wire.finishReceived('Donor answer', failed: failed);
    await sending;
    await until(() => !canonical.snapshot.hasActiveTurn && wire.reads >= 2);
    if (!wire.isHolding && flights.isNotEmpty) {
      await flights.last.catchError((Object _) => <Map<String, dynamic>>[]);
      await pumpEventQueue();
    }
  }

  Future<void> close() async {
    wire.releaseHistory();
    await session.close();
    await controller.close();
    api?.close();
    await wire.close();
    await original;
  }
}

class _HistoryServer extends BindingServer {
  _HistoryServer(super.server);
  int reads = 0;
  bool holdNext = false;
  final held = Completer<void>();
  Completer<void>? _gate;
  bool get isHolding => _gate != null && !_gate!.isCompleted;
  static Future<_HistoryServer> start() async {
    final f = _HistoryServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    f.server.listen(f.handle);
    return f;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (request.uri.path.endsWith('/messages')) {
      reads++;
      if (holdNext) {
        holdNext = false;
        _gate = Completer<void>();
        final captured = jsonEncode({'data': rows});
        held.complete();
        await _gate!.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(captured);
        await request.response.close();
        return;
      }
    }
    return super.handle(request);
  }

  void releaseHistory() {
    if (isHolding) _gate!.complete();
  }

  void finishReceived(String text, {bool failed = false}) {
    running = false;
    final turn = 'wire-${prompts.length}';
    event('message.start', {}, turnId: turn);
    event('message.delta', {'text': text}, turnId: turn);
    event('message.complete', {'text': text}, turnId: turn);
    event(
      failed ? 'turn.error' : 'turn.end',
      failed ? {'status': 'failed', 'message': 'Interrupted donor'} : {},
      turnId: turn,
    );
  }
}
