import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/controllers/hands_free_conversation_controller.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/widgets/hands_free_voice_controls.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/hands_free_route_observer.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_hands_free_voice.dart';
import 'support/fake_voice_composer_adapter.dart';

class _HttpFixture extends http.BaseClient {
  final stream = StreamController<List<int>>.broadcast();
  int posts = 0;
  final sent = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> history = [
    {'id': 1, 'role': 'assistant', 'content': 'historic answer'},
  ];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      posts++;
      sent.add(
        jsonDecode((request as http.Request).body) as Map<String, dynamic>,
      );
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'data': history}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  void done([String text = 'owned REST public final']) {
    final token = jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    });
    final terminal = jsonEncode({
      'choices': [
        {'delta': {}, 'finish_reason': 'stop'},
      ],
    });
    stream.add(utf8.encode('data: $token\n\n'));
    stream.add(utf8.encode('data: $terminal\n\ndata: [DONE]\n\n'));
  }

  void error() => stream.add(
    utf8.encode(
      'event: error\ndata: {"error":{"message":"refused","type":"permission_denied"}}\n\n',
    ),
  );
}

class _Rig {
  _Rig(this.kind);
  final String kind;
  final native = FakeHandsFreeVoicePlatform();
  final speaker = FakeVoiceReplySpeaker();
  final manual = FakeVoiceComposerAdapter();
  final httpFixture = _HttpFixture();
  final navigator = GlobalKey<NavigatorState>();
  final recoverable = _RecoveryFixture();
  final remoteDone = Completer<void>();
  StreamCallback? remoteEvent;
  int remotePosts = 0;
  String? remoteText;
  final active = ValueNotifier(true);
  SavedConnection get connection => SavedConnection(
    id: 'hf-$kind',
    label: 'Voice fixture',
    host: 'voice.fixture',
    port: 8642,
    apiKey: 'fixture-only',
  );
  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    final api = ApiClient(
      baseUrl: 'http://voice.fixture',
      apiKey: 'fixture-only',
      httpClient: httpFixture,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        navigatorObservers: [handsFreeRouteObserver],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ValueListenableBuilder(
          valueListenable: active,
          builder: (context, visible, _) => ChatScreen(
            connection: connection,
            active: visible,
            session: const Session(
              id: 'voice-chat',
              title: 'Voice chat',
              model: 'unchanged-model',
              source: 'test',
              messageCount: 1,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: api,
            testVoiceComposerAdapter: manual,
            testHandsFreePlatform: native,
            testVoiceReplySpeaker: speaker,
            testTurnApplicationSession: kind == 'recovery' ? recoverable : null,
            testRemotePromptSubmit: kind == 'normal'
                ? ({
                    required sessionId,
                    required text,
                    required onEvent,
                    required onSent,
                  }) async {
                    remotePosts++;
                    remoteText = text;
                    remoteEvent = onEvent;
                    onSent();
                    onEvent(
                      StreamEvent(
                        type: 'message.start',
                        data: const {},
                        turnId: 'wire-owned',
                      ),
                    );
                    await remoteDone.future;
                  }
                : null,
            testNormalResume:
                ({required localSessionId, required storedSessionId}) async =>
                    const ResumedGatewaySession(
                      runtimeSessionId: 'wire-runtime',
                      running: false,
                    ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('hands-free-start')));
    await tester.tap(find.byKey(const Key('hands-free-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hands-free-confirm-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(native.count('armWake'), 1);
    native.armed();
    await tester.pump();
  }

  Future<void> prompt(WidgetTester tester) async {
    native.wake();
    await tester.pump();
    native.ready();
    native.emit('speechResult', {
      'transcript': 'preview only',
      'isFinal': false,
    });
    await tester.pump();
    expect(composer(tester).text, isEmpty);
    expect(httpFixture.posts + remotePosts + recoverable.submits, 0);
    native.finalAndEnd('spoken prompt');
    await tester.pump();
    await tester.pump();
  }

  TextEditingController composer(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('chat-message-composer')))
      .controller!;
  Future<void> finish(
    WidgetTester tester, [
    String text = 'owned public final',
  ]) async {
    if (kind == 'rest') {
      expect(
        httpFixture.stream.hasListener,
        isTrue,
        reason: 'SSE body listener ready',
      );
      httpFixture.done(text);
      await httpFixture.stream.close();
    } else if (kind == 'normal') {
      remoteEvent!(
        StreamEvent(
          type: 'message.delta',
          data: {'text': text},
          turnId: 'wire-owned',
        ),
      );
      remoteEvent!(
        StreamEvent(
          type: 'message.complete',
          data: {'text': text, 'status': 'completed'},
          turnId: 'wire-owned',
        ),
      );
      remoteEvent!(
        StreamEvent(
          type: 'turn.end',
          data: const {'status': 'completed'},
          turnId: 'wire-owned',
        ),
      );
    } else {
      recoverable.emit(_recoveryState(text: text));
    }
    // The real SSE parser joins StreamSubscription.cancel in the root zone.
    // Drain that boundary explicitly; this is not a timing-based sleep.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    if (!remoteDone.isCompleted) remoteDone.complete();
    if (!recoverable.done.isCompleted) {
      recoverable.done.complete(_recoveryState());
    }
    if (!httpFixture.stream.isClosed) await httpFixture.stream.close();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await native.stream.close();
    active.dispose();
  }
}

void main() {
  for (final phase in ['wake', 'waiting', 'playback']) {
    testWidgets('HF05 compact keyboard retains editor and Stop during $phase', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig('rest');
      await rig.pump(tester, textScale: 2);
      await rig.start(tester);
      if (phase != 'wake') await rig.prompt(tester);
      if (phase == 'playback') {
        rig.speaker.held = Completer<HandsFreeSpeechOutcome>();
        await rig.finish(tester);
        expect(rig.speaker.playing, isTrue);
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      await tester.pump();
      final stop = find.byKey(const Key('hands-free-quick-stop'));
      expect(stop.hitTestable(), findsOneWidget);
      expect(tester.getSize(stop), const Size(48, 48));
      expect(tester.getRect(stop).bottom, lessThanOrEqualTo(520));
      expect(
        tester.getSize(find.byKey(const Key('chat-message-composer'))).width,
        greaterThan(80),
      );
      if (phase == 'waiting') {
        final responseStop = find.byKey(const Key('chat-stop-response'));
        final send = find.byKey(const Key('chat-send-message'));
        expect(responseStop.hitTestable(), findsOneWidget);
        expect(send.hitTestable(), findsOneWidget);
        expect(tester.getSize(responseStop), const Size(48, 48));
        expect(tester.getSize(send), const Size(48, 48));
        expect(tester.getRect(stop).overlaps(tester.getRect(send)), isFalse);
      }
      await tester.tap(stop);
      await tester.pump();
      expect(rig.native.audio, 'none');
      expect(rig.speaker.playing, isFalse);
      expect(tester.takeException(), isNull);
      await rig.close(tester);
    });
  }
  testWidgets('HF05 fixed Stop stays visible at compact width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rig = _Rig('rest');
    await rig.pump(tester, textScale: 2);
    await rig.start(tester);
    expect(
      find.byKey(const Key('hands-free-quick-stop')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('hands-free-quick-stop')));
    await tester.pump();
    expect(rig.native.audio, 'none');
    expect(tester.takeException(), isNull);
    await rig.close(tester);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        ),
  );
  for (final kind in ['rest', 'normal', 'recovery']) {
    testWidgets(
      'HF04 $kind exact local voice turn speaks once, never history/sibling/duplicate',
      (tester) async {
        final rig = _Rig(kind);
        await rig.pump(tester);
        expect(rig.native.calls, isEmpty);
        expect(rig.speaker.texts, isEmpty);
        await rig.start(tester);
        await rig.prompt(tester);
        expect(
          rig.httpFixture.posts + rig.remotePosts + rig.recoverable.submits,
          1,
        );
        expect(rig.composer(tester).text, isEmpty);
        // Same-text old/sibling snapshots cannot acquire this binding.
        if (kind == 'recovery') {
          rig.recoverable.globalState?.call(
            _recoveryState(
              id: '44444444-4444-4444-8444-444444444444',
              text: 'sibling',
            ),
          );
        }
        if (kind == 'normal') {
          rig.remoteEvent!(
            StreamEvent(
              type: 'message.complete',
              data: const {'text': 'sibling'},
              turnId: 'other-wire',
            ),
          );
        }
        await tester.pump();
        expect(rig.speaker.texts, isEmpty);
        rig.speaker.held = Completer();
        await rig.finish(tester);
        expect(find.byKey(const Key('chat-stop-response')), findsNothing);
        expect(
          rig.speaker.texts,
          ['owned public final'],
          reason:
              '${tester.widget<HandsFreeVoiceControls>(find.byType(HandsFreeVoiceControls)).controller.state} / ${tester.widget<HandsFreeVoiceControls>(find.byType(HandsFreeVoiceControls)).controller.errorCode}',
        );
        expect(rig.native.audio, 'none');
        if (kind != 'rest') await rig.finish(tester);
        expect(rig.speaker.texts, hasLength(1));
        rig.speaker.held!.complete(HandsFreeSpeechOutcome.completed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 299));
        expect(rig.native.count('recognizeOnce'), 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(rig.native.count('recognizeOnce'), 2);
        await rig.close(tester);
      },
    );
    testWidgets(
      'HF04 $kind newer manual draft revokes voice without clearing or resending',
      (tester) async {
        final rig = _Rig(kind);
        await rig.pump(tester);
        await rig.start(tester);
        await rig.prompt(tester);
        await tester.enterText(
          find.byKey(const Key('chat-message-composer')),
          'new manual edit',
        );
        await tester.pump();
        await rig.finish(tester);
        expect(rig.speaker.texts, isEmpty);
        expect(rig.composer(tester).text, 'new manual edit');
        expect(
          rig.httpFixture.posts + rig.remotePosts + rig.recoverable.submits,
          1,
        );
        expect(rig.native.audio, 'none');
        await rig.close(tester);
      },
    );
  }
  testWidgets('HF04 REST in-band failure cannot speak an old history answer', (
    tester,
  ) async {
    final rig = _Rig('rest');
    await rig.pump(tester);
    await rig.start(tester);
    await rig.prompt(tester);
    rig.httpFixture.error();
    await rig.httpFixture.stream.close();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
    expect(rig.speaker.texts, isEmpty);
    expect(rig.httpFixture.posts, 1);
    expect(rig.composer(tester).text, isEmpty);
    await rig.close(tester);
  });
  for (final kind in ['normal', 'recovery']) {
    for (final outcome in ['failed', 'unknown', 'needsInput', 'hidden']) {
      testWidgets('HF04 $kind $outcome terminal cannot speak or resend', (
        tester,
      ) async {
        final rig = _Rig(kind);
        await rig.pump(tester);
        await rig.start(tester);
        await rig.prompt(tester);
        if (kind == 'normal') {
          switch (outcome) {
            case 'failed':
              rig.remoteEvent!(
                StreamEvent(
                  type: 'turn.error',
                  data: const {'message': 'fixture failure'},
                  turnId: 'wire-owned',
                ),
              );
            case 'unknown':
              rig.remoteDone.complete();
            case 'needsInput':
              rig.remoteEvent!(
                StreamEvent(
                  type: 'approval.request',
                  data: const {
                    'server_request_id': 'fixture:42',
                    'command': 'test',
                  },
                  turnId: 'wire-owned',
                ),
              );
            case 'hidden':
              rig.remoteEvent!(
                StreamEvent(
                  type: 'message.complete',
                  data: const {
                    'text': 'private model text',
                    'status': 'completed',
                    'display_content': '',
                    'display_kind': 'hidden',
                  },
                  turnId: 'wire-owned',
                ),
              );
              rig.remoteEvent!(
                StreamEvent(
                  type: 'turn.end',
                  data: const {'status': 'completed'},
                  turnId: 'wire-owned',
                ),
              );
          }
        } else {
          rig.recoverable.emit(
            outcome == 'unknown'
                ? _recoveryState().failReconcile(
                    GatewayTurnRecoveryFailure.protocolViolation,
                  )
                : _recoveryState(
                    status: outcome == 'needsInput'
                        ? 'waiting_input'
                        : outcome == 'hidden'
                        ? 'completed'
                        : 'failed',
                    text: outcome == 'hidden' ? '' : 'fixture output',
                  ),
          );
        }
        await tester.pump();
        await tester.pump();
        expect(rig.speaker.texts, isEmpty);
        expect(rig.native.audio, 'none');
        expect(rig.remotePosts + rig.recoverable.submits, 1);
        await rig.close(tester);
      });
    }
  }
  for (final action in [
    'covered',
    'tab',
    'inactive',
    'paused',
    'account',
    'pop',
    'root replacement',
  ]) {
    testWidgets(
      'HF05 $action revokes held model/native Start; resume never restarts',
      (tester) async {
        final rig = _Rig('rest');
        await rig.pump(tester);
        final load = rig.native.holds['armWake'] = Completer();
        await rig.start(tester);
        ConnectionMutationLease? lease;
        switch (action) {
          case 'covered':
            unawaited(
              showDialog<void>(
                context: tester.element(find.byType(ChatScreen)),
                builder: (_) => const AlertDialog(content: Text('Covered')),
              ),
            );
          case 'tab':
            rig.active.value = false;
          case 'inactive':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
          case 'paused':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
          case 'account':
            lease = ConnectionMutationBarrier.begin([rig.connection.id]);
          case 'pop':
            rig.navigator.currentState!.pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Elsewhere')),
              ),
            );
          case 'root replacement':
            await tester.pumpWidget(
              MaterialApp(
                key: const ValueKey('replacement-root'),
                navigatorObservers: [handsFreeRouteObserver],
                home: const Scaffold(body: Text('New root')),
              ),
            );
        }
        await tester.pump();
        expect(rig.native.revoked, isNotEmpty);
        load.complete();
        await tester.pump();
        expect(rig.native.audio, 'none');
        expect(rig.native.count('stop'), greaterThanOrEqualTo(1));
        if (action == 'covered') {
          rig.navigator.currentState!.pop();
        }
        rig.active.value = true;
        lease?.release();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(rig.native.count('armWake'), 1);
        expect(rig.speaker.texts, isEmpty);
        await rig.close(tester);
      },
    );
  }
  testWidgets(
    'HF05 already paused root never captures; resumed draft refuses Start',
    (tester) async {
      final rig = _Rig('rest');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await rig.pump(tester);
      expect(rig.native.calls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rig.native.calls, isEmpty);
      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'keep me',
      );
      await tester.tap(find.byKey(const Key('hands-free-start')));
      await tester.pump();
      expect(rig.native.calls, isEmpty);
      expect(rig.composer(tester).text, 'keep me');
      await rig.close(tester);
    },
  );
}

