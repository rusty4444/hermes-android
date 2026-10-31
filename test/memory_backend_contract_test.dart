import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/memory_fact.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/memory_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/memory/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'same-prefix legacy IDs cannot substitute another fact or issue a detail GET',
    () async {
      final original = MemoryFact.parseGraph(_fixture('legacy_graph')).first;
      final shifted = _fixture('shifted_legacy_detail');
      expect(original.id, 'memory:profile:0');
      expect(shifted['content'], startsWith(original.content));
      expect(shifted['content'], endsWith('UNIQUE_SECOND_FACT'));
      var requests = 0;
      final repository = MemoryRepository.fromConnection(
        SavedConnection(
          id: 'legacy',
          label: 'Legacy',
          host: 'fixture',
          port: 8642,
          apiKey: '',
          dashboardProxied: true,
        ),
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(shifted), 200);
        }),
      );
      addTearDown(repository.close);
      await expectLater(
        repository.loadFullFact(original),
        throwsFormatException,
      );
      expect(requests, 0);
    },
  );

  test('real backend graph exposes every built-in fact, never skills', () {
    final graph = _fixture('graph');
    final facts = MemoryFact.parseGraph(graph);
    expect(facts.length, (graph['stats'] as Map)['memory_nodes']);
    expect(facts, hasLength(4));
    expect(
      facts
          .where((fact) => fact.source == MemoryFactSource.profile)
          .map((fact) => fact.content),
      ['User prefers concise replies.', 'User lives in Melbourne.'],
    );
    expect(
      facts.where((fact) => fact.source == MemoryFactSource.memory),
      hasLength(2),
    );
    expect(
      facts.map((fact) => fact.id),
      isNot(contains('fixture-contract-skill')),
    );
    expect(facts[2].id, 'memory:profile:2:ab20cb1374d6');
    expect(facts[3].id, 'memory:profile:3:58e7ee30d5d5');
  });

  test('real backend empty memory is empty even when a skill remains', () {
    final graph = _fixture('empty_graph');
    expect(graph['nodes'], isNotEmpty);
    expect(MemoryFact.parseGraph(graph), isEmpty);
  });

  test(
    'real graph preview and full-node response round trip through the client',
    () async {
      final graph = _fixture('graph');
      final detail = _fixture('long_fact');
      final requests = <String>[];
      final repository = MemoryRepository.fromConnection(
        SavedConnection(
          id: 'contract',
          label: 'Contract',
          host: 'fixture',
          port: 8642,
          apiKey: '',
          dashboardProxied: true,
          gatewayProfile: 'fixture-profile',
        ),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['profile'], 'fixture-profile');
          requests.add(request.url.path);
          if (request.url.path.endsWith('/node')) {
            expect(request.url.queryParameters['id'], detail['id']);
            return http.Response(jsonEncode(detail), 200);
          }
          return http.Response(jsonEncode(graph), 200);
        }),
      );
      addTearDown(repository.close);
      final facts = await repository.loadFacts();
      final fact = facts.singleWhere((fact) => fact.id == detail['id']);
      expect(fact.mayBeTruncated, isTrue);
      expect(fact.content.runes.length, 1200);
      expect(fact.content, isNot(contains('END_ANDROID_MEMORY_FIXTURE')));
      final full = await repository.loadFullFact(fact);
      expect(full, startsWith(fact.content));
      expect(full, endsWith('END_ANDROID_MEMORY_FIXTURE'));
      expect(full.runes.length, greaterThan(fact.content.runes.length));
      expect(
        sha256.convert(utf8.encode(full.trim())).toString().substring(0, 12),
        fact.id.split(':').last,
      );
      expect(requests, ['/api/learning/graph', '/api/learning/node']);
    },
  );
}
