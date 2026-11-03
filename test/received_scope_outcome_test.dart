import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/received_scope_outcome.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final first in [true, false]) {
    test(
      'immutable received outcome $first survives opposite next turn and prepare cancel',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        await f.start('first');
        f.emit('message.delta', {'text': 'same body'});
        await f.finish(first);
        final prior = f.owner.snapshot.receivedOutcomes.single;
        final preparing = f.owner.reserve()!;
        expect(f.owner.snapshot.receivedOutcomes.single, same(prior));
        f.owner.cancelPreparation(preparing);
        expect(f.owner.snapshot.receivedOutcomes.single, same(prior));
        await f.start('second');
        f.emit('message.delta', {'text': 'same body'});
        await f.finish(!first);
        expect(f.owner.snapshot.receivedOutcomes.map((o) => o.outcome), [
          first
              ? ReceivedLifecycleOutcome.completed
              : ReceivedLifecycleOutcome.failed,
          first
              ? ReceivedLifecycleOutcome.failed
              : ReceivedLifecycleOutcome.completed,
        ]);
        expect(f.owner.snapshot.receivedOutcomes.first, same(prior));
        f.emit('turn.error', {'error': 'old terminal'}, turn: 'wire-1');
        expect(f.owner.snapshot.receivedOutcomes.first, same(prior));
        expect(f.submits, 2);
      },
    );
  }

  test(
    'prewire rejection creates no failed server turn and preserves prior fact',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start('received');
      f.emit('message.delta', {'text': 'retained'});
      await f.finish(false);
      final fact = f.owner.snapshot.receivedOutcomes.single;
      f.reject = true;
      await expectLater(f.start('rejected'), throwsStateError);
      expect(f.owner.snapshot.receivedOutcomes.single, same(fact));
      expect(
        f.owner.snapshot.displayRows.where((r) => r['content'] == 'rejected'),
        isEmpty,
      );
    },
  );

  test(
    'authoritative idle unknown is not definite failure or completion',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start('unknown');
      f.emit('message.delta', {'text': 'unconfirmed body'});
      f.running = false;
      f.emit('message.complete', {'status': 'unknown'}, turn: null);
      f.owner.requestRecovery();
      await _until(() => !f.owner.snapshot.hasActiveTurn);
      expect(
        f.owner.snapshot.receivedOutcomes.single.outcome,
        ReceivedLifecycleOutcome.unknown,
      );
    },
  );

  for (final kind in ['reasoning', 'tool']) {
    test(
      '$kind-only scope retains one associated fact after user anchor removal from projection',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        await f.start(kind);
        if (kind == 'reasoning') {
          f.emit('reasoning.delta', {'text': 'retained reasoning'});
        } else {
          f.emit('tool.start', {'tool': 'read_file', 'tool_id': 'tool'});
        }
        await f.finish(false);
        final snapshot = f.owner.snapshot;
        final sections = buildNormalChatDisplaySections(
          canonicalRows: const [],
          receivedRows: snapshot.displayRows
              .where((r) => r['role'] != 'user')
              .toList(),
          receivedTimeline: snapshot.timeline,
          receivedTools: snapshot.tools,
          receivedOutcomes: snapshot.receivedOutcomes,
        );
        final r = sections.single;
        expect(
          r.outcomes.values.single.outcome,
          ReceivedLifecycleOutcome.failed,
        );
        expect(r.items, hasLength(1));
        expect(
          snapshot.receivedOutcomes.single.scopes,
          contains(snapshot.timeline.runs.single.scope),
        );
      },
    );
  }

  test(
    'partially retained imported tool scope cannot borrow siblings same-string tool outcome',
    () {
      final old = GatewayToolActivity(
        name: 'read_file',
        toolId: 'reused',
        phase: GatewayToolActivityPhase.completed,
      );
      final newer = GatewayToolActivity(
        name: 'read_file',
        toolId: 'reused',
        phase: GatewayToolActivityPhase.completed,
      );
      final timeline = const ChatTimeline().tool('new', newer).precededBy([
        const ChatTimeline().tool('old', old),
      ]);
      final failed = ReceivedScopeOutcome(
        id: 'old-operation',
        scopes: ['old'],
        outcome: ReceivedLifecycleOutcome.failed,
      );
      final completed = ReceivedScopeOutcome(
        id: 'new-operation',
        scopes: ['new'],
        outcome: ReceivedLifecycleOutcome.completed,
      );
      final section = buildNormalChatDisplaySections(
        canonicalRows: [],
        receivedRows: [
          {'role': 'assistant', 'content': '', '_normal_projection_id': 'old'},
        ],
        receivedTimeline: timeline,
        receivedOutcomes: [failed, completed],
      ).single;
      expect(section.outcomes.values.single, same(failed));
      expect(section.items.single, isA<ChatToolActivityGroup>());
    },
  );

  test(
    'verified alias imports facts without minting C/R correspondence',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.session.ready;
      final source = f.session.chatFor('unsent', title: 'Source');
      await f.start('donor');
      f.emit('reasoning.delta', {'text': 'donor reasoning'});
      await f.finish(false);
      final fact = f.owner.snapshot.receivedOutcomes.single;
      source.bindStoredSession('stored');
      final merged = f.session.findChat('stored')!;
      expect(merged.snapshot.receivedOutcomes.single, same(fact));
      expect(merged.snapshot.historyRows, isEmpty);
      expect(merged.snapshot.timeline.runs.single.text, 'donor reasoning');
    },
  );

  test(
    'latest empty C and detached subscribe retain outcomes; scope eviction and close prune them',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      for (var i = 0; i < 140; i++) {
        await f.start('prompt-$i');
        f.emit('message.delta', {'text': 'body-$i'});
        await f.finish(i.isEven);
      }
      final snapshot = f.owner.snapshot;
      expect(snapshot.displayRows.length, lessThanOrEqualTo(258));
      final scopes = snapshot.displayRows
          .map((r) => r['_normal_projection_id'])
          .toSet();
      expect(
        snapshot.receivedOutcomes.every((o) => o.scopes.any(scopes.contains)),
        true,
      );
      expect(
        snapshot.receivedOutcomes.length,
        lessThanOrEqualTo(snapshot.displayRows.length),
      );
      final before = snapshot.receivedOutcomes.map((o) => o.id).toList();
      final read = f.owner.beginHistoryRead('stored');
      expect(f.owner.observeHistory([], read: read), true);
      NormalGatewayChatSnapshot? reopened;
      final token = f.owner.subscribe((s) => reopened = s);
      expect(reopened!.receivedOutcomes.map((o) => o.id).toList(), before);
      f.owner.unsubscribe(token);
      await f.close();
      expect(f.owner.snapshot.receivedOutcomes, isEmpty);
    },
  );
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), true);
}

