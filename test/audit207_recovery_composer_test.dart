import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

const _composer = Key('chat-message-composer');
const _send = Key('chat-send-message');
const _stop = Key('chat-stop-response');
const _clientA = '33333333-3333-4333-8333-333333333333';
const _clientB = '44444444-4444-4444-8444-444444444444';
const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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

  testWidgets('H1 nonterminal Stop retains callbacks through wind-down and '
      'the real terminal unlocks Send', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    await tester.enterText(find.byKey(_composer), 'Next draft');

    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    expect(session.interrupts, [_clientA]);
    session.stopResult.complete(_snapshot(text: 'Winding down'));
    await _pump(tester);
    expect(find.byKey(_stop), findsOneWidget);
    expect(session.submitted, ['Original task']);

    session.publish(_snapshot(text: 'Still winding down', seq: 2));
    await _pump(tester);
    session.publish(
      _snapshot(text: 'Final stopped output', status: 'interrupted', seq: 3),
    );
    await _pump(tester);
    expect(find.byKey(_stop), findsNothing);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(_draft(tester), 'Next draft');
    expect(find.text('Response stopped.'), findsOneWidget);
    expect(session.submitted, ['Original task']);
    // Quiet mode must not promote interrupted partial prose to a success.
    expect(find.text('Final stopped output'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('H1 Stop failure keeps the live observer and unknown outcome '
      'until an authoritative terminal', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    session.stopResult.completeError(StateError('Synthetic stop outage'));
    await _pump(tester);
    expect(find.byKey(_stop), findsOneWidget);
    expect(_button(tester, _stop).onPressed, isNotNull);
    expect(find.textContaining('Response closed locally'), findsNothing);
    expect(session.submitted, ['Original task']);

    session.publish(_snapshot(text: 'Actual final', status: 'completed'));
    await _pump(tester);
    expect(find.byKey(_stop), findsNothing);
    expect(find.text('Actual final'), findsOneWidget);
    expect(_button(tester, _send).onPressed, isNotNull);
    await _unmount(tester);
  });

  testWidgets('M3 Stop before the first v2 callback waits for its identity '
      'and interrupts exactly that turn once', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    expect(session.callbacks, hasLength(1));
    final stop = _button(tester, _stop).onPressed!;
    stop();
    stop();
    await _pump(tester);
    expect(session.interrupts, isEmpty);
    expect(find.byKey(_stop), findsOneWidget);
    expect(_button(tester, _send).onPressed, isNull);
    expect(tester.widget<TextField>(find.byKey(_composer)).enabled, isTrue);
    await tester.enterText(find.byKey(_composer), 'Draft while Stop waits');

    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    expect(session.interrupts, [_clientA]);
    session.stopResult.complete(
      _snapshot(status: 'interrupted', text: 'Stopped'),
    );
    await _pump(tester);
    expect(find.byKey(_stop), findsNothing);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(_draft(tester), 'Draft while Stop waits');
    expect(session.submitted, ['Original task']);
    await _unmount(tester);
  });

  testWidgets('M3 definite rejection before the first callback releases a '
      'queued Stop without a legacy interrupt or resend', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    session.submitResults.single.completeError(
      JsonRpcError('prompt.submit', 'Rejected', reason: 'schema_violation'),
    );
    await _pump(tester);
    expect(session.interrupts, isEmpty);
    expect(_draft(tester), 'Original task');
    expect(find.byKey(_stop), findsNothing);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(session.submitted, ['Original task']);
    await _unmount(tester);
  });

  testWidgets('M3 terminal first callback needs no interrupt and queued Stop '
      'does not reopen or resend the turn', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    final terminal = _snapshot(
      text: 'Finished before Stop',
      status: 'completed',
    );
    session.publish(terminal);
    session.finishSubmit(terminal);
    await _pump(tester);
    expect(session.interrupts, isEmpty);
    expect(find.text('Finished before Stop'), findsOneWidget);
    expect(find.byKey(_stop), findsNothing);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(session.submitted, ['Original task']);
    await _unmount(tester);
  });

  testWidgets('H1 delayed callbacks and submit completion from the stopped '
      'turn cannot overwrite a newer admission', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    await _pump(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    session.stopResult.complete(
      _snapshot(status: 'interrupted', text: 'A stopped'),
    );
    await _pump(tester);
    expect(find.byKey(_stop), findsNothing);
    await tester.enterText(find.byKey(_composer), 'New turn B');
    await tester.tap(find.byKey(_send));
    await _pump(tester);
    session.publish(_accepted(clientId: _clientB), index: 1);
    await _pump(tester);

    session.publish(_snapshot(text: 'Late A', status: 'completed'));
    session.finishSubmit(_snapshot(text: 'Late A', status: 'completed'));
    await _pump(tester);
    expect(find.text('Late A'), findsNothing);
    expect(find.byKey(_stop), findsOneWidget);
    session.publish(
      _snapshot(text: 'Actual B', status: 'completed', clientId: _clientB),
      index: 1,
    );
    session.finishSubmit(
      _snapshot(text: 'Actual B', status: 'completed', clientId: _clientB),
      index: 1,
    );
    await _pump(tester);
    expect(find.text('Actual B'), findsOneWidget);
    expect(find.byKey(_stop), findsNothing);
    expect(session.submitted, ['Original task', 'New turn B']);
    await _unmount(tester);
  });

  testWidgets('H1 Stop and send keeps its new draft and never submits while '
      'the original recovery turn is still winding down', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    await tester.enterText(find.byKey(_composer), 'Explicit next prompt');
    await tester.tap(find.byKey(_send));
    await _pump(tester);
    expect(session.interrupts, [_clientA]);
    session.stopResult.complete(_snapshot(text: 'Still active'));
    await _pump(tester);
    expect(_draft(tester), 'Explicit next prompt');
    expect(session.submitted, ['Original task']);
    session.publish(_snapshot(text: 'Stopped', status: 'interrupted'));
    await _pump(tester);
    expect(session.submitted, ['Original task']);
    expect(_draft(tester), 'Explicit next prompt');
    expect(_button(tester, _send).onPressed, isNotNull);
    await _unmount(tester);
  });

  testWidgets('H1 real terminal during a held Stop wins over its late running '
      'read-back without relocking the composer', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    session.publish(_snapshot(text: 'True final', status: 'completed', seq: 3));
    await _pump(tester);
    expect(find.byKey(_stop), findsNothing);
    expect(_button(tester, _send).onPressed, isNull);
    session.stopResult.complete(_snapshot(text: 'Stale running', seq: 2));
    await _pump(tester);
    expect(find.byKey(_stop), findsNothing);
    expect(find.text('True final'), findsOneWidget);
    expect(find.text('Stale running'), findsNothing);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(session.submitted, ['Original task']);
    await _unmount(tester);
  });

  testWidgets('M3 disposed queued Stop cannot interrupt a late admitted turn '
      'or emit UI after the route has left', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    await _unmount(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    expect(session.interrupts, isEmpty);
    expect(session.submitted, ['Original task']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('L6 attachments-only Send during recovery work gives visible '
      'feedback and preserves the staged file without interrupting', (
    tester,
  ) async {
    final session = _ControlledRecovery()..recovered = [_accepted()];
    await _mount(tester, session: session, attachments: [_attachment()]);
    expect(find.byKey(_stop), findsOneWidget);
    expect(_draft(tester), isEmpty);
    await tester.tap(find.byKey(_send));
    await _pump(tester);
    expect(
      find.text(
        'Hermes could not accept this message. Your draft was kept; '
        'stop the response or wait, then send again.',
      ),
      findsOneWidget,
    );
    expect(find.text('notes.txt'), findsOneWidget);
    expect(session.staged, isEmpty);
    expect(session.interrupts, isEmpty);
    expect(session.submitted, isEmpty);
    await _unmount(tester);
  });

  testWidgets('L5 nonterminal recovery Stop releases the visible Stop and '
      'Send gates without requiring another transport callback', (
    tester,
  ) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    session.stopResult.complete(_snapshot(text: 'Winding down'));
    await _pump(tester);
    expect(find.byKey(_stop), findsOneWidget);
    expect(_button(tester, _stop).onPressed, isNotNull);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(session.interrupts, [_clientA]);
    await _unmount(tester);
  });

  testWidgets('L5 failed Stop releases Send without a subsequent transport '
      'callback, text edit, or history refresh', (tester) async {
    final session = _ControlledRecovery();
    await _mount(tester, session: session);
    await _start(tester);
    session.publish(_accepted());
    session.finishSubmit(_accepted());
    await _pump(tester);
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    expect(_button(tester, _send).onPressed, isNull);
    session.stopResult.completeError(StateError('Synthetic Stop failure'));
    await _pump(tester);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(session.submitted, ['Original task']);
    await _unmount(tester);
  });

  testWidgets('L5 joined REST cancellation rebuilds Send after its Stop '
      'flight releases, without unrelated text or history changes', (
    tester,
  ) async {
    final rest = _HeldCancellation();
    addTearDown(() {
      if (!rest.release.isCompleted) rest.release.complete();
    });
    await _mount(tester, rest: rest);
    await _start(tester);
    expect(rest.prompts, hasLength(1));
    await tester.tap(find.byKey(_stop));
    await _pump(tester);
    expect(rest.cancelEntered.isCompleted, isTrue);
    expect(_button(tester, _send).onPressed, isNull);
    ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).showSnackBar(
      const SnackBar(
        content: Text('Existing status'),
        duration: Duration(hours: 1),
      ),
    );
    await tester.pumpAndSettle();
    rest.release.complete();
    await _pump(tester);
    expect(_button(tester, _send).onPressed, isNotNull);
    expect(rest.prompts, hasLength(1));
    expect(rest.historyReads, 1);
    await _unmount(tester);
  });
}

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));
String _draft(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composer)).controller!.text;

