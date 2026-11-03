import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/notification_approval_fixture.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/widgets/gateway_approval_dialog.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/recording_turn_notification_sink.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

final _fixtureConnection = SavedConnection(
  id: 'notif-fixture',
  label: 'Notification fixture',
  host: 'notif.fixture',
  port: 8642,
  apiKey: '',
);

const _clientTurnId = '123e4567-e89b-42d3-a456-426614174000';

/// Wires the notification path ChatScreen actually uses when a turn settles.
///
/// The TurnNotificationService unit tests prove the service posts what it is
/// asked to post. These tests prove ChatScreen asks — the seam between "a turn
/// finished while the app was backgrounded" and "Android shows something" had
/// no coverage, so a regression there would ship silently.
void main() {
  late RecordingTurnNotificationSink sink;
  late TurnNotificationService notifications;
  late _CallbackCapturingTurnSession turnSession;

  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    sink = RecordingTurnNotificationSink();
    notifications = TurnNotificationService(sink: sink);
    turnSession = _CallbackCapturingTurnSession();
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    SavedConnection? connection,
    String sessionId = 'notif-session',
    String title = 'Roadmap',
  }) async {
    final selectedConnection = connection ?? _fixtureConnection;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(
          key: ValueKey('${selectedConnection.id}:$sessionId'),
          connection: selectedConnection,
          session: Session(
            id: sessionId,
            title: title,
            model: 'fixture-model',
            source: 'test',
            messageCount: 0,
            isActive: true,
            preview: '',
            startedAt: 1,
          ),
          testApiClient: ApiClient(
            baseUrl: 'http://notif.fixture',
            apiKey: '',
            httpClient: _EmptyChatHttpClient(),
          ),
          testTurnApplicationSession: turnSession,
          testTurnNotifications: notifications,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Android walks the full lifecycle chain; skipping a step trips Flutter's
  /// transition assertions, so tests must move the same way a device does.
  void background(WidgetTester tester) {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void foreground(WidgetTester tester) {
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('a turn settling in the background posts a notification', (
    tester,
  ) async {
    await pumpChat(tester);

    // Android moved the app off screen.
    background(tester);
    await tester.pump();

    turnSession.settle(_completedState());
    await tester.pump();

    expect(sink.shown, hasLength(1));
    // The session title tells the user which chat answered.
    expect(sink.shown.single.body, contains('Roadmap'));
  });

  testWidgets('a turn settling in the foreground posts nothing', (
    tester,
  ) async {
    await pumpChat(tester);

    // App is on screen: the user already watches the answer arrive.
    turnSession.settle(_completedState());
    await tester.pump();

    expect(sink.shown, isEmpty);
  });

  testWidgets(
    'returning to the app preserves completion and attention notifications',
    (tester) async {
      await pumpChat(tester);

      background(tester);
      await tester.pump();
      turnSession.settle(_completedState());
      await tester.pump();

      foreground(tester);
      await tester.pump();

      expect(sink.cancelAllCount, 0);
    },
  );

  testWidgets(
    'a failed turn settling in the background posts the failure notification',
    (WidgetTester tester) async {
      await pumpChat(tester);
      background(tester);

      turnSession.settle(_failedState());
      await tester.pump();

      expect(sink.shown, hasLength(1));
      expect(sink.shown.single.channel.id, 'hermes_turn_notifications');
      expect(sink.shown.single.title, contains('failed'));
    },
  );

  testWidgets(
    'an interrupted turn is reported as failed, never response ready',
    (WidgetTester tester) async {
      await pumpChat(tester);
      background(tester);

      turnSession.settle(_interruptedState());
      await tester.pump();

      expect(sink.shown, hasLength(1));
      expect(sink.shown.single.title, contains('failed'));
      expect(sink.shown.single.body, isNot(contains('Response ready')));
    },
  );

  testWidgets(
    'a background approval redacts command text without changing actions',
    (WidgetTester tester) async {
      await pumpChat(tester);
      background(tester);

      turnSession.emitAsync('approval.request', {
        'server_request_id': 'req-1',
        'command': 'fixture-tool PRIVATE-COMMAND-SENTINEL',
        'description': 'PRIVATE-DESCRIPTION-SENTINEL',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sink.shown, hasLength(1));
      final posted = sink.shown.single;
      expect(posted.channel.id, 'hermes_attention');
      expect(posted.actions.map((a) => a.id), ['approve', 'reject']);
      expect(posted.payload, contains('req-1'));
      expect(posted.body, 'Open the chat to review the requested action.');
      expect(
        '${posted.title} ${posted.body} ${posted.payload}',
        isNot(contains('PRIVATE-COMMAND-SENTINEL')),
      );
      expect(
        '${posted.title} ${posted.body} ${posted.payload}',
        isNot(contains('PRIVATE-DESCRIPTION-SENTINEL')),
      );
    },
  );

  for (final eventType in [
    'clarify.request',
    'sudo.request',
    'secret.request',
  ]) {
    testWidgets(
      '$eventType redacts input details in background notifications',
      (WidgetTester tester) async {
        await pumpChat(tester);
        background(tester);

        turnSession.emitAsync(eventType, {
          'request_id': 'private-input-request',
          'question': 'PRIVATE-QUESTION-SENTINEL',
          'prompt': 'PRIVATE-PROMPT-SENTINEL',
          'env_var': 'PRIVATE-FIELD-SENTINEL',
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(sink.shown, hasLength(1));
        final posted = sink.shown.single;
        expect(posted.channel.id, 'hermes_attention');
        expect(posted.body, 'Open the chat to respond.');
        expect(posted.actions, isEmpty);
        expect(posted.payload, contains('notif-session'));
        expect(
          '${posted.title} ${posted.body} ${posted.payload}',
          isNot(contains('PRIVATE-')),
        );
        expect(turnSession.approvalResponses, isEmpty);
      },
    );
  }

  testWidgets('an answered approval never opens its queued post-frame dialog', (
    WidgetTester tester,
  ) async {
    await pumpChat(tester);
    foreground(tester);

    turnSession.emitAsync('approval.request', {
      'server_request_id': 'req-stale',
      'command': 'rm -rf build',
      'description': 'Remove the build folder',
    });
    await turnSession.tryRespondToApproval(
      sessionId: 'notif-session',
      choice: 'deny',
      requestId: 'req-stale',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(turnSession.approvalOwnershipChecks, 1);
    expect(find.byType(GatewayApprovalDialog), findsNothing);
  });

  testWidgets(
    'a pending notification approval is answered once the chat is up',
    (WidgetTester tester) async {
      addPendingNotificationApproval(
        PendingNotificationApproval(
          authority: fixtureApprovalAuthority(_fixtureConnection),
          connectionId: _fixtureConnection.id,
          sessionId: 'notif-session',
          requestId: 'req-9',
          choice: 'once',
        ),
      );
      addTearDown(() => pendingNotificationApprovals.value = const []);

      await pumpChat(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(turnSession.approvalResponses, [
        ('notif-session', 'once', 'req-9'),
      ]);
      expect(pendingNotificationApprovals.value, isEmpty);
    },
  );

  testWidgets('a mounted chat answers a pending notification approval', (
    WidgetTester tester,
  ) async {
    await pumpChat(tester);

    // The app-level controller did not own the request, so the handler left
    // it pending while the owning chat is already open — the mounted chat
    // must observe the notifier, not only a freshly pushed route.
    addPendingNotificationApproval(
      PendingNotificationApproval(
        authority: fixtureApprovalAuthority(_fixtureConnection),
        connectionId: _fixtureConnection.id,
        sessionId: 'notif-session',
        requestId: 'req-11',
        choice: 'deny',
      ),
    );
    addTearDown(() => pendingNotificationApprovals.value = const []);
    await tester.pump(const Duration(milliseconds: 50));

    expect(turnSession.approvalResponses, [
      ('notif-session', 'deny', 'req-11'),
    ]);
    expect(pendingNotificationApprovals.value, isEmpty);
  });

  testWidgets('several queued approvals are all answered', (
    WidgetTester tester,
  ) async {
    await pumpChat(tester);

    addPendingNotificationApproval(
      PendingNotificationApproval(
        authority: fixtureApprovalAuthority(_fixtureConnection),
        connectionId: _fixtureConnection.id,
        sessionId: 'notif-session',
        requestId: 'req-a',
        choice: 'once',
      ),
    );
    addPendingNotificationApproval(
      PendingNotificationApproval(
        authority: fixtureApprovalAuthority(_fixtureConnection),
        connectionId: _fixtureConnection.id,
        sessionId: 'notif-session',
        requestId: 'req-b',
        choice: 'deny',
      ),
    );
    addTearDown(() => pendingNotificationApprovals.value = const []);
    await tester.pump(const Duration(milliseconds: 50));

    expect(turnSession.approvalResponses, [
      ('notif-session', 'once', 'req-a'),
      ('notif-session', 'deny', 'req-b'),
    ]);
    expect(pendingNotificationApprovals.value, isEmpty);
  });

  testWidgets('a pending approval for another session is left untouched', (
    WidgetTester tester,
  ) async {
    await pumpChat(tester);

    addPendingNotificationApproval(
      PendingNotificationApproval(
        authority: fixtureApprovalAuthority(_fixtureConnection),
        connectionId: _fixtureConnection.id,
        sessionId: 'some-other-session',
        requestId: 'req-12',
        choice: 'once',
      ),
    );
    addTearDown(() => pendingNotificationApprovals.value = const []);
    await tester.pump(const Duration(milliseconds: 50));

    // Only the chat that owns the request may answer it.
    expect(turnSession.approvalResponses, isEmpty);
    expect(pendingNotificationApprovals.value, hasLength(1));
  });

  testWidgets(
    'same-endpoint saved profiles cannot consume each other approvals',
    (WidgetTester tester) async {
      await pumpChat(tester);
      final siblingProfile = SavedConnection(
        id: 'sibling-saved-profile',
        label: 'Sibling profile',
        host: _fixtureConnection.host,
        port: _fixtureConnection.port,
        apiKey: 'different-secret',
        gatewayProfile: 'other-profile',
      );
      expect(siblingProfile.baseUrl, _fixtureConnection.baseUrl);

      addPendingNotificationApproval(
        PendingNotificationApproval(
          authority: fixtureApprovalAuthority(siblingProfile),
          connectionId: siblingProfile.id,
          sessionId: 'notif-session',
          requestId: 'req-13',
          choice: 'once',
        ),
      );
      addTearDown(() => pendingNotificationApprovals.value = const []);
      await tester.pump(const Duration(milliseconds: 50));

      // Identical endpoint + session ids on different saved profiles never cross.
      expect(turnSession.approvalResponses, isEmpty);
      expect(pendingNotificationApprovals.value, hasLength(1));
    },
  );

  testWidgets(
    'settlement listeners are session-scoped and disposed with routes',
    (WidgetTester tester) async {
      ChatScreen chat(String sessionId, String title) => ChatScreen(
        key: ValueKey(sessionId),
        connection: _fixtureConnection,
        session: Session(
          id: sessionId,
          title: title,
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: ApiClient(
          baseUrl: 'http://notif.fixture',
          apiKey: '',
          httpClient: _EmptyChatHttpClient(),
        ),
        testTurnApplicationSession: turnSession,
        testTurnNotifications: notifications,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: IndexedStack(
            children: [chat('session-a', 'Alpha'), chat('session-b', 'Beta')],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      background(tester);

      turnSession.settle(
        _completedState(
          clientTurnId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          turnId: 'turn-a',
        ),
        sessionId: 'session-a',
      );
      turnSession.settle(
        _completedState(
          clientTurnId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          turnId: 'turn-b',
        ),
        sessionId: 'session-b',
      );
      await tester.pump();

      expect(sink.shown, hasLength(2));
      expect(
        sink.shown.map((notice) => notice.body),
        containsAll(['Alpha: Response ready', 'Beta: Response ready']),
      );

      foreground(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(turnSession.settledListenerCount, 0);
      turnSession.settle(
        _completedState(
          clientTurnId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          turnId: 'turn-c',
        ),
        sessionId: 'session-a',
      );
      await tester.pump();
      expect(sink.shown, hasLength(2));
    },
  );

  for (final oldSuccess in [true, false]) {
    testWidgets(
      'held route answer $oldSuccess cannot acknowledge fresh authority with reused IDs',
      (tester) async {
        await pumpChat(tester);
        final oldGate = Completer<bool>();
        final newGate = Completer<bool>();
        addTearDown(() {
          if (!oldGate.isCompleted) oldGate.complete(false);
          if (!newGate.isCompleted) newGate.complete(false);
          pendingNotificationApprovals.value = [];
        });
        turnSession.approvalGate = oldGate;
        final old = PendingNotificationApproval(
          connectionId: _fixtureConnection.id,
          sessionId: 'notif-session',
          requestId: 'reused',
          choice: 'once',
          authority: fixtureApprovalAuthority(_fixtureConnection),
        );
        addPendingNotificationApproval(old);
        await tester.pump(const Duration(milliseconds: 50));
        expect(turnSession.approvalResponses, hasLength(1));
        ConnectionMutationBarrier.begin([_fixtureConnection.id]).release();
        turnSession.approvalGate = newGate;
        final fresh = PendingNotificationApproval(
          connectionId: _fixtureConnection.id,
          sessionId: 'notif-session',
          requestId: 'reused',
          choice: 'deny',
          authority: fixtureApprovalAuthority(_fixtureConnection),
        );
        addPendingNotificationApproval(fresh);
        await tester.pump(const Duration(milliseconds: 50));
        expect(turnSession.approvalResponses, hasLength(2));
        oldGate.complete(oldSuccess);
        await tester.pump(const Duration(milliseconds: 50));
        expect(pendingNotificationApprovals.value.single, same(fresh));
        newGate.complete(true);
        await tester.pump(const Duration(milliseconds: 50));
        expect(pendingNotificationApprovals.value, isEmpty);
        expect(turnSession.approvalResponses.map((r) => r.$2), [
          'once',
          'deny',
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a throw while answering keeps the approval pending', (
    WidgetTester tester,
  ) async {
    await pumpChat(tester);
    turnSession.approvalShouldThrow = true;

    addPendingNotificationApproval(
      PendingNotificationApproval(
        authority: fixtureApprovalAuthority(_fixtureConnection),
        connectionId: _fixtureConnection.id,
        sessionId: 'notif-session',
        requestId: 'req-14',
        choice: 'once',
      ),
    );
    addTearDown(() => pendingNotificationApprovals.value = const []);
    await tester.pump(const Duration(milliseconds: 50));

    // Unresolved, not answered: the tap must survive for a later retry.
    expect(pendingNotificationApprovals.value, hasLength(1));
  });

  testWidgets('an unanswered probe keeps the approval pending', (
    WidgetTester tester,
  ) async {
    await pumpChat(tester);
    turnSession.approvalAnswer = false;

    addPendingNotificationApproval(
      PendingNotificationApproval(
        authority: fixtureApprovalAuthority(_fixtureConnection),
        connectionId: _fixtureConnection.id,
        sessionId: 'notif-session',
        requestId: 'req-15',
        choice: 'once',
      ),
    );
    addTearDown(() => pendingNotificationApprovals.value = const []);
    await tester.pump(const Duration(milliseconds: 50));

    // The route-local gateway does not own it yet: keep it for a retry.
    expect(pendingNotificationApprovals.value, hasLength(1));
  });
}

GatewayTurnRecoveryState _completedState({
  String clientTurnId = _clientTurnId,
  String turnId = 'server-turn',
}) => GatewayTurnRecoveryState.rehydrate(
  clientTurnId: clientTurnId,
  turnId: turnId,
  status: GatewayRecoveryTurnStatus.completed,
  lastSeq: 1,
  terminalEventRecorded: true,
  terminalResult: GatewayTurnTerminalResult(
    messageId: 'message-$clientTurnId',
    assistantText: 'Done',
  ),
  ackUncertain: false,
);

GatewayTurnRecoveryState _failedState() =>
    GatewayTurnRecoveryState.initial(
      clientTurnId: _clientTurnId,
    ).markSubmissionStarted().applyAck(
      const GatewayTurnAck(
        clientTurnId: _clientTurnId,
        turnId: 'server-turn',
        status: GatewayRecoveryTurnStatus.failed,
        // lastSeq stays 0 so the ack applies instead of triggering the
        // reconcile path, which preserves the previous (null) status.
        lastSeq: 0,
        created: false,
      ),
    );

GatewayTurnRecoveryState _interruptedState() =>
    GatewayTurnRecoveryState.initial(
      clientTurnId: _clientTurnId,
    ).markSubmissionStarted().applyAck(
      const GatewayTurnAck(
        clientTurnId: _clientTurnId,
        turnId: 'server-turn',
        status: GatewayRecoveryTurnStatus.interrupted,
        lastSeq: 0,
        created: false,
      ),
    );

/// Turn session that keeps the settle callback ChatScreen registers, so a test
/// can fire it the way the real gateway would.
class _CallbackCapturingTurnSession implements GatewayTurnApplicationSession {
  @override
  bool get hasActiveTurn => false;

  @override
  Object addTurnActivityListener(void Function() listener) => Object();

  @override
  void removeTurnActivityListener(Object token) {}

  final Map<String, (Object, GatewayTurnSettledCallback)> _settledListeners =
      {};
  final Set<String> _activeApprovals = {};
  int approvalOwnershipChecks = 0;
  DesktopAsyncEventCallback? _asyncListener;
  String _asyncSessionId = '';

  int get settledListenerCount => _settledListeners.length;

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) {
    _asyncListener = listener;
    _asyncSessionId = localSessionId;
    return Object();
  }

  /// Fires an async gateway event the way the live socket would.
  void emitAsync(String type, Map<String, dynamic> data) {
    if (type == 'approval.request') {
      final requestId = data['server_request_id']?.toString();
      if (requestId != null) {
        _activeApprovals.add('$_asyncSessionId|$requestId');
      }
    }
    _asyncListener?.call(_asyncSessionId, StreamEvent(type: type, data: data));
  }

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {}

  @override
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) {
    final token = Object();
    _settledListeners[localSessionId] = (token, listener);
    return token;
  }

  @override
  void removeTurnSettledListener(String localSessionId, Object registration) {
    final current = _settledListeners[localSessionId];
    if (current != null && identical(current.$1, registration)) {
      _settledListeners.remove(localSessionId);
    }
  }

  @override
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) {
    approvalOwnershipChecks += 1;
    return _activeApprovals.contains('$sessionId|$requestId');
  }

  /// Approval responses this fake was asked to send.
  final List<(String sessionId, String choice, String? requestId)>
  approvalResponses = [];
  Completer<bool>? approvalGate;

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async {
    approvalResponses.add((sessionId, choice, requestId));
    final gate = approvalGate;
    if (gate != null) return await gate.future;
    if (approvalShouldThrow) throw StateError('gateway not ready');
    if (approvalAnswer && requestId != null) {
      _activeApprovals.remove('$sessionId|$requestId');
    }
    return approvalAnswer;
  }

  /// When true, [tryRespondToApproval] throws instead of answering.
  bool approvalShouldThrow = false;

  /// What [tryRespondToApproval] returns when it does not throw.
  bool approvalAnswer = true;

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async => false;

  @override
  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  }) async => false;

  @override
  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  }) async => false;

  void settle(
    GatewayTurnRecoveryState state, {
    String sessionId = 'notif-session',
  }) => _settledListeners[sessionId]?.$2(state);

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {}

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async => const <GatewayTurnRecoveryState>[];

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => throw UnimplementedError();
}

class _EmptyChatHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': <Object>[]}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
