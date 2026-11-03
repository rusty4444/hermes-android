import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/widgets/attachment_preview_dialog.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:image/image.dart' as image;

class _Files extends Fake implements RemoteFilesDataSource {
  _Files(this.payload);
  final List<int> payload;
  final requests = <String>[];
  Completer<RemoteFileDownload>? held;

  @override
  Future<RemoteFileDownload> download(String path) async {
    requests.add(path);
    return held?.future ??
        RemoteFileDownload(filename: 'ignored', bytes: payload);
  }
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
    return 'content://saved/file';
  }
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _bubble(
  String source,
  String text,
  _Files files, {
  Map<String, dynamic> metadata = const {},
}) => MessageBubble(
  key: const ValueKey('same-bubble'),
  content: text,
  isUser: false,
  metadata: metadata,
  mediaFilesClient: () => files,
  mediaSourceIdentity: source,
);

void _openInline(WidgetTester tester) {
  tester.widget<MarkdownBody>(find.byType(MarkdownBody).first).onTapLink!(
    'file',
    '/old.txt',
    '',
  );
}

void main() {
  late _Picker picker;
  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() => FilePicker.platform = FilePickerIO());

  for (final replacement in ['unmount', 'source', 'reference']) {
    testWidgets(
      'inline preview revokes held bytes on $replacement replacement',
      (tester) async {
        final old = _Files(utf8.encode('OLD PRIVATE BYTES'))
          ..held = Completer<RemoteFileDownload>();
        final current = _Files(utf8.encode('NEW BYTES'));
        await tester.pumpWidget(
          _app(_bubble('source-A', '[old](/old.txt)', old)),
        );
        _openInline(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final controller = tester
            .widget<AttachmentPreviewDialog>(
              find.byType(AttachmentPreviewDialog),
            )
            .controller;
        expect(old.requests, ['/old.txt']);
        await tester.pumpWidget(
          _app(
            replacement == 'unmount'
                ? const Text('No bubble')
                : _bubble(
                    replacement == 'source' ? 'source-B' : 'source-A',
                    replacement == 'reference'
                        ? 'No delivered file.'
                        : '[new owner](/old.txt)',
                    current,
                  ),
          ),
        );
        old.held!.complete(
          RemoteFileDownload(
            filename: 'old.txt',
            bytes: utf8.encode('OLD PRIVATE BYTES'),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.active, isFalse);
        expect(find.byType(AttachmentPreviewDialog), findsNothing);
        await controller.save(dialogTitle: 'Save');
        await controller.share();
        expect(picker.names, isEmpty);
        expect(current.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('ordinary same-source rebuild retains the inline held download', (
    tester,
  ) async {
    final files = _Files(utf8.encode('owned bytes'))
      ..held = Completer<RemoteFileDownload>();
    await tester.pumpWidget(_app(_bubble('A', '[old](/old.txt)', files)));
    _openInline(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(
      _app(_bubble('A', 'More prose. [old](/old.txt)', files)),
    );
    files.held!.complete(
      RemoteFileDownload(
        filename: 'ignored',
        bytes: utf8.encode('owned bytes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('attachment-preview-save')));
    await tester.pumpAndSettle();
    expect(picker.names, ['old.txt']);
    expect(picker.payloads.single, utf8.encode('owned bytes'));
    expect(files.requests, ['/old.txt']);
    await tester.tap(find.byKey(const Key('attachment-preview-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('revocation removes only the inline popup, not a newer route', (
    tester,
  ) async {
    final files = _Files(utf8.encode('hello'));
    await tester.pumpWidget(_app(_bubble('A', '[old](/old.txt)', files)));
    _openInline(tester);
    await tester.pumpAndSettle();
    final dialogContext = tester.element(find.byType(AttachmentPreviewDialog));
    unawaited(
      showDialog<void>(
        context: dialogContext,
        builder: (_) => const AlertDialog(title: Text('Other route')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(const Text('Origin removed')));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentPreviewDialog), findsNothing);
    expect(find.text('Other route'), findsOneWidget);
    Navigator.of(tester.element(find.text('Other route'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'select-text link previews retain their originating bubble owner',
    (tester) async {
      final files = _Files(utf8.encode('hello'));
      await tester.pumpWidget(_app(_bubble('A', '[old](/old.txt)', files)));
      await tester.longPress(find.byKey(const Key('message-bubble')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select text'));
      await tester.pumpAndSettle();
      tester
          .widget<MarkdownBody>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(MarkdownBody),
            ),
          )
          .onTapLink!('old', '/old.txt', '');
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
      await tester.pumpWidget(_app(const Text('Origin removed')));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentPreviewDialog), findsNothing);
      expect(find.text('Select text'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(picker.names, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final inline in [false, true]) {
    testWidgets(
      'extensionless generated URL echo retains image preview inline=$inline',
      (tester) async {
        const url = 'https://cdn.example/generated/opaque-id?format=png';
        final rows = <Map<String, dynamic>>[
          {
            'id': 2,
            'role': 'tool',
            'tool_name': 'image_generate',
            'tool_call_id': 'image-1',
            'content': jsonEncode({'success': true, 'image': url}),
          },
          {
            'id': 3,
            'role': 'assistant',
            'content': inline ? 'Here it is: MEDIA:"$url".' : 'MEDIA:"$url"',
          },
        ];
        final before = jsonEncode(rows);
        final items = buildChatDisplayItems(messages: rows);
        expect(items.whereType<ChatAttachmentItem>(), isEmpty);
        final row = items.whereType<Map<String, dynamic>>().single;
        final files = _Files(image.encodePng(image.Image(width: 2, height: 2)));
        await tester.pumpWidget(
          _app(
            _bubble(
              'A',
              row['_display_content'] as String,
              files,
              metadata: row,
            ),
          ),
        );
        expect(files.requests, isEmpty);
        if (inline) {
          final markdown = tester.widget<MarkdownBody>(
            find.byType(MarkdownBody).first,
          );
          final href = RegExp(
            r'\]\(([^)]+)\)',
          ).firstMatch(markdown.data)!.group(1)!;
          markdown.onTapLink!('file', href, '');
        } else {
          final card = tester.widget<MediaArtifactCard>(
            find.byType(MediaArtifactCard),
          );
          expect(card.ref.filename, 'generated-image.png');
          expect(card.ref.extension, 'png');
          await tester.tap(
            find.descendant(
              of: find.byType(MediaArtifactCard),
              matching: find.byType(ListTile),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('attachment-image-preview')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('attachment-preview-save')));
        await tester.pumpAndSettle();
        expect(picker.names, ['generated-image.png']);
        expect(picker.payloads.single, files.payload);
        expect(files.requests, [url]);
        expect(jsonEncode(rows), before);
        await tester.tap(find.byKey(const Key('attachment-preview-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
