import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/completed_stock_turn.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

const _clientTurnId = '123e4567-e89b-42d3-a456-426614174000';
const _turnId = 'server-turn';
const _messageId = 'server-assistant-message';
const _manifestDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  test('recovery v2 is reserved for local drafts, not server sessions', () {
    const serverSession = Session(
      id: 'server-existing',
      title: 'Existing chat',
      model: 'hermes-agent',
      source: 'gateway',
      messageCount: 4,
      isActive: false,
      preview: 'Earlier message',
      startedAt: 1,
    );
    const localDraft = Session(
      id: 'mobile-draft',
      title: 'New chat',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: 2,
      isLocalDraft: true,
    );

    expect(shouldUseRecoveryV2ForSession(serverSession), isFalse);
    expect(shouldUseRecoveryV2ForSession(localDraft), isTrue);
    // session.open has no cwd: a Project draft must use stock
    // session.create(cwd) rather than silently becoming Unassigned.
    expect(
      shouldUseRecoveryV2ForSession(
        localDraft,
        projectWorkingDirectory: ' /srv/projects/work ',
      ),
      isFalse,
    );
    expect(
      shouldEstablishLegacyDesktopSession(
        serverSession,
        legacyTransportFallback: false,
      ),
      isTrue,
    );
    expect(
      shouldEstablishLegacyDesktopSession(
        localDraft,
        legacyTransportFallback: false,
      ),
      isFalse,
    );
    expect(
      shouldEstablishLegacyDesktopSession(
        localDraft,
        legacyTransportFallback: true,
      ),
      isTrue,
    );
  });

  test('stored session identity wins when resolving the Project header', () {
    final overview = ProjectsTreeOverview.fromJson({
      'projects': [
        {
          'id': 'project-1',
          'label': 'Hermes Android',
          'sessionIds': ['stored-session'],
        },
        {
          'id': ProjectsTreeOverview.noProjectId,
          'label': 'Home',
          'isNoProject': true,
          'sessionIds': ['mobile-draft'],
        },
      ],
    });

    final resolution = resolveChatProjectHeader(overview, const [
      'stored-session',
      'mobile-draft',
    ]);

    expect(resolution.known, isTrue);
    expect(resolution.projectName, 'Hermes Android');
  });

  testWidgets(
    'session binding reconciles an Unassigned header with server placement',
    (tester) async {
      final session = _FakeTurnSession([const <GatewayTurnRecoveryState>[]]);
      var loads = 0;
      await _pumpChat(
        tester,
        turnSession: session,
        projectOverviewLoader: () async {
          loads += 1;
          return ProjectsTreeOverview.fromJson({
            'projects': [
              {
                'id': 'project-1',
                'label': 'Hermes Android',
                'sessionIds': ['stored-session'],
              },
            ],
          });
        },
      );

      expect(find.text('Unassigned'), findsOneWidget);

      session.bind('recovery-session', 'stored-session');
      await tester.pumpAndSettle();

      expect(loads, greaterThanOrEqualTo(2));
      expect(find.text('Hermes Android'), findsOneWidget);
      expect(find.text('Unassigned'), findsNothing);
    },
  );

  testWidgets('disposed chat releases its Project binding listener', (
    tester,
  ) async {
    final session = _FakeTurnSession([const <GatewayTurnRecoveryState>[]]);
    var loads = 0;
    await _pumpChat(
      tester,
      turnSession: session,
      projectOverviewLoader: () async {
        loads += 1;
        return ProjectsTreeOverview.empty;
      },
    );
    expect(loads, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    session.bind('recovery-session', 'stored-session');
    await tester.pump();

    expect(loads, 1);
  });

  testWidgets(
    'lazy stock fallback binding refreshes the draft Project header',
    (tester) async {
      final session = _FakeTurnSession(
        const <Object>[],
        recoverError: const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.unsupportedCapability,
          stockGateway: true,
        ),
      );
      var loads = 0;
      await _pumpChat(
        tester,
        turnSession: session,
        chatSession: const Session(
          id: 'mobile-draft',
          title: 'Draft chat',
          model: 'fixture-model',
          source: 'mobile',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
          isLocalDraft: true,
        ),
        projectOverviewLoader: () async {
          loads += 1;
          return loads == 1
              ? ProjectsTreeOverview.empty
              : _projectOverview('Hermes Android', 'stored-draft');
        },
        testRemotePromptSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              session.bind('mobile-draft', 'stored-draft');
              onSent();
            },
      );

      expect(find.text('Unassigned'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Persist this draft');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(loads, greaterThanOrEqualTo(2));
      expect(find.text('Hermes Android'), findsOneWidget);
      expect(find.text('Unassigned'), findsNothing);
    },
  );

  testWidgets('Project metadata retries after startup failure and reconnect', (
    tester,
  ) async {
    final session = _FakeTurnSession([const <GatewayTurnRecoveryState>[]]);
    final connectionHook = TestDesktopConnectionHook();
    var loads = 0;
    await _pumpChat(
      tester,
      turnSession: session,
      connectionHook: connectionHook,
      projectOverviewLoader: () async {
        loads += 1;
        if (loads == 1) throw StateError('offline at startup');
        return _projectOverview('Reconnected Project', 'recovery-session');
      },
    );

    expect(loads, 1);
    expect(find.text('Unassigned'), findsOneWidget);

    connectionHook.handler?.call(DesktopConnectionState.connected);
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('Reconnected Project'), findsOneWidget);
  });

  testWidgets('stale Project response cannot overwrite a newer generation', (
    tester,
  ) async {
    final session = _FakeTurnSession([const <GatewayTurnRecoveryState>[]]);
    final stale = Completer<ProjectsTreeOverview>();
    final current = Completer<ProjectsTreeOverview>();
    var loads = 0;
    await _pumpChat(
      tester,
      turnSession: session,
      projectOverviewLoader: () {
        loads += 1;
        return loads == 1 ? stale.future : current.future;
      },
    );

    expect(loads, 1);
    session.bind('recovery-session', 'stored-session');
    await tester.pump();
    expect(loads, 2);

    current.complete(_projectOverview('Current Project', 'stored-session'));
    await tester.pumpAndSettle();
    expect(find.text('Current Project'), findsOneWidget);

    stale.complete(_projectOverview('Stale Project', 'recovery-session'));
    await tester.pumpAndSettle();
    expect(find.text('Current Project'), findsOneWidget);
    expect(find.text('Stale Project'), findsNothing);
  });

  testWidgets('resume reconciles and materializes one authoritative response', (
    tester,
  ) async {
    final session = _FakeTurnSession([
      _acceptedState(),
      _completedState('Recovered after returning to Hermes'),
    ]);
    await _pumpChat(tester, turnSession: session);

    expect(session.recoverCount, 1);
    expect(session.submitCount, 0);
    expect(find.text('Recovering Hermes…'), findsOneWidget);

    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pumpAndSettle();

    expect(session.recoverCount, 2);
    expect(session.submitCount, 0);
    expect(find.text('Recovered after returning to Hermes'), findsOneWidget);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('screen remount reuses owner and does not duplicate snapshot', (
    tester,
  ) async {
    final session = _FakeTurnSession([
      _acceptedState(),
      _completedState('Recovered exactly once'),
    ]);
    await _pumpChat(tester, turnSession: session);
    expect(session.recoverCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(session.closeCount, 0);

    await _pumpChat(tester, turnSession: session);
    expect(session.recoverCount, 2);
    expect(session.submitCount, 0);
    expect(find.text('Recovered exactly once'), findsOneWidget);
  });

  testWidgets('new v2 submit sends raw text exactly once', (tester) async {
    final session = _FakeTurnSession([
      const <GatewayTurnRecoveryState>[],
    ], submitResult: _completedState('Done'));
    await _pumpChat(tester, turnSession: session);

    await tester.enterText(find.byType(TextField), 'Raw user prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(session.submitCount, 1);
    expect(session.submittedTexts, ['Raw user prompt']);
    expect(session.submittedTexts.single, isNot(contains('@file:')));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('v2 terminal state refreshes history skipped during submit', (
    tester,
  ) async {
    // Recovery/read ordering must preserve raw history without inventing
    // completion evidence for these untyped saved transcript rows.
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    final submitGate = Completer<void>();
    final history = _DelayedRefreshChatHttpClient();
    final session = _FakeTurnSession(
      [const <GatewayTurnRecoveryState>[]],
      submitResult: _completedState('Done'),
      submitGate: submitGate,
    );
    await _pumpChat(
      tester,
      turnSession: session,
      apiClient: ApiClient(
        baseUrl: 'http://recovery.fixture',
        apiKey: 'test-key',
        httpClient: history,
      ),
    );
    await history.firstMessagesUri.future;

    await tester.enterText(find.byType(TextField), 'Durable turn');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(session.submitCount, 1);

    history.releaseFirst();
    await history.firstResponseReturned.future;
    await tester.pump();
    submitGate.complete();
    final refreshedUri = await history.refreshedMessagesUri.future;
    expect(refreshedUri.queryParameters, {'limit': '50', 'order': 'latest'});
    await tester.pumpAndSettle();

    expect(find.text('Stale transcript row'), findsNothing);
    expect(find.text('Existing transcript row'), findsOneWidget);
    expect(find.text('Durable turn'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a recovery-v2 turn never arms legacy reattach polling', (
    tester,
  ) async {
    final submitGate = Completer<void>();
    final hook = TestDesktopConnectionHook();
    final history = _ResyncChatHttpClient();
    final session = _FakeTurnSession(
      [const <GatewayTurnRecoveryState>[]],
      submitResult: _completedState('Done'),
      submitGate: submitGate,
    );
    await _pumpChat(
      tester,
      turnSession: session,
      apiClient: ApiClient(
        baseUrl: 'http://recovery.fixture',
        apiKey: 'fixture-key',
        httpClient: history,
      ),
      connectionHook: hook,
    );

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Durable turn');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(session.submitCount, 1);

    hook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();
    expect(find.textContaining('will reattach automatically'), findsNothing);
    hook.handler?.call(DesktopConnectionState.connected);
    submitGate.complete();
    await tester.pumpAndSettle();

    expect(history.messageRequestCount, 1);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('recovery blocks submission but leaves draft editing available', (
    tester,
  ) async {
    final recoveryGate = Completer<void>();
    final session = _FakeTurnSession([
      const <GatewayTurnRecoveryState>[],
    ], recoverGate: recoveryGate);
    await _pumpChat(tester, turnSession: session);

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send),
    );
    expect(find.text('Recovering Hermes…'), findsOneWidget);
    expect(sendButton.onPressed, isNull);
    expect(session.submitCount, 0);
    final composer = find.byKey(const Key('chat-message-composer'));
    expect(tester.widget<TextField>(composer).enabled, isNot(false));
    await tester.enterText(composer, 'Draft during recovery');

    recoveryGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNotNull,
    );
    expect(session.submitCount, 0);
    expect(
      tester.widget<TextField>(composer).controller!.text,
      'Draft during recovery',
    );
  });

  testWidgets('definitive v2 rejection restores the editable prompt', (
    tester,
  ) async {
    final session = _FakeTurnSession(
      [const <GatewayTurnRecoveryState>[]],
      submitError: JsonRpcError(
        'prompt.submit',
        'Prompt rejected',
        reason: 'schema_violation',
      ),
    );
    await _pumpChat(tester, turnSession: session);

    await tester.enterText(find.byType(TextField), 'Fix this prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(session.submitCount, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Fix this prompt',
    );
    expect(
      find.text('Send failed: JsonRpcError(prompt.submit): Prompt rejected'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNotNull,
    );
  });

  for (final rejected in [false, true]) {
    testWidgets('v2 submit preserves a newer draft (rejected=$rejected)', (
      tester,
    ) async {
      final submitGate = Completer<void>();
      final session = _FakeTurnSession(
        [const <GatewayTurnRecoveryState>[]],
        submitGate: submitGate,
        submitError: rejected
            ? JsonRpcError(
                'prompt.submit',
                'Rejected',
                reason: 'schema_violation',
              )
            : null,
      );
      await _pumpChat(tester, turnSession: session);
      final composer = find.byKey(const Key('chat-message-composer'));
      await tester.enterText(composer, 'Original v2 prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(session.submittedTexts, ['Original v2 prompt']);
      expect(tester.widget<TextField>(composer).enabled, isTrue);
      await tester.enterText(composer, 'New v2 draft');
      submitGate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'New v2 draft',
      );
    });
  }

  testWidgets('v2 attachment staging failure preserves a newer draft', (
    tester,
  ) async {
    final stageGate = Completer<void>();
    final session = _FakeTurnSession([
      const <GatewayTurnRecoveryState>[],
    ], stageGate: stageGate);
    await _pumpChat(
      tester,
      turnSession: session,
      attachmentDraftService: _MemoryAttachmentDraftService(),
      initialDrafts: [
        AttachmentDraft(
          id: 'staged-file',
          cachedPath: 'synthetic-file',
          name: 'file.txt',
          byteLength: 4,
          mediaType: 'text/plain',
          kind: AttachmentDraftKind.genericFile,
        ),
      ],
    );
    final composer = find.byKey(const Key('chat-message-composer'));
    await tester.enterText(composer, 'Original staged prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(session.stageCount, 1);
    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    await tester.enterText(composer, 'Draft during staging');
    stageGate.complete();
    await tester.pumpAndSettle();
    expect(session.submitCount, 0);
    expect(
      tester.widget<TextField>(composer).controller!.text,
      'Draft during staging',
    );
    expect(find.text('file.txt'), findsOneWidget);
  });

  testWidgets(
    'explicit unsupported recovery enables one visible legacy submit',
    (tester) async {
      // Inspect transport diagnostics/raw recovered prose in Verbose mode.
      SharedPreferences.setMockInitialValues({'verbose_mode': true});
      final session = _FakeTurnSession(
        const <Object>[],
        recoverError: const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.unsupportedCapability,
        ),
      );
      var legacySubmitCount = 0;
      await _pumpChat(
        tester,
        turnSession: session,
        testRemotePromptSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              legacySubmitCount += 1;
              expect(sessionId, 'recovery-session');
              expect(text, 'Legacy once');
            },
      );

      expect(
        find.text('Background recovery unavailable — legacy transport'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Legacy once');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(legacySubmitCount, 1);
      expect(session.submitCount, 0);
      expect(session.stageCount, 0);
      expect(
        find.text('Background recovery unavailable — legacy transport'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'stock gateway fallback shows the calm capability notice, not the failure banner',
    (tester) async {
      // Inspect transport diagnostics/raw recovered prose in Verbose mode.
      SharedPreferences.setMockInitialValues({'verbose_mode': true});
      final session = _FakeTurnSession(
        const <Object>[],
        recoverError: const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.unsupportedCapability,
          stockGateway: true,
        ),
      );
      var legacySubmitCount = 0;
      await _pumpChat(
        tester,
        turnSession: session,
        testRemotePromptSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              legacySubmitCount += 1;
            },
      );

      expect(
        find.text(
          "This server doesn't offer background recovery — chats run live",
        ),
        findsOneWidget,
      );
      expect(
        find.text('Background recovery unavailable — legacy transport'),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), 'Stock send');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(legacySubmitCount, 1);
      expect(session.submitCount, 0);
    },
  );

  testWidgets(
    'legacy fallback resyncs a backgrounded turn once the stream disconnects',
    (tester) async {
      // Inspect transport diagnostics/raw recovered prose in Verbose mode.
      SharedPreferences.setMockInitialValues({'verbose_mode': true});
      final session = _FakeTurnSession(
        const <Object>[],
        recoverError: const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.unsupportedCapability,
        ),
      );
      final submission = Completer<void>();
      final history = _ResyncChatHttpClient();
      final apiClient = ApiClient(
        baseUrl: 'http://recovery.fixture',
        apiKey: 'fixture-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        turnSession: session,
        apiClient: apiClient,
        testRemotePromptSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
      );

      expect(history.messageRequestCount, 1);
      await tester.enterText(find.byType(TextField), 'Finish in background');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      for (final state in const <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      history.includeCompletedTurn = true;
      submission.completeError(StateError('socket closed'));
      await tester.pump();
      await tester.pumpAndSettle();

      // The saved final precedes the separate retained received section.
      await tester.scrollUntilVisible(
        find.text('Server-side final response'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Server-side final response'), findsOneWidget);
      expect(history.messageRequestCount, 2);

      for (final state in const <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(history.messageRequestCount, 2);
    },
  );

  testWidgets(
    'network auth malformed and unsafe journal errors never enable legacy',
    (tester) async {
      final errors = <Object>[
        const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.transportUnavailable,
        ),
        JsonRpcError('gateway.ready', 'Unauthorized', reason: 'unauthorized'),
        const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        ),
        const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.unsupportedCapabilityWithPendingTurns,
        ),
      ];
      for (final error in errors) {
        var legacySubmitCount = 0;
        final session = _FakeTurnSession(const <Object>[], recoverError: error);
        await _pumpChat(
          tester,
          turnSession: session,
          testRemotePromptSubmit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                onSent();
                legacySubmitCount += 1;
              },
        );

        expect(
          find.text('Background recovery unavailable — legacy transport'),
          findsNothing,
        );
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
              .onPressed,
          isNull,
        );
        expect(legacySubmitCount, 0);
        expect(session.submitCount, 0);
        expect(session.stageCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('fallback uploads mixed attachments and legacy-submits once', (
    tester,
  ) async {
    final session = _FakeTurnSession(
      const <Object>[],
      recoverError: const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.unsupportedCapability,
      ),
    );
    final drafts = <AttachmentDraft>[
      AttachmentDraft(
        id: 'image-draft',
        cachedPath: 'synthetic-image',
        name: 'photo.png',
        byteLength: 3,
        mediaType: 'image/png',
        kind: AttachmentDraftKind.image,
        sourceImageFormat: AttachmentImageFormat.png,
        sanitized: true,
      ),
      AttachmentDraft(
        id: 'file-draft',
        cachedPath: 'synthetic-file',
        name: 'notes.txt',
        byteLength: 4,
        mediaType: 'text/plain',
        kind: AttachmentDraftKind.genericFile,
      ),
    ];
    var legacySubmitCount = 0;
    final uploads = <String>[];
    await _pumpChat(
      tester,
      turnSession: session,
      attachmentDraftService: _MemoryAttachmentDraftService(),
      initialDrafts: drafts,
      testRemoteAttachmentUpload: ({required draft, required dataUrl}) async {
        uploads.add(draft.name);
        return AttachmentUploadReceipt(refText: '@file:${draft.name}');
      },
      testRemotePromptSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            legacySubmitCount += 1;
            expect(text, contains('@file:photo.png'));
            expect(text, contains('@file:notes.txt'));
          },
    );

    await tester.enterText(find.byType(TextField), 'Mixed legacy');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(uploads, <String>['photo.png', 'notes.txt']);
    expect(legacySubmitCount, 1);
    expect(session.stageCount, 0);
    expect(session.submitCount, 0);
  });

  testWidgets('disconnect during a legacy attachment upload does not arm '
      'prompt recovery', (tester) async {
    final session = _FakeTurnSession(
      const <Object>[],
      recoverError: const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.unsupportedCapability,
      ),
    );
    final hook = TestDesktopConnectionHook();
    final uploadGate = Completer<void>();
    final history = _ResyncChatHttpClient();
    var submitCount = 0;
    await _pumpChat(
      tester,
      turnSession: session,
      apiClient: ApiClient(
        baseUrl: 'http://recovery.fixture',
        apiKey: 'fixture-key',
        httpClient: history,
      ),
      connectionHook: hook,
      attachmentDraftService: _MemoryAttachmentDraftService(),
      initialDrafts: [
        AttachmentDraft(
          id: 'upload-draft',
          cachedPath: 'synthetic-upload',
          name: 'upload.txt',
          byteLength: 4,
          mediaType: 'text/plain',
          kind: AttachmentDraftKind.genericFile,
        ),
      ],
      testRemoteAttachmentUpload: ({required draft, required dataUrl}) async {
        await uploadGate.future;
        return const AttachmentUploadReceipt(refText: '@file:upload');
      },
      testRemotePromptSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            submitCount += 1;
          },
    );

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Upload first');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    hook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();

    expect(find.textContaining('will reattach automatically'), findsNothing);
    uploadGate.completeError(StateError('upload connection closed'));
    await tester.pump();
    await tester.pumpAndSettle();
    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump(const Duration(seconds: 3));
    expect(submitCount, 0);
    expect(history.messageRequestCount, 1);
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _FakeTurnSession turnSession,
  Session chatSession = const Session(
    id: 'recovery-session',
    title: 'Recovery chat',
    model: 'fixture-model',
    source: 'test',
    messageCount: 0,
    isActive: true,
    preview: '',
    startedAt: 1,
  ),
  ApiClient? apiClient,
  TestRemotePromptSubmit? testRemotePromptSubmit,
  TestRemoteAttachmentUpload? testRemoteAttachmentUpload,
  AttachmentDraftService? attachmentDraftService,
  List<AttachmentDraft> initialDrafts = const [],
  TestDesktopConnectionHook? connectionHook,
  TestProjectOverviewLoader? projectOverviewLoader,
}) async {
  apiClient ??= ApiClient(
    baseUrl: 'http://recovery.fixture',
    apiKey: 'synthetic-key',
    httpClient: _EmptyChatHttpClient(),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'recovery-fixture',
          label: 'Recovery fixture',
          host: 'recovery.fixture',
          port: 8642,
          apiKey: 'synthetic-key',
        ),
        session: chatSession,
        testApiClient: apiClient,
        testTurnApplicationSession: turnSession,
        testRemotePromptSubmit: completedStockTurn(testRemotePromptSubmit),
        testNormalResume:
            ({required localSessionId, required storedSessionId}) async =>
                const ResumedGatewaySession(
                  runtimeSessionId: 'fixture-runtime',
                  running: false,
                ),
        testRemoteAttachmentUpload: testRemoteAttachmentUpload,
        testAttachmentDraftService: attachmentDraftService,
        testInitialAttachmentDrafts: initialDrafts,
        testDesktopConnectionHook: connectionHook,
        testProjectOverviewLoader: projectOverviewLoader,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

ProjectsTreeOverview _projectOverview(String label, String sessionId) {
  return ProjectsTreeOverview.fromJson({
    'projects': [
      {
        'id': 'project-${label.toLowerCase().replaceAll(' ', '-')}',
        'label': label,
        'sessionIds': [sessionId],
      },
    ],
  });
}

GatewayTurnRecoveryState _acceptedState() =>
    GatewayTurnRecoveryState.initial(
      clientTurnId: _clientTurnId,
    ).markSubmissionStarted().applyAck(
      const GatewayTurnAck(
        clientTurnId: _clientTurnId,
        turnId: _turnId,
        status: GatewayRecoveryTurnStatus.accepted,
        lastSeq: 0,
        created: true,
      ),
    );

GatewayTurnRecoveryState _completedState(String text) {
  final page = GatewayTurnReconcilePage.fromWire(
    {
      'automatic_resubmit': false,
      'mode': 'snapshot',
      'earliest_seq': 1,
      'last_seq': 4,
      'next_after_seq': 4,
      'has_more': false,
      'snapshot': {
        'turn_id': _turnId,
        'client_turn_id': _clientTurnId,
        'status': 'completed',
        'last_seq': 4,
        'assistant': {'message_id': _messageId, 'text': text, 'complete': true},
        'attachment_manifest_digest': _manifestDigest,
        'final_message_ref': 7,
      },
    },
    expectedAfterSeq: 0,
    expectedTurnId: _turnId,
    expectedClientTurnId: _clientTurnId,
  )!;
  return _acceptedState().applyReconcilePage(page);
}

class _FakeTurnSession implements GatewayTurnApplicationSession {
  @override
  bool get hasActiveTurn => false;

  @override
  Object addTurnActivityListener(void Function() listener) => Object();

  @override
  void removeTurnActivityListener(Object token) {}

  final List<Object> _recoverResults;
  final GatewayTurnRecoveryState? submitResult;
  final Object? submitError;
  final Object? recoverError;
  final Completer<void>? recoverGate;
  final Completer<void>? submitGate;
  final Completer<void>? stageGate;
  int recoverCount = 0;
  int submitCount = 0;
  int stageCount = 0;
  int closeCount = 0;
  final List<String> submittedTexts = [];
  GatewayTurnSessionBoundCallback? _onSessionBound;
  Object? _sessionBoundRegistration;

  void bind(String localSessionId, String storedSessionId) {
    _onSessionBound?.call(localSessionId, storedSessionId);
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

  _FakeTurnSession(
    this._recoverResults, {
    this.submitResult,
    this.submitError,
    this.recoverError,
    this.recoverGate,
    this.submitGate,
    this.stageGate,
  });

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async {
    await recoverGate?.future;
    if (recoverError case final error?) throw error;
    final index = recoverCount < _recoverResults.length
        ? recoverCount
        : _recoverResults.length - 1;
    recoverCount += 1;
    final value = _recoverResults[index];
    final states = value is GatewayTurnRecoveryState
        ? <GatewayTurnRecoveryState>[value]
        : (value as List<GatewayTurnRecoveryState>);
    for (final state in states) {
      onState?.call(state);
    }
    return states;
  }

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) async {
    submitCount += 1;
    submittedTexts.add(text);
    await submitGate?.future;
    if (submitError case final error?) throw error;
    final state = submitResult ?? _completedState('Done');
    onState?.call(state);
    return state;
  }

  @override
  Future<void> close() async => closeCount++;

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) {
    final token = Object();
    _sessionBoundRegistration = token;
    _onSessionBound = listener;
    return token;
  }

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {
    if (!identical(_sessionBoundRegistration, registration)) return;
    _sessionBoundRegistration = null;
    _onSessionBound = null;
  }

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
  }) async {
    stageCount += 1;
    await stageGate?.future;
    throw StateError('Recovery staging must not run in legacy fallback.');
  }
}

class _MemoryAttachmentDraftService extends AttachmentDraftService {
  @override
  Future<String> readDataUrl(AttachmentDraft draft) async =>
      'data:${draft.mediaType};base64,AA==';

  @override
  Future<void> removeAll(Iterable<AttachmentDraft> drafts) async {}

  @override
  Future<void> removeCachedFile(AttachmentDraft draft) async {}
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

class _DelayedRefreshChatHttpClient extends http.BaseClient {
  final Completer<Uri> firstMessagesUri = Completer<Uri>();
  final Completer<Uri> refreshedMessagesUri = Completer<Uri>();
  final Completer<void> firstResponseReturned = Completer<void>();
  final Completer<void> _releaseFirst = Completer<void>();
  int _messageRequestCount = 0;

  void releaseFirst() {
    if (!_releaseFirst.isCompleted) _releaseFirst.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      _messageRequestCount += 1;
      if (_messageRequestCount == 1) {
        firstMessagesUri.complete(request.url);
        await _releaseFirst.future;
        firstResponseReturned.complete();
        return _response([
          {'role': 'assistant', 'content': 'Stale transcript row'},
        ]);
      }
      if (!refreshedMessagesUri.isCompleted) {
        refreshedMessagesUri.complete(request.url);
      }
      return _response([
        {'role': 'assistant', 'content': 'Existing transcript row'},
        {'role': 'user', 'content': 'Durable turn'},
        {'role': 'assistant', 'content': 'Done'},
      ]);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _response(List<Map<String, dynamic>> messages) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
        200,
        headers: {'content-type': 'application/json'},
      );
}

class _ResyncChatHttpClient extends http.BaseClient {
  int messageRequestCount = 0;
  bool includeCompletedTurn = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      messageRequestCount += 1;
      final messages = includeCompletedTurn
          ? <Map<String, dynamic>>[
              {'id': 1, 'role': 'user', 'content': 'Finish in background'},
              {
                'id': 2,
                'role': 'assistant',
                'content': 'Server-side final response',
              },
            ]
          : <Map<String, dynamic>>[];
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
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