const _client = '33333333-3333-4333-8333-333333333333';
GatewayTurnRecoveryState _recoveryState({
  String id = _client,
  String text = 'owned public final',
  String status = 'completed',
}) {
  final initial = GatewayTurnRecoveryState.initial(clientTurnId: id)
      .markSubmissionStarted()
      .applyAck(
        GatewayTurnAck(
          clientTurnId: id,
          turnId: 'turn-recovery',
          status: GatewayRecoveryTurnStatus.accepted,
          lastSeq: 0,
          created: true,
        ),
      );
  if (status == 'waiting_input') {
    return initial.applyEvent(
      const GatewayTurnEvent(
        turnId: 'turn-recovery',
        seq: 1,
        messageId: 'reply',
        type: 'turn.status',
        payload: {'status': 'waiting_input'},
      ),
    );
  }
  final page = GatewayTurnReconcilePage.fromWire(
    {
      'automatic_resubmit': false,
      'mode': 'snapshot',
      'earliest_seq': 1,
      'last_seq': 4,
      'next_after_seq': 4,
      'has_more': false,
      'snapshot': {
        'turn_id': 'turn-recovery',
        'client_turn_id': id,
        'status': status,
        'last_seq': 4,
        'assistant': {'message_id': 'reply', 'text': text, 'complete': true},
        'attachment_manifest_digest':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'final_message_ref': 7,
      },
    },
    expectedAfterSeq: 0,
    expectedTurnId: 'turn-recovery',
    expectedClientTurnId: id,
  )!;
  return initial.applyReconcilePage(page);
}

