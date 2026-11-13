import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_turn_notification_sink.dart';

SavedConnection _conn() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
);

Map<String, dynamic> _frame(int seq, String type, [Map<String, dynamic>? p]) =>
    {'type': type, 'session_id': 'rt', 'seq': seq, 'payload': p ?? {}};

void main() {
  group('replay', () {
    test('a complete replay comes back in order, skipping what was seen', () {
      final events = ngParseReplay(
        {
          'events': [
            _frame(3, 'message.delta', {'text': 'old'}),
            _frame(4, 'message.delta', {'text': 'a'}),
            _frame(5, 'message.complete', {'status': 'complete'}),
          ],
          'latest_seq': 5,
          'truncated': false,
          'epoch': 'e1',
        },
        'rt',
        3,
        'e1',
      )!;
      expect(events.map((e) => e.type), ['message.delta', 'message.complete']);
      expect(events.first.seq, 4);
      expect(events.first.data['text'], 'a');
    });

    test('a replay that cannot be trusted means reading the chat again', () {
      Map<String, dynamic> reply({
        List<Map<String, dynamic>>? events,
        bool truncated = false,
        String epoch = 'e1',
        int latest = 5,
      }) => {
        'events': events ?? [_frame(4, 'x'), _frame(5, 'y')],
        'latest_seq': latest,
        'truncated': truncated,
        'epoch': epoch,
      };
      expect(ngParseReplay(reply(truncated: true), 'rt', 3, 'e1'), isNull);
      expect(ngParseReplay(reply(epoch: 'e2'), 'rt', 3, 'e1'), isNull);
      expect(ngParseReplay(reply(latest: 2), 'rt', 3, 'e1'), isNull);
      expect(
        ngParseReplay(reply(events: [_frame(5, 'gap')]), 'rt', 3, 'e1'),
        isNull,
      );
      expect(
        ngParseReplay(
          reply(
            events: [
              {..._frame(4, 'x'), 'session_id': 'other'},
            ],
          ),
          'rt',
          3,
          'e1',
        ),
        isNull,
      );
      expect(ngParseReplay(const {}, 'rt', 3, 'e1'), isNull);
    });
  });

  group('live order', () {
    late NextGenGateway gateway;
    late NgChatController chat;
    setUp(() {
      gateway = NextGenGateway(_conn());
      chat = NgChatController(gateway, sessionId: 'stored')..runtimeId = 'rt';
    });
    tearDown(() {
      chat.dispose();
      gateway.dispose();
    });
    StreamEvent ev(int seq, String type, [Map<String, dynamic>? p]) =>
        WsClient.parseGatewayEvent(_frame(seq, type, p))!;

    test('an event sent twice applies once', () async {
      gateway.debugEmit(ev(1, 'message.start'));
      gateway.debugEmit(ev(2, 'message.delta', {'text': 'Hel'}));
      gateway.debugEmit(ev(2, 'message.delta', {'text': 'Hel'}));
      gateway.debugEmit(ev(3, 'message.delta', {'text': 'lo'}));
      await pumpEventQueue();
      expect(chat.items.whereType<NgAssistantItem>().single.text, 'Hello');
    });

    test(
      'a gap holds live events until the catch-up, then applies them',
      () async {
        gateway.debugEmit(ev(1, 'message.start'));
        gateway.debugEmit(ev(2, 'message.delta', {'text': 'A'}));
        // 3 and 4 were missed; the replay fails offline, so the held events
        // still land rather than being lost.
        gateway.debugEmit(ev(5, 'message.delta', {'text': 'B'}));
        gateway.debugEmit(ev(6, 'message.complete', {'status': 'interrupted'}));
        await pumpEventQueue(times: 50);
        expect(chat.running, isFalse);
        expect(chat.lastTurnInterrupted, isTrue);
        expect(chat.lastTurnFailed, isFalse);
      },
    );

    test('a failed turn says so, for its notification', () async {
      gateway.debugEmit(ev(1, 'message.start'));
      gateway.debugEmit(ev(2, 'message.complete', {'status': 'error'}));
      await pumpEventQueue();
      expect(chat.lastTurnFailed, isTrue);
    });
  });

  test('a posted request notification can be taken down again', () async {
    final sink = RecordingTurnNotificationSink()..permissionResult = true;
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    final posted = await service.showKind(
      kind: HermesNotificationKind.approval,
      title: 'Allow?',
      body: 'rm -rf build',
      eventId: 'req-1',
      sessionId: 's1',
      connectionId: 'c1',
      actions: const [
        TurnNotificationAction(id: 'approve', label: 'Allow once'),
        TurnNotificationAction(id: 'reject', label: 'Deny'),
      ],
    );
    expect(posted, isTrue);
    final id = sink.shown.single.id;
    expect(sink.shown.single.actions.map((a) => a.id), ['approve', 'reject']);
    await service.cancelKind(
      kind: HermesNotificationKind.approval,
      eventId: 'req-1',
      sessionId: 's1',
      connectionId: 'c1',
    );
    expect(sink.cancelled, contains(id));
  });

  test('approval buttons route to NextGen only while it runs', () {
    nextGenEnabled.value = false;
    expect(
      routeNotificationAnswerToNextGen(
        connectionId: 'c1',
        sessionId: 's1',
        requestId: 'r1',
        choice: 'once',
      ),
      isFalse,
    );
    nextGenEnabled.value = true;
    addTearDown(() {
      nextGenEnabled.value = false;
      nextGenNotificationAnswer.value = null;
    });
    expect(
      routeNotificationAnswerToNextGen(
        connectionId: 'c1',
        sessionId: 's1',
        requestId: 'r1',
        choice: null,
      ),
      isFalse,
      reason: 'a body tap only opens the chat',
    );
    expect(
      routeNotificationAnswerToNextGen(
        connectionId: 'c1',
        sessionId: 's1',
        requestId: 'r1',
        choice: 'deny',
      ),
      isTrue,
    );
    expect(nextGenNotificationAnswer.value?.choice, 'deny');
  });

  testWidgets('notification settings switch kinds and fit a narrow phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    notificationPrefs.value = NotificationPrefs.defaults;
    addTearDown(() => notificationPrefs.value = NotificationPrefs.defaults);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nextGenTheme(Brightness.light, NextGenLook.instance),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: SingleChildScrollView(child: NgNotificationSettings()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('ng-notify-replies')));
    await tester.pumpAndSettle();
    expect(
      notificationPrefs.value.kindEnabled(HermesNotificationKind.turnDone),
      isFalse,
    );
    expect(
      notificationPrefs.value.kindEnabled(HermesNotificationKind.turnError),
      isFalse,
    );
    expect(
      notificationPrefs.value.kindEnabled(HermesNotificationKind.approval),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('ng-notify-requests')));
    await tester.pumpAndSettle();
    expect(
      notificationPrefs.value.kindEnabled(HermesNotificationKind.input),
      isFalse,
    );
  });
}
