import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

final connection = SavedConnection(
  id: 'quality-owner-drafts',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture',
);

class Remote {
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

Future<void> open(
  WidgetTester tester,
  GatewayTurnApplicationController controller,
  Remote remote, {
  String id = 'local',
  bool draft = false,
  bool push = false,
  Future<String?> Function({
    required String connectionId,
    required String sessionId,
  })?
  reader,
}) async {
  final screen = ChatScreen(
    key: UniqueKey(),
    connection: connection,
    session: Session(
      id: id,
      title: 'Quality owner',
      model: 'fixture',
      source: 'test',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: 1,
      isLocalDraft: draft,
    ),
    projectWorkingDirectory: draft ? '/project' : null,
    turnApplicationController: controller,
    testApiClient: ApiClient(
      baseUrl: connection.baseUrl,
      apiKey: 'fixture',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'data': []}), 200),
      ),
    ),
    testRemotePromptSubmit: remote.submit,
    testComposerDraftReader: reader,
    testStoredSessionKey: (_) => 'stored',
    testLegacyProjectSessionEnsure: (_, _) async {},
    testNormalResume:
        ({required localSessionId, required storedSessionId}) async =>
            const ResumedGatewaySession(
              runtimeSessionId: 'runtime',
              running: true,
            ),
    testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
  );
  if (push) {
    unawaited(
      Navigator.of(
        tester.element(find.byType(ChatScreen)),
      ).push<void>(MaterialPageRoute(builder: (_) => screen)),
    );
  } else {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    );
  }
  await tester.pump();
  await tester.pump();
  if (push) {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  testWidgets(
    'a newer clear fences held hydration, while resumed explicit editing reclaims authority',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = Remote();
      final held = Completer<String?>();
      await open(
        tester,
        controller,
        remote,
        id: 'stored',
        reader: ({required connectionId, required sessionId}) => held.future,
      );
      await open(tester, controller, remote, id: 'stored', push: true);
      await tester.enterText(find.byType(TextField), 'New intent');
      await tester.enterText(find.byType(TextField), '');
      Navigator.of(tester.element(find.byType(ChatScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      held.complete('Obsolete hydration');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(
        await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'stored',
        ),
        isNull,
      );
      // The older route is not permanently disqualified: an actual new edit is
      // fresh intent, unlike dispose/background/selection/hydration callbacks.
      await tester.enterText(
        find.byType(TextField),
        'Resumed explicit instruction',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'stored',
        ),
        'Resumed explicit instruction',
      );
      expect(remote.submissions, 0);
    },
  );

  testWidgets('local stored alias draft survives a fresh application owner', (
    tester,
  ) async {
    final first = GatewayTurnApplicationController();
    final remote = Remote();
    await open(tester, first, remote, draft: true);
    await tester.enterText(find.byType(TextField), 'Submitted once');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Next after restart');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await first.close();
    final prefs = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues({
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    });
    final second = GatewayTurnApplicationController();
    addTearDown(second.close);
    await open(tester, second, remote, id: 'stored');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Next after restart',
    );
    expect(
      await ComposerDraftStore.read(
        connectionId: connection.id,
        sessionId: 'local',
      ),
      'Next after restart',
    );
    expect(remote.submissions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await second.close();
  });

  testWidgets(
    'local-to-canonical owner reattachment preserves the next draft',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = Remote();
      await open(tester, controller, remote, draft: true);
      await tester.enterText(find.byType(TextField), 'Submitted prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      final owner = controller.normalSessionFor(connection).findChat('local')!;
      expect(owner.storedSessionId, 'stored');
      expect(remote.submissions, 1);
      await tester.enterText(find.byType(TextField), 'Unsent next instruction');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'local',
        ),
        'Unsent next instruction',
      );
      await open(tester, controller, remote, id: 'stored');
      expect(
        identical(
          controller.normalSessionFor(connection).findChat('stored'),
          owner,
        ),
        isTrue,
      );
      final visibleDraft = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(visibleDraft, 'Unsent next instruction');
    },
  );

  testWidgets(
    'older still-mounted same-owner route cannot erase a newer route draft',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = Remote();
      await open(tester, controller, remote, id: 'stored');
      await tester.enterText(find.byType(TextField), 'Submitted prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      await open(tester, controller, remote, id: 'stored', push: true);
      expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'Newer route instruction');
      Navigator.of(tester.element(find.byType(ChatScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'stored',
        ),
        'Newer route instruction',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(remote.submissions, 1);
      expect(
        await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'stored',
        ),
        'Newer route instruction',
      );
    },
  );
}