Future<void> _pump(WidgetTester tester) async {
  // Yield I/O zones for real SSE cancellation, never use wall-clock sleeps.
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<void> _start(WidgetTester tester) async {
  await tester.enterText(find.byKey(_composer), 'Original task');
  await tester.tap(find.byKey(_send));
  await _pump(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pump(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _mount(
  WidgetTester tester, {
  _ControlledRecovery? session,
  http.Client? rest,
  List<AttachmentDraft> attachments = const [],
}) async {
  final controller = GatewayTurnApplicationController();
  addTearDown(controller.close);
  if (session != null) addTearDown(session.close);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'audit207-composer',
          label: 'Audit fixture',
          host: 'audit207.invalid',
          port: 8642,
          apiKey: 'synthetic',
        ),
        session: const Session(
          id: 'local-audit207',
          title: 'Fixture chat',
          model: 'fixture',
          source: 'mobile',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
          isLocalDraft: true,
        ),
        turnApplicationController: controller,
        testTurnApplicationSession: session,
        testInitialAttachmentDrafts: attachments,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testApiClient: ApiClient(
          baseUrl: 'http://audit207.invalid',
          apiKey: 'synthetic',
          httpClient:
              rest ??
              MockClient((_) async => http.Response('{"data":[]}', 200)),
        ),
      ),
    ),
  );
  await _pump(tester);
  // Drain only opening scroll scheduling; turn order is controlled by gates.
  await tester.pump(const Duration(milliseconds: 100));
  await _pump(tester);
}

