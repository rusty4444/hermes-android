import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';

List<String> render(List<MediaTextSegment> segments) =>
    segments.map((s) => s.isMedia ? 'CARD:${s.media!.path}' : s.text).toList();

class _FakeFiles implements RemoteFilesDataSource {
  final Map<String, List<int>> files;
  final List<String> requested = [];
  _FakeFiles(this.files);

  @override
  Future<RemoteDirectory> defaultDirectory() async =>
      throw UnimplementedError();

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async =>
      throw UnimplementedError();

  @override
  Future<RemoteTextPreview> readText(String path) async =>
      throw UnimplementedError();

  @override
  Future<RemoteFileDownload> download(String path) async {
    requested.add(path);
    final bytes = files[path];
    if (bytes == null) throw Exception('no such file: $path');
    return RemoteFileDownload(filename: path.split('/').last, bytes: bytes);
  }
}

void main() {
  group('splitMediaTags (cards only for standalone-line refs)', () {
    test('plain text passes through untouched', () {
      expect(render(splitMediaTags('nothing here')), ['nothing here']);
    });

    test('tag alone on its line becomes a card and consumes the line', () {
      expect(
        render(splitMediaTags('Here you go:\nMEDIA:/home/jon/out.png\nbye')),
        ['Here you go:\n', 'CARD:/home/jon/out.png', 'bye'],
      );
    });

    test('mid-line tag stays prose (rendered later as an inline link)', () {
      expect(
        render(
          splitMediaTags('Here is the chart MEDIA:/home/jon/out.png done'),
        ),
        ['Here is the chart MEDIA:/home/jon/out.png done'],
      );
    });

    test('trailing punctuation on a standalone tag sheds into prose', () {
      expect(render(splitMediaTags('MEDIA:/tmp/a.pdf.')), [
        'CARD:/tmp/a.pdf',
        '.',
      ]);
    });

    test('degenerate captures stay prose', () {
      expect(render(splitMediaTags('MEDIA:...')), ['MEDIA:...']);
      expect(render(splitMediaTags('MEDIA:stuff')), ['MEDIA:stuff']);
    });

    test('quoted capture keeps interior spaces and punctuation', () {
      expect(render(splitMediaTags('MEDIA:"/tmp/my file.png"')), [
        'CARD:/tmp/my file.png',
      ]);
      expect(render(splitMediaTags("MEDIA:'/tmp/stop!.md'")), [
        'CARD:/tmp/stop!.md',
      ]);
    });

    test('multiple standalone refs each become a card', () {
      expect(render(splitMediaTags('MEDIA:/a.png\nMEDIA:/b.pdf')), [
        'CARD:/a.png',
        'CARD:/b.pdf',
      ]);
    });

    test('streaming partial at end of text stays prose', () {
      // Mid-token: the next delta could extend the path.
      expect(render(splitMediaTags('here MEDIA:/home/jon/repo')), [
        'here MEDIA:/home/jon/repo',
      ]);
    });

    test('completed path at end of text converts to a card', () {
      expect(render(splitMediaTags('here:\nMEDIA:/home/jon/report.pdf')), [
        'here:\n',
        'CARD:/home/jon/report.pdf',
      ]);
    });

    test('windows and tilde anchors parse', () {
      expect(render(splitMediaTags(r'MEDIA:C:\out\chart.png')), [
        'CARD:C:\\out\\chart.png',
      ]);
      expect(render(splitMediaTags('MEDIA:~/docs/note.md')), [
        'CARD:~/docs/note.md',
      ]);
    });

    test('apostrophes stay inside bare paths', () {
      expect(render(splitMediaTags("MEDIA:/tmp/john's.md")), [
        "CARD:/tmp/john's.md",
      ]);
    });

    test('uppercase extension parses (guard and pattern agree)', () {
      expect(render(splitMediaTags('MEDIA:/tmp/x.PNG')), ['CARD:/tmp/x.PNG']);
    });
  });

  group('inlineMediaTagsAsLinks', () {
    test('mid-line ref becomes a markdown link with the basename label', () {
      expect(
        inlineMediaTagsAsLinks('see MEDIA:/tmp/report.pdf ok'),
        'see [report.pdf](media-artifact:///tmp/report.pdf) ok',
      );
    });

    test('degenerate captures are left alone', () {
      expect(inlineMediaTagsAsLinks('MEDIA:stuff'), 'MEDIA:stuff');
    });

    test('streaming partial at end of text is not linked', () {
      expect(
        inlineMediaTagsAsLinks('see MEDIA:/tmp/repo'),
        'see MEDIA:/tmp/repo',
      );
    });
  });

  group('MessageBubble media rendering', () {
    Future<void> pumpBubble(
      WidgetTester tester, {
      required String content,
      required bool isUser,
      RemoteFilesDataSource Function()? filesClient,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              content: content,
              isUser: isUser,
              mediaFilesClient: filesClient,
            ),
          ),
        ),
      );
    }

    testWidgets('standalone ref renders a card, prose stays markdown', (
      tester,
    ) async {
      final files = _FakeFiles({
        '/out/report.pdf': [1, 2, 3],
      });
      await pumpBubble(
        tester,
        content: 'Done.\nMEDIA:/out/report.pdf',
        isUser: false,
        filesClient: () => files,
      );
      expect(find.byKey(Key('media-card-/out/report.pdf')), findsOneWidget);
      expect(find.textContaining('Done.'), findsOneWidget);
    });

    testWidgets('mid-line ref does NOT fragment into a card', (tester) async {
      await pumpBubble(
        tester,
        content: '- fetch the chart MEDIA:/out/a.png and open it',
        isUser: false,
        filesClient: () => _FakeFiles({}),
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('MEDIA: inside a closed code fence stays verbatim', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        content: 'example:\n```\nMEDIA:/fake.png\n```\nend',
        isUser: false,
        filesClient: () => _FakeFiles({}),
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('MEDIA: inside an UNCLOSED fence (streaming) leaks no card', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        content: 'doc:\n```md\nMEDIA:/tmp/example.png',
        isUser: false,
        filesClient: () => _FakeFiles({}),
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('user bubbles never parse refs', (tester) async {
      await pumpBubble(
        tester,
        content: 'Done.\nMEDIA:/out/report.pdf',
        isUser: true,
        filesClient: () => _FakeFiles({}),
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('no files client leaves refs as prose', (tester) async {
      await pumpBubble(
        tester,
        content: 'Done.\nMEDIA:/out/report.pdf',
        isUser: false,
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('tap downloads via the exact ref path', (tester) async {
      final files = _FakeFiles({
        '/out/report.pdf': [1, 2, 3],
      });
      await pumpBubble(
        tester,
        content: 'MEDIA:/out/report.pdf',
        isUser: false,
        filesClient: () => files,
      );
      await tester.tap(find.byKey(Key('media-card-download-/out/report.pdf')));
      await tester.pump();
      // The share sheet is platform UI; assert only that the gateway fetch
      // fired for the exact ref path.
      expect(files.requested, ['/out/report.pdf']);
    });

    testWidgets(
      'ref change resets card state (no stale bytes under new name)',
      (tester) async {
        final files = _FakeFiles({
          '/a/x.pdf': [1],
          '/b/y.pdf': [2],
        });
        await pumpBubble(
          tester,
          content: 'MEDIA:/a/x.pdf',
          isUser: false,
          filesClient: () => files,
        );
        await tester.tap(find.byKey(Key('media-card-download-/a/x.pdf')));
        await tester.pump();
        expect(files.requested, ['/a/x.pdf']);
        // Same position, different ref (streaming ref growth / recycling).
        await pumpBubble(
          tester,
          content: 'MEDIA:/b/y.pdf',
          isUser: false,
          filesClient: () => files,
        );
        await tester.pump();
        // The new card must not show a downloaded state from the old ref.
        expect(find.textContaining('Tap to download'), findsOneWidget);
      },
    );
  });
}
