import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/attachment_preview_dialog.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/completed_stock_turn.dart';
import 'support/fake_voice_composer_adapter.dart';

const _path = '/Users/sam/.hermes/image_cache/generated.png';
const _result = {
  'success': true,
  'image': _path,
  'host_image': _path,
  'agent_visible_image': '/sandbox/.hermes/image_cache/generated.png',
};
final _connection = SavedConnection(
  id: 'generated-image-card',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture',
);
const _session = Session(
  id: 'stored-image-chat',
  title: 'Images',
  model: 'fixture',
  source: 'desktop',
  messageCount: 0,
  isActive: false,
  preview: '',
  startedAt: 1,
);

/// Producer fixture matches tool.complete's actual name/args/result contract.
/// The final answer deliberately has neither MEDIA nor any image/file link.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  testWidgets('image_generate plus Done renders and previews an image in quiet '
      'chat, then reopens from raw saved JSON without resubmitting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final remote = _ImageRemote();
    final liveController = GatewayTurnApplicationController();
    addTearDown(liveController.close);
    final files = _ImageFiles();
    await _open(tester, remote, liveController, files);
    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Generate an image and send it to me.',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(remote.submissions, 1);
    final liveCard = find.byType(MediaArtifactCard);
    expect(liveCard.hitTestable(), findsOneWidget);
    expect(tester.widget<MediaArtifactCard>(liveCard).ref.path, _path);
    expect(tester.widget<MediaArtifactCard>(liveCard).ref.extension, 'png');
    expect(
      tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .where((bubble) => !bubble.isUser)
          .map((bubble) => bubble.content),
      ['Done.'],
    );
    expect(files.requests, isEmpty, reason: 'Rendering must not fetch bytes.');

    // Reach the actual image popup from the user-visible card, not just a
    // parser assertion. The same exact host path must reach the file source.
    await tester.tap(
      find.descendant(of: liveCard, matching: find.byType(ListTile)),
    );
    await tester.pumpAndSettle();
    expect(files.requests, [_path]);
    expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AttachmentPreviewDialog),
        matching: find.byType(Image),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(AttachmentPreviewDialog))).pop();
    await tester.pumpAndSettle();

    // A fresh application owner is a cold history reopen, not in-memory
    // received output lending its attachment to canonical history.
    final readsBefore = remote.historyReads;
    remote.history = [
      {
        'id': 1,
        'role': 'user',
        'content': 'Generate an image and send it to me.',
      },
      {
        'id': 2,
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'call-image',
            'type': 'function',
            'function': {
              'name': 'image_generate',
              'arguments': '{"prompt":"a red square"}',
            },
          },
        ],
      },
      {
        'id': 3, 'role': 'tool', 'tool_call_id': 'call-image',
        // Raw saved tool rows need not carry name. Only the real tool_calls
        // correlation above establishes the producer, never an output heuristic.
        'content': jsonEncode(_result), 'timestamp': 10,
      },
      {
        'id': 4,
        'role': 'assistant',
        'content': 'Done.',
        'timestamp': 11,
        'finish_reason': 'stop',
      },
    ];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final reopenedController = GatewayTurnApplicationController();
    addTearDown(reopenedController.close);
    await _open(
      tester,
      remote,
      reopenedController,
      files,
      key: const ValueKey('cold-history-reopen'),
    );
    expect(remote.historyReads, greaterThan(readsBefore));
    expect(
      remote.submissions,
      1,
      reason: 'History browsing must not invoke the agent.',
    );
    final savedCard = find.byType(MediaArtifactCard);
    expect(savedCard.hitTestable(), findsOneWidget);
    expect(tester.widget<MediaArtifactCard>(savedCard).ref.path, _path);
    expect(
      tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .where((bubble) => !bubble.isUser)
          .map((bubble) => bubble.content),
      ['Done.'],
    );
    expect(files.requests, [
      _path,
    ], reason: 'Reopening must not auto-download.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _open(
  WidgetTester tester,
  _ImageRemote remote,
  GatewayTurnApplicationController controller,
  _ImageFiles files, {
  Key? key,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        key: key,
        connection: _connection,
        session: _session,
        turnApplicationController: controller,
        testApiClient: ApiClient(
          baseUrl: _connection.baseUrl,
          apiKey: 'fixture',
          httpClient: MockClient((_) async {
            remote.historyReads++;
            return http.Response(
              jsonEncode({'data': remote.history}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
        testRemotePromptSubmit: completedStockTurn(remote.submit),
        testStoredSessionKey: (_) => _session.id,
        testMediaFilesClient: (sessionId) {
          expect(sessionId, _session.id);
          return files;
        },
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ImageRemote {
  List<Map<String, dynamic>> history = [];
  int historyReads = 0;
  int submissions = 0;

  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) async {
    submissions++;
    onSent();
    onEvent(
      StreamEvent(
        type: 'tool.start',
        data: const {
          'tool_id': 'call-image',
          'name': 'image_generate',
          'args': {'prompt': 'a red square'},
        },
      ),
    );
    onEvent(
      StreamEvent(
        type: 'tool.complete',
        data: const {
          'tool_id': 'call-image',
          'name': 'image_generate',
          'args': {'prompt': 'a red square'},
          'result': _result,
          'duration_s': 1.2,
        },
      ),
    );
    onEvent(
      StreamEvent(type: 'message.complete', data: const {'text': 'Done.'}),
    );
  }
}

class _ImageFiles implements RemoteFilesDataSource {
  final requests = <String>[];

  @override
  Future<RemoteFileDownload> download(String path) async {
    requests.add(path);
    return RemoteFileDownload(
      filename: 'generated.png',
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      ),
    );
  }

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();
  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();
  @override
  Future<RemoteTextPreview> readText(String path) => throw UnimplementedError();
}