class _RecoveryFixture
    implements GatewayTurnApplicationSession, GuardedGatewayTurnSubmission {
  int submits = 0;
  final done = Completer<GatewayTurnRecoveryState>();
  GatewayTurnStateCallback? callback;
  GatewayTurnStateCallback? globalState;
  void emit(GatewayTurnRecoveryState state) {
    callback?.call(state);
  }

  @override
  Future<GatewayTurnRecoveryState> submitGuarded({
    required String localSessionId,
    required String text,
    required bool Function() maySubmit,
    GatewayTurnStateCallback? onState,
  }) async {
    if (!maySubmit()) throw const GatewayTurnAdmissionRevoked();
    submits++;
    callback = onState;
    onState?.call(
      GatewayTurnRecoveryState.initial(
        clientTurnId: _client,
      ).markSubmissionStarted().applyAck(
        const GatewayTurnAck(
          clientTurnId: _client,
          turnId: 'turn-recovery',
          status: GatewayRecoveryTurnStatus.accepted,
          lastSeq: 0,
          created: true,
        ),
      ),
    );
    return done.future;
  }

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async {
    globalState = onState;
    return [];
  }

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) => Object();
  @override
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) => Object();
  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();
  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {}
  @override
  void removeTurnSettledListener(String localSessionId, Object registration) {}
  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
