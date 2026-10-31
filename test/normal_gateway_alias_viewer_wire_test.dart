// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_alias_viewer_wire_test.dart
// Base 4a53e32 blob e505c50f645f0224fe693bbaf2bc48fcb9787dbf; SHA256 0f94dc78acce0aa82e6f6cf5b5f5a63c45e1b102355d7183b27c69a5a3788dd9.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, send, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';

void main() {
  for (final width in [400.0, 1000.0]) {
    testWidgets(
      'already-open real task viewer survives idle alias convergence and parent hydration ($width)',
      (tester) async {
        SharedPreferences.setMockInitialValues({'verbose_mode': true});
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = previous);
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
        final server = (await tester.runAsync(_ViewerServer.start))!;
        final controller = GatewayTurnApplicationController();
        addTearDown(() async {
          await controller.close();
          await server.close();
        });
        final session = controller.normalSessionFor(server.connection);
        var ready = false;
        session.ready.then((_) => ready = true);
        await widgetUntil(tester, () => ready);
        final local = session.chatFor('local', title: 'Original allocation');
        final ensuring = session.client!.ensureSession('local');
        ensuring.ignore();
        var ensured = false;
        ensuring.then((_) => ensured = true);
        await widgetUntil(tester, () => server.createEntered.isCompleted);
        server.rows.addAll([
          for (var id = 1; id <= 40; id++)
            {
              'id': id,
              'role': id.isOdd ? 'user' : 'assistant',
              'content':
                  'Parent history $id. ${List.filled(6, 'Retained context.').join(' ')}',
            },
        ]);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(
              connection: server.connection,
              session: const Session(
                id: 'stored',
                title: 'Canonical parent',
                model: 'fixture',
                source: 'test',
                messageCount: 40,
                isActive: false,
                preview: '',
                startedAt: 1,
              ),
              turnApplicationController: controller,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        final canonical = session.findChat('stored')!;
        await widgetUntil(
          tester,
          () => canonical.snapshot.historyRows.length == 40,
        );
        var resumed = false;
        session.client!.ensureSession('stored').then((_) => resumed = true);
        await widgetUntil(tester, () => resumed);
        server.event('subagent.progress', {
          'subagent_id': 'agent-root',
          'child_session_id': 'child-root',
          'goal': 'Retain original child goal',
          'model': 'fixture',
          'status': 'running',
        });
        await widgetUntil(
          tester,
          () => canonical.snapshot.subagents.length == 1,
        );
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Keep parent draft');
        final card = tester.widget<GatewaySubagentCard>(
          find.byType(GatewaySubagentCard),
        );
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ChatScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        await tester.pump(const Duration(milliseconds: 400));
        scroll.jumpTo(scroll.maxScrollExtent / 2);
        await tester.pump();
        final offset = scroll.pixels;
        card.onOpenTask!(card.activities.single);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await widgetUntil(
          tester,
          () =>
              find.byType(DelegatedTaskTimeline).evaluate().isNotEmpty &&
              server.childReads > 0,
        );
        final viewer = tester.widget<DelegatedTaskTimeline>(
          find.byType(DelegatedTaskTimeline),
        );
        await widgetUntil(tester, () => viewer.controller.hasRead);
        expect(viewer.controller.error, isNull);
        expect(viewer.controller.task.childSessionId, 'child-root');
        expect(
          viewer.controller.rows.single['content'],
          'Recorded child progress',
        );
        expect(
          find.descendant(
            of: find.byType(DelegatedTaskTimeline),
            matching: find.byType(TextField),
          ),
          findsNothing,
        );
        server.releaseCreate();
        await widgetUntil(tester, () => ensured);
        await tester.pump();
        expect(session.chats, hasLength(1));
        expect(
          canonical.snapshot.subagents.single.goal,
          'Retain original child goal',
        );
        expect(viewer.controller.task.goal, 'Retain original child goal');
        expect(scroll.pixels, offset);
        final sending = send(local, 'One parent prompt');
        sending.ignore();
        var sent = false;
        sending.then((_) => sent = true);
        await widgetUntil(tester, () => server.prompts.length == 1);
        expect(controller.activeChatActivities, hasLength(1));
        server.event('message.delta', {
          'text': 'Current parent text',
        }, turnId: 'wire-1');
        server.event('reasoning.delta', {
          'text': 'Exposed current reasoning',
        }, turnId: 'wire-1');
        server.event('tool.start', {
          'tool': 'read_file',
          'tool_id': 'current-tool',
        }, turnId: 'wire-1');
        await widgetUntil(tester, () => local.snapshot.tools.length == 1);
        expect(scroll.pixels, offset);
        server.finish('Current parent final');
        await widgetUntil(tester, () => sent);
        await widgetUntil(
          tester,
          () =>
              !local.snapshot.hasActiveTurn &&
              local.snapshot.historyRows.any(
                (row) => row['content'] == 'Current parent final',
              ),
        );
        // Canonical hydration retains both parent receipts and the child anchor.
        canonical.observeHistory(local.snapshot.historyRows);
        canonical.observeHistory(local.snapshot.historyRows);
        server.childFinal = true;
        server.event('subagent.progress', {
          'subagent_id': 'new-runtime-alias',
          'child_session_id': 'child-root',
          'status': 'completed',
        });
        await widgetUntil(
          tester,
          () =>
              viewer.controller.task.isComplete &&
              viewer.controller.rows.any(
                (r) => r['content'] == 'Recorded child final',
              ),
        );
        canonical.observeHistory(local.snapshot.historyRows);
        expect(
          local.snapshot.subagents.single.goal,
          'Retain original child goal',
        );
        expect(viewer.controller.task.childSessionId, 'child-root');
        expect(viewer.controller.task.goal, 'Retain original child goal');
        expect(viewer.controller.task.succeeded, isTrue);
        expect(scroll.pixels, offset);
        expect(server.prompts, hasLength(1));
        expect(
          server.childRequests.every((request) => request.method == 'GET'),
          isTrue,
        );
        expect(
          server.childRequests
              .where((r) => r.uri.path.endsWith('/messages'))
              .every(
                (request) =>
                    request.uri.queryParameters['include_compacted'] == 'true',
              ),
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(find.byType(TextField, skipOffstage: false))
              .controller!
              .text,
          'Keep parent draft',
        );
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(DelegatedTaskTimeline), findsNothing);
        expect(scroll.pixels, offset);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Keep parent draft',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await controller.close();
        await tester.runAsync(server.close);
        await tester.pump(const Duration(seconds: 16));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _ViewerServer extends BindingServer {
  _ViewerServer(super.server);
  bool childFinal = false;
  int childReads = 0;
  final childRequests = <HttpRequest>[];
  static Future<_ViewerServer> start() async {
    final fixture = _ViewerServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen(fixture.handle);
    return fixture;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (!request.uri.path.startsWith('/api/sessions/child-root')) {
      return super.handle(request);
    }
    childRequests.add(request);
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path.endsWith('/messages')) {
      childReads++;
      request.response.write(
        jsonEncode({
          'session_id': 'child-root',
          'messages': [
            {
              'id': 1,
              'role': 'assistant',
              'content': childFinal
                  ? 'Recorded child final'
                  : 'Recorded child progress',
            },
          ],
          'pagination': {
            'limit': 50,
            'offset': 0,
            'order': 'latest',
            'returned': 1,
          },
        }),
      );
    } else {
      request.response.write(
        jsonEncode({'id': 'child-root', 'source': 'subagent'}),
      );
    }
    await request.response.close();
  }
}
