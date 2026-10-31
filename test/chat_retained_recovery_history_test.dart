import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/chat_end_affordance.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

const _retainedButton = Key('chat-retained-received-output');
const _retainedClose = Key('chat-retained-received-close');
const _oldReply = 'Earlier received reply, lifecycle unconfirmed';
const _latestReply = 'Newest saved reply';

void main() {
  setUp(mockChatImageRecovery);
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': true}));

  for (final verbose in [true, false]) {
    testWidgets(
      'fresh saved history is latest; old unknown output stays inspectable (verbose=$verbose)',
      (tester) async {
        SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = _Fixture();
        final gate = Completer<void>();
        f.gate = gate;
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await f.controller.close();
        });
        await f.seedUnknown(tester);
        await tester.pumpWidget(f.widget());
        await pumpChatUpdates(tester);
        expect(
          find.byKey(_retainedButton),
          findsNothing,
          reason: 'Pending history does not hide received output',
        );
        expect(f.owner.snapshot.historyRows, isEmpty);
        gate.complete();
        await pumpChatUpdates(tester);
        expect(f.owner.snapshot.historyRows.last['id'], 22);
        expect(tester.takeException(), isNull);
        expect(
          _bubble(_latestReply).hitTestable(),
          findsOneWidget,
          reason: 'Latest must be the newer saved reply, not the received tail',
        );
        expect(find.byKey(_retainedButton), findsOneWidget);
        expect(
          f.owner.snapshot.displayRows.any(
            (row) => row['content'] == _oldReply,
          ),
          isTrue,
        );
        final position = _chatPosition(tester);
        final pixels = position.pixels;
        await tester.tap(find.byKey(_retainedButton));
        await pumpChatUpdates(tester);
        expect(_bubble(_oldReply), verbose ? findsOneWidget : findsNothing);
        for (final bubble in tester.widgetList<MessageBubble>(
          find.descendant(
            of: find.byKey(const Key('retained-recovery-inspector')),
            matching: find.byType(MessageBubble),
          ),
        )) {
          expect(bubble.onEdit, isNull);
          expect(bubble.onRetry, isNull);
        }
        expect(f.submissions, 1, reason: 'Inspecting recovery never resends');
        await tester.tap(find.byKey(_retainedClose));
        await pumpChatUpdates(tester);
        expect(_chatPosition(tester), same(position));
        expect(position.pixels, pixels);
        expect(_bubble(_latestReply).hitTestable(), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await f.controller.close();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'later live prompt, work and reply remain inline after retained recovery',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _Fixture();
      addTearDown(f.controller.close);
      await f.seedUnknown(tester);
      final saved = f.rows;
      await tester.pumpWidget(f.widget());
      await pumpChatUpdates(tester);
      expect(_bubble(_latestReply).hitTestable(), findsOneWidget);
      f.holdSubmit = Completer<void>();
      f.running = true;
      await tester.enterText(find.byType(TextField), 'Current live prompt');
      await tester.tap(find.byKey(const Key('chat-send-message')));
      await pumpChatUpdates(tester);
      expect(f.submissions, 2);
      expect(_bubble('Current live prompt').hitTestable(), findsOneWidget);
      f.emit('message.start', const {});
      f.emit('message.delta', {'text': 'Current live reply'});
      f.emit('tool.start', {'tool_id': 'new-tool', 'name': 'terminal'});
      await pumpChatUpdates(tester);
      expect(_bubble('Current live reply'), findsOneWidget);
      expect(find.byKey(_retainedButton), findsOneWidget);
      f.emit('tool.complete', {'tool_id': 'new-tool', 'name': 'terminal'});
      f.emit('message.complete', {'text': 'Current live reply'});
      f.emit('turn.end', {'status': 'completed'});
      f.holdSubmit!.complete();
      await pumpChatUpdates(tester);
      expect(f.owner.snapshot.hasActiveTurn, isFalse);
      expect(_bubble('Current live reply').hitTestable(), findsOneWidget);
      expect(
        f.owner.snapshot.displayRows.any((row) => row['content'] == _oldReply),
        isTrue,
      );
      final before = f.historyReads;
      f.failReads = false;
      f.rows = saved;
      await _refresh(tester);
      expect(f.historyReads, greaterThan(before));
      expect(find.byKey(_retainedButton), findsOneWidget);
      expect(
        _bubble('Current live reply').hitTestable(),
        findsOneWidget,
        reason: 'A stale saved page cannot hide a newer successful receipt',
      );
      expect(f.submissions, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await f.controller.close();
      await tester.pump();
    },
  );

  testWidgets(
    'recovery inspector tool and reasoning expansion never share scroll storage',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _Fixture();
      addTearDown(f.controller.close);
      await f.seedUnknown(tester, withWork: true);
      await tester.pumpWidget(f.widget());
      await pumpChatUpdates(tester);
      await tester.tap(find.byKey(_retainedButton));
      await pumpChatUpdates(tester);
      for (final card in [
        find.byType(GatewayReasoningCard),
        find.byType(GatewayActivityCard),
      ]) {
        await tester.scrollUntilVisible(
          card,
          100,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(card, findsOneWidget);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        final tile = find.descendant(
          of: card,
          matching: find.byType(ExpansionTile),
        );
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.widget<ExpansionTile>(tile).controller!.isExpanded,
          isTrue,
        );
      }
      final list = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListView),
      );
      for (var i = 0; i < 5; i++) {
        await tester.drag(list, const Offset(0, -650));
        await tester.pumpAndSettle();
      }
      tester.widget<ListView>(list).controller!.jumpTo(0);
      await pumpChatUpdates(tester);
      expect(tester.takeException(), isNull);
      for (final type in [GatewayReasoningCard, GatewayActivityCard]) {
        final card = find.byType(type);
        await tester.scrollUntilVisible(
          card,
          100,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final tile = tester.widget<ExpansionTile>(
          find.descendant(of: card, matching: find.byType(ExpansionTile)),
        );
        expect(
          tile.controller!.isExpanded,
          isTrue,
          reason: 'Inspector visit pins survive lazy eviction',
        );
      }
      await tester.tap(find.byKey(_retainedClose));
      await pumpChatUpdates(tester);
      expect(_bubble(_latestReply).hitTestable(), findsOneWidget);
      expect(f.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await f.controller.close();
      await tester.pump();
    },
  );

  for (final failed in [true, false]) {
    testWidgets(
      '${failed ? 'failed' : 'empty'} initial latest read cannot hide received recovery',
      (tester) async {
        final f = _Fixture();
        addTearDown(f.controller.close);
        await f.seedUnknown(tester);
        final saved = f.rows;
        if (failed) {
          f.failReads = true;
        } else {
          f.rows = [];
        }
        await tester.pumpWidget(f.widget());
        await pumpChatUpdates(tester);
        expect(find.byKey(_retainedButton), findsNothing);
        expect(_bubble(_oldReply), findsOneWidget);
        expect(
          f.owner.snapshot.displayRows.any(
            (row) => row['content'] == _oldReply,
          ),
          isTrue,
        );
        final before = f.historyReads;
        f.failReads = false;
        f.rows = saved;
        await _refresh(tester);
        expect(f.historyReads, greaterThan(before));
        expect(find.byKey(_retainedButton), findsOneWidget);
        expect(_bubble(_latestReply).hitTestable(), findsOneWidget);
        expect(f.submissions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await f.controller.close();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'held opening read preserves a reader gesture; Latest explicitly selects saved history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _Fixture();
      final gate = Completer<void>();
      f.gate = gate;
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await f.controller.close();
      });
      await f.seedUnknown(tester, longRecovery: true);
      await tester.pumpWidget(f.widget());
      await pumpChatUpdates(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 250));
      await tester.pumpAndSettle();
      gate.complete();
      await pumpChatUpdates(tester);
      expect(f.owner.snapshot.historyRows.last['id'], 22);
      expect(
        find.byKey(_retainedButton),
        findsNothing,
        reason: 'Late history must not override a newer reader gesture',
      );
      expect(
        find.byKey(ChatEndAffordance.buttonKey).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ChatEndAffordance.buttonKey));
      await pumpChatUpdates(tester);
      expect(find.byKey(_retainedButton), findsOneWidget);
      expect(_bubble(_latestReply).hitTestable(), findsOneWidget);
      expect(f.submissions, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await f.controller.close();
      await tester.pump();
    },
  );

  testWidgets(
    'actual Navigator pop and reopen keep latest saved and retained unknown output',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.controller.close);
      await f.seedUnknown(tester);
      await tester.pumpWidget(
        f.widget(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open-fixture'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => f.screen())),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      for (var visit = 0; visit < 2; visit++) {
        final before = f.historyReads;
        await tester.tap(find.byKey(const Key('open-fixture')));
        await pumpChatUpdates(tester);
        expect(f.historyReads, greaterThan(before));
        expect(_bubble(_latestReply).hitTestable(), findsOneWidget);
        expect(find.byKey(_retainedButton), findsOneWidget);
        await tester.tap(find.byKey(_retainedButton));
        await pumpChatUpdates(tester);
        expect(_bubble(_oldReply), findsOneWidget);
        await tester.tap(find.byKey(_retainedClose));
        await pumpChatUpdates(tester);
        await tester.pageBack();
        await pumpChatUpdates(tester);
        expect(find.byType(ChatScreen), findsNothing);
      }
      expect(f.submissions, 1);
      expect(
        f.owner.snapshot.displayRows.any((row) => row['content'] == _oldReply),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await f.controller.close();
      await tester.pump();
    },
  );
}

