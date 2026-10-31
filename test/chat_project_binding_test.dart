import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

Widget _chat({
  String? projectCwd,
  required Future<void> Function(String, String) ensureProject,
  required Future<void> Function() submit,
}) {
  final connection = SavedConnection(
    id: 'project-binding',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture-key',
  );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: preferredSupportedLocales(),
    localeListResolutionCallback: resolvePreferredLocale,
    home: ChatScreen(
      connection: connection,
      session: const Session(
        id: 'draft-project',
        title: 'New chat · Project',
        model: 'hermes-agent',
        source: 'mobile',
        messageCount: 0,
        isActive: true,
        preview: '',
        startedAt: 1,
        isLocalDraft: true,
      ),
      projectName: projectCwd == null ? null : 'Project',
      projectWorkingDirectory: projectCwd,
      testApiClient: ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: connection.apiKey,
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      ),
      testLegacyProjectSessionEnsure: ensureProject,
      testRemotePromptSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            await submit();
            onEvent(
              StreamEvent(
                type: 'turn.end',
                data: const {'status': 'completed'},
              ),
            );
          },
      testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
    ),
  );
}

void main() {
  setUp(mockChatImageRecovery);
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  testWidgets('project draft binds cwd before its first legacy prompt', (
    tester,
  ) async {
    final events = <String>[];
    final bind = Completer<void>();
    await tester.pumpWidget(
      _chat(
        projectCwd: ' /srv/projects/work ',
        ensureProject: (sessionId, cwd) {
          events.add('bind:$sessionId:$cwd');
          return bind.future;
        },
        submit: () async => events.add('submit'),
      ),
    );
    await pumpChatUpdates(tester);
    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Start work',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(events, ['bind:draft-project:/srv/projects/work']);
    bind.complete();
    await pumpChatUpdates(tester);
    expect(events, ['bind:draft-project:/srv/projects/work', 'submit']);
  });

  testWidgets('quick draft does not inherit a project binding', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      _chat(
        ensureProject: (_, _) async => events.add('bind'),
        submit: () async => events.add('submit'),
      ),
    );
    await pumpChatUpdates(tester);
    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Quick question',
    );
    await tester.tap(find.byTooltip('Send'));
    await pumpChatUpdates(tester);
    expect(events, ['submit']);
  });

  testWidgets('failed project binding does not submit an unfiled chat', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      _chat(
        projectCwd: '/srv/projects/work',
        ensureProject: (_, _) async => throw StateError('binding failed'),
        submit: () async => submitted = true,
      ),
    );
    await pumpChatUpdates(tester);
    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Do not lose this',
    );
    await tester.tap(find.byTooltip('Send'));
    await pumpChatUpdates(tester);
    expect(submitted, isFalse);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat-message-composer')))
          .controller
          ?.text,
      'Do not lose this',
    );
  });
}
