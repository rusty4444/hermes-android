import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/fallback_config.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

import 'support/fallback_config_contract.dart';
import 'support/mtls_fixture.dart';

// Separate from widget tests: their binding overrides HttpClient with HTTP 400.
void main() {
  test(
    'actual older schema blocks ignored-query HTTP-200 trap and reordered secret on TCP; current schema restores raw editing',
    () async {
      final contract = fallbackConfigContract();
      final trap = contract['old_ignored_query'] as Map;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var older = true;
      final seen = <String>[];
      var raw = trap['raw'] as Map<String, dynamic>;
      server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        Object payload;
        if (request.uri.path == '/proxy/openapi.json') {
          expect(request.uri.queryParameters, isEmpty);
          payload = fallbackConfigSchema(older: older);
        } else {
          // Faithful old-host danger: the query is ignored, HTTP stays 200.
          expect(request.uri.path, '/proxy/api/config');
          if (request.method == 'PUT') {
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            raw = {...raw, ...body['config'] as Map<String, dynamic>};
            payload = {'ok': true};
          } else {
            expect(request.uri.queryParameters, {
              'profile': 'selected-fixture',
              'include_defaults': 'false',
            });
            payload = older ? trap['response'] as Map : raw;
          }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(payload));
        await request.response.close();
      });
      final client = DashboardClient(
        host: '127.0.0.1',
        port: server.port,
        pathPrefix: '/proxy',
        gatewayProfile: 'selected-fixture',
        proxied: true,
      );
      try {
        final expanded = FallbackConfig.fromConfig(
          trap['response'] as Map<String, dynamic>,
        );
        await expectLater(client.getFallbackConfig(), throwsFormatException);
        await expectLater(
          client.setFallbackProviders(expanded.entries.reversed.toList()),
          throwsFormatException,
        );
        expect(seen, ['GET /proxy/openapi.json', 'GET /proxy/openapi.json']);
        expect(raw['fallback_providers'][1]['api_key'], r'${FAKE_REVIEW_KEY}');
        older = false;
        final before = await client.getFallbackConfig();
        final reordered = before.entries.reversed.toList();
        expect(await client.setFallbackProviders(reordered), isTrue);
        final after = await client.getFallbackConfig();
        expect(after.confirms(reordered, before), isTrue);
        expect(raw['fallback_providers'][0]['api_key'], r'${FAKE_REVIEW_KEY}');
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'capability schema and config read/write retain actual mTLS identity and prefix',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        expect(request.uri.path, startsWith('/proxy/'));
        fixture.json(
          request,
          request.uri.path == '/proxy/openapi.json'
              ? fallbackConfigSchema()
              : request.method == 'PUT'
              ? {'ok': true}
              : {'fallback_providers': []},
        );
        await request.response.close();
      });
      try {
        await withLoopbackTrust(() async {
          final client = DashboardClient.fromConnection(
            SavedConnection(
              id: 'mtls',
              label: 'mTLS',
              host: 'wrong.invalid',
              port: 8642,
              apiKey: '',
              desktopGatewayUrl: '${fixture.origin}/proxy',
              gatewayProfile: 'chosen',
              dashboardProxied: true,
              clientCertificate: loopbackIdentity,
            ),
          );
          try {
            await client.getFallbackConfig();
            expect(await client.setFallbackProviders([]), isTrue);
            await client.getFallbackConfig();
          } finally {
            client.close();
          }
        });
        expect(fixture.anonymousRequests, 0);
        expect(fixture.requests.map((r) => '${r.method} ${r.uri.path}'), [
          'GET /proxy/openapi.json',
          'GET /proxy/api/config',
          'GET /proxy/openapi.json',
          'PUT /proxy/api/config',
          'GET /proxy/openapi.json',
          'GET /proxy/api/config',
        ]);
        for (final request in fixture.requests) {
          expect(request.certificate, isNotNull);
          expect(request.headers.value('authorization'), isNull);
          expect(request.headers.value('cookie'), isNull);
          expect(
            request.uri.queryParameters,
            request.uri.path.endsWith('openapi.json') || request.method == 'PUT'
                ? isEmpty
                : {'profile': 'chosen', 'include_defaults': 'false'},
          );
        }
      } finally {
        await fixture.close();
      }
    },
  );

  for (final proxied in [false, true]) {
    test(
      'fallback raw GET/minimal PUT/fresh exact readback retain selected profile, prefix and ${proxied ? 'proxy' : 'password'} auth on TCP',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final seen = <Map<String, dynamic>>[];
        final launch = {
          'fallback_providers': [
            {'provider': 'launch-provider', 'model': 'launch-model'},
          ],
          'untouched': 'launch',
        };
        final selected = <String, dynamic>{
          'fallback_providers': [
            {
              'provider': 'retired',
              'model': 'unlisted',
              'api_key': r'${RAW_KEY}',
              'base_url': 'https://private.invalid/v1',
              'future': {
                'v': [3, false],
              },
            },
          ],
          'fallback_model': {
            'provider': 'legacy',
            'model': 'legacy-model',
            'key_env': 'OLD_KEY',
          },
          'unrelated': {'secret': 'do-not-send'},
          'model': {'provider': 'main', 'default': 'main-model'},
        };
        final launchBytes = jsonEncode(launch);
        final legacyBytes = jsonEncode(selected['fallback_model']);
        server.listen((request) async {
          final text = await utf8.decoder.bind(request).join();
          final body = text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>;
          final profile =
              body['profile'] ?? request.uri.queryParameters['profile'];
          seen.add({
            'method': request.method,
            'path': request.uri.path,
            'query': request.uri.queryParameters,
            'cookie': request.headers.value('cookie'),
            'authorization': request.headers.value('authorization'),
            'body': body,
          });
          Object payload;
          var status = 200;
          if (request.uri.path == '/prefix/auth/password-login') {
            request.response.headers.add(
              'set-cookie',
              'hermes_session_at=fallback-cookie; HttpOnly; Path=/',
            );
            payload = {'ok': true};
          } else if (request.uri.path == '/prefix/openapi.json') {
            payload = fallbackConfigSchema();
          } else if (profile != null && profile != 'research & development') {
            status = 404;
            payload = {'detail': 'unknown profile'};
          } else if (request.uri.path == '/prefix/api/model/options') {
            payload = {
              'providers': [
                {
                  'slug': 'other',
                  'models': ['other-model'],
                },
              ],
            };
          } else if (request.uri.path == '/prefix/api/config') {
            final target = profile == null ? launch : selected;
            if (request.method == 'PUT') {
              target.addAll((body['config'] as Map).cast<String, dynamic>());
              payload = {'ok': true};
            } else {
              payload = target;
            }
          } else {
            status = 404;
            payload = {};
          }
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(payload));
          await request.response.close();
        });
        final connection = SavedConnection(
          id: 'wire',
          label: 'Wire',
          host: 'wrong.invalid',
          port: 8642,
          apiKey: 'unused-api-server-key',
          desktopGatewayUrl: 'http://127.0.0.1:${server.port}/prefix',
          gatewayProfile: 'research & development',
          dashboardProxied: proxied,
          dashboardUsername: proxied ? '' : 'fixture-user',
          dashboardPassword: proxied ? '' : 'fixture-password',
        );
        final client = DashboardClient.fromConnection(connection);
        final fresh = DashboardClient.fromConnection(connection);
        final unknown = DashboardClient.fromConnection(
          connection.copyWith(gatewayProfile: 'unknown'),
        );
        try {
          expect(client.baseUrl, 'http://127.0.0.1:${server.port}/prefix');
          expect(fresh.baseUrl, client.baseUrl);
          expect(unknown.baseUrl, client.baseUrl);
          final before = await client.getFallbackConfig();
          await client.getModelOptions();
          final expected = [
            FallbackEntry({'provider': 'other', 'model': 'other-model'}),
            ...before.entries,
          ];
          expect(await client.setFallbackProviders(expected), isTrue);
          final actual = await fresh.getFallbackConfig();
          expect(actual.confirms(expected, before), isTrue);
          expect(jsonEncode(launch), launchBytes);
          expect(jsonEncode(selected['fallback_model']), legacyBytes);
          expect(selected['unrelated'], {'secret': 'do-not-send'});
          expect(await client.setFallbackProviders([]), isTrue);
          final cleared = await fresh.getFallbackConfig();
          expect(cleared.confirms([], actual), isTrue);
          expect(cleared.legacyEntries.single.model, 'legacy-model');
          await expectLater(unknown.getFallbackConfig(), throwsException);
          expect(
            await client
                .setFallbackProviders([FallbackEntry.blank()])
                .then<Object>((v) => v, onError: (Object e) => e),
            isA<FormatException>(),
          );
          final api = seen
              .where((r) => (r['path'] as String).contains('/api/'))
              .toList();
          expect(api, hasLength(7));
          for (final request in api) {
            expect(request['path'], startsWith('/prefix/api/'));
            expect(request['authorization'], isNull);
            expect(
              request['cookie'],
              proxied ? isNull : contains('hermes_session_at=fallback-cookie'),
            );
            if (request['method'] == 'GET') {
              expect(
                (request['query'] as Map)['profile'],
                request == api.last ? 'unknown' : 'research & development',
              );
              if (request['path'] == '/prefix/api/config') {
                expect((request['query'] as Map)['include_defaults'], 'false');
              }
            }
          }
          final writes = api.where((r) => r['method'] == 'PUT').toList();
          final schemas = seen.where(
            (r) => r['path'] == '/prefix/openapi.json',
          );
          expect(
            schemas,
            hasLength(
              api.where((r) => r['path'] == '/prefix/api/config').length,
            ),
          );
          for (final request in schemas) {
            expect(request['query'], isEmpty);
            expect(request['body'], isEmpty);
            expect(request['authorization'], isNull);
            expect(
              request['cookie'],
              proxied ? isNull : contains('hermes_session_at=fallback-cookie'),
            );
          }
          expect(writes, hasLength(2));
          expect(writes.first['body'], {
            'config': {
              'fallback_providers': expected.map((e) => e.toJson()).toList(),
            },
            'profile': 'research & development',
          });
          expect(writes.last['body'], {
            'config': {'fallback_providers': []},
            'profile': 'research & development',
          });
          expect(writes.every((r) => (r['query'] as Map).isEmpty), isTrue);
          expect(
            seen.where((r) => r['path'] == '/prefix/auth/password-login'),
            hasLength(proxied ? 0 : 3),
          );
        } finally {
          client.close();
          fresh.close();
          unknown.close();
          await server.close(force: true);
        }
      },
    );
  }
  test(
    'omitted-profile legacy connections retain omission, not invented default authority',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        seen.add({
          'query': request.uri.queryParameters,
          'body': body.isEmpty ? null : jsonDecode(body),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          request.uri.path == '/openapi.json'
              ? jsonEncode(fallbackConfigSchema())
              : request.method == 'PUT'
              ? '{"ok":true}'
              : '{"fallback_providers":[]}',
        );
        await request.response.close();
      });
      final client = DashboardClient.fromConnection(
        SavedConnection(
          id: 'legacy',
          label: 'Legacy',
          host: 'wrong.invalid',
          port: 8642,
          apiKey: '',
          desktopGatewayUrl: 'http://127.0.0.1:${server.port}',
          dashboardProxied: true,
        ),
      );
      try {
        expect(client.baseUrl, 'http://127.0.0.1:${server.port}');
        await client.getFallbackConfig();
        await client.setFallbackProviders([]);
        expect(seen, [
          {'query': {}, 'body': null},
          {
            'query': {'include_defaults': 'false'},
            'body': null,
          },
          {'query': {}, 'body': null},
          {
            'query': {},
            'body': {
              'config': {'fallback_providers': []},
            },
          },
        ]);
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );
}
