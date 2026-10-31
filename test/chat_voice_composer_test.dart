import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/voice_composer_controls.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/completed_stock_turn.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets(
    'partial and final only edit composer; explicit Send submits exactly once',
    (tester) async {
      final voice = FakeVoiceComposerAdapter();
      var submitCount = 0;
      String? submittedText;
      await _pumpChat(
        tester,
        voice: voice,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              submitCount += 1;
              submittedText = text;
            },
      );

      await tester.enterText(find.byType(TextField), 'Before after');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 12,
      );

      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump();
      voice.emitPartial('dict');
      await tester.pump();
      expect(field.controller!.text, 'Before dict');
      expect(submitCount, 0);

      voice.emitFinal('dictated words');
      await tester.pump();
      expect(field.controller!.text, 'Before dictated words');
      expect(find.byKey(VoiceComposerIndicator.indicatorKey), findsNothing);
      expect(submitCount, 0);

      field.controller!.text = '${field.controller!.text}!';
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(submitCount, 1);
      expect(submittedText, 'Before dictated words!');
    },
  );

  testWidgets(
    'error and status done never submit or mutate from late results',
    (tester) async {
      final voice = FakeVoiceComposerAdapter();
      var submitCount = 0;
      await _pumpChat(
        tester,
        voice: voice,
        remoteSubmit:
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
      final field = tester.widget<TextField>(find.byType(TextField));

      await tester.enterText(find.byType(TextField), 'first');
      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump();
      voice.emitPartial('heard');
      voice.emitError('speech failed');
      voice.emitFinal('late after error');
      await tester.pump();
      expect(field.controller!.text, 'first heard');
      expect(submitCount, 0);

      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump();
      voice.emitPartial('again');
      voice.emitStatus('done');
      voice.emitFinal('late after done');
      await tester.pump(const Duration(seconds: 3));
      expect(field.controller!.text, 'first heard again');
      expect(submitCount, 0);
    },
  );

  testWidgets(
    'Stop final transcript stays editable and never submits automatically',
    (tester) async {
      final voice = FakeVoiceComposerAdapter(
        finalTranscriptOnStop: 'final dictated words',
      );
      var submitCount = 0;
      await _pumpChat(
        tester,
        voice: voice,
        remoteSubmit:
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
      final field = tester.widget<TextField>(find.byType(TextField));

      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump();
      expect(find.byKey(VoiceComposerIndicator.indicatorKey), findsOneWidget);

      voice.emitPartial('interim words');
      await tester.pump();
      expect(field.controller!.text, 'Draft interim words');
      expect(find.byKey(VoiceComposerIndicator.indicatorKey), findsOneWidget);
      expect(submitCount, 0);

      await tester.tap(find.byKey(VoiceComposerIndicator.stopKey));
      await tester.pumpAndSettle();

      expect(field.controller!.text, 'Draft final dictated words');
      expect(find.byKey(VoiceComposerIndicator.indicatorKey), findsNothing);
      expect(voice.stopCount, 1);
      expect(submitCount, 0);
    },
  );

  testWidgets(
    'Stop keeps dictation and Cancel restores exactly with zero submit',
    (tester) async {
      final voice = FakeVoiceComposerAdapter();
      var submitCount = 0;
      await _pumpChat(
        tester,
        voice: voice,
        remoteSubmit:
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
      final field = tester.widget<TextField>(find.byType(TextField));

      field.controller!.value = const TextEditingValue(
        text: 'prefix suffix',
        selection: TextSelection(baseOffset: 7, extentOffset: 13),
      );
      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump();
      voice.emitPartial('spoken');
      await tester.pump();
      await tester.tap(find.byKey(VoiceComposerIndicator.stopKey));
      await tester.pump();
      expect(field.controller!.text, 'prefix spoken');
      expect(submitCount, 0);

      const snapshot = TextEditingValue(
        text: 'keep exact',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      field.controller!.value = snapshot;
      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump();
      voice.emitPartial('replace');
      await tester.pump();
      await tester.tap(find.byKey(VoiceComposerIndicator.cancelKey));
      await tester.pump(const Duration(seconds: 3));

      expect(field.controller!.value, snapshot);
      expect(submitCount, 0);
      expect(voice.stopCount, 1);
      expect(voice.cancelCount, 1);
    },
  );

  testWidgets(
    'listening elapsed and actions stay semantic without compact overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final voice = FakeVoiceComposerAdapter();
      final semantics = tester.ensureSemantics();

      await _pumpChat(tester, voice: voice, textScale: 2);
      await tester.tap(find.bySemanticsLabel('Start voice input'));
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.bySemanticsLabel(RegExp(r'Listening, elapsed 00:02')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Stop voice input'), findsOneWidget);
      expect(find.bySemanticsLabel('Cancel voice input'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(VoiceComposerIndicator.stopKey));
      await tester.pump();
      expect(voice.stopCount, 1);
      expect(find.byKey(VoiceComposerIndicator.indicatorKey), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required FakeVoiceComposerAdapter voice,
  TestRemotePromptSubmit? remoteSubmit,
  double textScale = 1,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://voice.fixture',
    apiKey: 'synthetic-key',
    httpClient: _EmptyChatHttpClient(),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ChatScreen(
        connection: SavedConnection(
          id: 'voice-fixture',
          label: 'Voice fixture',
          host: 'voice.fixture',
          port: 8642,
          apiKey: 'synthetic-key',
        ),
        session: const Session(
          id: 'voice-session',
          title: 'Voice chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: apiClient,
        testRemotePromptSubmit: completedStockTurn(remoteSubmit),
        testVoiceComposerAdapter: voice,
      ),
    ),
  );
  await tester.pumpAndSettle();
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
