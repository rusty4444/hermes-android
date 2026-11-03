import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final exports = <String>[];
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    exports.clear();
    messenger.setMockMethodCallHandler(share, (call) async {
      if (call.method == 'share') {
        exports.add((call.arguments as Map)['text'] as String);
      }
      return 'success';
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(share, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
  });

  for (final exclusion in <Map<String, dynamic>>[
    {'display_kind': 'hidden'},
    {'display_kind': 'compaction'},
    {
      'display_metadata': {'model_only': true},
    },
    {'display_content': null},
    {'display_content': ''},
  ]) {
    testWidgets(
      'legacy export honours public exclusion ${jsonEncode(exclusion)}',
      (tester) async {
        final rows = <Map<String, dynamic>>[
          {'id': 1, 'role': 'user', 'content': 'Visible question'},
          {'id': 2, 'role': 'assistant', 'content': 'Visible answer'},
          for (final role in ['user', 'assistant', 'agent'])
            {
              'id': 3 + ['user', 'assistant', 'agent'].indexOf(role),
              'role': role,
              'content': 'PRIVATE $role CONTENT',
              ...exclusion,
            },
        ];
        final raw = jsonEncode(rows);
        await _openAndExport(tester, rows);
        expect(exports, hasLength(1));
        expect(exports.single, contains('Visible question'));
        expect(exports.single, contains('Visible answer'));
        expect(exports.single, isNot(contains('PRIVATE')));
        expect(jsonEncode(rows), raw);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'legacy export uses public replacement, not physical tool wrapper',
    (tester) async {
      await _openAndExport(tester, [
        {
          'id': 1,
          'role': 'user',
          'content': AndroidPromptContext.forModel('Visible question'),
        },
        {
          'id': 2,
          'role': 'assistant',
          'content': '<untrusted_tool_result>PRIVATE</untrusted_tool_result>',
          'display_content': 'Public replacement',
        },
      ]);
      expect(exports.single, contains('Visible question'));
      expect(exports.single, contains('Public replacement'));
      expect(exports.single, isNot(contains('PRIVATE')));
      expect(exports.single, isNot(contains(AndroidPromptContext.header)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('legacy export keeps image-only refresh text clean', (
    tester,
  ) async {
    await _openAndExport(tester, [
      {
        'id': 1,
        'role': 'user',
        'content': GatewayChatClient.buildUserContent(
          message: '',
          imageDataUrl: 'data:image/png;base64,Zml4dHVyZQ==',
        ),
      },
      {'id': 2, 'role': 'assistant', 'content': 'Image reply'},
    ]);
    expect(exports.single, contains('[Image]'));
    expect(exports.single, isNot(contains('[Unsupported content:')));
    expect(exports.single, isNot(contains(AndroidPromptContext.header)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'legacy export preserves literal notes on slash and ordinary inputs',
    (tester) async {
      const slash = '/custom literal${AndroidPromptContext.suffix}';
      const ordinary = 'Explain literal${AndroidPromptContext.suffix}';
      await _openAndExport(tester, [
        {
          'id': 1,
          'role': 'user',
          'content': AndroidPromptContext.forModel(slash),
        },
        {'id': 2, 'role': 'assistant', 'content': 'First answer'},
        {
          'id': 3,
          'role': 'user',
          'content': AndroidPromptContext.forModel(ordinary),
        },
        {'id': 4, 'role': 'assistant', 'content': 'Second answer'},
      ]);
      expect(exports.single, contains(slash));
      expect(exports.single, contains(ordinary));
      expect(
        AndroidPromptContext.header.allMatches(exports.single),
        hasLength(2),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _openAndExport(
  WidgetTester tester,
  List<Map<String, dynamic>> rows,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final connection = SavedConnection(
    id: 'legacy-export',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture',
  );
  var reads = 0;
  final api = ApiClient(
    baseUrl: connection.baseUrl,
    apiKey: 'fixture',
    httpClient: MockClient((request) async {
      final Object body;
      if (request.url.path.endsWith('/messages')) {
        reads++;
        body = {'data': rows};
      } else {
        body = {'id': 'stored-export', 'archived': false, 'data': []};
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: connection,
        session: const Session(
          id: 'stored-export',
          title: 'Export fixture',
          model: 'fixture',
          source: 'api',
          messageCount: 2,
          isActive: false,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: api,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(reads, greaterThan(0), reason: 'Exercise hydrated raw history.');
  await tester.tap(find.byTooltip('Chat actions').hitTestable());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Export / share').hitTestable());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}
