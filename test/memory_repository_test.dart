import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/memory_fact.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/memory_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Small synthetic responses exercise invalid and transport-specific cases.
// Backend-produced fixtures cover the real route contract separately.
Map<String, dynamic> _graph() => {
  'memory': <Map<String, dynamic>>[
    {'source': 'memory', 'body': 'The workspace uses Dart.'},
    {'source': 'profile', 'body': 'User prefers concise replies.'},
  ],
  'nodes': [
    {'kind': 'skill', 'id': 'not-a-memory'},
    {
      'kind': 'memory',
      'id': 'memory:memory:0:0123456789ab',
      'memorySource': 'memory',
    },
    {
      'kind': 'memory',
      'id': 'memory:profile:1:abcdef012345',
      'memorySource': 'profile',
    },
  ],
};

SavedConnection _connection() => SavedConnection(
  id: 'memory-test',
  label: 'Test',
  host: 'gateway.example',
  port: 8642,
  apiKey: 'unused-test-key',
  dashboardPortOverride: 9443,
  useHttps: true,
  dashboardPrefix: '/dashboard',
  dashboardProxied: true,
  gatewayProfile: 'work',
);

http.Response _json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('parses actual facts rather than configuration or skill nodes', () {
    final facts = MemoryFact.parseGraph(_graph());
    expect(facts.map((fact) => fact.content), [
      'The workspace uses Dart.',
      'User prefers concise replies.',
    ]);
    expect(facts.map((fact) => fact.source), [
      MemoryFactSource.memory,
      MemoryFactSource.profile,
    ]);
    expect(facts.last.source.fileName, 'USER.md');
    expect(facts.first.source.fileName, 'MEMORY.md');
    expect(() => facts.clear(), throwsUnsupportedError);
  });

  test('only an explicit empty memory list is an empty result', () {
    expect(MemoryFact.parseGraph({'memory': [], 'nodes': []}), isEmpty);
    for (final invalid in <Map<String, dynamic>>[
      {},
      {
        'memory': {'memory_enabled': true},
      },
      {'memory': null, 'nodes': []},
      {
        'memory': [null],
        'nodes': [],
      },
      {'memory': [], 'nodes': null},
    ]) {
      expect(() => MemoryFact.parseGraph(invalid), throwsFormatException);
    }
  });

  test(
    'malformed facts and mismatched identities are not silently omitted',
    () {
      for (final bad in [
        {'source': 'profile', 'body': true},
        {'source': 'profile', 'body': ''},
        {'source': 'unknown-provider', 'body': 'Not a built-in memory'},
      ]) {
        final graph = _graph();
        (graph['memory'] as List)[1] = bad;
        expect(() => MemoryFact.parseGraph(graph), throwsFormatException);
      }
      final mismatched = _graph();
      (mismatched['nodes'] as List)[2]['id'] = 'memory:memory:1:abcdef012345';
      expect(() => MemoryFact.parseGraph(mismatched), throwsFormatException);
    },
  );

  test('malformed memory IDs are rejected verbatim, never normalised', () {
    for (final id in [
      'memory:profile:1:abcdef012345\n',
      ' memory:profile:1:abcdef012345',
      'memory:profile:01:abcdef012345',
      'memory:profile:1:NOT-A-DIGEST',
    ]) {
      final graph = _graph();
      (graph['nodes'] as List)[2]['id'] = id;
      expect(() => MemoryFact.parseGraph(graph), throwsFormatException);
    }
  });

  test('preview boundary counts Unicode code points like Python', () {
    final graph = _graph();
    (graph['memory'] as List)[1]['body'] = List.filled(1199, '🙂').join();
    expect(MemoryFact.parseGraph(graph).last.mayBeTruncated, isFalse);
    (graph['memory'] as List)[1]['body'] += 'x';
    expect(MemoryFact.parseGraph(graph).last.mayBeTruncated, isTrue);
  });

  test(
    'reads GET learning graph with dashboard prefix, auth and profile',
    () async {
      final requests = <http.Request>[];
      final repository = MemoryRepository.fromConnection(
        _connection(),
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://gateway.example:9443/dashboard/api/learning/graph?profile=work',
          );
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          return _json(_graph());
        }),
      );
      addTearDown(repository.close);
      expect(await repository.loadFacts(), hasLength(2));
      expect(requests, hasLength(1));
    },
  );

  test('honours a distinct explicit Desktop gateway origin', () async {
    final repository = MemoryRepository.fromConnection(
      _connection().copyWith(
        desktopGatewayUrl: 'https://desktop.example:9444/remote/',
      ),
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://desktop.example:9444/remote/api/learning/graph?profile=work',
        );
        return _json(_graph());
      }),
    );
    addTearDown(repository.close);
    await repository.loadFacts();
  });

  test(
    'reuses dashboard password-cookie auth for graph and full fact',
    () async {
      var logins = 0;
      final connection = _connection().copyWith(
        dashboardProxied: false,
        dashboardUsername: 'test-user',
        dashboardPassword: 'test-password',
      );
      final repository = MemoryRepository.fromConnection(
        connection,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/password-login')) {
            logins++;
            expect(request.method, 'POST');
            return http.Response(
              '{}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=test-session; Path=/; HttpOnly',
              },
            );
          }
          expect(request.method, 'GET');
          expect(request.headers['cookie'], 'hermes_session_at=test-session');
          expect(request.url.queryParameters['profile'], 'work');
          if (request.url.path.endsWith('/learning/node')) {
            expect(
              request.url.queryParameters['id'],
              'memory:profile:1:abcdef012345',
            );
            return _json({
              'ok': true,
              'kind': 'memory',
              'id': 'memory:profile:1:abcdef012345',
              'content': 'User prefers concise replies. Full saved fact.',
            });
          }
          return _json(_graph());
        }),
      );
      addTearDown(repository.close);
      final facts = await repository.loadFacts();
      expect(
        await repository.loadFullFact(facts.last),
        'User prefers concise replies. Full saved fact.',
      );
      expect(logins, 1);
    },
  );

  test('unsupported endpoint never falls back to configuration', () async {
    final paths = <String>[];
    final repository = MemoryRepository.fromConnection(
      _connection(),
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('Not found', 404);
      }),
    );
    addTearDown(repository.close);
    await expectLater(
      repository.loadFacts(),
      throwsA(isA<DashboardHttpException>()),
    );
    expect(paths, ['/dashboard/api/learning/graph']);
  });

  test('a shifted legacy node cannot substitute a different fact', () async {
    const fact = MemoryFact(
      id: 'memory:profile:1',
      source: MemoryFactSource.profile,
      content: 'User prefers concise replies.',
    );
    final repository = MemoryRepository.fromConnection(
      _connection(),
      httpClient: MockClient(
        (_) async => _json({
          'ok': true,
          'kind': 'memory',
          'id': fact.id,
          'content': 'User lives in Melbourne.',
        }),
      ),
    );
    addTearDown(repository.close);
    await expectLater(repository.loadFullFact(fact), throwsFormatException);
  });

  test(
    'rejects full fact responses for another node or non-memory content',
    () async {
      for (final invalid in [
        {'ok': true, 'kind': 'memory', 'id': 'wrong', 'content': 'Wrong fact'},
        {
          'ok': true,
          'kind': 'skill',
          'id': 'memory:profile:1:abcdef012345',
          'content': 'Skill',
        },
        {
          'ok': false,
          'kind': 'memory',
          'id': 'memory:profile:1:abcdef012345',
          'content': '',
        },
      ]) {
        final repository = MemoryRepository.fromConnection(
          _connection(),
          httpClient: MockClient((_) async => _json(invalid)),
        );
        addTearDown(repository.close);
        await expectLater(
          repository.loadFullFact(MemoryFact.parseGraph(_graph()).last),
          throwsFormatException,
        );
      }
    },
  );
}
