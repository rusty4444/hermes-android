import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/services/chat_history_window.dart';

// Independent adverse review: production and existing assertions unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'review: every raw receipt row, exact type, order and own final required',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      call.emit('message.delta', {'text': 'Received answer'});
      call.emit('tool.start', {'tool_id': 'middle-tool', 'name': 'terminal'});
      call.emit('tool.complete', {
        'tool_id': 'middle-tool',
        'name': 'terminal',
        'result': 'Passed',
      });
      call.emit('message.complete', {
        'text': 'Received answer',
        'persisted_turn': {
          'row_ids': [12, 13, 14, 15],
          'complete': true,
          'user_row_id': 12,
          'user_row_ids': [12],
          'final_assistant_row_id': 15,
        },
      });
      call.emit('turn.end', {'status': 'completed'});
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      final full = <Map<String, dynamic>>[
        _row(12, 'user', 'Current question'),
        _row(
          13,
          'assistant',
          'Working',
          extra: {
            'tool_calls': [
              {
                'id': 'middle-tool',
                'function': {'name': 'terminal', 'arguments': '{}'},
              },
            ],
          },
        ),
        _row(14, 'tool', 'Passed', extra: {'tool_call_id': 'middle-tool'}),
        _row(
          15,
          'assistant',
          'Canonical answer',
          extra: {'status': 'completed'},
        ),
      ];
      for (final incomplete in <List<Map<String, dynamic>>>[
        [full[0], full[1], full[3]],
        [full[0], full[2], full[3]],
        [full[0], full[1], full[2], full[2], full[3]],
        [full[0], full[2], full[1], full[3]],
        [
          full[0],
          full[1],
          {...full[2], 'id': '14'},
          full[3],
        ],
        [
          full[0],
          full[1],
          {...full[2], 'id': 14.0},
          full[3],
        ],
        [
          full[0],
          {...full[1], 'role': 'user'},
          full[2],
          full[3],
        ],
        [
          full[0],
          full[1],
          full[2],
          {...full[3], 'partial': true},
        ],
        [
          full[0],
          full[1],
          full[2],
          {...full[3], 'display_content': ''},
        ],
      ]) {
        expect(chat.observeHistory([..._previous, ...incomplete]), isTrue);
        expect(
          chat.snapshot.displayRows.map((r) => r['content']),
          contains('Received answer'),
        );
        expect(chat.snapshot.tools, hasLength(1));
      }
      expect(chat.observeHistory([..._previous, ...full]), isTrue);
      expect(chat.snapshot.displayRows, isEmpty);
      expect(chat.snapshot.tools, isEmpty);
      expect(chat.snapshot.timeline.runs, isEmpty);
      expect(_quiet(chat.snapshot), [
        'Older question',
        'Older confirmed answer',
        'Current question',
        'Canonical answer',
      ]);
    },
  );

  test(
    'review: source cleanup preserves one canonical asset and independent child observer',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Generate image');
      const result = {
        'success': true,
        'image': '/fixture/generated.png',
        'host_image': '/fixture/generated.png',
      };
      call.emit('reasoning.delta', {'text': 'Private reasoning'});
      call.emit('message.delta', {'text': 'Working'});
      call.emit('message.interim', {
        'text': 'Working',
        'already_streamed': true,
      });
      call.emit('tool.start', {
        'tool_id': 'image-1',
        'name': 'image_generate',
        'args': {'prompt': 'square'},
      });
      call.emit('tool.complete', {
        'tool_id': 'image-1',
        'name': 'image_generate',
        'args': {'prompt': 'square'},
        'result': result,
      });
      call.emit('subagent.start', {
        'subagent_id': 'child-1',
        'child_session_id': 'child-chat',
        'goal': 'Independent child',
      });
      call.emit('message.complete', {
        'text': 'Done.',
        'persisted_turn': {
          'row_ids': [12, 13, 14, 15],
          'complete': true,
          'user_row_id': 12,
          'user_row_ids': [12],
          'final_assistant_row_id': 15,
        },
      });
      call.emit('turn.end', {'status': 'completed'});
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.snapshot.tools, hasLength(1));
      expect(chat.snapshot.timeline.runs, isNotEmpty);
      final canonical = <Map<String, dynamic>>[
        ..._previous,
        _row(12, 'user', 'Generate image'),
        _row(
          13,
          'assistant',
          'Working',
          extra: {
            'reasoning': 'Private reasoning',
            'tool_calls': [
              {
                'id': 'image-1',
                'function': {
                  'name': 'image_generate',
                  'arguments': '{"prompt":"square"}',
                },
              },
            ],
          },
        ),
        _row(
          14,
          'tool',
          jsonEncode(result),
          extra: {'tool_call_id': 'image-1'},
        ),
        _row(15, 'assistant', 'Done.', extra: {'finish_reason': 'stop'}),
      ];
      expect(chat.observeHistory(canonical), isTrue);
      expect(chat.snapshot.displayRows, isEmpty);
      expect(chat.snapshot.timeline.runs, isEmpty);
      expect(chat.snapshot.timeline.scopes, isEmpty);
      expect(chat.snapshot.tools, isEmpty);
      expect(chat.snapshot.receivedOutcomes, isEmpty);
      final sections = buildNormalChatDisplaySections(
        canonicalRows: chat.snapshot.historyRows,
        receivedRows: chat.snapshot.displayRows,
        receivedTimeline: chat.snapshot.timeline,
        receivedTools: chat.snapshot.tools,
        subagentActivities: chat.snapshot.subagents,
        conversationOnly: true,
      );
      expect(
        sections.expand((s) => s.items).whereType<ChatAttachmentItem>(),
        hasLength(1),
      );
      expect(
        sections.where((s) => s.source == ChatDisplaySource.received),
        isEmpty,
      );
      expect(_quiet(chat.snapshot), [
        'Older question',
        'Older confirmed answer',
        'Generate image',
        'Done.',
      ]);
      f.session.receiveEvent(
        'stored',
        StreamEvent(
          type: 'subagent.complete',
          data: {
            'subagent_id': 'child-1',
            'status': 'completed',
            'summary': 'Child finished',
          },
        ),
      );
      expect(chat.snapshot.subagents.single.isComplete, isTrue);
      expect(chat.observeHistory(canonical), isTrue);
      expect(chat.snapshot.subagents.single.isComplete, isTrue);
      expect(chat.snapshot.subagents.single.detail, 'Child finished');
      expect(chat.snapshot.displayRows, isEmpty);
      expect(f.calls, hasLength(1));
    },
  );

  test(
    'review: receipt context is bounded on initialized window and manual retry',
    () async {
      final window = ChatHistoryWindow();
      window.acceptRecent(ChatHistoryPageBatch(_previous, 2, false));
      final all = <Map<String, dynamic>>[
        _row(12, 'user', 'Long prompt'),
        for (var id = 13; id < 813; id++) _row(id, 'tool', 'Result $id'),
        _row(813, 'assistant', 'Long final', extra: {'status': 'completed'}),
      ];
      for (var attempt = 0; attempt < 2; attempt++) {
        final offsets = <int>[];
        final batch = await window.fetchRecent((offset) async {
          offsets.add(offset);
          final end = (all.length - offset).clamp(0, all.length);
          return all.sublist((end - 50).clamp(0, end), end);
        }, needsContext: (_) => true);
        expect(offsets, [for (var n = 0; n < 12; n++) n * 50]);
        expect(batch.rows, hasLength(600));
        expect(batch.rawCount, 600);
        expect(batch.hasOlder, isTrue);
        expect(batch.rows.any((r) => r['id'] == 12), isFalse);
        window.acceptRecent(batch);
      }
      expect(
        window.rows.map((r) => r['id']).toSet().length,
        window.rows.length,
      );
    },
  );

  test(
    'review: context page error retains usable latest and retries same offset',
    () async {
      final all = [
        for (var id = 1; id <= 120; id++) _row(id, 'tool', 'Result $id'),
      ];
      final window = ChatHistoryWindow();
      window.acceptRecent(ChatHistoryPageBatch(_previous, 2, false));
      final offsets = <int>[];
      var reject = true;
      Future<List<Map<String, dynamic>>> fetch(int offset) async {
        offsets.add(offset);
        if (offset > 0 && reject) throw StateError('older page unavailable');
        final end = (all.length - offset).clamp(0, all.length);
        return all.sublist((end - 50).clamp(0, end), end);
      }

      final failed = await window.fetchRecent(fetch, needsContext: (_) => true);
      expect(offsets, [0, 50]);
      expect(failed.rows, hasLength(50));
      expect(failed.hasOlder, isTrue);
      window.acceptRecent(failed);
      reject = false;
      offsets.clear();
      final retried = await window.fetchRecent(
        fetch,
        needsContext: (_) => true,
      );
      expect(offsets, [0, 50, 100]);
      expect(retried.rows, all);
    },
  );
}

