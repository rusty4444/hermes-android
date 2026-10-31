import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_document_service.dart';
import 'package:hermes_android/core/widgets/attachment_document_preview.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

const _notice =
    'Text preview. Layout, images and formatting may differ from the original.';
const _failed =
    'This document could not be previewed. Save or share the original file.';
const _empty = 'No readable text was found in this document.';
const _word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _sheet = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _presentation =
    'http://schemas.openxmlformats.org/presentationml/2006/main';
const _drawing = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _officeRels =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _packageRels =
    'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  for (final entry in parts.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

Uint8List _docx(String text) => _zip({
  'word/document.xml':
      '<w:document xmlns:w="$_word"><w:body><w:p><w:r>'
      '<w:t>$text</w:t></w:r></w:p></w:body></w:document>',
});

Widget _host(
  Uint8List bytes, {
  String extension = 'docx',
  AttachmentDocumentLoader loader = AttachmentDocumentService.preview,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: brightness,
    ),
  ),
  home: Scaffold(
    body: AttachmentDocumentPreview(
      key: const Key('same-document-state'),
      bytes: bytes,
      extension: extension,
      loader: loader,
    ),
  ),
);

/// Isolate work runs outside the test clock. Yield deliberately in runAsync,
/// then pump the widget zone; never await a compute Future inside fake async or
/// pumpAndSettle while a loading spinner is intentionally still active.
Future<void> _waitFor(WidgetTester tester, bool Function() completed) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (completed()) return;
  }
  fail('Document worker did not finish within the bounded test wait');
}

Future<void> _waitForPreview(WidgetTester tester) => _waitFor(
  tester,
  () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
);

String? _previewText(WidgetTester tester) {
  final finder = find.byKey(const Key('attachment-document-preview'));
  return finder.evaluate().isEmpty
      ? null
      : tester.widget<SelectableText>(finder).data;
}

