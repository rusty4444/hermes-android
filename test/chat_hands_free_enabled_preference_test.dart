// Regression: the Settings switch removes the hands-free surface from chats.
//
// handsFreeEnabled is a global per-device preference. Disabling it must hide
// the composer start control and the in-chat voice controls, and stop a
// running session without ever restarting capture on re-enable.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hands_free_preference.dart';
import 'package:hermes_android/core/services/hands_free_route_observer.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_hands_free_voice.dart';
import 'support/fake_voice_composer_adapter.dart';

class _Rig {
  final native = FakeHandsFreeVoicePlatform();
  final speaker = FakeVoiceReplySpeaker();
  final manual = FakeVoiceComposerAdapter();

  SavedConnection get connection => SavedConnection(
    id: 'hf-pref',
    label: 'Preference fixture',
    host: 'voice.fixture',
    port: 8642,
    apiKey: 'fixture-key',
  );

  Future<void> pump(WidgetTester tester) async {
    final api = ApiClient(
      baseUrl: 'http://voice.fixture',
      apiKey: 'fixture-key',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 1, 'role': 'assistant', 'content': 'historic answer'},
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [handsFreeRouteObserver],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(
          connection: connection,
          session: const Session(
            id: 'voice-chat',
            title: 'Voice chat',
            model: 'fixture-model',
            source: 'test',
            messageCount: 1,
            isActive: true,
            preview: '',
            startedAt: 1,
            isLocalDraft: true,
          ),
          testApiClient: api,
          testVoiceComposerAdapter: manual,
          testHandsFreePlatform: native,
          testVoiceReplySpeaker: speaker,
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
    native.armed();
    await tester.pump();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handsFreeEnabled.value = true;
  });

  tearDown(() {
    handsFreeEnabled.value = true;
  });

  testWidgets(
    'disabling hands-free in settings hides the start control from the chat',
    (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      expect(find.byKey(const Key('hands-free-start')), findsOneWidget);

      handsFreeEnabled.value = false;
      await tester.pump();
      expect(find.byKey(const Key('hands-free-start')), findsNothing);
      expect(find.byKey(const Key('hands-free-quick-stop')), findsNothing);

      handsFreeEnabled.value = true;
      await tester.pump();
      expect(find.byKey(const Key('hands-free-start')), findsOneWidget);
    },
  );

  testWidgets(
    'disabling hands-free while a session runs stops it and hides the controls',
    (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.start(tester);
      final stopsBefore = rig.native.count('stop');
      // Wake the session so capture is genuinely active.
      rig.native.wake();
      await tester.pump();
      rig.native.ready();
      await tester.pump();
      expect(rig.native.count('armWake'), 1);

      handsFreeEnabled.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.native.count('stop'), greaterThan(stopsBefore));

      // Once stopped, nothing hands-free remains in the composer.
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hands-free-start')), findsNothing);
      expect(find.byKey(const Key('hands-free-quick-stop')), findsNothing);
    },
  );

  testWidgets('re-enabling hands-free never restarts capture', (tester) async {
    final rig = _Rig();
    await rig.pump(tester);
    await rig.start(tester);
    rig.native.wake();
    await tester.pump();
    rig.native.ready();
    await tester.pump();
    final armsBefore = rig.native.count('armWake');

    handsFreeEnabled.value = false;
    await tester.pump();
    await tester.pumpAndSettle();
    final armsAfterDisable = rig.native.count('armWake');

    handsFreeEnabled.value = true;
    await tester.pumpAndSettle();

    expect(rig.native.count('armWake'), armsBefore);
    expect(armsAfterDisable, armsBefore);
    // The start control returns, but nothing started on its own.
    expect(find.byKey(const Key('hands-free-start')), findsOneWidget);
  });
}