Future<void> _refresh(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  final item = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == 'refresh',
  );
  expect(item.hitTestable(), findsOneWidget);
  await tester.tap(item);
  await pumpChatUpdates(tester);
}

Finder _bubble(String text) => find.byWidgetPredicate(
  (widget) => widget is MessageBubble && widget.content == text,
);

ScrollPosition _chatPosition(WidgetTester tester) => tester
    .widget<ListView>(
      find
          .descendant(
            of: find.byType(ChatScreen),
            matching: find.byType(ListView),
          )
          .first,
    )
    .controller!
    .position;

class _Fixture {
  final controller = GatewayTurnApplicationController();
  final connection = SavedConnection(
    id: 'recovery-history-fixture',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture',
  );
  bool running = true;
  bool failReads = false;
  int submissions = 0;
  int historyReads = 0;
  Completer<void>? gate;
  Completer<void>? holdSubmit;
  StreamCallback? callback;
  List<Map<String, dynamic>> rows = [
    {'id': 20, 'role': 'user', 'content': 'Newer saved question'},
    {
      'id': 21,
      'role': 'assistant',
      'content': List.filled(30, 'Saved context.\n\n').join(),
      'finish_reason': 'stop',
    },
    {
      'id': 22,
      'role': 'assistant',
      'content': _latestReply,
      'finish_reason': 'stop',
    },
  ];
  late final app = controller.normalSessionFor(
    connection,
    submit: submit,
    resume: resume,
    history: (_) async => <Map<String, dynamic>>[],
  );
  late final owner = app.chatFor(
    'stored',
    storedSessionId: 'stored',
    title: 'Fixture',
  );
  late final api = ApiClient(
    baseUrl: 'http://fixture.invalid',
    apiKey: 'fixture',
    httpClient: MockClient((request) async {
      if (!request.url.path.endsWith('/messages')) {
        return http.Response(
          '{}',
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      historyReads++;
      await gate?.future;
      return http.Response(
        jsonEncode(failReads ? {} : {'data': rows}),
        failReads ? 503 : 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  Future<ResumedGatewaySession> resume({
    required String localSessionId,
    required String storedSessionId,
  }) async =>
      ResumedGatewaySession(runtimeSessionId: 'runtime', running: running);

  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) async {
    submissions++;
    callback = onEvent;
    onSent();
    if (holdSubmit != null) await holdSubmit!.future;
  }

  void emit(String type, Map<String, dynamic> data) => app.receiveEvent(
    'stored',
    StreamEvent(type: type, data: data, turnId: 'wire-$submissions'),
  );

  Future<void> seedUnknown(
    WidgetTester tester, {
    bool longRecovery = false,
    bool withWork = false,
  }) async {
    await app.ready;
    owner.observeHistory([]);
    await owner.submitPrepared(
      reservation: owner.reserve()!,
      text: 'Older prompt',
      localContent: longRecovery
          ? List.filled(30, 'Older prompt\n\n').join()
          : 'Older prompt',
    );
    emit('message.delta', {'text': _oldReply});
    if (withWork) {
      emit('reasoning.delta', {'text': 'Earlier reasoning'});
      emit('tool.start', {'tool_id': 'earlier-tool', 'name': 'terminal'});
      emit('tool.complete', {
        'tool_id': 'earlier-tool',
        'name': 'terminal',
        'output': 'Earlier result',
      });
      emit('message.delta', {
        'text': List.filled(
          50,
          '\n\nEarlier trailing context after work.',
        ).join(),
      });
    }
    running = false;
    app.receiveEvent(
      'stored',
      StreamEvent(type: 'message.complete', data: const {'status': 'unknown'}),
    );
    owner.requestRecovery();
    for (
      var attempt = 0;
      attempt < 50 && owner.snapshot.hasActiveTurn;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(owner.snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);
  }

  Widget widget({Widget? home}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home ?? screen(),
  );

  ChatScreen screen() => ChatScreen(
    connection: connection,
    session: const Session(
      id: 'stored',
      title: 'Fixture',
      model: 'fixture',
      source: 'matrix',
      messageCount: 500,
      isActive: true,
      preview: '',
      startedAt: 1,
    ),
    turnApplicationController: controller,
    testApiClient: api,
    testRemotePromptSubmit: submit,
    testNormalResume: resume,
    testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
  );
}
