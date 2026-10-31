import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_approval.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/gateway_approval_dialog.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/recording_turn_notification_sink.dart';

const _priorChatKey = Key('prior-chat');
const _targetChatKey = Key('notification-target-chat');
const _targetSessionId = 'approval-target-session';
const _requestId = 'approval-route-fixture:1';

void main() {
  for (final cancelDuringResponse in [false, true]) {
    testWidgets(
      cancelDuringResponse
          ? 'server cancellation during Deny keeps notification-targeted chat'
          : 'normal approval Deny closes only its dialog and keeps notification-targeted chat',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({'verbose_mode': false});
        final connection = SavedConnection(
          id: 'approval-route-fixture',
          label: 'Approval route fixture',
          host: 'fixture.invalid',
          port: 8642,
          apiKey: '',
          desktopGatewayUrl: 'http://fixture.invalid:8642',
        );
        final gateway = _HeldApprovalClient();
        final notifications = TurnNotificationService(
          sink: RecordingTurnNotificationSink(),
        );
        final normal = NormalGatewayApplicationSession(
          connection: connection,
          scope: 'approval-route-fixture',
          client: gateway,
          notifications: notifications,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async =>
                  throw StateError('This test must not submit a prompt.'),
          resume: ({required localSessionId, required storedSessionId}) async =>
              const ResumedGatewaySession(
                runtimeSessionId: 'fixture-runtime',
                running: false,
                status: 'completed',
              ),
          history: (_) async => [],
        );
        final controller = _NormalOwnerController(normal);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          if (!gateway.response.isCompleted) gateway.response.complete();
          await controller.close();
          await tester.pump();
        });
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _RouteObserver();

        ChatScreen chat(String id, String title, Key key) => ChatScreen(
          key: key,
          connection: connection,
          session: Session(
            id: id,
            title: title,
            model: 'fixture',
            source: 'test',
            messageCount: 0,
            isActive: true,
            preview: '',
            startedAt: 1,
          ),
          turnApplicationController: controller,
          testTurnNotifications: notifications,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          testProjectOverviewLoader: () async => ProjectsTreeOverview.empty,
          testApiClient: ApiClient(
            baseUrl: connection.baseUrl,
            apiKey: '',
            httpClient: MockClient((request) async {
              if (request.url.path.endsWith('/messages')) {
                return http.Response(jsonEncode({'data': []}), 200);
              }
              return http.Response(
                jsonEncode({
                  'session': {'id': id, 'archived': false},
                }),
                200,
              );
            }),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [observer],
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: chat('prior-session', 'Prior chat', _priorChatKey),
          ),
        );
        await _pumpFrames(tester);
        await normal.ready;

        // Reproduce the stack a notification body tap leaves behind: the old
        // ChatScreen stays mounted beneath a newly pushed target ChatScreen.
        // Notification parsing/platform delivery is intentionally not exercised.
        // Use bool, not void, so an erroneous pop(true) is observed as navigation
        // loss rather than an unrelated route-result type error.
        final targetRoute = MaterialPageRoute<bool>(
          settings: const RouteSettings(name: '/notification-target-chat'),
          builder: (_) => chat(_targetSessionId, 'Target chat', _targetChatKey),
        );
        unawaited(navigatorKey.currentState!.push(targetRoute));
        await _pumpFrames(tester, const Duration(milliseconds: 400));
        expect(targetRoute.isCurrent, isTrue);
        expect(find.byKey(_targetChatKey), findsOneWidget);
        expect(find.byKey(_priorChatKey), findsNothing);
        expect(find.byKey(_priorChatKey, skipOffstage: false), findsOneWidget);

        // Only transport delivery is faked. Both pending-input retention and
        // tryRespondToApproval's cleanup/notify are the real normal owner.
        normal.receiveEvent(
          _targetSessionId,
          StreamEvent(
            type: 'approval.request',
            data: const {
              'server_request_id': _requestId,
              'command': 'echo fixture',
              'description': 'Approve fixture command?',
              'choices': ['once', 'deny'],
            },
          ),
        );
        await _pumpFrames(tester, const Duration(milliseconds: 200));
        expect(find.byType(GatewayApprovalDialog), findsOneWidget);
        final dialogRoute = observer.pushed
            .whereType<DialogRoute<bool>>()
            .single;
        final owner = normal.findChat(_targetSessionId)!;
        expect(owner.snapshot.pendingInput, hasLength(1));

        await tester.tap(find.byKey(const Key('approval-deny')));
        await tester.pump();
        expect(gateway.answers, [
          (sessionId: _targetSessionId, requestId: _requestId, choice: 'deny'),
        ]);
        expect(owner.snapshot.pendingInput, hasLength(1));
        expect(dialogRoute.isCurrent, isTrue);
        expect(observer.dismissed, isEmpty);
        await tester.tap(find.byKey(const Key('approval-deny')));
        await tester.pump();
        expect(
          gateway.answers,
          hasLength(1),
          reason: 'In-flight taps are disabled.',
        );

        // Do not manually cancel/remove the dialog, nor pump between response
        // completion and the async continuations. Production normal-owner
        // cleanup removes pending input, synchronously notifies ChatScreen,
        // synthesizes request.cancel and removes the owned dialog route before
        // GatewayApprovalDialog's awaited onRespond has returned. The widget is
        // still mounted until the next frame; mounted alone cannot own a pop.
        if (cancelDuringResponse) {
          normal.receiveEvent(
            _targetSessionId,
            StreamEvent(
              type: 'request.cancel',
              data: const {'id': _requestId, 'method': 'approval'},
            ),
          );
          // Complete in the same frame, while the removed dialog can be mounted.
        }
        gateway.response.complete();
        await _pumpFrames(tester, const Duration(milliseconds: 400));

        expect(
          gateway.answers,
          hasLength(1),
          reason: 'Deny must send only once.',
        );
        expect(owner.snapshot.pendingInput, isEmpty);
        expect(find.byType(GatewayApprovalDialog), findsNothing);
        expect(
          observer.dismissed.where((route) => identical(route, dialogRoute)),
          hasLength(1),
          reason: 'The approval dialog must close exactly once.',
        );
        expect(
          targetRoute.isCurrent,
          isTrue,
          reason:
              'Approval completion must not pop the notification-targeted '
              'ChatScreen and reveal the prior chat.',
        );
        expect(observer.dismissed, isNot(contains(same(targetRoute))));
        expect(find.byKey(_targetChatKey), findsOneWidget);
        expect(find.byKey(_priorChatKey), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('approval response closes its own route below a newer prompt', (
    tester,
  ) async {
    final response = Completer<void>();
    var sends = 0;
    final navigatorKey = GlobalKey<NavigatorState>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!response.isCompleted) response.complete();
      await tester.pump();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Underlying chat')),
      ),
    );
    final navigator = navigatorKey.currentState!;
    final approvalRoute = DialogRoute<bool>(
      context: navigator.context,
      builder: (_) => GatewayApprovalDialog(
        request: GatewayApprovalRequest.fromEventData({
          'command': 'echo fixture',
          'choices': ['deny'],
        }),
        onRespond: (_) async {
          sends++;
          await response.future;
        },
      ),
    );
    unawaited(navigator.push(approvalRoute));
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('approval-deny')));
    await tester.pump();
    expect(sends, 1);

    final newerRoute = DialogRoute<bool>(
      context: navigator.context,
      builder: (_) => const AlertDialog(title: Text('Newer prompt')),
    );
    unawaited(navigator.push(newerRoute));
    await _pumpFrames(tester, const Duration(milliseconds: 200));
    expect(newerRoute.isCurrent, isTrue);

    response.complete();
    await _pumpFrames(tester, const Duration(milliseconds: 400));
    expect(
      newerRoute.isCurrent,
      isTrue,
      reason: 'The older approval response must not pop a newer prompt.',
    );
    expect(approvalRoute.isActive, isFalse);
    expect(find.text('Newer prompt'), findsOneWidget);
    expect(sends, 1);
    expect(tester.takeException(), isNull);
  });
}

