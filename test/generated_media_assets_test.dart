import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/assets_screen.dart';
import 'package:hermes_android/core/services/chat_assets_client.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

const _session = Session(
  id: 'source-session',
  title: 'Source',
  model: 'fixture',
  source: 'desktop',
  messageCount: 5,
  isActive: false,
  preview: '',
  startedAt: 1,
);

Map<String, dynamic> _tool(String path, {String? name = 'image_generate'}) => {
  'id': 42,
  'role': 'tool',
  'tool_call_id': 'call-image',
  'name': ?name,
  'content': jsonEncode({'success': true, 'image': path}),
  'timestamp': 10,
};

Map<String, dynamic> _calls(String name) => {
  'id': 41,
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    {
      'id': 'call-image',
      'type': 'function',
      'function': {'name': name, 'arguments': '{"prompt":"draw an image"}'},
    },
  ],
};

class _PagedAssetsSource extends Fake implements ChatAssetsDataSource {
  _PagedAssetsSource(this.pages);

  final List<List<Map<String, dynamic>>> pages;
  final offsets = <int>[];

  @override
  Future<ChatAssetsSessionPage> listSessions({
    int offset = 0,
    int limit = 10,
  }) async => const ChatAssetsSessionPage(
    sessions: [_session],
    nextOffset: 10,
    hasMore: false,
  );

  @override
  Future<ChatAssetsMessagePage> getMessages(
    Session session, {
    int offset = 0,
    int limit = 100,
  }) async {
    offsets.add(offset);
    return ChatAssetsMessagePage(
      messages: pages[offset ~/ 100],
      nextOffset: offset + limit,
      hasMore: offset == 0,
    );
  }
}

class _NoFetchFiles extends Fake implements RemoteFilesDataSource {
  final downloads = <String>[];

  @override
  Future<RemoteFileDownload> download(String path) async {
    downloads.add(path);
    throw StateError('Assets must not fetch files while rendering');
  }
}