class _Fixture {
  final connection = SavedConnection(
    id: 'outcome-fixture',
    label: 'Fixture',
    host: 'outcome.fixture',
    port: 1,
    apiKey: 'fixture',
  );
  late final session = NormalGatewayApplicationSession(
    connection: connection,
    scope: 'outcome-fixture',
    submit:
        ({
          required sessionId,
          required text,
          required onEvent,
          required onSent,
        }) async {
          if (reject) throw StateError('Rejected before wire');
          submits++;
          onSent();
        },
    resume: ({required localSessionId, required storedSessionId}) async =>
        ResumedGatewaySession(runtimeSessionId: 'runtime', running: running),
    history: (_) async => [],
  );
  late final owner = session.chatFor(
    'local',
    storedSessionId: 'stored',
    title: 'Fixture',
  );
  bool running = true;
  bool reject = false;
  int submits = 0;
  Future<void> start(String text) async {
    await session.ready;
    owner.observeHistory([]);
    running = true;
    await owner.submitPrepared(
      reservation: owner.reserve()!,
      text: text,
      localContent: text,
    );
  }

  void emit(
    String type,
    Map<String, dynamic> data, {
    String? turn = 'current',
  }) => session.receiveEvent(
    'local',
    StreamEvent(
      type: type,
      data: data,
      turnId: turn == 'current' ? 'wire-$submits' : turn,
    ),
  );
  Future<void> finish(bool success) async {
    running = false;
    emit('turn.end', {
      'status': success ? 'completed' : 'error',
      if (!success) 'error': 'Fixture failure',
    });
    await _until(() => !owner.snapshot.hasActiveTurn);
  }

  Future<void> close() => session.close();
}
