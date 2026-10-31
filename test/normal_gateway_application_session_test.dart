// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_application_session_test.dart
// Base 4a53e32 blob 95ccf5c12f79e9915b0e68c56621dc133caa3c43; SHA256 b365a27d4551f13da243eedf4e08d8f9fcc4ee97abdb64594089350518d5715d.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_message_time.dart';
// flutter_test supplies this deterministic timer clock via its SDK dependency.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/chat_history_window.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'stock send and receipt times survive updates and canonical-alias reopen',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      final sent = ChatMessageTime.fromRow(f.owner.snapshot.displayRows.first)!;
      expect(sent.source, ChatMessageTimeSource.sent);
      f.emit('message.delta', {'text': 'first'});
      final received = ChatMessageTime.fromRow(
        f.owner.snapshot.displayRows.last,
      )!;
      f.emit('message.delta', {'text': 'second'});
      expect(
        ChatMessageTime.fromRow(f.owner.snapshot.displayRows.last)!.at,
        received.at,
      );
      f.finish('message.complete', {
        'text': 'final',
        'timestamp': 1718456700.125,
      });
      final finalTime = ChatMessageTime.fromRow(
        f.owner.snapshot.displayRows.last,
      )!;
      expect(finalTime.source, ChatMessageTimeSource.recorded);
      expect(finalTime.at.millisecondsSinceEpoch, 1718456700125);
      NormalGatewayChatSnapshot? reopened;
      final owner = f.chat('stored', stored: 'stored');
      owner.subscribe((value) => reopened = value);
      expect(
        ChatMessageTime.fromRow(reopened!.displayRows.last)!.at,
        finalTime.at,
      );
      expect(ChatMessageTime.fromRow(reopened!.displayRows.first)!.at, sent.at);
      expect(f.submissions, 1);
    },
  );

  test(
    'binding notifies real canonical changes but not duplicate route aliases',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.session.ready;
      final owner = f.chat('local');
      var notifications = 0;
      owner.subscribe((_) => notifications++);
      owner.bindStoredSession('stored');
      expect(notifications, 2);
      expect(identical(f.session.findChat('stored'), owner), isTrue);
      expect(identical(f.chat('stored', stored: 'stored'), owner), isTrue);
      expect(identical(f.chat('local', stored: 'stored'), owner), isTrue);
      expect(
        notifications,
        2,
        reason: 'same canonical binding must not fan out during route mount',
      );
      owner.bindStoredSession('canonical-tip');
      expect(notifications, 3);
      expect(owner.storedSessionId, 'canonical-tip');
      expect(identical(f.session.findChat('canonical-tip'), owner), isTrue);
    },
  );

  test(
    'duplicate routes and durable/local aliases share synchronous admission',
    () async {
      final f = _Fixture();
      await f.session.ready;
      final a = f.chat('draft', stored: 'stored');
      final alias = f.chat('stored', stored: 'stored');
      expect(identical(a, alias), isTrue);
      final reservation = a.reserve()!;
      expect(alias.reserve(), isNull);
      expect(f.chat('other', stored: 'other-stored').reserve(), isNotNull);
      a.cancelPreparation(reservation);
      expect(alias.reserve(), isNotNull);
      await f.close();
    },
  );

  test(
    'unsubscribed owner reduces tokens, tools and reasoning; reattach is immediate',
    () async {
      final f = _Fixture();
      await f.start();
      var calls = 0;
      final token = f.owner.subscribe((_) => calls++);
      f.owner.unsubscribe(token);
      final before = calls;
      f.emit('message.delta', {'text': 'While absent'});
      f.emit('tool.start', {'tool': 'read_file', 'tool_id': 't1'});
      f.emit('tool.complete', {
        'tool': 'read_file',
        'tool_id': 't1',
        'status': 'completed',
      });
      f.emit('reasoning.delta', {'text': 'Considering'});
      expect(calls, before);
      NormalGatewayChatSnapshot? restored;
      f.owner.subscribe((value) => restored = value);
      expect(restored!.displayRows.last['content'], 'While absent');
      expect(restored!.tools, hasLength(1));
      expect(restored!.tools.single.isTerminal, isTrue);
      expect(f.submissions, 1);
      f.rows = [
        {'id': 12, 'role': 'assistant', 'content': 'Finished while absent'},
      ];
      f.running = false;
      f.finish('message.complete', {'text': 'Finished while absent'});
      f.rpc.complete();
      await f.flight;
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      expect(
        f.owner.snapshot.historyRows.last['content'],
        'Finished while absent',
      );
      expect(await f.store.load('scope'), isEmpty);
      await f.close();
    },
  );

  for (final role in ['assistant', 'agent']) {
    test(
      'later fresh $role history atomically retires completed presentation',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        await f.start();
        f.emit('message.delta', {'text': 'Wire preview'});
        f.emit('reasoning.delta', {'text': 'Transient reasoning'});
        f.emit('tool.start', {'tool': 'read_file', 'tool_id': 't1'});
        f.emit('subagent.start', {
          'subagent_id': 'runtime-root',
          'child_session_id': 'child-root',
          'goal': 'Inspect',
        });
        f.emit('subagent.text', {
          'subagent_id': 'runtime-root',
          'child_session_id': 'child-tip',
          'text': 'Progress',
        });
        f.finish('message.complete', {'text': 'Wire preview'});
        await _flush();
        final retained = f.owner.snapshot;
        expect(retained.phase, NormalGatewayTurnPhase.completed);
        expect(retained.rowFloor, 10);
        expect(retained.displayRows.last['content'], 'Wire preview');
        expect(retained.timeline.runs, isNotEmpty);
        expect(retained.tools, isNotEmpty);
        expect(retained.subagents, isNotEmpty);
        final observations = <NormalGatewayChatSnapshot>[];
        f.owner.subscribe(observations.add);
        observations.clear();

        f.owner.observeHistory([
          {'id': 11, 'role': 'user', 'content': 'private prompt'},
          {'id': 12, 'role': role, 'content': 'Canonical final'},
        ]);

        expect(observations, hasLength(1));
        final hydrated = observations.single;
        expect(hydrated.historyRows.last['content'], 'Canonical final');
        expect(hydrated.displayRows, isNotEmpty);
        expect(hydrated.timeline.runs, isNotEmpty);
        expect(hydrated.tools, isNotEmpty);
        expect(hydrated.subagents, isNotEmpty);
        expect(hydrated.phase, NormalGatewayTurnPhase.completed);
        expect(hydrated.turnId, retained.turnId);
        expect(identical(f.session.findChat('stored'), f.owner), isTrue);

        // Hydration retires presentation, not the observer's lineage knowledge.
        f.emit('subagent.complete', {
          'subagent_id': 'new-runtime-alias',
          'child_session_id': 'child-tip',
          'status': 'failed',
        });
        final child = f.owner.snapshot.subagents.single;
        expect(child.id, 'runtime-root');
        expect(child.childSessionId, 'child-root');
        expect(child.latestChildSessionId, 'child-tip');
        expect(child.goal, 'Inspect');
        expect(child.failed, isTrue);
        expect(f.owner.snapshot.hasActiveTurn, isFalse);
        expect(f.owner.snapshot.displayRows, retained.displayRows);
        f.owner.observeHistory(hydrated.historyRows);
        expect(f.owner.snapshot.subagents.single.childSessionId, 'child-root');
        expect(f.owner.snapshot.subagents.single.failed, isTrue);
        expect(f.submissions, 1);
      },
    );
  }

  test(
    'late old, interim, tool, user and empty pages retain completed response',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.finish('message.complete', {'text': 'Wire preview'});
      await _flush();
      for (final rows in <List<Map<String, dynamic>>>[
        [],
        [
          {'id': 10, 'role': 'assistant', 'content': 'Old final'},
        ],
        [
          {'id': 11, 'role': 'user', 'content': 'private prompt'},
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Interim',
            'interim': true,
          },
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Interim',
            '_gateway_interim': true,
          },
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Interim',
            'is_interim': true,
          },
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Tool',
            'tool_calls': [
              {'id': 't1'},
            ],
          },
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Tool',
            'finish_reason': 'tool_calls',
          },
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Tool',
            'tool_call_id': 't1',
          },
        ],
        [
          {'id': 12, 'role': 'tool', 'content': 'Result'},
        ],
        [
          {'id': 12, 'role': 'assistant', 'content': '  '},
        ],
        [
          {'role': 'assistant', 'content': 'No durable identity'},
        ],
      ]) {
        f.owner.observeHistory(rows);
        expect(
          f.owner.snapshot.displayRows.last['content'],
          'Wire preview',
          reason: '$rows',
        );
        expect(f.owner.snapshot.timeline.runs, isNotEmpty, reason: '$rows');
        expect(f.owner.phase, NormalGatewayTurnPhase.completed);
      }
    },
  );

  test(
    'latest history cannot replace an active reply or its admission baseline',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.emit('message.delta', {'text': 'Still running'});
      final before = f.owner.snapshot;
      f.owner.observeHistory([
        {'id': 12, 'role': 'assistant', 'content': 'Not terminal evidence'},
      ]);
      expect(f.owner.snapshot.phase, NormalGatewayTurnPhase.running);
      expect(f.owner.snapshot.historyRows, before.historyRows);
      expect(f.owner.snapshot.displayRows, before.displayRows);
      expect(f.owner.snapshot.timeline, same(before.timeline));
      expect(f.owner.snapshot.rowFloor, 10);
    },
  );

  for (final durableIds in [false, true]) {
    test(
      'completed empty scaffold hands off without text correlation (durableIds=$durableIds)',
      () async {
        final f = _Fixture()..rows = [];
        addTearDown(f.close);
        await f.start(seedHistory: false, unavailableAdmission: true);
        f.finish('turn.end', {'status': 'completed'});
        await _flush();
        expect(f.owner.phase, NormalGatewayTurnPhase.completed);
        expect(f.owner.snapshot.rowFloor, isNull);
        expect(f.owner.snapshot.displayRows.first['content'], 'private prompt');
        expect(f.owner.snapshot.displayRows.last['content'], isEmpty);
        expect(f.owner.snapshot.timeline.runs, isEmpty);

        // History owns an unmaterialized scaffold, not a text-matched turn.
        // Rewritten canonical prompt text must not be an identity heuristic.
        f.owner.observeHistory([
          {
            if (durableIds) 'id': 11,
            'role': 'user',
            'content': 'Canonical prompt representation',
          },
          {
            if (durableIds) 'id': 12,
            'role': 'assistant',
            'content': 'Canonical response',
          },
        ]);
        expect(f.owner.snapshot.displayRows, isEmpty);
        expect(
          f.owner.snapshot.historyRows.last['content'],
          'Canonical response',
        );
        expect(f.owner.phase, NormalGatewayTurnPhase.completed);
        expect(f.submissions, 1);
      },
    );
  }

  test(
    'completed empty scaffold survives failed and incomplete latest reads',
    () async {
      final f = _Fixture()..historyFails = true;
      addTearDown(f.close);
      await f.start(seedHistory: false, unavailableAdmission: true);
      f.finish('turn.end', {'status': 'completed'});
      await _flush();
      final scaffold = f.owner.snapshot.displayRows;
      expect(scaffold, hasLength(2));
      for (final rows in <List<Map<String, dynamic>>>[
        [],
        [
          {'role': 'assistant', 'content': 'Old assistant without a user turn'},
        ],
        [
          {'role': 'user', 'content': 'private prompt'},
        ],
        [
          {'role': 'user', 'content': 'private prompt'},
          {'role': 'assistant', 'content': ''},
        ],
        [
          {'role': 'user', 'content': 'private prompt'},
          {'role': 'assistant', 'content': 'Interim', 'interim': true},
        ],
        [
          {'role': 'user', 'content': 'private prompt'},
          {
            'role': 'assistant',
            'content': 'Tool',
            'finish_reason': 'tool_calls',
          },
        ],
      ]) {
        f.owner.observeHistory(rows);
        expect(f.owner.snapshot.displayRows, scaffold, reason: '$rows');
        expect(f.owner.snapshot.rowFloor, isNull);
      }
    },
  );

  test('known stale full turn cannot replace even an empty scaffold', () async {
    final f = _Fixture()
      ..rows = [
        {'id': 9, 'role': 'user', 'content': 'private prompt'},
        {
          'id': 10,
          'role': 'assistant',
          'content': 'Old repeated-prompt answer',
        },
      ];
    addTearDown(f.close);
    await f.start();
    f.finish('turn.end', {'status': 'completed'});
    await _flush();
    expect(f.owner.snapshot.rowFloor, 10);
    expect(f.owner.snapshot.displayRows, hasLength(2));
    f.owner.observeHistory(f.rows);
    expect(f.owner.snapshot.displayRows, hasLength(2));
    f.owner.observeHistory([
      ...f.rows,
      {'id': 11, 'role': 'user', 'content': 'private prompt'},
      {'id': 12, 'role': 'assistant', 'content': 'Fresh canonical answer'},
    ]);
    expect(f.owner.snapshot.displayRows, isEmpty);
  });

  for (final (type, data) in <(String, Map<String, dynamic>)>[
    ('message.delta', {'text': 'Received reply'}),
    ('reasoning.delta', {'text': 'Received reasoning'}),
    ('tool.start', {'tool': 'read_file', 'tool_id': 't1'}),
    ('subagent.start', {'subagent_id': 'child', 'goal': 'Inspect'}),
  ]) {
    test('unknown-floor $type is not an empty submission scaffold', () async {
      final f = _Fixture()..rows = [];
      addTearDown(f.close);
      await f.start(seedHistory: false, unavailableAdmission: true);
      f.emit(type, data);
      f.finish('turn.end', {'status': 'completed'});
      await _flush();
      final retained = f.owner.snapshot;
      f.owner.observeHistory([
        {'role': 'user', 'content': 'private prompt'},
        {'role': 'assistant', 'content': 'Old repeated-prompt answer'},
      ]);
      expect(f.owner.snapshot.displayRows, retained.displayRows);
      expect(f.owner.snapshot.timeline, same(retained.timeline));
      expect(f.owner.snapshot.tools, retained.tools);
      expect(f.owner.snapshot.subagents, retained.subagents);
    });
  }

  test(
    'empty latest turn cannot hand off a prior materialized reply',
    () async {
      final f = _Fixture()..historyFails = true;
      addTearDown(f.close);
      await f.start(seedHistory: false, unavailableAdmission: true);
      f.finish('message.complete', {'text': 'Prior received reply'});
      await _flush();
      f.rpc.complete();
      await f.flight;
      f.resetRpc();
      f.flight = f.owner.submitPrepared(
        reservation: f.owner.reserve()!,
        text: 'Next prompt',
        localContent: 'Next prompt',
      );
      await _flush();
      f.finish('turn.end', {'status': 'completed'});
      await _flush();
      final retained = f.owner.snapshot;
      expect(retained.rowFloor, isNull);
      expect(retained.displayRows, hasLength(4));
      f.owner.observeHistory([
        {'role': 'user', 'content': 'Next prompt'},
        {'role': 'assistant', 'content': 'Uncorrelated canonical reply'},
      ]);
      expect(f.owner.snapshot.displayRows, retained.displayRows);
      expect(f.owner.snapshot.timeline, same(retained.timeline));
    },
  );

  test('unknown outcome does not hand off an empty scaffold', () async {
    final f = _Fixture()
      ..rows = []
      ..running = false
      ..terminalStatus = 'idle';
    addTearDown(f.close);
    await f.start(seedHistory: false, unavailableAdmission: true);
    f.rpc.complete();
    await f.flight;
    await _flush();
    final retained = f.owner.snapshot.displayRows;
    expect(f.owner.phase, NormalGatewayTurnPhase.reconciledUnknown);
    f.owner.observeHistory([
      {'role': 'user', 'content': 'private prompt'},
      {'role': 'assistant', 'content': 'Unconfirmed canonical reply'},
    ]);
    expect(f.owner.snapshot.displayRows, retained);
  });

  test(
    'unknown floor never retires materialized reply by matching an old prompt',
    () async {
      final f = _Fixture()
        ..rows = [
          {'id': 1, 'role': 'user', 'content': 'private prompt'},
          {
            'id': 2,
            'role': 'assistant',
            'content': 'Old identical-prompt answer',
          },
        ];
      addTearDown(f.close);
      await f.start(seedHistory: false, unavailableAdmission: true);
      f.finish('message.complete', {'text': 'New wire response'});
      await _flush();
      expect(f.owner.snapshot.rowFloor, isNull);
      expect(f.owner.snapshot.displayRows.last['content'], 'New wire response');
      f.owner.observeHistory([
        ...f.rows,
        {'id': 100, 'role': 'assistant', 'content': 'Uncorrelated final'},
      ]);
      expect(f.owner.snapshot.displayRows.last['content'], 'New wire response');
      expect(f.owner.snapshot.timeline.runs, isNotEmpty);
      expect(f.owner.snapshot.rowFloor, isNull);
    },
  );

  test(
    'late history preserves an unknown outcome and its materialized reply',
    () async {
      final f = _Fixture()
        ..running = false
        ..terminalStatus = 'idle';
      addTearDown(f.close);
      await f.start();
      f.emit('message.delta', {'text': 'Unconfirmed wire response'});
      f.rpc.complete();
      await f.flight;
      await _flush();
      expect(f.owner.phase, NormalGatewayTurnPhase.reconciledUnknown);
      f.owner.observeHistory([
        {'id': 12, 'role': 'assistant', 'content': 'Later partial response'},
      ]);
      expect(f.owner.phase, NormalGatewayTurnPhase.reconciledUnknown);
      expect(f.owner.snapshot.status!.kind, 'reconciled_unknown');
      expect(
        f.owner.snapshot.displayRows.last['content'],
        'Unconfirmed wire response',
      );
      expect(f.owner.snapshot.timeline.runs, isNotEmpty);
    },
  );

  test(
    'fresh latest history retires prior and current completed projections together',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.finish('message.complete', {'text': 'First wire response'});
      await _flush();
      f.rpc.complete();
      await f.flight;
      f.resetRpc();
      await f.start();
      f.finish('message.complete', {'text': 'Second wire response'});
      await _flush();
      expect(
        f.owner.snapshot.displayRows.map((row) => row['content']),
        containsAll(['First wire response', 'Second wire response']),
      );
      f.owner.observeHistory([
        {'id': 20, 'role': 'assistant', 'content': 'Latest canonical response'},
      ]);
      expect(
        f.owner.snapshot.displayRows.map((row) => row['content']),
        containsAll(['First wire response', 'Second wire response']),
      );
      expect(f.owner.snapshot.timeline.runs, isNotEmpty);
      expect(f.owner.snapshot.historyRows.single['id'], 20);
      expect(f.submissions, 2);
    },
  );

  test(
    'unknown-floor presentation pins known context, not later canonical rows',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.session.ready;
      const before = [
        {'id': 3, 'role': 'assistant', 'content': 'Older numeric context'},
        {
          'id': 'legacy',
          'role': 'assistant',
          'content': 'Known legacy context',
        },
      ];
      f.chat('local', stored: 'stored').observeHistory(before);
      await f.start(seedHistory: false, unavailableAdmission: true);
      expect(f.owner.snapshot.rowFloor, isNull);
      f.emit('message.delta', {'text': 'Received response'});
      expect(f.owner.snapshot.historyRows, before);
      f.finish('message.complete', {'text': 'Received response'});
      await _flush();
      const canonical = [
        {'id': 11, 'role': 'user', 'content': 'Unrelated canonical prompt'},
        {
          'id': 12,
          'role': 'assistant',
          'content': 'Unproven different response',
        },
      ];
      f.owner.observeHistory(canonical);
      expect(f.owner.snapshot.historyRows, canonical);
      expect(f.owner.snapshot.historyRows, canonical);
      const older = {
        'id': 1,
        'role': 'assistant',
        'content': 'Paged older context',
      };
      final window = ChatHistoryWindow();
      window.acceptRecent(const ChatHistoryPageBatch(before, 2, false));
      window.acceptOlder([older]);
      window.acceptRecent(const ChatHistoryPageBatch(canonical, 2, false));
      expect(window.rows, [older, before.first, ...canonical]);
      expect(f.owner.snapshot.displayRows.last['content'], 'Received response');
      expect(f.owner.snapshot.timeline.runs, isNotEmpty);
    },
  );

  test(
    'a newer numeric baseline cannot retire an older unknown-floor reply',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start(seedHistory: false, unavailableAdmission: true);
      f.finish('message.complete', {'text': 'Uncorrelated first response'});
      await _flush();
      expect(f.owner.snapshot.historyRows.single['id'], 10);
      f.rpc.complete();
      await f.flight;
      f.resetRpc();
      await f.start(seedHistory: false, unavailableAdmission: true);
      expect(f.owner.snapshot.rowFloor, isNull);
      f.finish('message.complete', {'text': 'Second received response'});
      await _flush();
      f.owner.observeHistory([
        {'id': 20, 'role': 'assistant', 'content': 'New canonical response'},
      ]);
      expect(f.owner.snapshot.displayRows, hasLength(4));
      expect(
        f.owner.snapshot.displayRows.map((row) => row['content']),
        containsAll([
          'Uncorrelated first response',
          'Second received response',
        ]),
      );
      expect(
        f.owner.snapshot.historyRows.single['content'],
        'New canonical response',
      );
    },
  );

  test('RPC acknowledgement alone is unresolved, never terminal', () async {
    final f = _Fixture();
    await f.start();
    f.rpc.complete();
    await f.flight;
    expect(f.owner.snapshot.hasActiveTurn, isTrue);
    expect(f.owner.phase, NormalGatewayTurnPhase.reconciling);
    expect(f.submissions, 1);
    await f.close();
  });

  test(
    'late latest history retires settled presentation only beyond its durable floor',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.emit('message.start', {}, turnId: 'A');
      f.emit('message.delta', {'text': 'Wire reply'}, turnId: 'A');
      f.emit('tool.start', {
        'tool': 'read_file',
        'tool_id': 'optimistic',
      }, turnId: 'A');
      f.emit('subagent.start', {'id': 'child', 'task': 'Task'}, turnId: 'A');
      f.emit('turn.end', {'status': 'completed'}, turnId: 'A');
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      final runs = f.owner.snapshot.timeline.runs.map((run) => run.id).toList();
      for (final rows in <List<Map<String, dynamic>>>[
        [],
        [
          {'id': 9, 'role': 'assistant', 'content': 'Old reply'},
        ],
        [
          {'id': 11, 'role': 'user', 'content': 'User only'},
        ],
        [
          {
            'id': 12,
            'role': 'assistant',
            'content': 'Tool intermediate',
            'tool_calls': [
              {'id': 'tc'},
            ],
          },
        ],
        [
          {
            'id': 13,
            'role': 'assistant',
            'content': 'Interim',
            'interim': true,
          },
        ],
        [
          {'role': 'assistant', 'content': 'No durable identity'},
        ],
      ]) {
        f.owner.observeHistory(rows);
        expect(
          f.owner.snapshot.displayRows.last['content'],
          'Wire reply',
          reason: '$rows',
        );
        expect(f.owner.snapshot.tools, hasLength(1));
        expect(f.owner.snapshot.timeline.runs.map((run) => run.id), runs);
      }
      f.owner.observeHistory([
        {'id': 20, 'role': 'agent', 'content': 'Canonical different reply'},
      ]);
      expect(f.owner.snapshot.displayRows.last['content'], 'Wire reply');
      expect(f.owner.snapshot.timeline.runs.map((run) => run.id), runs);
      expect(f.owner.snapshot.tools.single.toolId, 'optimistic');
      expect(f.owner.snapshot.subagents, isNotEmpty);
      expect(f.owner.snapshot.historyRows.single['id'], 20);
    },
  );

  test(
    'late history cannot erase an active overlay or change its baseline',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.emit('message.delta', {'text': 'Still running'});
      f.emit('tool.start', {'tool': 'read_file', 'tool_id': 'live'});
      f.owner.observeHistory([
        {'id': 100, 'role': 'assistant', 'content': 'A late route response'},
      ]);
      expect(f.owner.snapshot.displayRows.last['content'], 'Still running');
      expect(f.owner.snapshot.tools, hasLength(1));
      expect(f.owner.snapshot.rowFloor, 10);
      expect(f.owner.snapshot.historyRows.single['id'], 10);
    },
  );

  test(
    'unknown settled floor cannot retire projection on old matching prompt text',
    () async {
      final f = _Fixture()..historyFails = true;
      addTearDown(f.close);
      await f.start(seedHistory: false);
      f.historyFails = false;
      f.rows = [
        {'id': 1, 'role': 'user', 'content': 'private prompt'},
        {'id': 2, 'role': 'assistant', 'content': 'Old identical prompt reply'},
      ];
      f.emit('message.start', {}, turnId: 'A');
      f.emit('message.delta', {'text': 'Wire reply'}, turnId: 'A');
      f.emit('turn.end', {'status': 'completed'}, turnId: 'A');
      await _flush();
      expect(f.owner.snapshot.rowFloor, isNull);
      expect(f.owner.snapshot.displayRows.last['content'], 'Wire reply');
      f.owner.observeHistory([
        {'id': 100, 'role': 'assistant', 'content': 'Arbitrary old assistant'},
      ]);
      expect(f.owner.snapshot.displayRows.last['content'], 'Wire reply');
    },
  );

  test(
    'pre-wire rejection clears receipt; post-wire loss never resends',
    () async {
      final rejected = _Fixture()..emitOnSubmit = false;
      await rejected.start();
      rejected.rpc.completeError(StateError('before wire'));
      await expectLater(rejected.flight, throwsStateError);
      expect(rejected.owner.snapshot.hasActiveTurn, isFalse);
      expect(rejected.owner.snapshot.displayRows, isEmpty);
      expect(await rejected.store.load('scope'), isEmpty);
      await rejected.close();

      final lost = _Fixture();
      await lost.start();
      lost.rpc.completeError(StateError('after wire'));
      await lost.flight;
      expect(lost.owner.snapshot.hasActiveTurn, isTrue);
      expect(lost.owner.snapshot.wireEmitted, isTrue);
      expect(await lost.store.load('scope'), hasLength(1));
      lost.session.connectionChanged(DesktopConnectionState.connected);
      await _flush();
      expect(lost.submissions, 1);
      expect(lost.resumes, greaterThan(0));
      await lost.close();
    },
  );

  test(
    'write-ahead receipt exists before submit and contains no prompt/runtime/credential',
    () async {
      final f = _Fixture();
      await f.start();
      final marker = f.atInvocation.single;
      expect(marker.phase, 'write_ahead');
      expect(marker.rowFloor, 10);
      expect(marker.storedSessionId, 'stored');
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(NormalGatewayPendingStore.preferenceKey)!;
      expect(json, isNot(contains('private prompt')));
      expect(json, isNot(contains('private-key')));
      expect(json, isNot(contains('runtime')));
      expect(jsonDecode(json).single.keys.toSet(), {
        'schema',
        'scope',
        'local_id',
        'stored_id',
        'local_turn_id',
        'row_floor',
        'phase',
        'created_at',
        'updated_at',
      });
      await f.close();
    },
  );

  for (final phase in ['write_ahead', 'emitted']) {
    test(
      'crash receipt $phase restores reconciling, resume-only, no create/submit',
      () async {
        final store = NormalGatewayPendingStore();
        await store.put(_marker('local', phase: phase));
        final resumed = Completer<ResumedGatewaySession>();
        var submissions = 0;
        var resumes = 0;
        final session = NormalGatewayApplicationSession(
          connection: _connection,
          scope: 'scope',
          pendingStore: store,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                submissions++;
              },
          resume: ({required localSessionId, required storedSessionId}) {
            expect(localSessionId, 'local');
            expect(storedSessionId, 'stored');
            resumes++;
            return resumed.future;
          },
          history: (_) async => [
            {'id': 12, 'role': 'agent', 'content': 'Recovered final'},
          ],
        );
        await session.ready;
        final owner = session.findChat('stored')!;
        expect(owner.phase, NormalGatewayTurnPhase.reconciling);
        expect(owner.reserve(), isNull);
        expect(resumes, 1);
        resumed.complete(
          const ResumedGatewaySession(
            runtimeSessionId: 'runtime',
            running: false,
          ),
        );
        await _flush();
        expect(owner.snapshot.hasActiveTurn, isFalse);
        expect(owner.snapshot.historyRows.single['role'], 'agent');
        expect(submissions, 0);
        expect(await store.load('scope'), isEmpty);
        await session.close();
      },
    );
  }

  test(
    'fresh sliding rows required; running, tool and interim rows cannot settle',
    () async {
      final f = _Fixture();
      await f.start();
      f.rpc.completeError(StateError('wire lost'));
      await f.flight;
      f.running = false;
      for (final row in [
        {'id': 10, 'role': 'assistant', 'content': 'Old retained final'},
        {'id': 11, 'role': 'user', 'content': 'Prompt'},
        {
          'id': 12,
          'role': 'assistant',
          'content': 'tool',
          'tool_calls': [
            {'id': 'tc'},
          ],
        },
        {'id': 13, 'role': 'assistant', 'content': 'Interim', 'interim': true},
      ]) {
        f.rows = [row];
        f.owner.requestRecovery();
        await _flush();
        expect(f.owner.snapshot.hasActiveTurn, isTrue, reason: '$row');
      }
      f.rows = [
        {'id': 999, 'role': 'agent', 'content': 'Fresh final, no overlap'},
      ];
      f.running = true;
      f.owner.requestRecovery();
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isTrue);
      f.running = null;
      f.owner.requestRecovery();
      await _flush();
      expect(
        f.owner.snapshot.hasActiveTurn,
        isTrue,
        reason: 'unknown running state is unresolved',
      );
      f.running = false;
      f.owner.requestRecovery();
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      expect(f.owner.snapshot.historyRows.single['id'], 999);
      await f.close();
    },
  );

  test(
    'history failures and unknown baseline never manufacture empty completion',
    () async {
      final f = _Fixture()..historyFails = true;
      await f.start(seedHistory: false);
      expect(f.owner.snapshot.rowFloor, isNull);
      f.rpc.completeError(StateError('lost'));
      await f.flight;
      f.historyFails = false;
      f.running = false;
      f.rows = [
        {'id': 100, 'role': 'assistant', 'content': 'May be older'},
      ];
      f.owner.requestRecovery();
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isTrue);
      await f.close();
    },
  );

  test(
    'unknown existing history is read before wire; retained old terminal cannot settle',
    () async {
      final f = _Fixture()
        ..rows = [
          {'id': 75, 'role': 'assistant', 'content': 'Retained old final'},
        ];
      addTearDown(f.close);
      await f.start(seedHistory: false);
      expect(f.historyIds, ['stored']);
      expect(f.owner.snapshot.rowFloor, 75);
      expect(f.atInvocation.single.rowFloor, 75);
      expect(f.atInvocation.single.phase, 'write_ahead');
      f.running = false;
      f.emit('message.complete', {'text': 'Retained old final'});
      f.rpc.complete();
      await f.flight;
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isTrue);
      expect(await f.store.load('scope'), hasLength(1));
      f.rows = [
        {'id': 76, 'role': 'user', 'content': 'private prompt'},
        {'id': 77, 'role': 'assistant', 'content': 'New final'},
      ];
      f.owner.requestRecovery();
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      expect(await f.store.load('scope'), isEmpty);
      expect(f.submissions, 1);
    },
  );

  for (final status in [404, 503]) {
    test(
      'pre-wire HTTP $status is unknown, never floor zero or old-history completion',
      () async {
        final f = _Fixture()..historyError = Exception('HTTP $status');
        addTearDown(f.close);
        await f.start(seedHistory: false);
        expect(f.owner.snapshot.rowFloor, isNull);
        expect(f.atInvocation.single.rowFloor, isNull);
        expect(f.historyIds, ['stored']);
        f.historyError = null;
        f.rows = [
          {'id': 100, 'role': 'assistant', 'content': 'Possibly old final'},
        ];
        f.running = false;
        f.emit('message.complete', {'text': 'Possibly old final'});
        f.rpc.complete();
        await f.flight;
        await _flush();
        expect(f.owner.snapshot.hasActiveTurn, isTrue);
        expect(f.owner.snapshot.rowFloor, isNull);
        expect(await f.store.load('scope'), hasLength(1));
        expect(f.submissions, 1);
      },
    );
  }

  test(
    'known canonical baseline avoids a redundant slow pre-wire read',
    () async {
      final f = _Fixture()
        ..historyGate = Completer<List<Map<String, dynamic>>>();
      addTearDown(f.close);
      await f.start();
      expect(f.historyIds, isEmpty);
      expect(f.submissions, 1);
      expect(f.owner.snapshot.rowFloor, 10);
      expect(f.atInvocation.single.rowFloor, 10);
    },
  );

  test('close during binding cannot start an admission read or wire', () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.session.ready;
    final chat = f.chat('local');
    chat.subscribe((snapshot) {
      if (snapshot.storedSessionId != null) unawaited(f.session.close());
    });
    await chat.submitPrepared(
      reservation: chat.reserve()!,
      text: 'Prompt',
      localContent: 'Prompt',
      knownStoredSessionId: 'stored',
    );
    expect(f.historyIds, isEmpty);
    expect(f.submissions, 0);
    expect(await f.store.load('scope'), isEmpty);
  });

  for (final closeBeforeDeadline in [false, true]) {
    test(
      'bounded admission read closeBeforeDeadline=$closeBeforeDeadline fences late baseline and cancels timer',
      () async {
        final prefs = await SharedPreferences.getInstance();
        fakeAsync((clock) {
          final held = Completer<List<Map<String, dynamic>>>();
          final rpc = Completer<void>();
          var submissions = 0;
          late NormalGatewayChatOwner chat;
          final session = NormalGatewayApplicationSession(
            connection: _connection,
            scope: 'scope',
            pendingStore: NormalGatewayPendingStore(
              preferences: () async => prefs,
            ),
            history: (_) => held.future,
            resume:
                ({required localSessionId, required storedSessionId}) async =>
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
                }) {
                  submissions++;
                  onSent();
                  return rpc.future;
                },
          );
          session.ready.then((_) {
            chat = session.chatFor(
              'local',
              storedSessionId: 'stored',
              title: 'Chat',
            );
            unawaited(
              chat.submitPrepared(
                reservation: chat.reserve()!,
                text: 'Prompt',
                localContent: 'Prompt',
              ),
            );
          });
          clock.flushMicrotasks();
          expect(submissions, 0);
          expect(clock.pendingTimers, hasLength(1));
          if (closeBeforeDeadline) {
            session.close(); // invalidates this submission's generation
            clock.flushMicrotasks();
            expect(clock.pendingTimers, isEmpty);
          } else {
            clock.elapse(const Duration(milliseconds: 1999));
            expect(submissions, 0);
            clock.elapse(const Duration(milliseconds: 1));
            expect(submissions, 1);
            expect(chat.snapshot.wireEmitted, isTrue);
            expect(clock.pendingTimers, isEmpty);
          }
          held.complete([
            {'id': 999, 'role': 'assistant', 'content': 'Too late'},
          ]);
          clock.flushMicrotasks();
          expect(chat.snapshot.rowFloor, isNull);
          expect(chat.snapshot.historyRows, isEmpty);
          expect(submissions, closeBeforeDeadline ? 0 : 1);
          session.close();
          rpc.complete();
          clock.flushMicrotasks();
          expect(clock.pendingTimers, isEmpty);
          session.pendingStore.load('scope').then((markers) {
            expect(markers, hasLength(closeBeforeDeadline ? 0 : 1));
            if (markers.isNotEmpty) expect(markers.single.rowFloor, isNull);
          });
          clock.flushMicrotasks();
        });
      },
    );
  }

  test(
    'recovery single flight hands old held history to next generation',
    () async {
      final f = _Fixture();
      await f.start();
      f.rpc.completeError(StateError('lost'));
      await f.flight;
      await _flush();
      final held = Completer<List<Map<String, dynamic>>>();
      f.historyGate = held;
      f.owner.requestRecovery();
      await _flush();
      final firstTurn = f.owner.turnId;
      f.emit('message.start', {}, turnId: 'A');
      f.emit('turn.end', {'status': 'completed'}, turnId: 'A');
      await _flush();
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      f.resetRpc();
      await f.start(seedHistory: true);
      expect(f.owner.turnId, isNot(firstTurn));
      f.rpc.completeError(StateError('second lost'));
      await f.flight;
      f.rows = [
        {'id': 30, 'role': 'agent', 'content': 'Second final'},
      ];
      f.running = false;
      f.historyGate = null;
      held.complete([
        {'id': 11, 'role': 'agent', 'content': 'Stale first final'},
      ]);
      await _flush();
      expect(f.submissions, 2);
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      expect(f.owner.snapshot.historyRows.single['id'], 30);
      await f.close();
    },
  );

  test(
    'background policy pauses recovery without cancelling remote work',
    () async {
      final f = _Fixture();
      await f.start();
      f.session.setLifecycle(background: true, backgroundWorkEnabled: false);
      f.rpc.completeError(StateError('lost'));
      await f.flight;
      final count = f.resumes;
      f.owner.requestRecovery();
      await _flush();
      expect(f.resumes, count);
      expect(f.owner.snapshot.hasActiveTurn, isTrue);
      f.session.setLifecycle(background: false);
      await _flush();
      expect(f.resumes, greaterThan(count));
      expect(f.submissions, 1);
      await f.close();
    },
  );

  test(
    'retained approvals survive unsubscribe; socket replacement invalidates old identity',
    () async {
      final f = _Fixture();
      await f.start();
      final registration = f.owner.subscribe((_) {});
      f.owner.unsubscribe(registration);
      f.emit('approval.request', {
        'server_request_id': 'socket-a:42',
        'command': 'test',
      });
      expect(
        f.owner.snapshot.pendingInput.single.data['server_request_id'],
        'socket-a:42',
      );
      f.session.connectionChanged(DesktopConnectionState.disconnected);
      expect(f.owner.snapshot.pendingInput, isEmpty);
      f.emit('approval.request', {
        'server_request_id': 'socket-b:42',
        'command': 'test',
      });
      expect(
        await f.session.tryRespondToApproval(
          sessionId: 'stored',
          requestId: 'socket-a:42',
          choice: 'approve',
        ),
        isFalse,
      );
      expect(
        f.owner.snapshot.pendingInput.single.data['server_request_id'],
        'socket-b:42',
      );
      await f.close();
    },
  );

  test('pending stores serialize read/modify/write across instances', () async {
    final a = NormalGatewayPendingStore();
    final b = NormalGatewayPendingStore();
    await Future.wait([a.put(_marker('a')), b.put(_marker('b'))]);
    expect((await a.load('scope')).map((row) => row.localSessionId).toSet(), {
      'a',
      'b',
    });
    await Future.wait([a.remove(_marker('a')), b.put(_marker('c'))]);
    expect((await b.load('scope')).map((row) => row.localSessionId).toSet(), {
      'b',
      'c',
    });
    await a.put(_marker('b').withPhase('settled'));
    expect((await b.load('scope')).map((row) => row.localSessionId), ['c']);
  });

  test(
    'long outage has no attempt exhaustion and policy resume restarts immediately',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await NormalGatewayPendingStore().put(_marker('local'));
      fakeAsync((clock) {
        var attempts = 0;
        final session = NormalGatewayApplicationSession(
          connection: _connection,
          scope: 'scope',
          pendingStore: NormalGatewayPendingStore(
            preferences: () async => prefs,
          ),
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                fail('Recovery must never submit');
              },
          resume: ({required localSessionId, required storedSessionId}) async {
            attempts++;
            throw StateError('Still offline');
          },
          history: (_) async => [],
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(hours: 2));
        expect(attempts, greaterThan(100));
        expect(session.hasActiveTurn, isTrue);
        session.setLifecycle(background: true, backgroundWorkEnabled: false);
        final paused = attempts;
        clock.elapse(const Duration(hours: 1));
        expect(attempts, paused);
        session.setLifecycle(background: false);
        clock.flushMicrotasks();
        expect(attempts, paused + 1);
        session.close();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'terminal state stays active until the settlement receipt is durable',
    () async {
      final store = _HeldSettlementStore();
      var completed = false;
      final session = NormalGatewayApplicationSession(
        connection: _connection,
        scope: 'scope',
        pendingStore: store,
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
            },
        resume: ({required localSessionId, required storedSessionId}) async =>
            ResumedGatewaySession(
              runtimeSessionId: 'runtime',
              running: !completed,
            ),
        history: (_) async => [
          {'id': 12, 'role': 'assistant', 'content': 'Final'},
        ],
      );
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'Chat',
      );
      chat.observeHistory([]);
      await chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'Run',
        localContent: 'Run',
      );
      completed = true;
      session.receiveEvent(
        'local',
        StreamEvent(type: 'turn.end', data: const {'status': 'completed'}),
      );
      await store.entered.future;
      expect(session.hasActiveTurn, isTrue);
      expect(
        (await NormalGatewayPendingStore().load('scope')).single.phase,
        'emitted',
      );
      store.release.complete();
      await _flush();
      expect(session.hasActiveTurn, isFalse);
      expect(await store.load('scope'), isEmpty);
      await session.close();
    },
  );

  test('configuration fingerprint invalidates the old normal owner', () async {
    final controller = GatewayTurnApplicationController();
    NormalGatewayApplicationSession get(SavedConnection connection) =>
        controller.normalSessionFor(
          connection,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {},
          history: (_) async => [],
        );
    final old = get(_connection);
    await old.ready;
    final changed = get(_connection.copyWith(gatewayProfile: 'other'));
    expect(identical(old, changed), isFalse);
    expect(() => old.chatFor('x', title: 'X'), throwsStateError);
    await changed.ready;
    final changedHost = get(_connection.copyWith(host: 'other.fixture'));
    expect(identical(changed, changedHost), isFalse);
    await changedHost.ready;
    controller.revokeConnection(_connection.id);
    expect(() => changedHost.chatFor('x', title: 'X'), throwsStateError);
    await controller.close();
  });
}