GatewayTurnRecoveryState _accepted({String clientId = _clientA}) =>
    GatewayTurnRecoveryState.initial(
      clientTurnId: clientId,
    ).markSubmissionStarted().applyAck(
      GatewayTurnAck(
        clientTurnId: clientId,
        turnId: 'turn-$clientId',
        status: GatewayRecoveryTurnStatus.accepted,
        lastSeq: 0,
        created: true,
      ),
    );

GatewayTurnRecoveryState _snapshot({
  String text = 'Winding down',
  String status = 'running',
  int seq = 1,
  String clientId = _clientA,
}) {
  final terminal = ['completed', 'interrupted', 'failed'].contains(status);
  if (!terminal) {
    final page = GatewayTurnReconcilePage.fromWire(
      {
        'automatic_resubmit': false,
        'mode': 'events',
        'turn_id': 'turn-$clientId',
        'status': status,
        'earliest_seq': 1,
        'last_seq': seq,
        'next_after_seq': seq,
        'has_more': false,
        'events': [
          for (var i = 1; i <= seq; i++)
            {
              'turn_id': 'turn-$clientId',
              'seq': i,
              'message_id': 'message-$clientId',
              'type': 'message.delta',
              'payload': {'text': i == 1 ? text : ''},
            },
        ],
      },
      expectedAfterSeq: 0,
      expectedTurnId: 'turn-$clientId',
      expectedClientTurnId: clientId,
    )!;
    return _accepted(clientId: clientId).applyReconcilePage(page);
  }
  final page = GatewayTurnReconcilePage.fromWire(
    {
      'automatic_resubmit': false,
      'mode': 'snapshot',
      'earliest_seq': 1,
      'last_seq': seq,
      'next_after_seq': seq,
      'has_more': false,
      'snapshot': {
        'turn_id': 'turn-$clientId',
        'client_turn_id': clientId,
        'status': status,
        'last_seq': seq,
        'assistant': {
          'message_id': 'message-$clientId',
          'text': text,
          'complete': terminal,
        },
        'attachment_manifest_digest': _digest,
        if (terminal) 'final_message_ref': 7,
      },
    },
    expectedAfterSeq: 0,
    expectedTurnId: 'turn-$clientId',
    expectedClientTurnId: clientId,
  )!;
  return _accepted(clientId: clientId).applyReconcilePage(page);
}

