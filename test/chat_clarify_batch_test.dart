import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/fake_voice_composer_adapter.dart';

/// Mimics the production transport's batch-clarify behaviour: locking one
/// answer emits `clarify.remaining` before the response future completes
/// (see `DesktopGatewayClient.respondToClarify`).
class _BatchClarifySession implements GatewayTurnApplicationSession {
  @override
  bool get hasActiveTurn => false;

  @override
  Object addTurnActivityListener(void Function() listener) => Object();

  @override
  void removeTurnActivityListener(Object token) {}

  _BatchClarifySession(this.emit);

  final void Function(StreamEvent event) emit;
  final Map<String, Set<String>> _open = {};
  final List<({String requestId, String? questionId, String answer})> answers =
      [];
  final List<String> approvalAnswers = [];
  final Set<String> _expiredRequests = {};
  Completer<void>? _heldLock;

  void openBatch(String requestId, List<String> qids) {
    _open[requestId] = qids.toSet();
  }

  /// Leaves the next answer's `clarify.lock` in flight so a test can interleave
  /// a cancellation (and the gateway's late `status: expired` response) with it.
  void holdNextLock() => _heldLock = Completer<void>();

  void releaseHeldLock() => _heldLock?.complete();

  /// Resolves a held lock the way `DesktopGatewayClient.respondToClarify` does
  /// when the lock comes back `status: expired`: the answered question is gone,
  /// so the request reports an empty remaining set before the send returns.
  void expireHeldLock(String requestId) {
    _expiredRequests.add(requestId);
    _heldLock?.complete();
  }

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    answers.add((requestId: requestId, questionId: questionId, answer: answer));
    final held = _heldLock;
    if (held != null) {
      await held.future;
      _heldLock = null;
    }
    final remaining = _open[requestId];
    if (_expiredRequests.remove(requestId)) {
      remaining?.clear();
      emit(
        StreamEvent(
          type: 'clarify.remaining',
          data: {'id': requestId, 'remaining': <String>[]},
        ),
      );
      return true;
    }
    if (remaining != null && questionId != null) {
      remaining.remove(questionId);
      emit(
        StreamEvent(
          type: 'clarify.remaining',
          data: {'id': requestId, 'remaining': remaining.toList()},
        ),
      );
    }
    return true;
  }

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) => Object();

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {}

  @override
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) => Object();

  @override
  void removeTurnSettledListener(String localSessionId, Object registration) {}

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {}

  @override
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) => sessionId == _sessionId && requestId == 'approval-1';

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async {
    approvalAnswers.add(choice);
    return true;
  }

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

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async => const [];

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

const _sessionId = 'batch-clarify-session';

Future<(_BatchClarifySession, TestDesktopAsyncEventHook)> _pumpChat(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({'verbose_mode': false});
  final hook = TestDesktopAsyncEventHook();
  final session = _BatchClarifySession((event) => hook.handler?.call(event));

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'batch-clarify-fixture',
          label: 'Batch clarify fixture',
          host: 'fixture.invalid',
          port: 8000,
          apiKey: 'fixture-key',
          desktopGatewayUrl: 'http://127.0.0.1:9',
        ),
        session: const Session(
          id: _sessionId,
          title: 'Chat',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testDesktopAsyncEventHook: hook,
        testTurnApplicationSession: session,
        testApiClient: ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: 'fixture-key',
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'data': []}), 200),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  return (session, hook);
}

/// `tester.pump()` only builds a frame when one is already scheduled, so
/// post-frame work (the clarify queue opens its dialog from a post-frame
/// callback) needs an explicit frame request.
Future<void> _pumpFrames(WidgetTester tester, [Duration? step]) async {
  for (var i = 0; i < 3; i++) {
    tester.binding.scheduleFrame();
    await tester.pump(step);
  }
}

void _deliverBatchQuestion(TestDesktopAsyncEventHook hook) {
  hook.handler?.call(
    StreamEvent(
      type: 'clarify.request',
      data: {
        'request_id': 'r1',
        'questions': [
          {
            'qid': 'q1',
            'question': 'First question?',
            'choices': ['One A', 'One B'],
          },
          {
            'qid': 'q2',
            'question': 'Second question?',
            'choices': ['Two A', 'Two B'],
          },
        ],
      },
    ),
  );
}

/// The gateway cancelling a server request while its card is open or while an
/// answer is in flight (`DesktopGatewayClient` `request.cancel`).
void _deliverRequestCancel(TestDesktopAsyncEventHook hook, String requestId) {
  hook.handler?.call(
    StreamEvent(
      type: 'request.cancel',
      data: {'id': requestId, 'method': 'clarify'},
    ),
  );
}

/// A later, unrelated clarify request: the chat must still present it.
void _deliverSingleQuestion(
  TestDesktopAsyncEventHook hook, {
  required String requestId,
  required String qid,
  required String question,
}) {
  hook.handler?.call(
    StreamEvent(
      type: 'clarify.request',
      data: {
        'request_id': requestId,
        'questions': [
          {
            'qid': qid,
            'question': question,
            'choices': ['Later A', 'Later B'],
          },
        ],
      },
    ),
  );
}

