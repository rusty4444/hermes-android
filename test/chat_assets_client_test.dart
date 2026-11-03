import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_asset.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/chat_assets_client.dart'
    show ChatAssetsClient;
import 'package:hermes_android/core/services/connection_manager.dart'
    show DashboardClient, DashboardHttpException, SavedConnection;
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_markdown_fixtures.dart';

Session _session([String id = 'source-session']) => Session(
  id: id,
  title: 'Source chat',
  model: 'fixture',
  source: 'desktop',
  messageCount: 4,
  isActive: false,
  preview: '',
  startedAt: 1,
  lastActive: 999,
);

Map<String, dynamic> _sessionRow(String id, {bool pinned = false}) => {
  'id': id,
  'title': 'Chat $id',
  'model': 'fixture',
  'source': 'desktop',
  'message_count': 4,
  'started_at': 1,
  'last_active': 2,
  'is_active': false,
  'pinned': pinned,
};

Map<String, dynamic> _messageEnvelope({
  List<Map<String, dynamic>> messages = const [],
  int limit = 100,
  int offset = 0,
  String sessionId = 'source-session',
}) => {
  'session_id': sessionId,
  'messages': messages,
  'pagination': {
    'limit': limit,
    'offset': offset,
    'order': 'latest',
    'returned': messages.length,
  },
};

ChatAssetsClient _client(
  Future<http.Response> Function(http.Request) handler, {
  String? profile,
}) {
  final client = ChatAssetsClient(
    dashboard: DashboardClient(
      host: 'assets.fixture',
      proxied: true,
      httpClient: MockClient(handler),
    ),
    profile: profile,
  );
  addTearDown(client.close);
  return client;
}

