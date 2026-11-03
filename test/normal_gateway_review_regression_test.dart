import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notificationPrefs.value = NotificationPrefs.defaults;
  });
  tearDown(() => notificationPrefs.value = NotificationPrefs.defaults);

  test('pre-wire rejection never posts a server turn error', () async {
    final f = _Fixture(emit: false);
    addTearDown(f.close);
    await f.start();
    f.rpc.completeError(
      StateError('session setup rejected before prompt wire'),
    );
    await _flush();
    expect(f.chat.snapshot.wireEmitted, isFalse);
    expect(f.chat.snapshot.hasActiveTurn, isFalse);
    expect(f.chat.phase, NormalGatewayTurnPhase.failed);
    expect(await f.session.pendingStore.load('review'), isEmpty);
    expect(f.sink.rows, isEmpty);
  });

  for (final status in [
    'error',
    'failed',
    'interrupted',
    'cancelled',
    'canceled',
  ]) {
    test('live $status alerts once while absent, never success', () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.emit('message.complete', {'text': 'Partial output', 'status': status});
      await _flush();
      f.emit('turn.end', {'status': status});
      await _flush();
      expect(f.chat.phase, NormalGatewayTurnPhase.failed);
      expect(f.sink.rows, hasLength(1));
      expect(f.sink.rows.single.title, 'Hermes turn failed');
      final payload = jsonDecode(f.sink.rows.single.payload) as Map;
      expect(payload['sessionId'], 'canonical');
      expect(payload['connectionId'], _connection.id);
      expect(payload['turnId'], f.chat.turnId);
    });
  }

  test('session preparation failure before submit is silent', () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.session.ready;
    final chat = f.session.chatFor('unbound', title: 'Unbound');
    await expectLater(
      chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'Not submitted',
        localContent: 'Not submitted',
      ),
      throwsA(isA<TypeError>()),
    );
    expect(chat.phase, NormalGatewayTurnPhase.failed);
    expect(chat.wireEmitted, isFalse);
    expect(f.submissions, 0);
    expect(f.sink.rows, isEmpty);
  });

  test('absent-route success alerts once with canonical deep link', () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.start();
    f.emit('message.complete', {'text': 'Done', 'status': 'complete'});
    await _flush();
    f.emit('message.complete', {'text': 'Done', 'status': 'complete'});
    f.emit('turn.end', {'status': 'completed'});
    await _flush();
    expect(f.sink.rows, hasLength(1));
    expect(f.sink.rows.single.title, 'Hermes response ready');
    final payload = jsonDecode(f.sink.rows.single.payload) as Map;
    expect(payload['sessionId'], 'canonical');
    expect(payload['connectionId'], _connection.id);
    expect(payload['turnId'], f.chat.turnId);
    expect(f.submissions, 1);
  });

  test(
    'foreground and per-kind notification preferences suppress alerts',
    () async {
      final fg = _Fixture(background: false);
      await fg.start();
      fg.emit('message.complete', {'text': 'Done', 'status': 'complete'});
      await _flush();
      expect(fg.sink.rows, isEmpty);
      await fg.close();
      notificationPrefs.value = NotificationPrefs.defaults.copyWith(
        kind: HermesNotificationKind.turnDone,
        kindValue: false,
      );
      final off = _Fixture();
      await off.start();
      off.emit('message.complete', {'text': 'Done', 'status': 'complete'});
      await _flush();
      expect(off.sink.rows, isEmpty);
      await off.close();
      notificationPrefs.value = NotificationPrefs.defaults.copyWith(
        kind: HermesNotificationKind.turnError,
        kindValue: false,
      );
      final err = _Fixture();
      await err.start();
      err.emit('message.complete', {'status': 'error', 'text': 'Failed'});
      await _flush();
      expect(err.sink.rows, isEmpty);
      await err.close();
    },
  );

  test(
    'RPC ACK and socket loss remain unresolved, silent and never resubmit',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      f.rpc.complete();
      await _flush();
      f.session.connectionChanged(DesktopConnectionState.disconnected);
      await _flush();
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      expect(f.sink.rows, isEmpty);
      expect(f.submissions, 1);
    },
  );

  test(
    'lost interrupted terminal plus stock durable partial is unknown, not success',
    () async {
      // Captured by executing stock _complete_turn_payload, _session_live_status,
      // _inflight_snapshot, close_interrupted_tool_sequence, and _message_response
      // definitions in an isolated AST harness. Only clock/ancillary rendering and
      // usage callbacks were stubbed; this is not a live provider/server result.
      final stock =
          jsonDecode(
                File(
                  'test/fixtures/normal_gateway_interrupted_stock.json',
                ).readAsStringSync(),
              )
              as Map;
      final resume = stock['resume'] as Map;
      final rows = (stock['history'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      expect(
        (stock['terminal_lost_to_socket'] as Map)['status'],
        'interrupted',
      );
      expect(resume['status'], 'idle');
      expect(resume['inflight'], isNull);
      final f = _Fixture(
        running: resume['running'] as bool,
        status: resume['status'] as String,
        history: rows,
      );
      addTearDown(f.close);
      await f.start();
      f.rpc.completeError(
        StateError('socket lost before interrupted terminal'),
      );
      await _flush();
      expect(f.chat.phase, NormalGatewayTurnPhase.reconciledUnknown);
      expect(f.chat.snapshot.hasActiveTurn, isFalse);
      expect(f.chat.snapshot.error, isNull);
      expect(f.chat.snapshot.status!.kind, 'reconciled_unknown');
      expect(f.chat.snapshot.historyRows.last['content'], rows.last['content']);
      expect(f.sink.rows, isEmpty);
      expect(f.submissions, 1);
      expect(await f.session.pendingStore.load('review'), isEmpty);
      final next = f.chat.reserve();
      expect(
        next,
        isNotNull,
        reason: 'idle unknown must not deadlock admission',
      );
      f.chat.cancelPreparation(next!);
    },
  );

  for (final baseline in [false, true]) {
    test(
      'authoritative idle releases unknown even without fresh rows: baseline=$baseline',
      () async {
        final f = _Fixture(running: false, status: 'idle');
        addTearDown(f.close);
        await f.start(seedHistory: baseline);
        f.rpc.completeError(StateError('lost terminal'));
        await _flush();
        expect(f.chat.phase, NormalGatewayTurnPhase.reconciledUnknown);
        expect(f.sink.rows, isEmpty);
        expect(f.submissions, 1);
        expect(await f.session.pendingStore.load('review'), isEmpty);
      },
    );
  }

  for (final status in ['completed', 'failed', 'interrupted']) {
    test('explicit recovered $status remains authoritative', () async {
      final f = _Fixture(
        running: false,
        status: status,
        history: [
          {'id': 12, 'role': 'assistant', 'content': 'Recovered output'},
        ],
      );
      addTearDown(f.close);
      await f.start();
      f.rpc.completeError(StateError('terminal frame lost'));
      await _flush();
      expect(
        f.chat.phase,
        status == 'completed'
            ? NormalGatewayTurnPhase.completed
            : NormalGatewayTurnPhase.failed,
      );
      expect(f.sink.rows, hasLength(1));
      expect(
        f.sink.rows.single.title,
        status == 'completed' ? 'Hermes response ready' : 'Hermes turn failed',
      );
      expect(f.submissions, 1);
    });
  }

  for (final restart in [false, true]) {
    testWidgets('local next draft survives canonical reopen; restart=$restart', (
      tester,
    ) async {
      var controller = GatewayTurnApplicationController();
      final remote = _Remote();
      await _open(tester, controller, remote, 'local');
      await tester.enterText(find.byType(TextField), 'Run');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(remote.submissions, 1);
      await tester.enterText(find.byType(TextField), 'Keep my next draft');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        await ComposerDraftStore.read(
          connectionId: _connection.id,
          sessionId: 'local',
        ),
        'Keep my next draft',
      );
      if (restart) {
        await controller.close();
        controller = GatewayTurnApplicationController();
        // Recreate the preference singleton too: no in-memory owner alias is
        // available to rescue the canonical composer after process replacement.
        final prefs = await SharedPreferences.getInstance();
        final disk = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
        SharedPreferences.setMockInitialValues(disk);
      }
      await _open(tester, controller, remote, 'canonical');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep my next draft',
      );
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
      remote.rpc.complete();
      await tester.pump();
    });
  }
  testWidgets('idle unknown is visible and leaves the composer/send usable', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    final remote = _Remote();
    await _open(tester, controller, remote, 'local', recoveredIdle: true);
    await tester.enterText(find.byType(TextField), 'Run');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    remote.rpc.completeError(StateError('lost terminal frame'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'The gateway is idle. The previous turn’s outcome could not be confirmed.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Stop response'), findsNothing);
    await tester.enterText(
      find.byType(TextField),
      'Another intentional prompt',
    );
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNotNull,
    );
    expect(remote.submissions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await controller.close();
  });

  testWidgets(
    'pending receipt hydrates an old local bucket before canonical composer read',
    (tester) async {
      var controller = GatewayTurnApplicationController();
      final remote = _Remote();
      final session = controller.normalSessionFor(
        _connection,
        submit: remote.submit,
      );
      await session.ready;
      final scope = session.scope;
      await controller.close();
      await ComposerDraftStore.save(
        connectionId: _connection.id,
        sessionId: 'local',
        text: 'Draft from before alias support',
      );
      await NormalGatewayPendingStore().put(
        NormalGatewayPendingMarker(
          scope: scope,
          localSessionId: 'local',
          storedSessionId: 'canonical',
          turnId: 'old-turn',
          rowFloor: 10,
          phase: 'emitted',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      controller = GatewayTurnApplicationController();
      await _open(tester, controller, remote, 'canonical');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft from before alias support',
      );
      expect(remote.submissions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
    },
  );
}

final _connection = SavedConnection(
  id: 'review',
  label: 'Review',
  host: 'review.invalid',
  port: 8642,
  apiKey: 'fixture-key',
);

class _Sink implements TurnNotificationSink {
  final rows = <TurnNotification>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<bool?> requestPermission() async => true;
  @override
  Future<bool?> checkPermission() async => true;
  @override
  Future<NotificationResponse?> takeInitialLaunchResponse() async => null;
  @override
  Future<void> show(TurnNotification notification) async =>
      rows.add(notification);
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
}

Future<void> _flush() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Fixture {
  final sink = _Sink();
  late final service = TurnNotificationService(sink: sink);
  late final NormalGatewayApplicationSession session;
  late NormalGatewayChatOwner chat;
  final rpc = Completer<void>();
  final entered = Completer<void>();
  int submissions = 0;
  _Fixture({
    bool emit = true,
    bool background = true,
    bool? running = true,
    String? status,
    List<Map<String, dynamic>> history = const [],
  }) {
    session = NormalGatewayApplicationSession(
      connection: _connection,
      scope: 'review',
      notifications: service,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            submissions++;
            if (emit) {
              onSent();
              session.receiveEvent(
                'local',
                StreamEvent(
                  type: 'turn.start',
                  data: const {},
                  turnId: 'fixture-turn-$submissions',
                ),
              );
            }
            entered.complete();
            return rpc.future;
          },
      resume: ({required localSessionId, required storedSessionId}) async =>
          ResumedGatewaySession(
            runtimeSessionId: 'runtime',
            running: running,
            status: status,
          ),
      history: (_) async => history,
    );
    session.setLifecycle(background: background);
  }
  Future<void> start({bool seedHistory = true}) async {
    await session.ready;
    await service.ensureInitialized();
    chat = session.chatFor(
      'local',
      storedSessionId: 'canonical',
      title: 'Example',
    );
    if (seedHistory) {
      chat.observeHistory([
        {'id': 10, 'role': 'assistant', 'content': 'Before'},
      ]);
    }
    chat
        .submitPrepared(
          reservation: chat.reserve()!,
          text: 'Prompt',
          localContent: 'Prompt',
        )
        .ignore();
    await entered.future;
  }

  void emit(String type, Map<String, dynamic> data) {
    final id = 'fixture-turn-$submissions';
    session.receiveEvent(
      'local',
      StreamEvent(type: type, data: data, turnId: id),
    );
    if (type == 'message.complete') {
      session.receiveEvent(
        'local',
        StreamEvent(type: 'turn.end', data: data, turnId: id),
      );
    }
  }

  Future<void> close() async {
    await session.close();
    if (!rpc.isCompleted) rpc.complete();
    await _flush();
  }
}

class _Remote {
  final rpc = Completer<void>();
  int submissions = 0;
  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) {
    submissions++;
    onSent();
    return rpc.future;
  }
}

Future<void> _open(
  WidgetTester tester,
  GatewayTurnApplicationController controller,
  _Remote remote,
  String id, {
  bool recoveredIdle = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        key: ValueKey(id),
        connection: _connection,
        session: Session(
          id: id,
          title: 'Example',
          model: 'fixture',
          source: 'mobile',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
          isLocalDraft: id == 'local',
        ),
        turnApplicationController: controller,
        testApiClient: ApiClient(
          baseUrl: _connection.baseUrl,
          apiKey: 'fixture-key',
          httpClient: MockClient(
            (_) async => http.Response('{"data":[]}', 200),
          ),
        ),
        testRemotePromptSubmit: remote.submit,
        testNormalResume:
            ({required localSessionId, required storedSessionId}) async =>
                ResumedGatewaySession(
                  runtimeSessionId: 'runtime',
                  running: !recoveredIdle,
                  status: recoveredIdle ? 'idle' : null,
                ),
        testStoredSessionKey: (_) => 'canonical',
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