Map<String, dynamic> _row(
  int id,
  String role,
  String content, {
  Map<String, dynamic> extra = const {},
}) => {'id': id, 'role': role, 'content': content, ...extra};

final _previous = [
  _row(10, 'user', 'Older question'),
  _row(
    11,
    'assistant',
    'Older confirmed answer',
    extra: {'status': 'completed'},
  ),
];

List<String> _present(
  NormalGatewayChatSnapshot snapshot, {
  required bool quiet,
}) => [
  for (final section in buildNormalChatDisplaySections(
    canonicalRows: snapshot.historyRows,
    receivedRows: snapshot.displayRows,
    receivedTimeline: snapshot.timeline,
    receivedTools: snapshot.tools,
    receivedOutcomes: snapshot.receivedOutcomes,
    conversationOnly: quiet,
    verbose: !quiet,
  ))
    for (final row in section.items.whereType<Map<String, dynamic>>())
      row['_display_content'] as String,
];

List<String> _quiet(NormalGatewayChatSnapshot snapshot) =>
    _present(snapshot, quiet: true);

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    predicate(),
    isTrue,
    reason: 'bounded owner transition did not arrive',
  );
}

class _Fixture {
  static const scope = 'strict-response-presentation';
  final NormalGatewayPendingStore pendingStore;
  late final NormalGatewayApplicationSession session;
  List<Map<String, dynamic>> rows;
  bool historyFails = false;
  int historyReads = 0;
  ResumedGatewaySession resumeResult = const ResumedGatewaySession(
    runtimeSessionId: 'runtime',
    running: true,
  );
  Future<ResumedGatewaySession> Function()? resumeHook;
  Future<List<Map<String, dynamic>>> Function()? historyHook;
  final calls = <_Call>[];
  final flights = <Future<void>>[];
  bool _closed = false;

