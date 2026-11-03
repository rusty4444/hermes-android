import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;

/// Captures the request URI so paging params can be asserted on the wire.
class _RecordingJsonClient extends http.BaseClient {
  final String Function(Uri uri) bodyFor;
  Uri? lastUri;

  _RecordingJsonClient({required this.bodyFor});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastUri = request.url;
    return http.StreamedResponse(
      Stream.value(utf8.encode(bodyFor(request.url))),
      200,
    );
  }
}

Map<String, dynamic> _row(String id) => {
  'id': id,
  'title': 'Chat $id',
  'model': 'gpt-oss-20b',
  'source': 'gateway',
  'message_count': 2,
  'is_active': true,
  'preview': 'hello',
  'started_at': 1750000000,
};

void main() {
  group('ApiClient.getSessionsPage', () {
    test('sends limit and offset query params', () async {
      final client = _RecordingJsonClient(
        bodyFor: (_) => jsonEncode({
          'object': 'list',
          'data': [_row('a')],
          'has_more': true,
        }),
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      await api.getSessionsPage(limit: 50, offset: 100);

      expect(client.lastUri!.queryParameters['limit'], '50');
      expect(client.lastUri!.queryParameters['offset'], '100');
    });

    test('parses has_more true', () async {
      final client = _RecordingJsonClient(
        bodyFor: (_) => jsonEncode({
          'object': 'list',
          'data': [_row('a'), _row('b')],
          'has_more': true,
        }),
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      final page = await api.getSessionsPage(limit: 2);

      expect(page.sessions, hasLength(2));
      expect(page.hasMore, isTrue);
    });

    test('parses has_more false on the last page', () async {
      final client = _RecordingJsonClient(
        bodyFor: (_) => jsonEncode({
          'object': 'list',
          'data': [_row('z')],
          'has_more': false,
        }),
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      final page = await api.getSessionsPage(limit: 50, offset: 50);

      expect(page.sessions.single.id, 'z');
      expect(page.hasMore, isFalse);
    });

    test('missing has_more is treated as no more pages', () async {
      final client = _RecordingJsonClient(
        bodyFor: (_) => jsonEncode({
          'object': 'list',
          'data': [_row('a')],
        }),
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      final page = await api.getSessionsPage();

      expect(page.hasMore, isFalse);
    });

    test('getSessions still returns the first page sessions', () async {
      final client = _RecordingJsonClient(
        bodyFor: (_) => jsonEncode({
          'object': 'list',
          'data': [_row('a'), _row('b')],
          'has_more': true,
        }),
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      final sessions = await api.getSessions();

      expect(sessions, hasLength(2));
      expect(sessions.map((s) => s.id), ['a', 'b']);
    });
  });

  group('ApiClient.getSessionById', () {
    test(
      'false has_more on a short pinned-root page cannot hide its tip (#207 M2)',
      () async {
        final offsets = <int>[];
        final api = ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: 'fixture-key',
          httpClient: _RecordingJsonClient(
            bodyFor: (uri) {
              final offset = int.parse(uri.queryParameters['offset']!);
              offsets.add(offset);
              return jsonEncode({
                'data': [
                  {..._row('root'), 'pinned': true},
                  if (offset == 50)
                    {..._row('current-tip'), '_lineage_root_id': 'root'},
                ],
                'has_more': false,
              });
            },
          ),
        );
        addTearDown(api.close);
        expect((await api.getSessionById('root'))?.id, 'current-tip');
        expect(offsets, [0, 50]);
      },
    );

    test(
      'canonical tip beats a back-filled root regardless of row order',
      () async {
        for (final rootFirst in [true, false]) {
          final root = {..._row('root'), 'pinned': true};
          final tip = {..._row('current-tip'), '_lineage_root_id': 'root'};
          final api = ApiClient(
            baseUrl: 'http://fixture.local',
            apiKey: 'fixture',
            httpClient: _RecordingJsonClient(
              bodyFor: (_) => jsonEncode({
                'data': rootFirst ? [root, tip] : [tip, root],
                'has_more': false,
              }),
            ),
          );
          expect((await api.getSessionById('root'))?.id, 'current-tip');
          api.close();
        }
      },
    );

    test(
      'pinned obsolete root cannot stop lookup before the current tip window',
      () async {
        final offsets = <int>[];
        final api = ApiClient(
          baseUrl: 'http://fixture.local',
          apiKey: 'fixture',
          httpClient: _RecordingJsonClient(
            bodyFor: (uri) {
              final offset = int.parse(uri.queryParameters['offset']!);
              offsets.add(offset);
              return jsonEncode({
                'data': offset == 0
                    ? [
                        for (var i = 0; i < 50; i++) _row('other-$i'),
                        {..._row('root'), 'pinned': true},
                      ]
                    : [
                        {..._row('current-tip'), '_lineage_root_id': 'root'},
                        {..._row('root'), 'pinned': true},
                      ],
                'has_more': false,
              });
            },
          ),
        );
        expect((await api.getSessionById('root'))?.id, 'current-tip');
        expect(offsets, [0, 50]);
        api.close();
      },
    );
    test(
      'revocation while asynchronous authority is held prevents even the first read',
      () async {
        var current = true;
        var reads = 0;
        final authority = Completer<bool>();
        final api = ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: 'test',
          httpClient: _RecordingJsonClient(
            bodyFor: (_) {
              reads++;
              return jsonEncode({
                'data': [_row('target')],
                'has_more': false,
              });
            },
          ),
        );
        final lookup = api.getSessionById(
          'target',
          canContinue: () => authority.future,
          isCurrent: () => current,
        );
        current = false;
        authority.complete(true);
        expect(await lookup, isNull);
        expect(reads, 0);
        api.close();
      },
    );

    test(
      'revoked response is rejected even when it contains the exact session',
      () async {
        var current = true;
        var reads = 0;
        final api = ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: 'test',
          httpClient: _RecordingJsonClient(
            bodyFor: (_) {
              reads++;
              current = false;
              return jsonEncode({
                'data': [_row('target')],
                'has_more': true,
              });
            },
          ),
        );
        expect(
          await api.getSessionById('target', isCurrent: () => current),
          isNull,
        );
        expect(reads, 1);
        api.close();
      },
    );

    test('pages until the exact id is found', () async {
      final uris = <Uri>[];
      final client = _RecordingJsonClient(
        bodyFor: (uri) {
          uris.add(uri);
          final offset = int.parse(uri.queryParameters['offset'] ?? '0');
          if (offset == 0) {
            return jsonEncode({
              'object': 'list',
              'data': [_row('a'), _row('b')],
              'has_more': true,
            });
          }
          return jsonEncode({
            'object': 'list',
            'data': [_row('target')],
            'has_more': false,
          });
        },
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      final session = await api.getSessionById('target');

      expect(session, isNotNull);
      expect(session!.id, 'target');
      expect(uris, hasLength(3));
      // OFFSET advances by the requested window, never sparse rows or pin back-fill.
      expect(uris[1].queryParameters['offset'], '50');
    });

    test(
      'continues past 500 rows while the server reports more pages',
      () async {
        final uris = <Uri>[];
        final client = _RecordingJsonClient(
          bodyFor: (uri) {
            uris.add(uri);
            final offset = int.parse(uri.queryParameters['offset'] ?? '0');
            if (offset < 500) {
              return jsonEncode({
                'object': 'list',
                'data': [
                  for (var index = 0; index < 50; index++)
                    _row('${offset + index}'),
                ],
                'has_more': true,
              });
            }
            return jsonEncode({
              'object': 'list',
              'data': [_row('target-after-500')],
              'has_more': false,
            });
          },
        );
        final api = ApiClient(
          baseUrl: 'http://fixture.local',
          apiKey: '',
          httpClient: client,
        );

        final session = await api.getSessionById('target-after-500');

        expect(session?.id, 'target-after-500');
        expect(uris, hasLength(12));
        expect(uris.last.queryParameters['offset'], '550');
      },
    );

    test('returns null once the last page is reached without the id', () async {
      final client = _RecordingJsonClient(
        bodyFor: (_) => jsonEncode({
          'object': 'list',
          'data': [_row('a')],
          'has_more': false,
        }),
      );
      final api = ApiClient(
        baseUrl: 'http://fixture.local',
        apiKey: 'fixture-key',
        httpClient: client,
      );

      expect(await api.getSessionById('missing'), isNull);
    });
  });

  test(
    'getMessages encodes an opaque session id inside one prefixed path segment (#207 L3)',
    () async {
      const id = 'stored/segment?x=1#fragment %猫';
      final client = _RecordingJsonClient(bodyFor: (_) => '{"data":[]}');
      final api = ApiClient(
        baseUrl: 'https://fixture.invalid',
        pathPrefix: '/profile/work',
        apiKey: 'fixture-key',
        httpClient: client,
      );
      addTearDown(api.close);
      await api.getMessages(id, limit: 25, offset: 50, latest: true);
      final uri = client.lastUri!;
      expect(uri.pathSegments, [
        'profile',
        'work',
        'api',
        'sessions',
        id,
        'messages',
      ]);
      expect(uri.fragment, isEmpty);
      expect(uri.queryParameters, {
        'limit': '25',
        'offset': '50',
        'order': 'latest',
      });
    },
  );
}
