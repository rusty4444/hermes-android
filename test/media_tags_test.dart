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
  group('splitMediaTags', () {
    test('plain text passes through untouched', () {
      expect(render(splitMediaTags('nothing here')), ['nothing here']);
    });

    test('mid-text ref becomes a card with prose around it', () {
      expect(
        render(
          splitMediaTags('Here is the chart MEDIA:/home/jon/out.png done'),
        ),
        ['Here is the chart ', 'CARD:/home/jon/out.png', ' done'],
      );
    });

    test('bare capture sheds trailing sentence punctuation into prose', () {
      expect(render(splitMediaTags('open MEDIA:/tmp/a.pdf.')), [
        'open ',
        'CARD:/tmp/a.pdf',
        '.',
      ]);
    });

    test('degenerate captures stay prose', () {
      expect(render(splitMediaTags('MEDIA:...')), ['MEDIA:...']);
      expect(render(splitMediaTags('MEDIA:stuff')), ['MEDIA:stuff']);
    });

    test('quoted capture keeps interior spaces and punctuation', () {
      expect(render(splitMediaTags('see MEDIA:"/tmp/my file.png" ok')), [
        'see ',
        'CARD:/tmp/my file.png',
        ' ok',
      ]);
      expect(render(splitMediaTags("MEDIA:'/tmp/stop!.md'")), [
        'CARD:/tmp/stop!.md',
      ]);
    });

    test('multiple refs each become a card', () {
      expect(render(splitMediaTags('MEDIA:/a.png and MEDIA:/b.pdf')), [
        'CARD:/a.png',
        ' and ',
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
      expect(render(splitMediaTags('here MEDIA:/home/jon/report.pdf')), [
        'here ',
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

    testWidgets('assistant ref renders a card, prose stays markdown', (
      tester,
    ) async {
      final files = _FakeFiles({
        '/out/report.pdf': [1, 2, 3],
      });
      await pumpBubble(
        tester,
        content: 'Done. MEDIA:/out/report.pdf',
        isUser: false,
        filesClient: () => files,
      );
      expect(find.byKey(Key('media-card-report.pdf')), findsOneWidget);
      expect(find.textContaining('Done.'), findsOneWidget);
    });

    testWidgets('user bubbles never parse refs', (tester) async {
      await pumpBubble(
        tester,
        content: 'Done. MEDIA:/out/report.pdf',
        isUser: true,
        filesClient: () => _FakeFiles({}),
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('no files client leaves refs as prose', (tester) async {
      await pumpBubble(
        tester,
        content: 'Done. MEDIA:/out/report.pdf',
        isUser: false,
      );
      expect(find.byType(MediaArtifactCard), findsNothing);
    });

    testWidgets('tap downloads and shares', (tester) async {
      final files = _FakeFiles({
        '/out/report.pdf': [1, 2, 3],
      });
      await pumpBubble(
        tester,
        content: 'MEDIA:/out/report.pdf',
        isUser: false,
        filesClient: () => files,
      );
      await tester.tap(find.byKey(Key('media-card-download-report.pdf')));
      await tester.pump();
      // The share sheet is platform UI; assert only that the gateway fetch
      // fired for the exact ref path.
      expect(files.requested, ['/out/report.pdf']);
    });
  });
}