final _connection = SavedConnection(
  id: 'normal-fixture',
  label: 'Normal',
  host: 'normal.fixture',
  port: 8642,
  apiKey: 'private-key',
);

NormalGatewayPendingMarker _marker(String local, {String phase = 'emitted'}) =>
    NormalGatewayPendingMarker(
      scope: 'scope',
      localSessionId: local,
      storedSessionId: 'stored',
      turnId: 'turn-$local',
      rowFloor: 10,
      phase: phase,
      createdAt: 1,
      updatedAt: 1,
    );

Future<void> _flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _HeldSettlementStore extends NormalGatewayPendingStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> put(NormalGatewayPendingMarker marker) async {
    if (marker.phase == 'settled') {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await super.put(marker);
  }
}

class _Fixture {
  final store = NormalGatewayPendingStore();
  late final NormalGatewayApplicationSession session;
  late NormalGatewayChatOwner owner;
  Completer<void> rpc = Completer<void>();
  Future<void>? flight;
  int submissions = 0;
  int resumes = 0;
  bool emitOnSubmit = true;
  bool? running = true;
  String terminalStatus = 'completed';
  bool historyFails = false;
  bool _unavailableAdmission = false;
  Object? historyError;
  final historyIds = <String>[];
  Completer<List<Map<String, dynamic>>>? historyGate;
  List<Map<String, dynamic>> rows = [
    {'id': 10, 'role': 'assistant', 'content': 'Before'},
  ];
  List<NormalGatewayPendingMarker> atInvocation = [];

