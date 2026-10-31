import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/screens/assets_screen.dart';
import 'package:hermes_android/core/services/chat_assets_client.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Session _session(String id, {String? title}) => Session(
  id: id,
  title: title ?? 'Chat $id',
  model: 'test',
  source: 'cli',
  messageCount: 4,
  isActive: false,
  preview: '',
  startedAt: 10,
);

Map<String, dynamic> _message(String path, [int timestamp = 20]) => {
  'id': timestamp,
  'role': 'assistant',
  'content': 'MEDIA:$path',
  'timestamp': timestamp,
};

class _Source implements ChatAssetsDataSource {
  final List<Session> sessions;
  final Map<String, List<Map<String, dynamic>>> messages;
  final reads = <String>[];
  final listOffsets = <int>[];
  Future<ChatAssetsSessionPage> Function(int offset)? list;
  Future<ChatAssetsMessagePage> Function(Session session, int offset)? read;

  _Source({this.sessions = const [], this.messages = const {}});

  @override
  Future<ChatAssetsSessionPage> listSessions({
    int offset = 0,
    int limit = 10,
  }) async {
    listOffsets.add(offset);
    if (list != null) return list!(offset);
    return ChatAssetsSessionPage(
      sessions: sessions,
      nextOffset: offset + limit,
      hasMore: false,
      partial: false,
    );
  }

  @override
  Future<ChatAssetsMessagePage> getMessages(
    Session session, {
    int offset = 0,
    int limit = 100,
  }) async {
    reads.add('${session.id}:$offset');
    if (read != null) return read!(session, offset);
    return ChatAssetsMessagePage(
      messages: messages[session.id] ?? const [],
      nextOffset: offset + limit,
      hasMore: false,
    );
  }
}

class _Files implements RemoteFilesDataSource {
  final downloads = <String>[];

  @override
  Future<RemoteFileDownload> download(String path) async {
    downloads.add(path);
    throw const DownloadSizeLimitException();
  }

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();
  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();
  @override
  Future<RemoteTextPreview> readText(String path) => throw UnimplementedError();
}

class _HeldFiles extends _Files {
  final pending = Completer<RemoteFileDownload>();