void main() {
  test(
    'asset merge preserves newest ownership and enriches exact identity',
    () {
      const url = 'https://cdn.example/generated/opaque-id?format=png';
      final newestSession = _session.withTitle('Newest session metadata');
      final echo = ChatAsset(
        session: newestSession,
        ref: const MediaTagRef(path: url, quoted: true),
        timestamp: 20,
      );
      const producer = ChatAsset(
        session: _session,
        ref: MediaTagRef(path: url, suggestedFilename: 'generated-image.png'),
        timestamp: 10,
      );
      for (final merged in [echo.merge(producer), producer.merge(echo)]) {
        expect(merged.session, same(newestSession));
        expect(merged.timestamp, 20);
        expect(merged.id, echo.id);
        expect(merged.ref.path, url);
        expect(merged.ref.quoted, isTrue);
        expect(merged.ref.filename, 'generated-image.png');
        expect(merged.kind, ChatAssetKind.image);
      }
      for (final distinct in [
        ChatAsset(
          session: _session.withStoredId('other'),
          ref: producer.ref,
          timestamp: 10,
        ),
        const ChatAsset(
          session: _session,
          ref: MediaTagRef(path: '$url&other=1'),
          timestamp: 10,
        ),
      ]) {
        expect(() => echo.merge(distinct), throwsArgumentError);
      }
    },
  );

  for (final producerFirst in [false, true]) {
    testWidgets(
      'Assets retains PNG metadata across pages (${producerFirst ? 'producer first' : 'echo first'})',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const url = 'https://cdn.example/generated/opaque-id?format=png';
        final producer = _tool(url);
        final echo = <String, dynamic>{
          'role': 'assistant',
          'content': 'MEDIA:"$url"',
          'timestamp': 20,
        };
        final source = _PagedAssetsSource([
          [producerFirst ? producer : echo],
          [producerFirst ? echo : producer],
        ]);
        final files = _NoFetchFiles();
        var clientCreations = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AssetsScreen(
              source: source,
              filesClient: (_) {
                clientCreations++;
                return files;
              },
              onOpenSession: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(source.offsets, [0]);
        expect(clientCreations, 0);
        await tester.ensureVisible(
          find.byKey(const Key('assets-older-messages')),
        );
        await tester.tap(find.byKey(const Key('assets-older-messages')));
        await tester.pumpAndSettle();
        expect(source.offsets, [0, 100]);
        expect(find.byType(MediaArtifactCard), findsOneWidget);
        final card = tester.widget<MediaArtifactCard>(
          find.byType(MediaArtifactCard),
        );
        expect(card.ref.path, url);
        expect(card.ref.filename, 'generated-image.png');
        expect(card.ref.extension, 'png');
        expect(find.text('generated-image.png'), findsOneWidget);
        final images = find.widgetWithText(FilterChip, 'Images');
        await tester.ensureVisible(images);
        await tester.tap(images);
        await tester.pumpAndSettle();
        expect(tester.widget<FilterChip>(images).selected, isTrue);
        expect(find.byType(MediaArtifactCard), findsOneWidget);
        expect(clientCreations, 0);
        expect(files.downloads, isEmpty);
        expect(source.offsets, [0, 100]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'indexes real named JSON tool results and exact assistant file links',
    () {
      final rows = [
        _tool('/out/generated.png'),
        {
          'role': 'assistant',
          'timestamp': 20,
          'content': '[Download report](/out/report.pdf)\nMEDIA:/out/voice.mp3',
        },
      ];
      final before = jsonEncode(rows);
      final assets = chatAssetsFromMessages(_session, rows);
      expect(assets.map((asset) => asset.ref.path).toSet(), {
        '/out/generated.png',
        '/out/report.pdf',
        '/out/voice.mp3',
      });
      expect(
        assets.every((asset) => identical(asset.session, _session)),
        isTrue,
      );
      expect(jsonEncode(rows), before);
    },
  );

  test('missing names require actual assistant tool_calls id correlation', () {
    for (final encoded in [false, true]) {
      final call = _calls('image_generate');
      if (encoded) call['tool_calls'] = jsonEncode(call['tool_calls']);
      expect(
        chatAssetsFromMessages(_session, [
          call,
          _tool('/out/a.png', name: null),
        ]).single.ref.path,
        '/out/a.png',
      );
    }
    for (final rows in [
      [_tool('/out/a.png', name: null)],
      [_calls('terminal'), _tool('/out/a.png', name: null)],
      [_calls('image_generate'), _tool('/out/a.png', name: 'terminal')],
      [
        _calls('image_generate'),
        _calls('terminal'),
        _tool('/out/a.png', name: null),
      ],
      [
        {..._calls('image_generate'), 'role': 'user'},
        _tool('/out/a.png', name: null),
      ],
      [
        {
          ..._calls('image_generate'),
          'display_metadata': {'model_only': true},
        },
        _tool('/out/a.png', name: null),
      ],
    ]) {
      expect(chatAssetsFromMessages(_session, rows), isEmpty);
    }
  });

  test(
    'ignores terminal/read_file results, uploads, sidecars and reasoning',
    () {
      final rows = <Map<String, dynamic>>[
        _tool('/out/not-generated.png', name: 'terminal'),
        _tool('/out/not-generated.png', name: 'read_file'),
        {..._tool('/out/upload.png'), 'role': 'user'},
        {..._tool('/out/system.png'), 'role': 'system'},
        {
          'role': 'assistant',
          'content': 'No delivered files.',
          '_gateway_reasoning': 'MEDIA:/out/reasoning.png',
          'attachments': ['/out/sidecar.png'],
          'tool_calls': [
            {
              'result': {'success': true, 'image': '/out/nested.png'},
            },
          ],
        },
        {
          'role': 'assistant',
          'content': [
            {'type': 'reasoning', 'text': 'MEDIA:/out/reasoning-part.png'},
            {
              'type': 'image_url',
              'image_url': {'url': '/out/upload.png'},
            },
          ],
        },
      ];
      expect(chatAssetsFromMessages(_session, rows), isEmpty);
    },
  );

  test(
    'display projection presence and hidden/model-only guards apply to tools',
    () {
      final rows = <Map<String, dynamic>>[
        for (final content in [null, '', 42, <Object>[]])
          {..._tool('/out/physical.png'), 'display_content': content},
        for (final kind in [
          'hidden',
          'compaction',
          'compaction_summary',
          'compression_summary',
          'context_summary',
        ])
          {..._tool('/out/hidden.png'), 'display_kind': kind},
        {
          ..._tool('/out/model.png'),
          'display_metadata': {'model_only': true},
        },
        {..._tool('/out/summary.png'), '_compressed_summary': true},
        {
          ..._tool('/out/physical.png'),
          'display_content': jsonEncode({
            'success': true,
            'image': '/out/public.png',
          }),
        },
        {
          ..._tool('/out/real-compacted.png'),
          'compacted': true,
          'active': false,
        },
      ];
      expect(
        chatAssetsFromMessages(_session, rows).map((a) => a.ref.path).toSet(),
        {'/out/public.png', '/out/real-compacted.png'},
      );
    },
  );

  test('failure and malformed results never index files', () {
    expect(
      chatAssetsFromMessages(_session, [
        {..._tool('/out/a.png'), 'content': '{malformed'},
        {
          ..._tool('/out/a.png'),
          'content': jsonEncode({'success': false, 'image': '/out/a.png'}),
        },
        {..._tool('/out/a.png'), 'error': 'failed'},
        {..._tool('/out/a.png'), 'status': 'failed'},
        {
          ..._tool('/out/a.png'),
          'content': 'source="image_generate" MEDIA:/out/a.png',
        },
      ]),
      isEmpty,
    );
  });

  test(
    'exact session/path dedupe retains newest tool or assistant timestamp',
    () {
      const path = '/out/雪 #%?.png';
      final assets = chatAssetsFromMessages(_session, [
        {..._tool(path), 'timestamp': 12},
        {'role': 'assistant', 'content': 'MEDIA:"$path"', 'timestamp': 30},
        {..._tool(path), 'timestamp': 21},
        {..._tool('/out/distinct.png'), 'timestamp': 40},
      ]);
      expect(assets.map((a) => a.ref.path), ['/out/distinct.png', path]);
      expect(assets.last.timestamp, 30);
      expect(jsonDecode(assets.last.id), [_session.id, path]);
      final otherSession = _session.withStoredId('other-session');
      expect(
        chatAssetsFromMessages(otherSession, [_tool(path)]).single.id,
        isNot(assets.last.id),
      );
    },
  );

  test('URL-only image remains a URL and has image type in Assets', () {
    const url = 'https://cdn.example/opaque?signature=exact%2Fvalue';
    final asset = chatAssetsFromMessages(_session, [_tool(url)]).single;
    expect(asset.ref.path, url);
    expect(asset.kind, ChatAssetKind.image);
    expect(asset.ref.filename, 'generated-image.png');
  });

  test(
    'newer text echo does not erase extensionless producer image semantics',
    () {
      const url = 'https://cdn.example/opaque?signature=exact';
      for (final rows in [
        [
          _tool(url),
          {'role': 'assistant', 'content': 'MEDIA:"$url"', 'timestamp': 30},
        ],
        [
          {'role': 'assistant', 'content': 'MEDIA:"$url"', 'timestamp': 30},
          _tool(url),
        ],
      ]) {
        final asset = chatAssetsFromMessages(_session, rows).single;
        expect(asset.ref.path, url);
        expect(asset.timestamp, 30);
        expect(asset.kind, ChatAssetKind.image);
      }
    },
  );
}