ChatAssetsClient _responding(Object? response, {String? profile}) => _client(
  (_) async => http.Response(
    jsonEncode(response),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
  profile: profile,
);

class _CloseTrackingClient extends MockClient {
  int closeCalls = 0;

  _CloseTrackingClient()
    : super((_) async => http.Response('{"sessions": []}', 200));

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

void main() {
  group('ChatAsset and chatAssetsFromMessages', () {
    for (final example in mediaMarkdownExamples.entries) {
      test('${example.key} discovers only later real assistant deliveries', () {
        final source = _session();
        final assets = chatAssetsFromMessages(source, [
          {
            'role': 'assistant',
            'content': '${example.value}\n\nMEDIA:/out/real.pdf',
            'timestamp': 2,
          },
        ]);
        expect(assets.map((asset) => asset.ref.path), ['/out/real.pdf']);
        expect(assets.single.session, same(source));
        expect(assets.single.timestamp, 2);
      });
    }

    test(
      'identity is a lossless session/path tuple, not a delimiter or hash',
      () {
        final first = ChatAsset(
          session: _session('a:b'),
          ref: const MediaTagRef(path: 'c/雪 #%?.pdf'),
          timestamp: 2,
        );
        final second = ChatAsset(
          session: _session('a'),
          ref: const MediaTagRef(path: 'b:c/雪 #%?.pdf'),
          timestamp: 2,
        );
        expect(jsonDecode(first.id), ['a:b', 'c/雪 #%?.pdf']);
        expect(first.id, isNot(second.id));
        expect(
          first.id,
          ChatAsset(
            session: _session('a:b'),
            ref: first.ref,
            timestamp: 900,
          ).id,
        );
      },
    );

    test(
      'classifies all gateway image/audio/video extensions case-insensitively',
      () {
        final families = {
          ChatAssetKind.image:
              'png jpg jpeg gif webp bmp tif tiff avif heic svg',
          ChatAssetKind.audio: 'mp3 m2a wav ogg opus m4a flac',
          ChatAssetKind.video:
              'mp4 m4v mov avi mkv webm 3gp 3gpp 3g2 mpeg mpg mpe m2v mts m2ts ogv flv f4v',
          ChatAssetKind.document: 'pdf zip pptx json py unknown wmv asf',
        };
        for (final family in families.entries) {
          for (final extension in family.value.split(' ')) {
            final asset = ChatAsset(
              session: _session(),
              ref: MediaTagRef(path: '/out/file.${extension.toUpperCase()}'),
              timestamp: 0,
            );
            expect(asset.kind, family.key, reason: extension);
          }
        }
        expect(
          ChatAsset(
            session: _session(),
            ref: const MediaTagRef(path: '/out/Caddyfile'),
            timestamp: 0,
          ).kind,
          ChatAssetKind.document,
        );
      },
    );

    test('explicit assistant/agent text and file links, never sidecars', () {
      final messages = <Map<String, dynamic>>[
        for (final role in [
          'user',
          'tool',
          'tool_result',
          'function',
          'system',
          'developer',
          null,
        ])
          {'role': role, 'content': 'MEDIA:/out/$role.pdf', 'timestamp': 100},
        {
          'role': 'assistant',
          'content': 'See MEDIA:/out/a.png now',
          'timestamp': 2,
        },
        {'role': 'agent', 'content': 'Done.\nMEDIA:/out/b.mp3', 'timestamp': 3},
        {
          'role': 'assistant',
          'content':
              '[download](/out/not-delivered.pdf) ![image](/out/upload.png)',
          'attachments': ['/out/attachment.pdf'],
          'tool_calls': [
            {'result': 'MEDIA:/out/sidecar.pdf'},
          ],
        },
      ];
      final session = _session();
      final before = jsonEncode(messages);
      final assets = chatAssetsFromMessages(session, messages);
      expect(assets.map((asset) => asset.ref.path), [
        '/out/b.mp3',
        '/out/a.png',
        '/out/not-delivered.pdf',
        '/out/upload.png',
      ]);
      expect(
        assets.every((asset) => identical(asset.session, session)),
        isTrue,
      );
      expect(jsonEncode(messages), before);
    });

    test(
      'structured content reads only text, never image/tool/reasoning parts',
      () {
        final assets = chatAssetsFromMessages(_session(), [
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'See MEDIA:/out/real.pdf now'},
              {'type': 'output_text', 'text': 'MEDIA:/out/second.png'},
              {'type': 'input_text', 'text': 'MEDIA:/out/third.md'},
              'MEDIA:/out/string.txt',
              {'type': 'image_url', 'text': 'MEDIA:/out/image-part.png'},
              {'type': 'tool_result', 'content': 'MEDIA:/out/tool.pdf'},
              {'type': 'reasoning', 'text': 'MEDIA:/out/thought.pdf'},
              {'text': 'MEDIA:/out/untyped.pdf'},
              {'type': 'text', 'text': 42},
              3,
              null,
            ],
          },
          {
            'role': 'assistant',
            'content': {'text': 'MEDIA:/out/opaque.pdf'},
          },
          {'role': 'assistant', 'content': null},
        ]);
        expect(assets.map((asset) => asset.ref.path).toSet(), {
          '/out/real.pdf',
          '/out/second.png',
          '/out/third.md',
          '/out/string.txt',
        });
      },
    );

    test('code stays protected across structured text parts', () {
      final assets = chatAssetsFromMessages(_session(), [
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': '```md'},
            {'type': 'text', 'text': 'MEDIA:/out/example.pdf'},
            {'type': 'text', 'text': '```\nMEDIA:/out/real.pdf'},
          ],
        },
      ]);
      expect(assets.map((asset) => asset.ref.path), ['/out/real.pdf']);
    });

    test(
      'display_content overrides physical content, including empty or null',
      () {
        final assets = chatAssetsFromMessages(_session(), [
          {
            'role': 'assistant',
            'content': 'MEDIA:/out/physical.pdf',
            'display_content': 'MEDIA:/out/display.pdf',
          },
          for (final display in ['', null, 42, <Object>[]])
            {
              'role': 'assistant',
              'content': 'MEDIA:/out/do-not-fallback.pdf',
              'display_content': display,
            },
          {
            'role': 'agent',
            '_compressed_summary': true,
            'content': '[CONTEXT SUMMARY]: MEDIA:/out/summary.pdf',
            'display_content': [
              {'type': 'text', 'text': 'MEDIA:/out/projected.pdf'},
            ],
          },
        ]);
        expect(assets.map((asset) => asset.ref.path).toSet(), {
          '/out/display.pdf',
          '/out/projected.pdf',
        });
      },
    );

    test(
      'hides synthetic compaction wrappers but retains real compacted rows',
      () {
        final assets = chatAssetsFromMessages(_session(), [
          for (final kind in [
            'hidden',
            'compaction',
            'compaction_summary',
            'compression_summary',
            'context_summary',
          ])
            {
              'role': 'assistant',
              'display_kind': kind,
              'content': 'MEDIA:/out/$kind.pdf',
              'display_content': 'MEDIA:/out/still-hidden.pdf',
            },
          {
            'role': 'assistant',
            '_compressed_summary': true,
            'content': 'MEDIA:/out/synthetic.pdf',
          },
          {
            'role': 'agent',
            'display_metadata': {'model_only': true},
            'content': 'MEDIA:/out/model-only.pdf',
          },
          for (final prefix in [
            '[CONTEXT SUMMARY]:',
            '[CONTEXT COMPACTION — REFERENCE ONLY]',
            '[PRIOR CONTEXT — for reference only; not a new message]',
          ])
            {'role': 'assistant', 'content': '$prefix\nMEDIA:/out/summary.pdf'},
          {
            'role': 'assistant',
            'compacted': true,
            'active': false,
            'content': 'MEDIA:/out/real-archived.pdf',
          },
          {
            'role': 'assistant',
            'content': 'Compaction is finished.\nMEDIA:/out/real-current.pdf',
          },
        ]);
        expect(assets.map((asset) => asset.ref.path).toSet(), {
          '/out/real-archived.pdf',
          '/out/real-current.pdf',
        });
      },
    );

    test(
      'dedupes by exact session/path with newest timestamp regardless of order',
      () {
        final assets = chatAssetsFromMessages(_session(), [
          {
            'role': 'assistant',
            'content': 'MEDIA:"/out/shared.pdf"',
            'timestamp': 9,
          },
          {
            'role': 'assistant',
            'content': 'MEDIA:/out/shared.pdf',
            'timestamp': 2,
          },
          {
            'role': 'agent',
            'content':
                'MEDIA:/out/second.pdf\nMEDIA:/out/shared.pdf\nMEDIA:/out/second.pdf',
            'timestamp': 5,
          },
          {
            'role': 'user',
            'content': 'MEDIA:/out/shared.pdf',
            'timestamp': 100,
          },
        ]);
        expect(assets.map((asset) => asset.ref.path), [
          '/out/shared.pdf',
          '/out/second.pdf',
        ]);
        expect(assets.map((asset) => asset.timestamp), [9.0, 5.0]);
        expect(assets.first.ref.quoted, isTrue);
        final other = chatAssetsFromMessages(_session('another-session'), [
          {
            'role': 'assistant',
            'content': 'MEDIA:/out/shared.pdf',
            'timestamp': 9,
          },
        ]);
        expect(assets.first.id, isNot(other.single.id));
      },
    );

    test('preserves exact paths, casing, encoding, quotes and backslashes', () {
      const paths = [
        r'C:\new\report.PNG',
        '/out/a #100%?.pdf',
        '/out/stop!.md',
        '/out/A.pdf',
        '/out/a.pdf',
        '/out/a%20b.pdf',
        '/out/a b.pdf',
      ];
      final assets = chatAssetsFromMessages(_session(), [
        {
          'role': 'assistant',
          'content': paths.map((path) => 'MEDIA:"$path"').join('\n'),
          'timestamp': 2,
        },
      ]);
      expect(assets.map((asset) => asset.ref.path).toSet(), paths.toSet());
      expect(assets.map((asset) => asset.id).toSet(), hasLength(paths.length));
    });

    test(
      'missing or invalid timestamps are unknown, never session recency',
      () {
        final assets = chatAssetsFromMessages(_session(), [
          for (final time in [null, 'bad', double.nan, double.infinity])
            {
              'role': 'assistant',
              'content': 'MEDIA:/out/unknown.pdf',
              'timestamp': time,
            },
          {
            'role': 'assistant',
            'content': 'MEDIA:/out/known.pdf',
            'timestamp': '12.5',
          },
        ]);
        expect(assets.map((asset) => asset.timestamp), [12.5, 0.0]);
      },
    );
  });

  group('ChatAssetsClient requests and scope', () {
    test(
      'default sessions request uses serving-profile dashboard list only',
      () async {
        final requests = <http.Request>[];
        final client = _client((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.url.path, '/api/sessions');
          expect(request.url.queryParameters, {
            'archived': 'include',
            'order': 'recent',
            'limit': '10',
            'offset': '0',
          });
          return http.Response(
            jsonEncode({
              'sessions': [
                {..._sessionRow('archived'), 'archived': true},
              ],
              'total': 25,
              'limit': 10,
              'offset': 0,
              'storage': <String, Object>{},
            }),
            200,
          );
        });
        final page = await client.listSessions();
        expect(page.sessions.single.id, 'archived');
        expect(page.sessions.single.archived, isTrue);
        expect(page.nextOffset, 10);
        expect(page.hasMore, isTrue);
        expect(page.partial, isFalse);
        expect(requests, hasLength(1));
      },
    );

    test(
      'default message request is encoded, latest, compacted, and text only',
      () async {
        final source = _session('source/with %雪?#');
        final requests = <http.Request>[];
        final client = _client((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.url.pathSegments, [
            'api',
            'sessions',
            source.id,
            'messages',
          ]);
          expect(
            request.url.toString(),
            contains('/${Uri.encodeComponent(source.id)}/messages?'),
          );
          expect(request.url.queryParameters, {
            'limit': '100',
            'offset': '0',
            'order': 'latest',
            'include_compacted': 'true',
            'inline_images': 'false',
          });
          return http.Response(
            jsonEncode(
              _messageEnvelope(
                sessionId: source.id,
                messages: [
                  {'role': 'assistant', 'content': 'MEDIA:/out/a.pdf'},
                ],
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final page = await client.getMessages(source);
        final assets = chatAssetsFromMessages(source, page.messages);
        expect(identical(assets.single.session, source), isTrue);
        expect(source.id, 'source/with %雪?#');
        expect(page.nextOffset, 100);
        expect(page.hasMore, isFalse);
        // Repeated reads keep the exact listed source identity.
        await client.getMessages(source);
        expect(requests, hasLength(2));
      },
    );

    test(
      'proxy factory reuses normalized dashboard origin, prefix and profile',
      () async {
        final requests = <http.Request>[];
        final client = ChatAssetsClient.fromConnection(
          SavedConnection(
            id: 'fixture',
            label: 'Fixture',
            host: 'assets.fixture',
            port: 8642,
            apiKey: 'unused-fixture-key',
            useHttps: true,
            dashboardPortOverride: 9443,
            dashboardPrefix: '/dashboard/',
            dashboardProxied: true,
            gatewayProfile: 'work',
          ),
          httpClient: MockClient((request) async {
            requests.add(request);
            expect(request.method, 'GET');
            expect(request.url.scheme, 'https');
            expect(request.url.host, 'assets.fixture');
            expect(request.url.port, 9443);
            expect(request.url.queryParameters['profile'], 'work');
            expect(request.headers.containsKey('authorization'), isFalse);
            expect(request.headers.containsKey('cookie'), isFalse);
            expect(
              request.headers.containsKey('x-hermes-session-token'),
              isFalse,
            );
            if (request.url.path == '/dashboard/api/sessions') {
              return http.Response(
                jsonEncode({
                  'sessions': [
                    {..._sessionRow('scoped'), 'profile': 'work'},
                  ],
                  'total': 1,
                  'limit': 10,
                  'offset': 0,
                }),
                200,
              );
            }
            expect(request.url.path, '/dashboard/api/sessions/scoped/messages');
            return http.Response(
              jsonEncode({
                ..._messageEnvelope(sessionId: 'scoped'),
                'profile': 'work',
              }),
              200,
            );
          }),
        );
        addTearDown(client.close);
        final sessions = await client.listSessions();
        await client.getMessages(sessions.sessions.single);
        expect(requests, hasLength(2));
      },
    );

    test(
      'factory honours distinct gateway override without query/fragment leakage',
      () async {
        final client = ChatAssetsClient.fromConnection(
          SavedConnection(
            id: 'fixture',
            label: 'Fixture',
            host: 'original.fixture',
            port: 8642,
            apiKey: 'unused-fixture-key',
            dashboardProxied: true,
            desktopGatewayUrl:
                'https://override.fixture/edge/?untrusted=1#fragment',
          ),
          httpClient: MockClient((request) async {
            expect(request.url.scheme, 'https');
            expect(request.url.host, 'override.fixture');
            expect(request.url.port, 443);
            expect(request.url.path, '/edge/api/sessions');
            expect(
              request.url.queryParameters.containsKey('untrusted'),
              isFalse,
            );
            expect(request.url.fragment, isEmpty);
            expect(request.url.queryParameters.containsKey('profile'), isFalse);
            return http.Response('{"sessions": [], "total": 0}', 200);
          }),
        );
        addTearDown(client.close);
        await client.listSessions();
      },
    );

    test(
      'password factory authenticates once then reuses dashboard cookie for reads',
      () async {
        final requests = <http.Request>[];
        final client = ChatAssetsClient.fromConnection(
          SavedConnection(
            id: 'fixture',
            label: 'Fixture',
            host: 'assets.fixture',
            port: 8642,
            apiKey: 'unused-fixture-key',
            dashboardPrefix: '/private',
            dashboardUsername: 'fixture-user',
            dashboardPassword: 'fixture-password',
            gatewayProfile: 'personal',
          ),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/private/auth/password-login') {
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'provider': 'basic',
                'username': 'fixture-user',
                'password': 'fixture-password',
              });
              return http.Response(
                '{}',
                200,
                headers: {
                  'set-cookie':
                      'hermes_session_at=fixture-cookie; Path=/; HttpOnly',
                },
              );
            }
            expect(request.method, 'GET');
            expect(
              request.headers['cookie'],
              'hermes_session_at=fixture-cookie',
            );
            expect(request.headers.containsKey('authorization'), isFalse);
            expect(request.url.queryParameters['profile'], 'personal');
            if (request.url.path == '/private/api/sessions') {
              return http.Response('{"sessions": [], "total": 0}', 200);
            }
            expect(
              request.url.path,
              '/private/api/sessions/source-session/messages',
            );
            return http.Response(
              jsonEncode({..._messageEnvelope(), 'profile': 'personal'}),
              200,
            );
          }),
        );
        addTearDown(client.close);
        await client.listSessions();
        await client.getMessages(_session());
        expect(requests.map((request) => request.method), [
          'POST',
          'GET',
          'GET',
        ]);
        expect(requests.every((request) => request.url.port == 9119), isTrue);
      },
    );

    test(
      'omits no supplied profile and rejects mixed-profile session/message rows',
      () async {
        for (final response in [
          {
            'sessions': [
              {..._sessionRow('wrong'), 'profile': 'other'},
            ],
          },
          {'sessions': <Object>[], 'profile': 'other'},
        ]) {
          await expectLater(
            _responding(response, profile: 'work').listSessions(),
            throwsFormatException,
          );
        }
        for (final response in [
          {..._messageEnvelope(), 'profile': 'other'},
          _messageEnvelope(
            messages: [
              {
                'role': 'assistant',
                'profile': 'other',
                'content': 'MEDIA:/x.pdf',
              },
            ],
          ),
        ]) {
          await expectLater(
            _responding(response, profile: 'work').getMessages(_session()),
            throwsFormatException,
          );
        }
        final legacy = _responding({
          'sessions': [_sessionRow('legacy')],
        }, profile: 'work');
        expect((await legacy.listSessions()).sessions.single.id, 'legacy');
      },
    );

    test(
      'valid title-cased profile aliases preserve query and match canonical identity',
      () async {
        for (final configured in ['Default', 'Work', ' Work ']) {
          final canonical = configured.trim().toLowerCase();
          final client = _client((request) async {
            expect(request.url.queryParameters['profile'], configured);
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/messages')
                    ? {..._messageEnvelope(), 'profile': canonical}
                    : {
                        'sessions': [
                          {
                            ..._sessionRow('source-session'),
                            'profile': canonical,
                          },
                        ],
                      },
              ),
              200,
            );
          }, profile: configured);
          final page = await client.listSessions();
          expect(page.sessions.single.id, 'source-session');
          await client.getMessages(page.sessions.single);
        }
      },
    );

    test(
      'implicit profile scope rejects mixed rows and later message ownership changes',
      () async {
        final mixed = _responding({
          'sessions': [
            {..._sessionRow('one'), 'profile': 'work'},
            {..._sessionRow('two'), 'profile': 'other'},
          ],
        });
        await expectLater(mixed.listSessions(), throwsFormatException);
        final client = _client(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/messages')
                  ? {..._messageEnvelope(), 'profile': 'other'}
                  : {
                      'sessions': [
                        {..._sessionRow('source-session'), 'profile': 'work'},
                      ],
                    },
            ),
            200,
          ),
        );
        final listed = await client.listSessions();
        await expectLater(
          client.getMessages(listed.sessions.single),
          throwsFormatException,
        );
      },
    );

    test(
      'failed profile validation does not poison inferred ownership',
      () async {
        var reads = 0;
        final client = _client(
          (_) async => http.Response(
            jsonEncode({
              'sessions': reads++ == 0
                  ? [
                      {..._sessionRow('one'), 'profile': 'work'},
                      {..._sessionRow('two'), 'profile': 'other'},
                    ]
                  : [
                      {..._sessionRow('source-session'), 'profile': 'other'},
                    ],
            }),
            200,
          ),
        );
        await expectLater(client.listSessions(), throwsFormatException);
        expect(
          (await client.listSessions()).sessions.single.id,
          'source-session',
        );
      },
    );

    test('malformed configured profile fails before any HTTP lookup', () async {
      var requests = 0;
      final client = _client((_) async {
        requests++;
        return http.Response('{}', 200);
      }, profile: 'work/../other');
      await expectLater(client.listSessions(), throwsFormatException);
      expect(requests, 0);
    });

    test(
      'invalid bounds fail before HTTP and closed clients cannot read again',
      () async {
        var calls = 0;
        final client = _client((_) async {
          calls++;
          return http.Response('{}', 500);
        });
        for (final request in [
          () => client.listSessions(offset: -1),
          () => client.listSessions(limit: 0),
          () => client.listSessions(limit: 101),
          () => client.getMessages(_session(), offset: -1),
          () => client.getMessages(_session(), limit: 0),
          () => client.getMessages(_session(), limit: 501),
        ]) {
          await expectLater(request(), throwsRangeError);
        }
        await expectLater(
          client.getMessages(_session(' ')),
          throwsArgumentError,
        );
        client.close();
        await expectLater(client.listSessions(), throwsStateError);
        await expectLater(client.getMessages(_session()), throwsStateError);
        expect(calls, 0);
      },
    );

    test('close releases the factory HTTP client exactly once', () {
      final httpClient = _CloseTrackingClient();
      final client = ChatAssetsClient.fromConnection(
        SavedConnection(
          id: 'fixture',
          label: 'Fixture',
          host: 'assets.fixture',
          port: 8642,
          apiKey: 'unused-fixture-key',
          dashboardProxied: true,
        ),
        httpClient: httpClient,
      );
      client.close();
      client.close();
      expect(httpClient.closeCalls, 1);
    });
  });

  group('ChatAssetsClient session paging and validation', () {
    test(
      'pins dedupe without changing OFFSET progress or total-based hasMore',
      () async {
        final requestedOffsets = <String>[];
        final client = _client((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          requestedOffsets.add('$offset');
          return http.Response(
            jsonEncode({
              'sessions': [
                _sessionRow('pin', pinned: true),
                _sessionRow('pin', pinned: true),
                if (offset == 0)
                  ...List.generate(10, (index) => _sessionRow('row-$index')),
                if (offset == 20) _sessionRow('older'),
              ],
              'limit': 10,
              'offset': offset,
              'total': 25,
            }),
            200,
          );
        });
        final first = await client.listSessions();
        expect(first.sessions, hasLength(11)); // Backfill can exceed the limit.
        expect(first.nextOffset, 10);
        expect(first.hasMore, isTrue);
        final pinOnly = await client.listSessions(offset: first.nextOffset);
        expect(pinOnly.sessions.map((session) => session.id), ['pin']);
        expect(pinOnly.nextOffset, 20);
        expect(pinOnly.hasMore, isTrue);
        final last = await client.listSessions(offset: pinOnly.nextOffset);
        expect(last.sessions.map((session) => session.id), ['pin', 'older']);
        expect(last.nextOffset, 30);
        expect(last.hasMore, isFalse);
        expect(requestedOffsets, ['0', '10', '20']);
      },
    );

    test('empty/short windows do not override an explicit total', () async {
      final client = _responding({'sessions': <Object>[], 'total': 23});
      expect((await client.listSessions(offset: 10)).hasMore, isTrue);
      expect((await client.listSessions(offset: 20)).hasMore, isFalse);
      final last = _responding({
        'sessions': [_sessionRow('pin')],
        'total': 0,
      });
      expect((await last.listSessions()).hasMore, isFalse);
    });

    test(
      'without total any nonempty raw page conservatively permits more',
      () async {
        final page = await _responding({
          'sessions': [_sessionRow('only')],
        }).listSessions(offset: 10);
        expect(page.hasMore, isTrue);
        expect(page.nextOffset, 20);
        final empty = await _responding({
          'sessions': <Object>[],
        }).listSessions();
        expect(empty.hasMore, isFalse);
      },
    );

    test(
      'unusable ids are filtered without altering exact valid ids or page progress',
      () async {
        final page = await _responding({
          'sessions': [
            {'id': ''},
            {'id': '  '},
            {'id': null},
            {'id': 42},
            <String, Object>{},
            _sessionRow('opaque /%雪'),
            _sessionRow('opaque /%雪'),
          ],
        }).listSessions(offset: 20);
        expect(page.sessions.map((session) => session.id), ['opaque /%雪']);
        expect(page.nextOffset, 30);
        expect(page.hasMore, isTrue);
        expect(page.partial, isTrue);
        final allInvalid = await _responding({
          'sessions': [
            {'id': null},
          ],
        }).listSessions();
        expect(allInvalid.sessions, isEmpty);
        expect(allInvalid.hasMore, isTrue);
        expect(allInvalid.partial, isTrue);
      },
    );

    test(
      'optional errors/storage flags expose partial reads rather than false emptiness',
      () async {
        for (final issue in [
          {'error': 'store is busy'},
          {
            'errors': ['unreadable row'],
          },
          {
            'errors': {'work': 'corrupt'},
          },
          {
            'storage': {'work': 'corrupt'},
          },
          {'storage_unavailable': true},
          {'partial': true},
          {'ok': false},
        ]) {
          final page = await _responding({
            'sessions': <Object>[],
            ...issue,
          }).listSessions();
          expect(page.partial, isTrue, reason: '$issue');
        }
        final page = await _responding({
          'sessions': <Object>[],
          'error': '',
          'errors': <Object>[],
          'storage': <String, Object>{},
          'partial': false,
        }).listSessions();
        expect(page.partial, isFalse);
      },
    );

    test('rejects malformed envelopes and contradictory pagination', () async {
      for (final response in <Object?>[
        null,
        [],
        {},
        {'data': []},
        {'error': 'cannot read'},
        {'sessions': null},
        {'sessions': {}},
        {
          'sessions': [1],
        },
        {'sessions': [], 'total': -1},
        {'sessions': [], 'total': '10'},
        {'sessions': [], 'total': null},
        {'sessions': [], 'offset': 1},
        {'sessions': [], 'limit': 9},
        {'sessions': [], 'offset': '0'},
        {'sessions': [], 'limit': null},
        {
          'sessions': [
            {..._sessionRow('bad'), 'title': 42},
          ],
        },
        {
          'sessions': [
            {..._sessionRow('bad'), 'profile': 42},
          ],
        },
      ]) {
        await expectLater(
          _responding(response).listSessions(),
          throwsFormatException,
          reason: '$response',
        );
      }
    });
  });

  group('ChatAssetsClient message paging and validation', () {
    test(
      'pages raw rows even when no asset survives role/display projection',
      () async {
        final offsets = <int>[];
        final client = _client((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(offset);
          final messages = offset == 0
              ? List.generate(
                  100,
                  (index) => <String, dynamic>{
                    'id': index,
                    'role': 'tool',
                    'content': 'MEDIA:/tool/$index.pdf',
                  },
                )
              : [
                  {
                    'id': 101,
                    'role': 'assistant',
                    'content': 'MEDIA:/out/older.pdf',
                  },
                ];
          return http.Response(
            jsonEncode(_messageEnvelope(messages: messages, offset: offset)),
            200,
          );
        });
        final source = _session();
        final first = await client.getMessages(source);
        expect(chatAssetsFromMessages(source, first.messages), isEmpty);
        expect(first.hasMore, isTrue);
        expect(first.nextOffset, 100);
        final last = await client.getMessages(source, offset: first.nextOffset);
        expect(last.hasMore, isFalse);
        expect(last.nextOffset, 200);
        expect(
          chatAssetsFromMessages(source, last.messages).single.ref.path,
          '/out/older.pdf',
        );
        expect(offsets, [0, 100]);
      },
    );

    test(
      'custom requested limit and offset are used, not the projected row count',
      () async {
        final client = _client((request) async {
          expect(request.url.queryParameters['limit'], '2');
          expect(request.url.queryParameters['offset'], '4');
          return http.Response(
            jsonEncode(
              _messageEnvelope(
                limit: 2,
                offset: 4,
                messages: [
                  {'role': 'assistant', 'content': 'MEDIA:/out/only.pdf'},
                ],
              ),
            ),
            200,
          );
        });
        final page = await client.getMessages(_session(), offset: 4, limit: 2);
        expect(page.nextOffset, 6);
        expect(page.hasMore, isFalse);
      },
    );

    test(
      'missing returned metadata keeps short nonempty legacy projections pageable',
      () async {
        for (final pagination in <Map<String, dynamic>?>[
          null,
          {'limit': 100, 'offset': 0, 'order': 'latest'},
        ]) {
          final client = _responding({
            'session_id': 'source-session',
            'messages': [
              {'role': 'assistant', 'content': 'MEDIA:/out/a.pdf'},
            ],
            'pagination': ?pagination,
          });
          expect((await client.getMessages(_session())).hasMore, isTrue);
        }
        final empty = await _responding({
          'session_id': 'source-session',
          'messages': <Object>[],
        }).getMessages(_session());
        expect(empty.hasMore, isFalse);
        final explicitEmpty = await _responding(
          _messageEnvelope(),
        ).getMessages(_session());
        expect(explicitEmpty.hasMore, isFalse);
      },
    );

    test(
      'rejects malformed messages and pagination, including returned/actual mismatch',
      () async {
        final valid = _messageEnvelope();
        for (final response in <Object?>[
          null,
          [],
          {},
          {'data': []},
          {'error': 'cannot read'},
          {'messages': null},
          {'messages': {}},
          {
            'messages': [1],
          },
          {'messages': <Object>[]},
          {...valid, 'session_id': ''},
          {...valid, 'session_id': 42},
          {...valid, 'session_id': 'different-canonical-tip'},
          {...valid, 'pagination': null},
          {...valid, 'pagination': []},
          for (final delta in [
            {'limit': 99},
            {'offset': 1},
            {'order': 'oldest'},
            {'returned': 1},
            {'returned': -1},
            {'returned': '0'},
            {'returned': null},
            {'limit': null},
            {'offset': '0'},
          ])
            {
              ...valid,
              'pagination': {...valid['pagination'] as Map, ...delta},
            },
          {
            'session_id': 'source-session',
            'messages': List.generate(
              101,
              (_) => {'role': 'tool', 'content': ''},
            ),
          },
        ]) {
          await expectLater(
            _responding(response).getMessages(_session()),
            throwsFormatException,
            reason: '$response',
          );
        }
      },
    );

    test(
      'message storage/error flags fail instead of presenting an empty success',
      () async {
        for (final issue in [
          {'error': 'unreadable'},
          {
            'errors': ['unreadable'],
          },
          {
            'storage': {'work': 'corrupt'},
          },
          {'partial': true},
        ]) {
          await expectLater(
            _responding({
              ..._messageEnvelope(),
              ...issue,
            }).getMessages(_session()),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'propagates HTTP failures and retries rejected auth only once',
      () async {
        var requests = 0;
        final client = _client((_) async {
          requests++;
          return http.Response('{"error":"unauthorized"}', 401);
        });
        await expectLater(
          client.listSessions(),
          throwsA(
            isA<DashboardHttpException>().having(
              (e) => e.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(requests, 2);
        final unavailable = _client(
          (_) async => http.Response('unavailable', 503),
        );
        await expectLater(
          unavailable.getMessages(_session()),
          throwsA(
            isA<DashboardHttpException>().having(
              (e) => e.statusCode,
              'status',
              503,
            ),
          ),
        );
        final disconnected = _client(
          (_) async => throw http.ClientException('fixture offline'),
        );
        await expectLater(
          disconnected.listSessions(),
          throwsA(isA<http.ClientException>()),
        );
      },
    );
  });
}