  @override
  Future<RemoteFileDownload> download(String path) {
    downloads.add(path);
    return pending.future;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Source source, {
  _Files? files,
  ValueChanged<Session>? onOpen,
  Size size = const Size(600, 1400),
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AssetsScreen(
        source: source,
        filesClient: (_) => files ?? _Files(),
        onOpenSession: onOpen ?? (_) {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows saved assets and source chat without eager downloads', (
    tester,
  ) async {
    final files = _Files();
    final opened = <String>[];
    final source = _Source(
      sessions: [_session('one')],
      messages: {
        'one': [_message('/out/chart.png'), _message('/out/report.pdf', 30)],
      },
    );
    await _pump(tester, source, files: files, onOpen: (s) => opened.add(s.id));
    await tester.pumpAndSettle();
    expect(find.byType(MediaArtifactCard), findsNWidgets(2));
    expect(find.textContaining('not a complete file'), findsOneWidget);
    expect(
      find.text('2 file references found across 1 scanned chats'),
      findsOneWidget,
    );
    expect(files.downloads, isEmpty);
    await tester.tap(find.text('Open chat: Chat one').first);
    await tester.pumpAndSettle();
    expect(opened, ['one']);
  });

  testWidgets('searches filenames and chat titles and filters file types', (
    tester,
  ) async {
    final source = _Source(
      sessions: [_session('a', title: 'Design review')],
      messages: {
        'a': [
          _message('/out/chart.png'),
          _message('/out/report.pdf'),
          _message('/out/demo.mp4'),
        ],
      },
    );
    await _pump(tester, source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Images'));
    await tester.pumpAndSettle();
    expect(find.text('chart.png'), findsOneWidget);
    expect(find.text('report.pdf'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.enterText(find.byKey(const Key('assets-search')), 'DESIGN');
    await tester.pumpAndSettle();
    expect(find.byType(MediaArtifactCard), findsNWidgets(3));
    await tester.enterText(find.byKey(const Key('assets-search')), 'report');
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('chart.png'), findsNothing);
    await tester.enterText(find.byKey(const Key('assets-search')), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching assets'), findsOneWidget);
  });

  testWidgets('older pages are explicit and duplicate paths are merged', (
    tester,
  ) async {
    final source = _Source(sessions: [_session('a')]);
    source.read = (session, offset) async => ChatAssetsMessagePage(
      messages: offset == 0
          ? [_message('/out/new.pdf', 40)]
          : [_message('/out/old.pdf', 10), _message('/out/new.pdf', 5)],
      nextOffset: offset + 100,
      hasMore: offset == 0,
    );
    await _pump(tester, source);
    await tester.pumpAndSettle();
    expect(source.reads, ['a:0']);
    expect(find.text('old.pdf'), findsNothing);
    await _tap(tester, find.byKey(const Key('assets-older-messages')));
    expect(source.reads, ['a:0', 'a:100']);
    expect(find.byType(MediaArtifactCard), findsNWidgets(2));
    expect(find.text('old.pdf'), findsOneWidget);
  });

  testWidgets('session paging advances and repeated pins are not reread', (
    tester,
  ) async {
    final source = _Source(
      messages: {
        'a': [_message('/out/a.pdf')],
        'b': [_message('/out/b.pdf')],
      },
    );
    source.list = (offset) async => ChatAssetsSessionPage(
      sessions: offset == 0 ? [_session('a')] : [_session('a'), _session('b')],
      nextOffset: offset + 10,
      hasMore: offset == 0,
      partial: false,
    );
    await _pump(tester, source);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('assets-more-chats')));
    expect(source.listOffsets, [0, 10]);
    expect(source.reads, ['a:0', 'b:0']);
    expect(find.text('b.pdf'), findsOneWidget);
  });

  testWidgets('initial work is bounded even with pin backfill', (tester) async {
    final source = _Source(
      sessions: [for (var i = 0; i < 25; i++) _session('$i')],
    );
    await _pump(tester, source);
    await tester.pumpAndSettle();
    expect(source.reads.length, 10);
    expect(source.listOffsets, [0]);
    await _tap(tester, find.byKey(const Key('assets-more-chats')));
    expect(source.reads.length, 20);
    expect(source.listOffsets, [0]);
  });

  testWidgets('failed reads keep successful results and retry only failures', (
    tester,
  ) async {
    var failed = false;
    final source = _Source(sessions: [_session('a'), _session('b')]);
    source.read = (session, offset) async {
      if (session.id == 'b' && !failed) {
        failed = true;
        throw const DashboardHttpException(503);
      }
      return ChatAssetsMessagePage(
        messages: [_message('/out/${session.id}.pdf')],
        nextOffset: 100,
        hasMore: false,
      );
    };
    await _pump(tester, source);
    await tester.pumpAndSettle();
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.textContaining('Results are incomplete'), findsOneWidget);
    await tester.tap(find.text('Retry failed history reads'));
    await tester.pumpAndSettle();
    expect(source.reads, ['a:0', 'b:0', 'b:0']);
    expect(find.text('b.pdf'), findsOneWidget);
    expect(find.textContaining('Results are incomplete'), findsNothing);
  });

  testWidgets(
    'list error is retryable and never presented as complete empty data',
    (tester) async {
      var calls = 0;
      final source = _Source();
      source.list = (offset) async {
        if (calls++ == 0) throw const DashboardHttpException(401);
        return ChatAssetsSessionPage(
          sessions: [_session('a')],
          nextOffset: 10,
          hasMore: false,
          partial: false,
        );
      };
      await _pump(tester, source);
      await tester.pumpAndSettle();
      expect(find.textContaining('Results are incomplete'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(source.reads, ['a:0']);
      expect(find.textContaining('Results are incomplete'), findsNothing);
    },
  );

  testWidgets('refresh fences an old held transcript response', (tester) async {
    final held = Completer<ChatAssetsMessagePage>();
    final source = _Source(sessions: [_session('a')]);
    var reads = 0;
    source.read = (session, offset) async {
      if (reads++ == 0) return held.future;
      return ChatAssetsMessagePage(
        messages: [_message('/out/fresh.pdf')],
        nextOffset: 100,
        hasMore: false,
      );
    };
    await _pump(tester, source);
    await tester.pump();
    expect(source.reads, ['a:0']);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('fresh.pdf'), findsOneWidget);
    held.complete(
      ChatAssetsMessagePage(
        messages: [_message('/out/stale.pdf')],
        nextOffset: 100,
        hasMore: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('stale.pdf'), findsNothing);
    expect(find.byKey(const Key('assets-older-messages')), findsNothing);
  });

  testWidgets('source replacement cannot show another connection history', (
    tester,
  ) async {
    final held = Completer<ChatAssetsSessionPage>();
    final old = _Source()..list = (_) => held.future;
    await _pump(tester, old);
    final fresh = _Source(
      sessions: [_session('new')],
      messages: {
        'new': [_message('/out/new.pdf')],
      },
    );
    await _pump(tester, fresh);
    await tester.pumpAndSettle();
    held.complete(
      ChatAssetsSessionPage(
        sessions: [_session('private')],
        nextOffset: 10,
        hasMore: true,
        partial: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('new.pdf'), findsOneWidget);
    expect(old.reads, isEmpty);
  });

  testWidgets('disposed pending scan performs no follow-up reads', (
    tester,
  ) async {
    final held = Completer<ChatAssetsSessionPage>();
    final source = _Source()..list = (_) => held.future;
    await _pump(tester, source);
    await tester.pumpWidget(const SizedBox());
    held.complete(
      ChatAssetsSessionPage(
        sessions: [_session('a')],
        nextOffset: 10,
        hasMore: false,
        partial: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(source.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download cap failure is visible and does not claim success', (
    tester,
  ) async {
    final files = _Files();
    final source = _Source(
      sessions: [_session('a')],
      messages: {
        'a': [_message('/out/large.png')],
      },
    );
    await _pump(tester, source, files: files);
    await tester.pumpAndSettle();
    expect(files.downloads, isEmpty);
    await tester.tap(find.text('large.png'));
    await tester.pumpAndSettle();
    expect(files.downloads, ['/out/large.png']);
    expect(find.textContaining('exceeds the download limit'), findsOneWidget);
    expect(find.textContaining('downloaded'), findsNothing);
  });

  testWidgets('retry batches do not starve a recoverable failure beyond ten', (
    tester,
  ) async {
    var recoverTail = false;
    final source = _Source(
      sessions: [for (var i = 0; i < 11; i++) _session('$i')],
    );
    source.read = (session, offset) async {
      if (session.id != '10' || !recoverTail) {
        throw const DashboardHttpException(503);
      }
      return ChatAssetsMessagePage(
        messages: [_message('/out/recovered.pdf')],
        nextOffset: 100,
        hasMore: false,
      );
    };
    await _pump(tester, source);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('assets-more-chats')));
    recoverTail = true;
    await tester.tap(find.text('Retry failed history reads'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry failed history reads'));
    await tester.pumpAndSettle();
    expect(source.reads.where((value) => value == '10:0'), hasLength(2));
    expect(find.text('recovered.pdf'), findsOneWidget);
  });

  testWidgets('inserting newer results preserves an active media card', (
    tester,
  ) async {
    final second = Completer<ChatAssetsMessagePage>();
    final source = _Source(sessions: [_session('a'), _session('b')]);
    source.read = (session, offset) async {
      if (session.id == 'b') return second.future;
      return ChatAssetsMessagePage(
        messages: [_message('/out/first.png', 10)],
        nextOffset: 100,
        hasMore: false,
      );
    };
    final files = _HeldFiles();
    await _pump(tester, source, files: files);
    await tester.pump();
    final first = find.byWidgetPredicate(
      (widget) =>
          widget is MediaArtifactCard && widget.ref.path == '/out/first.png',
    );
    final state = tester.state(first);
    await tester.tap(find.text('first.png'));
    await tester.pump();
    expect(files.downloads, ['/out/first.png']);
    second.complete(
      ChatAssetsMessagePage(
        messages: [_message('/out/newer.pdf', 20)],
        nextOffset: 100,
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(identical(state, tester.state(first)), isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(files.downloads, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    files.pending.complete(
      RemoteFileDownload(filename: 'first.png', bytes: const []),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated narrow light layout supports large text', (
    tester,
  ) async {
    final source = _Source(
      sessions: [
        _session(
          'a',
          title: 'A very long source chat title for a generated output',
        ),
      ],
      messages: {
        'a': [
          _message(
            '/out/a-very-long-generated-document-name-for-a-small-phone.pdf',
          ),
        ],
      },
    );
    await _pump(
      tester,
      source,
      size: const Size(320, 640),
      scale: 2,
      brightness: Brightness.light,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(MediaArtifactCard),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(MediaArtifactCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow light layout supports large text and honest empty state',
    (tester) async {
      await _pump(
        tester,
        _Source(),
        size: const Size(320, 640),
        scale: 2,
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('No assets found in scanned messages'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No assets found in scanned messages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
