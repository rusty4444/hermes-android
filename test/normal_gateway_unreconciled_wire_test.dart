import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/utils/chat_history_scroll.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, send, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previous);

  for (final missing in ['response', 'user', 'both', 'tool-only']) {
    for (final laterAtSettlement in [false, true]) {
      test(
        'POLICY actual wire missing=$missing later=$laterAtSettlement',
        () async {
          final wire = await BindingServer.start();
          final session = NormalGatewayApplicationSession.fromConnection(
            wire.connection,
            scope: 'wire-policy',
          );
          final api = ApiClient(
            baseUrl: wire.connection.baseUrl,
            apiKey: wire.connection.apiKey,
          );
          Future<void>? original;
          try {
            await session.ready;
            final source = session.chatFor('local', title: 'Original');
            original = send(source, 'Same prompt')..ignore();
            await wire.createEntered.future;
            wire.rows.add({'id': 37, 'role': 'assistant', 'content': 'Old'});
            final donor = session.chatFor(
              'stored',
              storedSessionId: 'stored',
              title: 'Donor',
            );
            final baseline = donor.beginHistoryRead('stored');
            donor.observeHistory(
              await api.getMessages('stored', latest: true),
              read: baseline,
            );
            send(donor, 'Same prompt').ignore();
            await wire.untilPrompts(1);
            wire.event('reasoning.delta', {
              'text': 'Donor reasoning',
            }, turnId: 'wire-1');
            wire.event('tool.start', {
              'tool': 'read_file',
              'tool_id': 'donor-tool',
            }, turnId: 'wire-1');
            if (missing != 'tool-only') {
              wire.event('message.delta', {
                'text': 'Same body',
              }, turnId: 'wire-1');
            }
            await until(() => donor.snapshot.tools.isNotEmpty);
            wire.running = false;
            wire.event('turn.error', {
              'error': 'Interrupted',
            }, turnId: 'wire-1');
            await until(() => !donor.snapshot.hasActiveTurn);
            final donorRuns = donor.snapshot.timeline.runs
                .map((r) => r.id)
                .toList();
            wire.releaseCreate();
            await wire.untilPrompts(2);
            final receipt = (await session.pendingStore.load(
              'wire-policy',
            )).single;
            expect(receipt.rowFloor, 37);
            wire.event('reasoning.delta', {
              'text': 'Current reasoning',
            }, turnId: 'wire-2');
            wire.event('message.delta', {
              'text': 'Same body',
            }, turnId: 'wire-2');
            await until(
              () => source.snapshot.displayRows.last['content'] == 'Same body',
            );
            final currentScope =
                source.snapshot.displayRows.last['_normal_projection_id'];
            final canonical = <Map<String, dynamic>>[
              {'id': 37, 'role': 'assistant', 'content': 'Old'},
              {'id': 70, 'role': 'assistant', 'content': 'Unrelated before'},
              if (missing != 'user' && missing != 'both')
                {'id': 98, 'role': 'user', 'content': 'Same prompt'},
              if (missing != 'response' && missing != 'both')
                {'id': 99, 'role': 'assistant', 'content': 'Same body'},
              {'id': 100, 'role': 'user', 'content': 'Same prompt'},
              {'id': 101, 'role': 'assistant', 'content': 'Same body'},
            ];
            final later = <Map<String, dynamic>>[
              {'id': 102, 'role': 'user', 'content': 'Unrelated after'},
              {'id': 103, 'role': 'assistant', 'content': 'Later answer'},
            ];
            wire.rows
              ..clear()
              ..addAll([...canonical, if (laterAtSettlement) ...later]);
            wire.running = false;
            wire.event('message.complete', {
              'text': 'Same body',
            }, turnId: 'wire-2');
            wire.event('turn.end', {}, turnId: 'wire-2');
            await original;
            await until(
              () =>
                  !source.snapshot.hasActiveTurn &&
                  source.snapshot.historyRows.length == wire.rows.length,
            );
            if (!laterAtSettlement) {
              wire.rows.addAll(later);
              final read = source.beginHistoryRead('stored');
              source.observeHistory(
                await api.getMessages('stored', latest: true),
                read: read,
              );
            }
            final snapshot = source.snapshot;
            expect(snapshot.historyRows, [...canonical, ...later]);
            expect(
              snapshot.displayRows.where((r) => r['role'] == 'user'),
              hasLength(2),
            );
            expect(
              snapshot.displayRows.where((r) => r['content'] == 'Same body'),
              hasLength(missing == 'tool-only' ? 1 : 2),
            );
            expect(
              snapshot.timeline.runs.map((r) => r.id),
              containsAll(donorRuns),
            );
            expect(
              snapshot.timeline.forScope(currentScope).map((r) => r.text),
              ['Current reasoning', 'Same body'],
            );
            final sections = buildNormalChatDisplaySections(
              canonicalRows: snapshot.historyRows,
              receivedRows: snapshot.displayRows,
              receivedTools: snapshot.tools,
              receivedTimeline: snapshot.timeline,
            );
            expect(sections.map((s) => s.source), [
              ChatDisplaySource.canonical,
              ChatDisplaySource.received,
            ]);
            expect(
              sections.first.items.whereType<Map<String, dynamic>>().map(
                (r) => r['id'],
              ),
              snapshot.historyRows.map((r) => r['id']),
            );
            expect(
              sections.last.items.whereType<Map<String, dynamic>>().where(
                (r) => r['_display_content'] == 'Same body',
              ),
              hasLength(missing == 'tool-only' ? 1 : 2),
            );
            expect(wire.prompts, [
              {
                'session_id': 'runtime',
                'text': AndroidPromptContext.forModel('Same prompt'),
                'title_preview': 'Same prompt',
              },
              {
                'session_id': 'runtime',
                'text': AndroidPromptContext.forModel('Same prompt'),
                'title_preview': 'Same prompt',
              },
            ]);
            expect(buildRestChatHistory(snapshot.historyRows), isNotEmpty);
            expect(
              snapshot.historyRows.any(
                (r) => r.keys.any((key) => key.startsWith('_normal')),
              ),
              isFalse,
            );
            expect(await session.pendingStore.load('wire-policy'), isEmpty);
            expect(snapshot.rowFloor, receipt.rowFloor);
          } finally {
            await session.close();
            api.close();
            await wire.close();
            if (original != null) await original;
          }
        },
      );
    }
  }
}
