import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/fallback_config.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fallback_config_contract.dart';

Map<String, dynamic> operation(Map<String, dynamic> schema) =>
    schema['paths']['/api/config']['get'] as Map<String, dynamic>;
List<dynamic> parameters(Map<String, dynamic> schema) =>
    operation(schema)['parameters'] as List<dynamic>;

void main() {
  final invalidSchemas = <String, Object Function()>{
    'actual older producer': () => fallbackConfigSchema(older: true),
    'missing paths': () => {},
    'non-map document': () => [],
    'wrong config path': () {
      final schema = fallbackConfigSchema();
      schema['paths']['/api/other'] = schema['paths'].remove('/api/config');
      return schema;
    },
    'POST is not GET': () {
      final schema = fallbackConfigSchema();
      schema['paths']['/api/config']['post'] = schema['paths']['/api/config']
          .remove('get');
      return schema;
    },
    'missing parameters': () {
      final schema = fallbackConfigSchema();
      operation(schema).remove('parameters');
      return schema;
    },
    'string instead of boolean': () {
      final schema = fallbackConfigSchema();
      parameters(schema).last['schema']['type'] = 'string';
      return schema;
    },
    'boolean header instead of query': () {
      final schema = fallbackConfigSchema();
      parameters(schema).last['in'] = 'header';
      return schema;
    },
    'duplicate ambiguous parameter': () {
      final schema = fallbackConfigSchema();
      parameters(schema).add(parameters(schema).last);
      return schema;
    },
    'unresolved reference': () {
      final schema = fallbackConfigSchema();
      parameters(schema)[1] = {
        r'$ref': '#/components/parameters/include_defaults',
      };
      return schema;
    },
    'malformed parameter': () {
      final schema = fallbackConfigSchema();
      parameters(schema).add('never-show-schema-secret');
      return schema;
    },
    'selected profile absent': () {
      final schema = fallbackConfigSchema();
      parameters(schema).removeAt(0);
      return schema;
    },
    'selected profile in body': () {
      final schema = fallbackConfigSchema();
      parameters(schema).first['in'] = 'body';
      return schema;
    },
    'profile boolean': () {
      final schema = fallbackConfigSchema();
      parameters(schema).first['schema'] = {'type': 'boolean'};
      return schema;
    },
  };
  for (final entry in invalidSchemas.entries) {
    for (final write in [false, true]) {
      test(
        '${entry.key}: typed ${write ? 'direct PUT' : 'GET'} fails closed before config traffic; retry works',
        () async {
          Object schema = entry.value();
          final seen = <http.Request>[];
          final client = DashboardClient(
            host: 'dashboard.test',
            pathPrefix: '/prefix/',
            proxied: true,
            gatewayProfile: 'selected & encoded',
            httpClient: MockClient((request) async {
              seen.add(request);
              if (request.url.path == '/prefix/openapi.json') {
                expect(request.url.queryParameters, isEmpty);
                expect(request.followRedirects, isFalse);
                return http.Response(jsonEncode(schema), 200);
              }
              return http.Response(
                request.method == 'PUT'
                    ? '{"ok":true}'
                    : '{"fallback_providers":[]}',
                200,
              );
            }),
          );
          addTearDown(client.close);
          Future<Object> invoke() => write
              ? client.setFallbackProviders([])
              : client.getFallbackConfig();
          await expectLater(
            invoke(),
            throwsA(
              isA<FormatException>().having(
                (e) => e.toString(),
                'safe error',
                'FormatException: Raw fallback configuration unavailable',
              ),
            ),
          );
          expect(seen.map((r) => r.url.path), ['/prefix/openapi.json']);
          schema = fallbackConfigSchema();
          await invoke();
          expect(seen.last.url.path, '/prefix/api/config');
          if (write) {
            expect(jsonDecode(seen.last.body), {
              'config': {'fallback_providers': []},
              'profile': 'selected & encoded',
            });
          } else {
            expect(seen.last.url.queryParameters, {
              'profile': 'selected & encoded',
              'include_defaults': 'false',
            });
          }
        },
      );
    }
  }

  for (final failure in [
    '404',
    '403',
    '401',
    '500',
    '302',
    'invalid JSON',
    'throw',
  ]) {
    test(
      'schema $failure is safe, bounded and retryable without config reads/writes',
      () async {
        var failing = true;
        var schemas = 0;
        var configs = 0;
        final client = DashboardClient(
          host: 'dashboard.test',
          proxied: true,
          httpClient: MockClient((request) async {
            if (request.url.path == '/openapi.json') {
              schemas++;
              if (!failing) {
                return http.Response(jsonEncode(fallbackConfigSchema()), 200);
              }
              if (failure == 'throw') {
                throw StateError('never-show-schema-secret');
              }
              if (failure == 'invalid JSON') {
                return http.Response('{never-show-schema-secret', 200);
              }
              return http.Response(
                'never-show-schema-secret',
                int.parse(failure),
                headers: {'location': 'https://untrusted.invalid/'},
              );
            }
            configs++;
            return http.Response('{"fallback_providers":[]}', 200);
          }),
        );
        addTearDown(client.close);
        await expectLater(
          client.getFallbackConfig(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.toString(),
              'safe error',
              isNot(contains('never-show')),
            ),
          ),
        );
        expect(schemas, failure == '401' ? 2 : 1);
        await expectLater(
          client.setFallbackProviders([]),
          throwsFormatException,
        );
        expect(configs, 0);
        failing = false;
        await client.getFallbackConfig();
        expect(configs, 1);
      },
    );
  }

  test(
    'schema 401 replaces password cookie once, preserving prefix and selected config',
    () async {
      final seen = <http.Request>[];
      var logins = 0;
      var schemas = 0;
      final client = DashboardClient(
        host: 'dashboard.test',
        pathPrefix: '/proxy',
        username: 'user',
        password: 'fake-password',
        gatewayProfile: 'chosen',
        httpClient: MockClient((request) async {
          seen.add(request);
          if (request.url.path == '/proxy/auth/password-login') {
            logins++;
            expect(request.url.queryParameters, isEmpty);
            return http.Response(
              '{}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=fake-$logins; Path=/; HttpOnly',
              },
            );
          }
          if (request.url.path == '/proxy/openapi.json') {
            schemas++;
            expect(
              request.headers['cookie'],
              'hermes_session_at=fake-$schemas',
            );
            expect(request.headers['authorization'], isNull);
            expect(request.url.queryParameters, isEmpty);
            return schemas == 1
                ? http.Response('never-show-secret', 401)
                : http.Response(jsonEncode(fallbackConfigSchema()), 200);
          }
          expect(request.headers['cookie'], 'hermes_session_at=fake-2');
          expect(request.url.queryParameters, {
            'profile': 'chosen',
            'include_defaults': 'false',
          });
          return http.Response('{"fallback_providers":[]}', 200);
        }),
      );
      addTearDown(client.close);
      await client.getFallbackConfig();
      expect(logins, 2);
      expect(schemas, 2);
      expect(seen.map((r) => r.url.path), [
        '/proxy/auth/password-login',
        '/proxy/openapi.json',
        '/proxy/auth/password-login',
        '/proxy/openapi.json',
        '/proxy/api/config',
      ]);
    },
  );

  test(
    'loopback SPA token auth applies to root schema and direct typed save',
    () async {
      final seen = <http.Request>[];
      final client = DashboardClient(
        host: '127.0.0.1',
        pathPrefix: '/local',
        httpClient: MockClient((request) async {
          seen.add(request);
          if (request.url.path == '/local/') {
            return http.Response(
              'window.__HERMES_SESSION_TOKEN__="fake-spa";',
              200,
            );
          }
          expect(request.headers['X-Hermes-Session-Token'], 'fake-spa');
          expect(request.headers['authorization'], isNull);
          expect(request.headers['cookie'], isNull);
          return http.Response(
            request.url.path.endsWith('openapi.json')
                ? jsonEncode(fallbackConfigSchema())
                : '{"ok":true}',
            200,
          );
        }),
      );
      addTearDown(client.close);
      expect(await client.setFallbackProviders([]), isTrue);
      expect(seen.map((r) => r.url.path), [
        '/local/',
        '/local/openapi.json',
        '/local/api/config',
      ]);
    },
  );

  test(
    'positive schema is not reused after downgrade before direct save',
    () async {
      var schema = fallbackConfigSchema();
      final seen = <http.Request>[];
      final client = DashboardClient(
        host: 'dashboard.test',
        proxied: true,
        httpClient: MockClient((request) async {
          seen.add(request);
          return http.Response(
            request.url.path == '/openapi.json'
                ? jsonEncode(schema)
                : '{"fallback_providers":[]}',
            200,
          );
        }),
      );
      addTearDown(client.close);
      await client.getFallbackConfig();
      schema = fallbackConfigSchema(older: true);
      await expectLater(client.setFallbackProviders([]), throwsFormatException);
      expect(seen.where((r) => r.method == 'PUT'), isEmpty);
    },
  );

  test(
    'actual ignored-query HTTP 200 plus reorder cannot reach a typed write',
    () async {
      final contract = fallbackConfigContract();
      final trap = contract['old_ignored_query'] as Map;
      expect(trap['status'], 200);
      expect(
        trap['raw']['fallback_providers'][1]['api_key'],
        r'${FAKE_REVIEW_KEY}',
      );
      final response = FallbackConfig.fromConfig(
        trap['response'] as Map<String, dynamic>,
      );
      final reordered = response.entries.reversed.toList();
      expect(
        trap['reordered_after_actual_template_guard']['fallback_providers'],
        reordered.map((e) => e.toJson()).toList(),
      );
      final seen = <http.Request>[];
      final client = DashboardClient(
        host: 'dashboard.test',
        proxied: true,
        httpClient: MockClient((request) async {
          seen.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('openapi.json')
                  ? contract['old_schema']
                  : trap['response'],
            ),
            200,
          );
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.setFallbackProviders(reordered),
        throwsFormatException,
      );
      await expectLater(client.getFallbackConfig(), throwsFormatException);
      expect(
        seen.every((r) => r.method == 'GET' && r.url.path == '/openapi.json'),
        isTrue,
      );
      expect(seen, hasLength(2));
    },
  );

  test(
    'held capability check does not block independent model requests',
    () async {
      final held = Completer<http.Response>();
      final seen = <String>[];
      final client = DashboardClient(
        host: 'dashboard.test',
        proxied: true,
        httpClient: MockClient((request) async {
          seen.add(request.url.path);
          if (request.url.path == '/openapi.json') return held.future;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      final fallback = client.getFallbackConfig();
      await client.getModelOptions();
      await client.getAuxiliaryModels();
      expect(
        seen,
        containsAll([
          '/openapi.json',
          '/api/model/options',
          '/api/model/auxiliary',
        ]),
      );
      expect(seen, isNot(contains('/api/config')));
      held.complete(http.Response('{}', 200));
      await expectLater(fallback, throwsFormatException);
    },
  );
}