  _Fixture() {
    session = NormalGatewayApplicationSession(
      connection: _connection,
      scope: 'scope',
      pendingStore: store,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            atInvocation = await store.load('scope');
            submissions++;
            _unavailableAdmission = false;
            if (emitOnSubmit) onSent();
            return rpc.future;
          },
      resume: ({required localSessionId, required storedSessionId}) async {
        resumes++;
        return ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: running,
          // This fixture's known-success reads include explicit terminal
          // evidence. Stock idle alone is covered separately as unknown.
          status: running == false ? terminalStatus : null,
        );
      },
      history: (id) async {
        historyIds.add(id);
        if (_unavailableAdmission) {
          throw StateError('admission history unavailable');
        }
        if (historyError != null) throw historyError!;
        if (historyFails) throw StateError('history unavailable');
        return historyGate?.future ?? rows;
      },
    );
  }
  NormalGatewayChatOwner chat(String local, {String? stored}) =>
      session.chatFor(local, storedSessionId: stored, title: local);
  Future<void> start({
    bool seedHistory = true,
    bool unavailableAdmission = false,
  }) async {
    _unavailableAdmission = unavailableAdmission;
    await session.ready;
    owner = chat('local', stored: 'stored');
    if (seedHistory) {
      owner.observeHistory([
        {'id': 10, 'role': 'assistant', 'content': 'Before'},
      ]);
    }
    flight = owner.submitPrepared(
      reservation: owner.reserve()!,
      text: 'private prompt',
      localContent: 'private prompt',
    );
    // Observe errors immediately; assertions join the original future later.
    flight!.ignore();
    await _flush();
  }

  void emit(String type, Map<String, dynamic> data, {String? turnId}) =>
      session.receiveEvent(
        'local',
        StreamEvent(type: type, data: data, turnId: turnId),
      );
  // Presentation tests need terminal authority independent of RPC waiting.
  // Real stock ID-less terminals are tested by the wire/epoch suites.
  void finish(String type, Map<String, dynamic> data) {
    final id = 'presentation-$submissions';
    emit('turn.start', {}, turnId: id);
    emit(type, data, turnId: id);
    if (type != 'turn.end') {
      emit('turn.end', {'status': 'completed'}, turnId: id);
    }
  }

  void resetRpc() {
    rpc = Completer<void>();
  }

  Future<void> close() async {
    await session.close();
    if (!rpc.isCompleted) rpc.complete();
    await flight?.catchError((Object _) {});
  }
}