AttachmentDraft _attachment() => AttachmentDraft(
  id: 'audit207-file',
  cachedPath: 'synthetic-file',
  name: 'notes.txt',
  byteLength: 4,
  mediaType: 'text/plain',
  kind: AttachmentDraftKind.genericFile,
);

class _ControlledRecovery implements GatewayTurnApplicationSession {
  List<GatewayTurnRecoveryState> recovered = [];
  final callbacks = <GatewayTurnStateCallback?>[];
  final submitResults = <Completer<GatewayTurnRecoveryState>>[];
  final stopResult = Completer<GatewayTurnRecoveryState>();
  final submitted = <String>[];
  final interrupts = <String>[];
  final staged = <String>[];

  void publish(GatewayTurnRecoveryState state, {int index = 0}) =>
      callbacks[index]?.call(state);
  void finishSubmit(GatewayTurnRecoveryState state, {int index = 0}) =>
      submitResults[index].complete(state);

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) {
    submitted.add(text);
    callbacks.add(onState);
    final result = Completer<GatewayTurnRecoveryState>();
    submitResults.add(result);
    return result.future;
  }

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async {
    if (recovered.isNotEmpty) callbacks.add(onState);
    for (final state in recovered) {
      onState?.call(state);
    }
    return recovered;
  }

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) {
    interrupts.add(clientTurnId);
    return stopResult.future;
  }

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) async {
    staged.add(name);
    throw StateError('No attachment should be staged during active work.');
  }

  @override
  Object setAsyncEventListener(String id, DesktopAsyncEventCallback listener) =>
      Object();
  @override
  Object setTurnSettledListener(
    String id,
    GatewayTurnSettledCallback listener,
  ) => Object();
  @override
  Object setSessionBoundListener(
    String id,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();
  @override
  void removeAsyncEventListener(String id, Object registration) {}
  @override
  void removeTurnSettledListener(String id, Object registration) {}
  @override
  void removeSessionBoundListener(String id, Object registration) {}
  @override
  bool get hasActiveTurn => false;
  @override
  Object addTurnActivityListener(void Function() listener) => Object();
  @override
  void removeTurnActivityListener(Object token) {}
  @override
  Future<void> close() async {
    final terminal = _snapshot(text: 'Fixture teardown', status: 'interrupted');
    for (final result in submitResults) {
      if (!result.isCompleted) result.complete(terminal);
    }
    if (!stopResult.isCompleted) stopResult.complete(terminal);
  }

  @override
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) => false;
  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async => false;
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
  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) async {}
}

class _HeldCancellation extends http.BaseClient {
  final cancelEntered = Completer<void>();
  final release = Completer<void>();
  final prompts = <String>[];
  int historyReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/v1/chat/completions')) {
      prompts.add(await request.finalize().bytesToString());
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelEntered.complete();
          return release.future;
        },
      );
      return http.StreamedResponse(
        body.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    if (request.url.path.endsWith('/messages')) historyReads++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"data":[]}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
