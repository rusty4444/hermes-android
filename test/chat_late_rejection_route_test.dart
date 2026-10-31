import 'dart:async';

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

void main() {
  for (final nextDraft in ['Newer canonical draft', '']) {
    testWidgets(
      'older mounted route rejection cannot overwrite newer canonical draft "$nextDraft"',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final connection = SavedConnection(
          id: 'late-rejection-review',
          label: 'Review',
          host: 'review.invalid',
          port: 8642,
          apiKey: 'fixture',
        );
        final controller = GatewayTurnApplicationController();
        final selected = ValueNotifier<int>(0);
        final addCanonical = ValueNotifier<bool>(false);
        final submit = Completer<void>();
        var submits = 0;
        Future<void> remoteSubmit({
          required String sessionId,
          required String text,
          required StreamCallback onEvent,
          required void Function() onSent,
        }) {
          submits++;
          // Definite failure before prompt wire emission, after identity binding.
          return submit.future;
        }

        Widget chat(String id) => ChatScreen(
          key: ValueKey(id),
          connection: connection,
          session: Session(
            id: id,
            title: 'Review',
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
            baseUrl: connection.baseUrl,
            apiKey: 'fixture',
            httpClient: MockClient(
              (_) async => http.Response('{"data":[]}', 200),
            ),
          ),
          testRemotePromptSubmit: remoteSubmit,
          testNormalResume:
              ({required localSessionId, required storedSessionId}) async =>
                  const ResumedGatewaySession(
                    runtimeSessionId: 'runtime',
                    running: true,
                  ),
          testStoredSessionKey: (_) => 'canonical',
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ValueListenableBuilder<bool>(
              valueListenable: addCanonical,
              builder: (_, add, _) => ValueListenableBuilder<int>(
                valueListenable: selected,
                builder: (_, index, _) => IndexedStack(
                  index: index,
                  children: [chat('local'), if (add) chat('canonical')],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        controller
            .normalSessionFor(connection, submit: remoteSubmit)
            .findChat('local')!
            .bindStoredSession('canonical');
        addCanonical.value = true;
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const Key('chat-message-composer')),
          'Original rejected prompt',
        );
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
        expect(submits, 1);
        selected.value = 1;
        await tester.pump();
        await tester.pump();
        final composer = find.byKey(const Key('chat-message-composer'));
        await tester.enterText(composer, 'Newer canonical draft');
        if (nextDraft.isEmpty) await tester.enterText(composer, '');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        await tester.pump();
        final before = await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'canonical',
        );
        expect(before, nextDraft.isEmpty ? isNull : nextDraft);
        submit.completeError(
          StateError('definite setup rejection before onSent'),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        final visible = tester.widget<TextField>(composer).controller!.text;
        final durable = await ComposerDraftStore.read(
          connectionId: connection.id,
          sessionId: 'canonical',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await controller.close();
        selected.dispose();
        addCanonical.dispose();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(visible, nextDraft);
        expect(
          durable,
          nextDraft.isEmpty ? isNull : nextDraft,
          reason:
              'old hidden route must not reclaim newer route write authority merely through programmatic rejection restoration',
        );
        expect(
          await ComposerDraftStore.read(
            connectionId: connection.id,
            sessionId: 'canonical',
          ),
          nextDraft.isEmpty ? isNull : nextDraft,
          reason: 'disposing both routes must retain the newer draft or clear',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
