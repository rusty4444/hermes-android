import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing storage seam; fail the real pending-marker persistence path.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fake_voice_composer_adapter.dart';

const _composer = Key('chat-message-composer');
const _send = Key('chat-send-message');
const _stop = Key('chat-stop-response');
final _connection = SavedConnection(
  id: 'mid-turn',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture-key',
);
const _session = Session(
  id: 'stored-chat',
  title: 'Chat',
  model: 'fixture',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

String _text(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composer)).controller!.text;
IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

Future<void> _pumpChat(
  WidgetTester tester, {
  _Remote? remote,
  GatewayTurnApplicationController? controller,
  http.Client? httpClient,
  double textScale = 1,
  String? initialText,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ChatScreen(
        connection: _connection,
        session: _session,
        initialComposerText: initialText,
        turnApplicationController: controller,
        testRemotePromptSubmit: remote?.submit,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testApiClient: ApiClient(
          baseUrl: 'http://fixture.invalid',
          apiKey: 'fixture-key',
          httpClient:
              httpClient ??
              MockClient((_) async => http.Response('{"data":[]}', 200)),
        ),
      ),
    ),
  );
  await _pump(tester);
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<void> _start(WidgetTester tester) async {
  await tester.enterText(find.byKey(_composer), 'Original task');
  await tester.tap(find.byKey(_send));
  await _pump(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        );
  });

  Future<
    ({
      GatewayTurnApplicationController controller,
      _Remote remote,
      NormalGatewayChatOwner chat,
    })
  >
  prepare(
    WidgetTester tester, {
    double textScale = 1,
    bool emit = true,
    NormalGatewayResume? resume,
  }) async {
    final remote = _Remote(emit: emit);
    final controller = GatewayTurnApplicationController();
    final session = controller.normalSessionFor(
      _connection,
      submit: remote.submit,
      steer: remote.steer,
      resume: resume,
      history: (_) async => [],
    );
    addTearDown(() async {
      await controller.close();
      if (!remote.turn.isCompleted) remote.turn.complete();
    });
    await _pumpChat(
      tester,
      controller: controller,
      remote: remote,
      textScale: textScale,
    );
    final chat = session.findChat(_session.id)!;
    return (controller: controller, remote: remote, chat: chat);
  }

  testWidgets(
    'terminal receipt keeps guidance when settlement storage fails before ACK',
    (tester) async {
      final previousPreferences = SharedPreferencesStorePlatform.instance;
      final storage = _PendingWriteFault();
      SharedPreferencesStorePlatform.instance = storage;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousPreferences,
      );
      final recoveryEntered = Completer<void>();
      final recovery = Completer<ResumedGatewaySession>();
      addTearDown(() {
        if (!recovery.isCompleted) {
          recovery.complete(
            const ResumedGatewaySession(
              runtimeSessionId: 'runtime',
              running: false,
            ),
          );
        }
      });
      final f = await prepare(
        tester,
        resume: ({required localSessionId, required storedSessionId}) {
          if (!recoveryEntered.isCompleted) recoveryEntered.complete();
          return recovery.future;
        },
      );
      await _start(tester);
      f.chat.requestRecovery();
      await _pump(tester);
      expect(recoveryEntered.isCompleted, isTrue);
      await tester.enterText(find.byKey(_composer), 'Keep uncertain guidance');
      await tester.tap(find.byKey(_send));
      await _pump(tester);
      storage.failSettlement = true;
      f.remote.event('turn.end', {'status': 'completed'});
      await _pump(tester);
      expect(storage.failures, 1);
      expect(f.chat.phase, NormalGatewayTurnPhase.reconciling);
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      final beforeAck = f.chat.snapshot.displayRows;
      ScaffoldMessenger.of(
        tester.element(find.byType(ChatScreen)),
      ).clearSnackBars();

      f.remote.ack.complete(true);
      await _pump(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_text(tester), 'Keep uncertain guidance');
      expect(f.chat.snapshot.displayRows, beforeAck);
      expect(f.chat.snapshot.steering, isFalse);
      expect(f.chat.canSteer, isFalse);
      expect(f.chat.reserve(), isNull);
      expect(find.text('Message queued for the current run.'), findsNothing);
      expect(
        find.text(
          'Message delivery could not be confirmed. Your draft was kept. Check the chat before retrying.',
        ),
        findsOneWidget,
      );
      expect(f.remote.prompts, ['Original task']);
      expect(f.remote.guidance, [('stored-chat', 'Keep uncertain guidance')]);
      f.remote.turn.complete();
      recovery.complete(
        const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
        ),
      );
      await _pump(tester);
      expect(f.chat.snapshot.hasActiveTurn, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await f.controller.close();
      await _pump(tester);
      expect(
        await ComposerDraftStore.read(
          connectionId: _connection.id,
          sessionId: _session.id,
        ),
        'Keep uncertain guidance',
      );
    },
  );

  for (final stopFirst in [false, true]) {
    testWidgets(
      'settlement before steering ACK retains the draft (Stop tapped=$stopFirst)',
      (tester) async {
        final f = await prepare(tester);
        await _start(tester);
        await tester.enterText(find.byKey(_composer), 'Keep this guidance');
        await tester.tap(find.byKey(_send));
        await _pump(tester);
        if (stopFirst) {
          expect(_button(tester, _stop).onPressed, isNotNull);
          await tester.tap(find.byKey(_stop));
          await _pump(tester);
        }
        f.remote.event('turn.end', {'status': 'completed'});
        f.remote.turn.complete();
        await _pump(tester);
        expect(f.chat.snapshot.hasActiveTurn, isFalse);
        ScaffoldMessenger.of(
          tester.element(find.byType(ChatScreen)),
        ).clearSnackBars();

        f.remote.ack.complete(true);
        await _pump(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(_text(tester), 'Keep this guidance');
        expect(find.text('Message queued for the current run.'), findsNothing);
        expect(
          find.text(
            'Message delivery could not be confirmed. Your draft was kept. Check the chat before retrying.',
          ),
          findsOneWidget,
        );
        expect(f.remote.prompts, ['Original task']);
        expect(f.remote.guidance, [('stored-chat', 'Keep this guidance')]);
        await tester.pumpWidget(const SizedBox.shrink());
        await f.controller.close();
        await _pump(tester);
        expect(
          await ComposerDraftStore.read(
            connectionId: _connection.id,
            sessionId: _session.id,
          ),
          'Keep this guidance',
        );
      },
    );
  }

  for (final flag in [
    'response_previewed',
    'response_reused',
    'response_transformed',
  ]) {
    testWidgets(
      'guidance preserves a same-turn $flag completion and later activity',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 1800);
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({'verbose_mode': true});
        final f = await prepare(tester);
        await _start(tester);
        f.remote.event('message.delta', {'text': 'Previewed answer'});
        f.remote.event('message.interim', {
          'text': 'Previewed answer',
          'already_streamed': true,
        });
        f.remote.event('tool.start', {'tool': 'read_file', 'tool_id': 't1'});
        f.remote.event('message.delta', {'text': 'Later commentary'});
        f.remote.event('message.interim', {
          'text': 'Later commentary',
          'already_streamed': true,
        });
        f.remote.event('reasoning.delta', {'text': 'Before guidance'});
        await _pump(tester);
        await tester.enterText(find.byKey(_composer), 'Keep the preview');
        await tester.tap(find.byKey(_send));
        await _pump(tester);
        f.remote.ack.complete(true);
        await _pump(tester);
        f.remote.event('tool.start', {'tool': 'read_file', 'tool_id': 't2'});
        f.remote.event('reasoning.delta', {'text': 'After guidance'});
        f.remote.event('message.complete', {
          'text': 'Previewed answer',
          flag: true,
        });
        await _pump(tester);

        expect(
          f.chat.snapshot.displayRows.where(
            (row) => row['content'] == 'Previewed answer',
          ),
          hasLength(1),
        );
        expect(
          find.text('Previewed answer', findRichText: true),
          findsOneWidget,
        );
        expect(
          f.chat.snapshot.timeline.runs.map(
            (run) => run.activity?.toolId ?? run.text,
          ),
          [
            'Previewed answer',
            't1',
            'Later commentary',
            'Before guidance',
            't2',
            'After guidance',
          ],
        );
        // Reusing an earlier preview must not leave a trailing guidance row
        // that disconnects later reasoning/tools from the live assistant.
        f.remote.event('reasoning.delta', {'text': 'Still working'});
        f.remote.event('tool.start', {'tool': 'read_file', 'tool_id': 't3'});
        await _pump(tester);
        expect(f.chat.snapshot.timeline.runs.last.activity?.toolId, 't3');
        expect(
          f.chat.snapshot.timeline.runs.map((run) => run.text),
          contains('Still working'),
        );
        expect(f.remote.prompts, ['Original task']);
        expect(f.remote.guidance, [('stored-chat', 'Keep the preview')]);
        await tester.pumpWidget(const SizedBox.shrink());
        await f.controller.close();
        await _pump(tester);
      },
    );
  }

  testWidgets(
    'Send and Stop are independent while guidance stays in the active turn',
    (tester) async {
      final f = await prepare(tester);
      expect(find.byKey(_stop), findsNothing);
      await _start(tester);
      expect(f.remote.prompts, ['Original task']);
      expect(find.byKey(_send), findsOneWidget);
      expect(find.byKey(_stop), findsOneWidget);
      expect(_button(tester, _send).onPressed, isNotNull);
      expect(_button(tester, _stop).onPressed, isNotNull);
      final turn = f.chat.turnId;
      f.remote.event('message.delta', {'text': 'Before guidance. '});
      await tester.enterText(find.byKey(_composer), 'Focus on authentication');
      // Captured callbacks must not bypass synchronous duplicate admission.
      final send = _button(tester, _send).onPressed!;
      send();
      send();
      await _pump(tester);
      expect(f.remote.guidance, [('stored-chat', 'Focus on authentication')]);
      expect(_button(tester, _send).onPressed, isNull);
      expect(_button(tester, _stop).onPressed, isNotNull);
      expect(tester.widget<TextField>(find.byKey(_composer)).enabled, isTrue);
      f.remote.ack.complete(true);
      await _pump(tester);
      expect(_text(tester), isEmpty);
      expect(f.chat.turnId, turn);
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      expect(f.remote.prompts, ['Original task']);
      expect(
        f.chat.snapshot.displayRows
            .where((r) => r['role'] == 'user')
            .map((r) => r['content']),
        ['Original task', 'Focus on authentication'],
      );
      f.remote.event('message.delta', {'text': 'After guidance.'});
      await _pump(tester);
      expect(
        f.chat.snapshot.displayRows.last['content'],
        'Before guidance. After guidance.',
      );
      expect(find.text('Message queued for the current run.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      expect(
        await ComposerDraftStore.read(
          connectionId: _connection.id,
          sessionId: _session.id,
        ),
        isNull,
      );
    },
  );

  for (final replacement in ['New draft', '', 'Steer this']) {
    testWidgets(
      'a held steering ack preserves newer edit ${jsonEncode(replacement)}',
      (tester) async {
        final f = await prepare(tester);
        await _start(tester);
        await tester.enterText(find.byKey(_composer), 'Steer this');
        await tester.tap(find.byKey(_send));
        await _pump(tester);
        await tester.enterText(find.byKey(_composer), 'Intervening edit');
        await tester.enterText(find.byKey(_composer), replacement);
        f.remote.ack.complete(true);
        await _pump(tester);
        expect(_text(tester), replacement);
        expect(f.remote.prompts, hasLength(1));
        expect(f.remote.guidance, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester);
        expect(
          await ComposerDraftStore.read(
            connectionId: _connection.id,
            sessionId: _session.id,
          ),
          replacement.isEmpty ? isNull : replacement,
        );
      },
    );
  }

  for (final outcome in ['rejected', 'unsupported', 'unknown']) {
    testWidgets(
      '$outcome steering keeps the draft and never falls back to prompt.submit',
      (tester) async {
        final f = await prepare(tester);
        await _start(tester);
        await tester.enterText(find.byKey(_composer), 'Keep this instruction');
        await tester.tap(find.byKey(_send));
        await _pump(tester);
        if (outcome == 'rejected') {
          f.remote.ack.complete(false);
        } else {
          f.remote.ack.completeError(
            JsonRpcError(
              'session.steer',
              outcome,
              code: outcome == 'unsupported' ? -32601 : null,
            ),
          );
        }
        await _pump(tester);
        expect(_text(tester), 'Keep this instruction');
        expect(f.remote.prompts, ['Original task']);
        expect(
          f.chat.snapshot.displayRows.where((r) => r['role'] == 'user'),
          hasLength(1),
        );
        expect(f.chat.snapshot.hasActiveTurn, isTrue);
        expect(_button(tester, _send).onPressed, isNotNull);
        expect(_button(tester, _stop).onPressed, isNotNull);
        expect(
          find.textContaining(
            outcome == 'unknown'
                ? 'delivery could not be confirmed'
                : 'could not accept this message',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(
          f.remote.guidance,
          hasLength(1),
          reason: 'No automatic retry after an uncertain acknowledgement',
        );
      },
    );
  }

  testWidgets(
    'empty guidance and pre-wire preparation cannot submit a second prompt',
    (tester) async {
      final f = await prepare(tester, emit: false);
      await _start(tester);
      expect(_button(tester, _send).onPressed, isNull);
      expect(f.remote.guidance, isEmpty);
      f.remote.onSent!();
      await _pump(tester);
      await tester.enterText(find.byKey(_composer), '  \n  ');
      await tester.tap(find.byKey(_send));
      await _pump(tester);
      expect(f.remote.guidance, isEmpty);
      expect(f.remote.prompts, hasLength(1));
    },
  );

  testWidgets(
    'a departed route cannot clear its replacement draft on a late ack',
    (tester) async {
      final f = await prepare(tester);
      await _start(tester);
      await tester.enterText(find.byKey(_composer), 'First route guidance');
      await tester.tap(find.byKey(_send));
      await _pump(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      await _pumpChat(
        tester,
        controller: f.controller,
        remote: f.remote,
        initialText: 'Replacement draft',
      );
      f.remote.ack.complete(true);
      await _pump(tester);
      expect(_text(tester), 'Replacement draft');
      expect(tester.takeException(), isNull);
      expect(f.remote.prompts, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      expect(
        await ComposerDraftStore.read(
          connectionId: _connection.id,
          sessionId: _session.id,
        ),
        'Replacement draft',
      );
    },
  );

  testWidgets(
    'both 48px controls and multiline editor fit a 320px keyboard viewport at 200%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = await prepare(tester, textScale: 2);
      await _start(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      await tester.enterText(
        find.byKey(_composer),
        'New direction\nSecond line',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _pump(tester);
      final send = tester.getRect(find.byKey(_send));
      final stop = tester.getRect(find.byKey(_stop));
      expect(send.size, const Size(48, 48));
      expect(stop.size, const Size(48, 48));
      expect(send.overlaps(stop), isFalse);
      expect(send.bottom, lessThanOrEqualTo(520));
      expect(stop.bottom, lessThanOrEqualTo(520));
      expect(tester.getSize(find.byKey(_composer)).width, greaterThan(80));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(_send));
      await _pump(tester);
      expect(f.remote.guidance.single.$2, 'New direction\nSecond line');
      f.remote.ack.complete(true);
      await _pump(tester);
    },
  );

  for (final priorSource in ['saved', 'received']) {
    for (final stopAndSend in [false, true]) {
      testWidgets(
        'cancelling empty SSE keeps the $priorSource final (Stop and send=$stopAndSend)',
        (tester) async {
          final client = _RestStreams();
          if (priorSource == 'saved') {
            client.historyRows = [
              {'id': 1, 'role': 'user', 'content': 'Prior question'},
              {
                'id': 2,
                'role': 'assistant',
                'content': 'Prior successful final',
                'status': 'completed',
              },
            ];
          }
          await _pumpChat(tester, httpClient: client);
          if (priorSource == 'received') {
            await _start(tester);
            client.delta(0, 'Prior successful final');
            client.finish(0);
            await _pump(tester);
          }
          Finder priorFinal() => find.byWidgetPredicate(
            (widget) =>
                widget is MessageBubble &&
                !widget.isUser &&
                widget.content == 'Prior successful final',
          );
          expect(priorFinal(), findsOneWidget);
          final priorMetadata = Map<String, dynamic>.of(
            tester.widget<MessageBubble>(priorFinal()).metadata,
          );
          await tester.enterText(find.byKey(_composer), 'Cancelled task');
          await tester.tap(find.byKey(_send));
          await _pump(tester);
          final cancelled = client.prompts.length - 1;
          // No assistant token has arrived for this admission. Removing its
          // empty scaffold must not lend cancellation to the preceding answer.
          if (stopAndSend) {
            await tester.enterText(find.byKey(_composer), 'Replacement task');
            await tester.tap(find.byKey(_send));
          } else {
            await tester.tap(find.byKey(_stop));
          }
          await _pump(tester);
          expect(client.cancelled, contains(cancelled));
          expect(client.prompts, hasLength(cancelled + (stopAndSend ? 2 : 1)));
          expect(priorFinal(), findsOneWidget);
          expect(
            tester.widget<MessageBubble>(priorFinal()).metadata,
            priorMetadata,
          );
          if (stopAndSend) {
            client.delta(cancelled + 1, 'Replacement final');
            client.finish(cancelled + 1);
            await _pump(tester);
            expect(priorFinal(), findsOneWidget);
          }
          final reads = client.historyReads;
          await tester.tap(find.byTooltip('Chat actions').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Refresh').hitTestable());
          await _pump(tester);
          expect(client.historyReads, greaterThan(reads));
          expect(priorFinal(), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await _pump(tester);
        },
      );
    }
  }

  testWidgets(
    'REST Stop and send cancels the old stream before one new prompt',
    (tester) async {
      final client = _RestStreams();
      await _pumpChat(tester, httpClient: client);
      await _start(tester);
      expect(client.prompts, hasLength(1));
      client.delta(0, 'Partial response');
      await _pump(tester);
      expect(find.byKey(_stop), findsOneWidget);
      expect(find.byTooltip('Stop and send'), findsOneWidget);
      await tester.enterText(find.byKey(_composer), 'New direction');
      final send = _button(tester, _send).onPressed!;
      send();
      send();
      await _pump(tester);
      expect(client.cancelled, [0]);
      expect(client.order, ['submit:0', 'cancel:0', 'submit:1']);
      expect(client.prompts, hasLength(2));
      final messages = client.prompts.last['messages'] as List;
      final wirePrompt = AndroidPromptContext.forModel('New direction');
      expect(messages.last, {'role': 'user', 'content': wirePrompt});
      expect(messages.where((r) => r['content'] == wirePrompt), hasLength(1));
      expect(_text(tester), isEmpty);
      await tester.enterText(find.byKey(_composer), 'Keep next draft');
      client.delta(1, 'New reply');
      client.finish(1);
      await _pump(tester);
      expect(_text(tester), 'Keep next draft');
      expect(find.byKey(_stop), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
    },
  );
}

class _Remote {
  _Remote({this.emit = true});
  final bool emit;
  final turn = Completer<void>();
  final ack = Completer<bool>();
  final prompts = <String>[];
  final guidance = <(String, String)>[];
  StreamCallback? onEvent;
  void Function()? onSent;

  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) async {
    prompts.add(text);
    this.onEvent = onEvent;
    this.onSent = onSent;
    if (emit) onSent();
    event('message.start', const {});
    await turn.future;
  }

  Future<bool> steer({required String sessionId, required String text}) {
    guidance.add((sessionId, text));
    return ack.future;
  }

  void event(String type, Map<String, dynamic> data) =>
      onEvent?.call(StreamEvent(type: type, data: data, turnId: 'wire-turn'));
}

class _PendingWriteFault extends InMemorySharedPreferencesStore {
  _PendingWriteFault() : super.empty();
  bool failSettlement = false;
  int failures = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (failSettlement &&
        key == 'flutter.${NormalGatewayPendingStore.preferenceKey}' &&
        value is String &&
        (jsonDecode(value) as List).whereType<Map>().any(
          (marker) => marker['phase'] == 'settled',
        )) {
      failSettlement = false;
      failures++;
      throw StateError('Synthetic settlement storage outage');
    }
    return super.setValue(type, key, value);
  }
}

class _RestStreams extends http.BaseClient {
  List<Map<String, dynamic>> historyRows = [];
  int historyReads = 0;
  final streams = <StreamController<List<int>>>[];
  final prompts = <Map<String, dynamic>>[];
  final cancelled = <int>[];
  final order = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/v1/chat/completions')) {
      final body = await request.finalize().bytesToString();
      final index = streams.length;
      prompts.add(jsonDecode(body) as Map<String, dynamic>);
      order.add('submit:$index');
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled.add(index);
          order.add('cancel:$index');
        },
      );
      streams.add(stream);
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    final messages = request.url.path.endsWith('/messages');
    if (messages) historyReads++;
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(jsonEncode({'data': messages ? historyRows : []})),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  void delta(int index, String text) => streams[index].add(
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n',
    ),
  );
  void finish(int index) {
    streams[index].add(utf8.encode('data: [DONE]\n\n'));
    unawaited(streams[index].close());
  }
}