// Explicit frame scheduling also flushes ChatScreen's post-frame prompt queue.
// Avoid pumpAndSettle while the intentionally held response shows a spinner.
Future<void> _pumpFrames(
  WidgetTester tester, [
  Duration step = const Duration(milliseconds: 20),
]) async {
  for (var i = 0; i < 3; i++) {
    tester.binding.scheduleFrame();
    await tester.pump(step);
  }
}

class _RouteObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  final dismissed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    dismissed.add(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    dismissed.add(route);
  }
}

// Supply a real NormalGatewayApplicationSession through the existing app-owner
// injection seam, without constructing any production network transport.
class _NormalOwnerController extends GatewayTurnApplicationController {
  _NormalOwnerController(this.normal);

  final NormalGatewayApplicationSession normal;

  @override
  NormalGatewayApplicationSession normalSessionFor(
    SavedConnection connection, {
    NormalGatewayPromptSubmit? submit,
    NormalGatewaySteer? steer,
    NormalGatewayResume? resume,
    NormalGatewayHistory? history,
    TurnNotificationService? notifications,
  }) => normal;

  @override
  Future<void> close() async {
    await normal.close();
    await super.close();
  }
}

// A controlled in-memory approval transport, not a fake normal owner. No WS,
// HTTP, device or notification-platform operations are performed by this fake.
class _HeldApprovalClient implements DesktopGatewayClient {
  final response = Completer<void>();
  final answers = <({String sessionId, String? requestId, String choice})>[];
  bool _unresolved = true;

  @override
  bool ownsApprovalRequest(String sessionId, {String? requestId}) =>
      _unresolved &&
      sessionId == _targetSessionId &&
      (requestId == null || requestId == _requestId);

  @override
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
    String? serverRequestId,
  }) async {
    answers.add((
      sessionId: sessionId,
      requestId: serverRequestId,
      choice: choice,
    ));
    await response.future;
    _unresolved = false;
  }

  @override
  void setSessionBoundListener(
    GatewayTurnSessionBoundCallback? listener, {
    GatewayTurnSessionBoundCallback? onCreated,
  }) {}

  @override
  void setSessionEventListener(DesktopAsyncEventCallback? listener) {}

  @override
  void setAsyncEventListener(
    DesktopAsyncEventCallback? listener, {
    DesktopAsyncEventSessionPredicate? acceptsSession,
  }) {}

  @override
  void setConnectionListener(DesktopConnectionCallback? listener) {}

  @override
  void setReconnectAllowed(bool allowed) {}

  @override
  void bindStoredSession(String localSessionId, String storedSessionId) {}

  @override
  String? storedSessionKeyFor(String mobileSessionId) => mobileSessionId;

  @override
  Future<void> ensureSession(
    String sessionId, {
    String? workingDirectory,
  }) async {}

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected gateway call: ${invocation.memberName}',
  );
}