  _Fixture({
    NormalGatewayPendingStore? pendingStore,
    List<Map<String, dynamic>>? rows,
  }) : pendingStore = pendingStore ?? NormalGatewayPendingStore(),
       rows = rows ?? List.of(_previous) {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'strict-response',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'review-fixture',
      ),
      scope: scope,
      pendingStore: this.pendingStore,
      history: readHistory,
      resume: ({required localSessionId, required storedSessionId}) async {
        final hook = resumeHook;
        return hook == null ? resumeResult : await hook();
      },
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            // The constructor's submit hook uses global application ingress;
            // its per-submit callback is intentionally inert in production.
            final call = _Call(
              'wire-${calls.length + 1}',
              (event) => session.receiveEvent(sessionId, event),
            );
            calls.add(call);
            onSent();
            return call.rpc.future;
          },
    );
  }

  Future<List<Map<String, dynamic>>> readHistory(String id) async {
    historyReads++;
    final hook = historyHook;
    if (hook != null) return hook();
    if (historyFails) throw StateError('history is unavailable');
    return rows;
  }

  Future<NormalGatewayChatOwner> open({bool seedHistory = true}) async {
    await session.ready;
    final chat = session.chatFor(
      'local',
      storedSessionId: 'stored',
      title: 'Fixture',
    );
    if (seedHistory) expect(chat.observeHistory(rows), isTrue);
    return chat;
  }

  Future<_Call> begin(
    NormalGatewayChatOwner chat,
    String prompt, {
    Object? reservation,
  }) async {
    await session.ready;
    final before = calls.length;
    final admission = reservation ?? chat.reserve();
    expect(admission, isNotNull);
    final flight = chat.submitPrepared(
      reservation: admission!,
      text: prompt,
      localContent: prompt,
    );
    flights.add(flight);
    flight.ignore();
    await _until(() => calls.length > before);
    final call = calls.last;
    call.emit('message.start', {});
    expect(chat.snapshot.wireEmitted, isTrue);
    return call;
  }

  Future<void> complete(
    NormalGatewayChatOwner chat,
    _Call call,
    String text,
  ) async {
    call.emit('message.complete', {'text': text});
    call.emit('turn.end', {'status': 'completed'});
    call.ack();
    await _until(() => !chat.snapshot.hasActiveTurn);
    expect(chat.snapshot.phase, NormalGatewayTurnPhase.completed);
    await pumpEventQueue();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await session.close();
    for (final call in calls) {
      call.ack();
    }
    for (final flight in flights) {
      await flight.catchError((Object _) {});
    }
  }
}

class _Call {
  _Call(this.turn, this.onEvent);
  final String turn;
  final StreamCallback onEvent;
  final rpc = Completer<void>();

  void emit(String type, Map<String, dynamic> data) =>
      onEvent(StreamEvent(type: type, turnId: turn, data: data));

  void ack() {
    if (!rpc.isCompleted) rpc.complete();
  }
}
