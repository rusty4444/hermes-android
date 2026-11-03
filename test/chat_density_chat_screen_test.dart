import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

import 'support/fake_voice_composer_adapter.dart';

/// Serves the two-message history the density assertions read, and answers any
/// other request the screen makes while it initialises.
http.Client _fixtureClient() {
  return MockClient((request) async {
    if (request.url.path.endsWith('/messages')) {
      return http.Response(
        jsonEncode({
          'data': [
            {'role': 'user', 'content': 'Hello there'},
            // Density concerns a completed conversation answer in quiet mode.
            {'role': 'assistant', 'content': 'Hello back', 'completed': true},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> _pumpChat(WidgetTester tester) async {
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(picker, (_) async => null);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null),
  );

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      localeListResolutionCallback: resolvePreferredLocale,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'density-fixture',
          label: 'Density fixture',
          host: 'density-fixture.invalid',
          port: 8642,
          apiKey: 'fixture-key',
        ),
        session: const Session(
          id: 'density-session',
          title: 'Density chat',
          model: 'fixture-model',
          source: 'api_server',
          messageCount: 2,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: ApiClient(
          baseUrl: 'https://density-fixture.invalid',
          apiKey: 'fixture-key',
          httpClient: _fixtureClient(),
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Sender labels this widget layer contributes to the semantics tree, in
/// message order. The visible label carries them in comfortable mode; compact
/// hands them to a [Semantics] node instead of spending a line on them.
List<String?> _bubbleSemanticsLabels(WidgetTester tester) {
  return tester
      .widgetList<Semantics>(
        find.ancestor(
          of: find.byKey(const Key('message-bubble')),
          matching: find.byType(Semantics),
        ),
      )
      .map((semantics) => semantics.properties.label)
      .whereType<String>()
      .toList();
}

Finder _senderLabel(String label) => find.descendant(
  of: find.byKey(const Key('message-bubble')),
  matching: find.text(label),
);

void main() {
  setUp(() {
    chatDensitySelection.value = ChatDensity.comfortable;
  });

  testWidgets('a launch with compact stored renders unlabelled bubbles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'verbose_mode': false,
      ChatDensity.preferenceKey: 'compact',
    });

    await _pumpChat(tester);

    expect(find.byKey(const Key('message-bubble')), findsNWidgets(2));
    expect(_senderLabel('You'), findsNothing);
    expect(_senderLabel('Hermes'), findsNothing);
  });

  testWidgets('a launch with no stored value keeps the sender labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});

    await _pumpChat(tester);

    expect(_senderLabel('You'), findsOneWidget);
    expect(_senderLabel('Hermes'), findsOneWidget);
  });

  testWidgets('stored preferences win over a stale density broadcast', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    // The broadcast still says compact from an earlier surface; the persisted
    // value is the truth, so the launch must not inherit the stale one.
    chatDensitySelection.value = ChatDensity.compact;

    await _pumpChat(tester);

    expect(_senderLabel('You'), findsOneWidget);
    expect(_senderLabel('Hermes'), findsOneWidget);
  });

  testWidgets('changing the density re-lays out an already open chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});

    await _pumpChat(tester);
    expect(_senderLabel('Hermes'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    await ChatDensityStore(prefs).save(ChatDensity.compact);
    await tester.pumpAndSettle();

    expect(_senderLabel('You'), findsNothing);
    expect(_senderLabel('Hermes'), findsNothing);

    await ChatDensityStore(prefs).save(ChatDensity.comfortable);
    await tester.pumpAndSettle();

    expect(_senderLabel('You'), findsOneWidget);
    expect(_senderLabel('Hermes'), findsOneWidget);
  });

  testWidgets('compact still announces the speaker to screen readers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'verbose_mode': false,
      ChatDensity.preferenceKey: 'compact',
    });
    await _pumpChat(tester);

    expect(_senderLabel('You'), findsNothing);
    expect(_bubbleSemanticsLabels(tester), ['You', 'Hermes']);
  });

  testWidgets('comfortable does not duplicate the speaker for screen readers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});

    await _pumpChat(tester);

    // The visible label already reads out; a Semantics wrapper on top of it
    // would make every message announce its speaker twice.
    expect(_bubbleSemanticsLabels(tester), isEmpty);
  });
}