void main() {
  testWidgets('real DOCX compute renders labelled inert selectable text', (
    tester,
  ) async {
    const source =
        '# not Markdown\nhttps://example.invalid/private.png\n'
        '&lt;script&gt;fetch("https://example.invalid")&lt;/script&gt;';
    await tester.pumpWidget(_host(_docx(source)));
    expect(find.text(_notice), findsOneWidget);
    await _waitForPreview(tester);
    expect(
      _previewText(tester),
      '# not Markdown\nhttps://example.invalid/private.png\n'
      '<script>fetch("https://example.invalid")</script>\n',
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text(_failed), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real XLSX compute preserves the title and sparse coordinates', (
    tester,
  ) async {
    final bytes = _zip({
      'xl/workbook.xml':
          '<workbook xmlns="$_sheet" xmlns:r="$_officeRels">'
          '<sheets><sheet name="Accounts" r:id="sheet"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':
          '<Relationships xmlns="$_packageRels"><Relationship Id="sheet"'
          ' Type="$_officeRels/worksheet" Target="worksheets/one.xml"/></Relationships>',
      'xl/worksheets/one.xml':
          '<worksheet xmlns="$_sheet"><sheetData><row r="2">'
          '<c r="C2" t="inlineStr"><is><t>visible</t></is></c>'
          '<c r="E2"/></row></sheetData></worksheet>',
    });
    await tester.pumpWidget(_host(bytes, extension: 'xlsx'));
    await _waitForPreview(tester);
    expect(_previewText(tester), '[Accounts]\nC2\tvisible\nE2\t\n');
    expect(find.text(_notice), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real PPTX compute uses presentation relationship order', (
    tester,
  ) async {
    String slide(String text) =>
        '<p:sld xmlns:p="$_presentation" xmlns:a="$_drawing">'
        '<p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>$text</a:t>'
        '</a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
    final bytes = _zip({
      'ppt/presentation.xml':
          '<p:presentation xmlns:p="$_presentation" xmlns:r="$_officeRels">'
          '<p:sldIdLst><p:sldId id="400" r:id="ten"/>'
          '<p:sldId id="200" r:id="two"/></p:sldIdLst></p:presentation>',
      'ppt/_rels/presentation.xml.rels':
          '<Relationships xmlns="$_packageRels"><Relationship Id="two"'
          ' Type="$_officeRels/slide" Target="slides/slide2.xml"/>'
          '<Relationship Id="ten" Type="$_officeRels/slide"'
          ' Target="slides/slide10.xml"/></Relationships>',
      'ppt/slides/slide2.xml': slide('second'),
      'ppt/slides/slide10.xml': slide('first'),
    });
    await tester.pumpWidget(_host(bytes, extension: 'pptx'));
    await _waitForPreview(tester);
    expect(_previewText(tester), 'first\n\nsecond\n');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real malformed and empty documents have different fallback UI', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Uint8List.fromList([1, 2, 3])));
    await _waitForPreview(tester);
    expect(find.text(_failed), findsOneWidget);
    expect(find.text(_empty), findsNothing);
    expect(_previewText(tester), isNull);
    await tester.pumpWidget(_host(_docx('')));
    await _waitForPreview(tester);
    expect(find.text(_empty), findsOneWidget);
    expect(find.text(_failed), findsNothing);
    expect(find.text(_notice), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('truncation notice accompanies bounded selectable text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _docx(''),
        loader: (_, extension) async => const AttachmentDocumentPreviewData(
          text: 'bounded prefix',
          truncated: true,
        ),
      ),
    );
    await tester.pump();
    expect(_previewText(tester), 'bounded prefix');
    expect(
      find.text('Preview shortened. Save or share the file to read all of it.'),
      findsOneWidget,
    );
    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets(
    'ordinary parent rebuilds retain one pending or completed parse',
    (tester) async {
      final bytes = _docx('');
      final pending = Completer<AttachmentDocumentPreviewData>();
      var calls = 0;
      Future<AttachmentDocumentPreviewData> loader(
        Uint8List input,
        String extension,
      ) {
        calls++;
        return pending.future;
      }

      await tester.pumpWidget(_host(bytes, loader: loader));
      await tester.pumpWidget(
        _host(bytes, loader: loader, brightness: Brightness.dark),
      );
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(const AttachmentDocumentPreviewData(text: 'cached'));
      await tester.pump();
      await tester.pumpWidget(_host(bytes, loader: loader));
      expect(calls, 1);
      expect(_previewText(tester), 'cached');
    },
  );

  testWidgets('replacement coalesces pending parses and rejects stale output', (
    tester,
  ) async {
    final old = _docx('old');
    final skipped = _docx('skipped');
    final current = _docx('current');
    final oldResult = Completer<AttachmentDocumentPreviewData>();
    final currentResult = Completer<AttachmentDocumentPreviewData>();
    final inputs = <Uint8List>[];
    final extensions = <String>[];
    Future<AttachmentDocumentPreviewData> loader(
      Uint8List input,
      String extension,
    ) {
      inputs.add(input);
      extensions.add(extension);
      return inputs.length == 1 ? oldResult.future : currentResult.future;
    }

    await tester.pumpWidget(_host(old, loader: loader));
    await tester.pumpWidget(_host(skipped, loader: loader));
    await tester.pumpWidget(_host(current, loader: loader, extension: 'xlsx'));
    expect(inputs, hasLength(1));
    oldResult.complete(const AttachmentDocumentPreviewData(text: 'stale'));
    await tester.pump();
    expect(inputs, hasLength(2));
    expect(identical(inputs.last, current), isTrue);
    expect(extensions, ['docx', 'xlsx']);
    expect(_previewText(tester), isNull);
    expect(find.text('stale'), findsNothing);
    currentResult.complete(const AttachmentDocumentPreviewData(text: 'newest'));
    await tester.pump();
    expect(_previewText(tester), 'newest');
    expect(find.text('stale'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extension-only replacement hides previous content and errors', (
    tester,
  ) async {
    final bytes = _docx('');
    final pending = Completer<AttachmentDocumentPreviewData>();
    var calls = 0;
    Future<AttachmentDocumentPreviewData> loader(
      Uint8List input,
      String extension,
    ) async {
      calls++;
      if (extension == 'docx') {
        return const AttachmentDocumentPreviewData(text: 'old');
      }
      return pending.future;
    }

    await tester.pumpWidget(_host(bytes, loader: loader));
    await tester.pump();
    expect(_previewText(tester), 'old');
    await tester.pumpWidget(_host(bytes, loader: loader, extension: 'xlsx'));
    expect(calls, 2);
    expect(_previewText(tester), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(const FormatException('secret parser/path details'));
    await tester.pump();
    expect(find.text(_failed), findsOneWidget);
    expect(find.textContaining('secret parser'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure and readable text use the active dark theme palette', (
    tester,
  ) async {
    final bytes = _docx('');
    await tester.pumpWidget(
      _host(
        bytes,
        brightness: Brightness.dark,
        loader: (_, extension) async =>
            const AttachmentDocumentPreviewData.failed(),
      ),
    );
    await tester.pump();
    final context = tester.element(find.text(_failed));
    expect(
      tester.widget<Text>(find.text(_failed)).style?.color,
      Theme.of(context).colorScheme.onSurface,
    );
    expect(find.text(_notice), findsOneWidget);
    await tester.pumpWidget(
      _host(
        bytes,
        brightness: Brightness.dark,
        loader: (_, extension) async =>
            const AttachmentDocumentPreviewData(text: 'dark'),
      ),
    );
    await tester.pump();
    final selectable = tester.widget<SelectableText>(
      find.byKey(const Key('attachment-document-preview')),
    );
    expect(
      selectable.style?.color,
      Theme.of(
        tester.element(find.byKey(const Key('attachment-document-preview'))),
      ).colorScheme.onSurface,
    );
  });

  testWidgets(
    'disposal ignores late results and starts no queued replacement',
    (tester) async {
      final pending = Completer<AttachmentDocumentPreviewData>();
      var calls = 0;
      Future<AttachmentDocumentPreviewData> loader(
        Uint8List input,
        String extension,
      ) {
        calls++;
        return pending.future;
      }

      await tester.pumpWidget(_host(_docx('old'), loader: loader));
      await tester.pumpWidget(_host(_docx('queued'), loader: loader));
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(const AttachmentDocumentPreviewData(text: 'late'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('late'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real compute can finish after disposal without setState errors',
    (tester) async {
      var completed = false;
      Future<AttachmentDocumentPreviewData> loader(
        Uint8List input,
        String extension,
      ) async {
        try {
          return await AttachmentDocumentService.preview(input, extension);
        } finally {
          completed = true;
        }
      }

      await tester.pumpWidget(_host(_docx('late worker'), loader: loader));
      await tester.pumpWidget(const SizedBox.shrink());
      await _waitFor(tester, () => completed);
      expect(
        find.byKey(const Key('attachment-document-preview')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
