import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/delivered_files.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/media_markdown_fixtures.dart';

class _Files implements RemoteFilesDataSource {
  final requested = <String>[];

  @override
  Future<RemoteFileDownload> download(String path) async {
    requested.add(path);
    return RemoteFileDownload(filename: 'notes.txt', bytes: [104, 105]);
  }

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();
  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();
  @override
  Future<RemoteTextPreview> readText(String path) => throw UnimplementedError();
}

Future<void> _bubble(
  WidgetTester tester,
  String content,
  _Files files, {
  bool isUser = false,
  bool isFinal = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MessageBubble(
            content: content,
            isUser: isUser,
            mediaReferencesFinal: isFinal,
            mediaFilesClient: () => files,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('explicit delivered filesystem links', () {
    final links = <String, String>{
      '[report](/srv/report.pdf)': '/srv/report.pdf',
      '[notes](file:///srv/data/notes.txt)': '/srv/data/notes.txt',
      '[todo](~/todo.md)': '~/todo.md',
      '[notes](<~/My Notes/todo with spaces.md>)':
          '~/My Notes/todo with spaces.md',
      r'[log](C:\logs\run.txt)': r'C:\logs\run.txt',
      '[literal](/out/100%25%20done.txt)': '/out/100% done.txt',
      '[literal](/out/literal%.txt)': '/out/literal%.txt',
      '[日本語](</out/日本語 & notes.txt>)': '/out/日本語 & notes.txt',
      '![chart](/out/chart.png)': '/out/chart.png',
      '[config](/out/Makefile)': '/out/Makefile',
      '[report][ref]\n\n[ref]: /out/result.pdf': '/out/result.pdf',
    };
    for (final entry in links.entries) {
      test('recognises ${entry.key}', () {
        expect(extractDeliveredFileRefs(entry.key).map((ref) => ref.path), [
          entry.value,
        ]);
      });
    }

    test('preserves explicit MEDIA names without URL-decoding them', () {
      expect(
        extractDeliveredFileRefs('MEDIA:"/out/literal%20.txt"').single.path,
        '/out/literal%20.txt',
      );
      expect(
        extractDeliveredFileRefs(
          'MEDIA:/out/report.pdf\n[report](/out/report.pdf)',
        ).map((ref) => ref.path),
        ['/out/report.pdf'],
      );
    });

    test('does not index relative/web links or arbitrary prose paths', () {
      for (final text in [
        '[documentation](docs/guide.md)',
        '[website](https://example.com/report.pdf)',
        '![web image](https://example.com/image.png)',
        '[network](//example.com/report.pdf)',
        '[content](content://downloads/1)',
        '[script](javascript:alert(1))',
        '[data](data:text/plain,hello)',
        '[remote](file://other-host/out/report.pdf)',
        '/out/unlinked.pdf',
      ]) {
        expect(extractDeliveredFileRefs(text), isEmpty, reason: text);
      }
    });

    test('keeps all protected Markdown containers inert', () {
      for (final example in mediaMarkdownExamples.values) {
        final source = example.replaceAll(
          'MEDIA:/out/example.pdf',
          '[example](/out/example.pdf)',
        );
        expect(
          extractDeliveredFileRefs(
            '$source\n\n[real](/out/real.pdf)',
          ).map((ref) => ref.path),
          ['/out/real.pdf'],
          reason: source,
        );
      }
      for (final source in [
        '`[example](/out/example.pdf)`',
        '~~~md\n[example](/out/example.pdf)\n~~~',
        '    [example](/out/example.pdf)',
      ]) {
        expect(extractDeliveredFileRefs(source), isEmpty);
      }
    });

    test('partial Markdown and unmatched live code stay non-actionable', () {
      expect(
        extractDeliveredFileRefs('[file](/out/a.pdf', isFinal: false),
        isEmpty,
      );
      expect(
        extractDeliveredFileRefs('`example [file](/out/a.pdf)', isFinal: false),
        isEmpty,
      );
      expect(
        extractDeliveredFileRefs(
          'MEDIA:/out/a.png',
          isFinal: false,
        ).single.path,
        '/out/a.png',
      );
      expect(
        extractDeliveredFileRefs('MEDIA:/out/Makefile', isFinal: false),
        isEmpty,
      );
    });

    test('rejects malformed URLs without throwing from a tap callback', () {
      for (final href in [
        '/out/bad%ZZ.pdf',
        '/out/line%0Abreak.pdf',
        'file:///out/a.pdf?query=not-a-path',
        'file:///out/a.pdf#fragment',
        'media-artifact://%ZZ',
      ]) {
        expect(deliveredFilePathFromHref(href), isNull);
      }
    });

    test(
      'URL filename excludes query and supports producer filename hints',
      () {
        expect(
          const MediaTagRef(
            path: 'https://cdn.example/chart.png?token=example',
          ).filename,
          'chart.png',
        );
        expect(
          const MediaTagRef(
            path: 'https://cdn.example/opaque',
            suggestedFilename: 'generated-image.png',
          ).extension,
          'png',
        );
      },
    );
  });

  testWidgets('assistant Markdown deliveries are lazy timeline cards', (
    tester,
  ) async {
    final files = _Files();
    await _bubble(tester, 'Done. [notes](/out/notes.txt)', files);
    expect(find.byType(MediaArtifactCard), findsOneWidget);
    expect(files.requested, isEmpty);
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    expect(files.requested, ['/out/notes.txt']);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsWidgets);
  });

  testWidgets(
    'image Markdown becomes a lazy card, not an eager image request',
    (tester) async {
      final files = _Files();
      await _bubble(tester, '![generated chart](/out/chart.png)', files);
      expect(find.byType(MediaArtifactCard), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(files.requested, isEmpty);
    },
  );

  testWidgets('same MEDIA and Markdown reference produces only one card', (
    tester,
  ) async {
    final files = _Files();
    await _bubble(
      tester,
      'MEDIA:/out/notes.txt\n\n[notes](/out/notes.txt)',
      files,
    );
    expect(find.byType(MediaArtifactCard), findsOneWidget);
  });

  testWidgets(
    'quoted examples, user links and partial streaming links stay inert',
    (tester) async {
      final files = _Files();
      await _bubble(tester, '> [example](/out/notes.txt)', files);
      expect(find.byType(MediaArtifactCard), findsNothing);
      await tester.tap(find.text('example'));
      await tester.pumpAndSettle();
      expect(files.requested, isEmpty);
      await _bubble(tester, '[notes](/out/notes.txt)', files, isUser: true);
      expect(find.byType(MediaArtifactCard), findsNothing);
      await _bubble(tester, '[notes](/out/notes.txt)', files, isFinal: false);
      expect(find.byType(MediaArtifactCard), findsNothing);
      await _bubble(tester, '[notes](/out/notes.txt)', files);
      expect(find.byType(MediaArtifactCard), findsOneWidget);
      expect(files.requested, isEmpty);
    },
  );
}
