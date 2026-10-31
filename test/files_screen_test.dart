import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/files_screen.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

class _FakeFilesDataSource implements RemoteFilesDataSource {
  Object? listError;
  final openedDirectories = <String>[];

  @override
  Future<RemoteDirectory> defaultDirectory() async =>
      const RemoteDirectory(path: '/srv/project', branch: 'main');

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) async {
    openedDirectories.add(path);
    if (listError != null) throw listError!;
    if (path == '/srv/project/lib') {
      return const [
        RemoteFileEntry(
          name: 'main.dart',
          path: '/srv/project/lib/main.dart',
          isDirectory: false,
        ),
      ];
    }
    return const [
      RemoteFileEntry(name: 'lib', path: '/srv/project/lib', isDirectory: true),
      RemoteFileEntry(
        name: 'README.md',
        path: '/srv/project/README.md',
        isDirectory: false,
      ),
    ];
  }

  @override
  Future<RemoteTextPreview> readText(String path) async => RemoteTextPreview(
    path: path,
    text: '# Hermes\nRemote preview',
    language: 'markdown',
    mimeType: 'text/markdown',
    byteSize: 23,
    binary: false,
    truncated: false,
  );

  @override
  Future<RemoteFileDownload> download(String path) async =>
      RemoteFileDownload(filename: path.split('/').last, bytes: [1, 2, 3]);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeFilesDataSource source, {
  ValueChanged<String>? onAddToChat,
  Future<void> Function(RemoteFileDownload download)? onSaveDownload,
}) => tester.pumpWidget(
  MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    theme: hermesTheme(Brightness.dark),
    home: FilesScreen(
      files: source,
      onAddToChat: onAddToChat,
      onSaveDownload: onSaveDownload,
    ),
  ),
);

void main() {
  testWidgets('shows the server root and navigates into a directory', (
    tester,
  ) async {
    final source = _FakeFilesDataSource();
    await _pump(tester, source);
    await tester.pumpAndSettle();

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('/srv/project'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(source.openedDirectories, contains('/srv/project/lib'));
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('previews text and adds its server reference to chat', (
    tester,
  ) async {
    final source = _FakeFilesDataSource();
    final references = <String>[];
    await _pump(tester, source, onAddToChat: references.add);
    await tester.pumpAndSettle();

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(find.text('# Hermes\nRemote preview'), findsOneWidget);
    expect(find.text('markdown'), findsOneWidget);
    await tester.tap(find.text('Add to chat'));
    await tester.pumpAndSettle();

    expect(references, ['/srv/project/README.md']);
  });

  testWidgets('downloads the selected file through the platform seam', (
    tester,
  ) async {
    final source = _FakeFilesDataSource();
    final downloads = <RemoteFileDownload>[];
    await _pump(
      tester,
      source,
      onSaveDownload: (download) async => downloads.add(download),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(downloads.single.filename, 'README.md');
    expect(downloads.single.bytes, [1, 2, 3]);
  });

  testWidgets('shows a retryable error when the directory cannot load', (
    tester,
  ) async {
    final source = _FakeFilesDataSource()..listError = Exception('offline');
    await _pump(tester, source);
    await tester.pumpAndSettle();

    expect(find.text('Could not load files'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
