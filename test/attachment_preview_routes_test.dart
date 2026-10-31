import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/assets_screen.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_assets_client.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/widgets/attachment_document_preview.dart';
import 'package:hermes_android/core/widgets/attachment_preview_dialog.dart';
import 'package:hermes_android/core/widgets/attachment_video_preview.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

const _session = Session(
  id: 'preview-session',
  title: 'Attachment previews',
  model: 'fixture',
  source: 'desktop',
  messageCount: 2,
  isActive: false,
  preview: '',
  startedAt: 1,
);

List<Map<String, dynamic>> _history(String path) => [
  {'id': 1, 'role': 'user', 'content': 'Please send the file.'},
  {
    'id': 2,
    'role': 'assistant',
    'content': 'MEDIA:$path',
    'timestamp': 10,
    'finish_reason': 'stop',
  },
];

Uint8List _document() {
  final xml = utf8.encode(
    '<w:document xmlns:w="http://schemas.openxmlformats.org/'
    'wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>'
    'Offline document preview</w:t></w:r></w:p></w:body></w:document>',
  );
  return Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('word/document.xml', xml.length, xml)),
    ),
  );
}

class _Files extends Fake implements RemoteFilesDataSource {
  _Files(this.bytes);
  final Uint8List bytes;
  final paths = <String>[];

  @override
  Future<RemoteFileDownload> download(String path) async {
    paths.add(path);
    return RemoteFileDownload(
      filename: 'server-name-is-not-authority',
      bytes: bytes,
    );
  }
}

class _Assets implements ChatAssetsDataSource {
  _Assets(this.path);
  final String path;

  @override
  Future<ChatAssetsSessionPage> listSessions({
    int offset = 0,
    int limit = 10,
  }) async => ChatAssetsSessionPage(
    sessions: [_session],
    nextOffset: offset + limit,
    hasMore: false,
    partial: false,
  );

  @override
  Future<ChatAssetsMessagePage> getMessages(
    Session session, {
    int offset = 0,
    int limit = 100,
  }) async => ChatAssetsMessagePage(
    messages: _history(path),
    nextOffset: offset + limit,
    hasMore: false,
  );
}

class _Picker extends FilePicker {
  final names = <String?>[];
  final payloads = <Uint8List?>[];

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    names.add(fileName);
    payloads.add(bytes);
    return 'content://saved/original';
  }
}

Future<void> _open(
  WidgetTester tester,
  String surface,
  String path,
  _Files files,
) async {
  final controller = GatewayTurnApplicationController();
  addTearDown(controller.close);
  final connection = SavedConnection(
    id: 'preview-connection',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture',
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: surface == 'Assets'
          ? AssetsScreen(
              source: _Assets(path),
              filesClient: (_) => files,
              onOpenSession: (_) {},
            )
          : ChatScreen(
              connection: connection,
              session: _session,
              turnApplicationController: controller,
              testApiClient: ApiClient(
                baseUrl: connection.baseUrl,
                apiKey: 'fixture',
                httpClient: MockClient(
                  (_) async => http.Response(
                    jsonEncode({'data': _history(path)}),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  ),
                ),
              ),
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

Future<void> _waitForDocument(WidgetTester tester) async {
  // compute() runs outside fake async; alternate real event-loop turns with
  // frames rather than treating a mocked parser response as rendering proof.
  for (var i = 0; i < 100; i++) {
    if (find
        .byKey(const Key('attachment-document-preview'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  fail('The real Office document parser did not produce its preview.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    FilePicker.platform = picker = _Picker();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(() {
    FilePicker.platform = FilePickerIO();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        );
  });

  for (final surface in ['Chat', 'Assets']) {
    for (final extension in ['docx', 'mp4']) {
      testWidgets(
        '$surface routes $extension to its viewer, saves original bytes '
        'and reopens from history without eager fetching',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1000, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final path = '/gateway/report.$extension';
          final original = extension == 'docx'
              ? _document()
              : Uint8List.fromList([1, 2, 3]);
          final files = _Files(original);
          await _open(tester, surface, path, files);
          expect(find.text('report.$extension').hitTestable(), findsOneWidget);
          expect(files.paths, isEmpty);

          await tester.tap(find.text('report.$extension'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
          if (extension == 'docx') {
            expect(find.byType(AttachmentDocumentPreview), findsOneWidget);
            await _waitForDocument(tester);
            expect(
              tester
                  .widget<SelectableText>(
                    find.byKey(const Key('attachment-document-preview')),
                  )
                  .data,
              contains('Offline document preview'),
            );
            expect(find.textContaining('Text preview.'), findsOneWidget);
          } else {
            // The widget tests do not have a native media player; its failure is
            // contained by the video viewer and must not remove file actions.
            expect(find.byType(AttachmentVideoPreview), findsOneWidget);
          }
          expect(files.paths, [path]);
          await tester.tap(find.byKey(const Key('attachment-preview-save')));
          await tester.pump();
          expect(picker.names, ['report.$extension']);
          expect(picker.payloads.single, orderedEquals(original));
          expect(
            find.byKey(const Key('attachment-preview-share')),
            findsOneWidget,
          );
          expect(files.paths, [path]);

          await tester.tap(find.byKey(const Key('attachment-preview-close')));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await _open(tester, surface, path, files);
          expect(find.text('report.$extension').hitTestable(), findsOneWidget);
          expect(files.paths, [path], reason: 'History reopen must not fetch.');
          await tester.tap(find.text('report.$extension'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          if (extension == 'docx') await _waitForDocument(tester);
          expect(files.paths, [path, path]);
          expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
          await tester.tap(find.byKey(const Key('attachment-preview-close')));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