void _deliverApproval(TestDesktopAsyncEventHook hook) {
  hook.handler?.call(
    StreamEvent(
      type: 'approval.request',
      data: {
        'server_request_id': 'approval-1',
        'command': 'echo safe',
        'description': 'Approve command?',
        'choices': ['once', 'deny'],
      },
    ),
  );
}

void main() {
  testWidgets('cancelled clarify below approval leaves approval open', (
    tester,
  ) async {
    final (session, hook) = await _pumpChat(tester);
    session.openBatch('r1', ['q1', 'q2']);
    _deliverBatchQuestion(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('First question?'), findsOneWidget);

    _deliverApproval(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('Approve command?'), findsOneWidget);

    _deliverRequestCancel(hook, 'r1');
    await _pumpFrames(tester, const Duration(milliseconds: 300));
    expect(find.text('First question?'), findsNothing);
    expect(find.text('Second question?'), findsNothing);
    expect(find.text('Approve command?'), findsOneWidget);
    expect(session.answers, isEmpty);
    expect(session.approvalAnswers, isEmpty);

    await tester.tap(find.byKey(const Key('approval-once')));
    await _pumpFrames(tester, const Duration(milliseconds: 300));
    expect(session.approvalAnswers, ['once']);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('clarify answer closes its own route below a newer approval', (
    tester,
  ) async {
    final (session, hook) = await _pumpChat(tester);
    session.openBatch('r1', ['q1', 'q2']);
    _deliverBatchQuestion(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('First question?'), findsOneWidget);

    session.holdNextLock();
    await tester.tap(find.byKey(const Key('clarify-choice-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester);
    expect(session.answers.single.questionId, 'q1');

    // The gateway can ask for an approval while clarify.lock is outstanding.
    _deliverApproval(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('Approve command?'), findsOneWidget);
    expect(find.text('First question?'), findsOneWidget);

    // The lock emits clarify.remaining before its response future returns.
    // Only the older clarify route may close, not approval.
    session.releaseHeldLock();
    await _pumpFrames(tester, const Duration(milliseconds: 300));
    expect(find.text('Approve command?'), findsOneWidget);
    expect(find.text('First question?'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(session.approvalAnswers, isEmpty);

    await tester.tap(find.byKey(const Key('approval-once')));
    await _pumpFrames(tester, const Duration(milliseconds: 300));
    expect(session.approvalAnswers, ['once']);
    expect(find.text('Approve command?'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);

    // The outstanding second batch question can still be answered.
    expect(find.text('Second question?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clarify-choice-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(session.answers.last.questionId, 'q2');
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('answers every question of a batch clarify request', (
    tester,
  ) async {
    final (session, hook) = await _pumpChat(tester);
    session.openBatch('r1', ['q1', 'q2']);

    _deliverBatchQuestion(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    // The first question is presented on its own card.
    expect(find.text('First question?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clarify-choice-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    expect(session.answers, hasLength(1));
    expect(session.answers.single.questionId, 'q1');
    expect(session.answers.single.answer, 'One B');

    // The chat must survive the answer: a second route pop here navigates the
    // user out of the conversation and strands the remaining question.
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Second question?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clarify-choice-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    expect(session.answers, hasLength(2));
    expect(session.answers.last.questionId, 'q2');
    expect(session.answers.last.answer, 'Two A');
    expect(find.text('Second question?'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('a cancellation mid-answer closes the card only once', (
    tester,
  ) async {
    final (session, hook) = await _pumpChat(tester);
    session.openBatch('r1', ['q1', 'q2']);

    _deliverBatchQuestion(hook);
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('First question?'), findsOneWidget);

    // The lock stays in flight while the gateway cancels the request, so the
    // cancellation closes the card the answer is being sent from.
    session.holdNextLock();
    await tester.tap(find.byKey(const Key('clarify-choice-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester);

    _deliverRequestCancel(hook, 'r1');
    // Deliberately not settled: the card's route is still animating out, which
    // is the window a late answer used to pop in.
    await _pumpFrames(tester, const Duration(milliseconds: 20));

    // The lock resolves late, as `expired`. Its card is closed already, so the
    // answer may not close a route: the surplus pop takes the chat screen (or
    // the next question's card) with it.
    session.expireHeldLock('r1');
    await _pumpFrames(tester, const Duration(milliseconds: 300));

    expect(find.text('First question?'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);

    // The conversation is still usable: a later request is presented and
    // answered.
    session.openBatch('r2', ['q3']);
    _deliverSingleQuestion(
      hook,
      requestId: 'r2',
      qid: 'q3',
      question: 'Third question?',
    );
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(find.text('Third question?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clarify-choice-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clarify-continue')));
    await _pumpFrames(tester, const Duration(milliseconds: 200));

    expect(session.answers, hasLength(2));
    expect(session.answers.last.requestId, 'r2');
    expect(session.answers.last.questionId, 'q3');
    expect(session.answers.last.answer, 'Later A');
    expect(find.text('Third question?'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
  });
}
