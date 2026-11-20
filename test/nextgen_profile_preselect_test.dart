import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DashboardApiClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  String? profile,
}) => DashboardApiClient.fromConnection(
  SavedConnection(
    id: 'fixture',
    label: 'fixture',
    host: 'fixture.test',
    port: 443,
    apiKey: 'unused-fixture',
    dashboardProxied: true,
    gatewayProfile: profile,
  ),
  httpClient: MockClient(handler),
);

void main() {
  group('profileOwningAllChats', () {
    test('picks the only non-default profile that has chats', () {
      expect(profileOwningAllChats({'default': 0, 'delta': 5}), 'delta');
      expect(profileOwningAllChats({'delta': 2}), 'delta');
    });

    test('leaves the server default alone when it is ambiguous', () {
      expect(profileOwningAllChats({'default': 3, 'delta': 5}), isNull);
      expect(profileOwningAllChats({'default': 4}), isNull);
      expect(profileOwningAllChats({'a': 1, 'b': 1}), isNull);
      expect(profileOwningAllChats({}), isNull);
    });
  });

  group('DashboardApiClient.profileSessionCounts', () {
    test('reads profile_totals from the all-profiles list', () async {
      final requests = <Uri>[];
      final client = clientFor((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'sessions': [],
            'total': 5,
            'profile_totals': {'default': 0, 'delta': 5},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }, profile: 'delta');
      final counts = await client.profileSessionCounts();
      expect(counts, {'default': 0, 'delta': 5});
      expect(requests.single.path, '/api/profiles/sessions');
      // Whatever profile the connection has, this call spans all of them.
      expect(requests.single.queryParameters.containsKey('profile'), isFalse);
      expect(requests.single.queryParameters['limit'], '1');
    });

    test('an odd response yields no counts', () async {
      final client = clientFor(
        (_) async => http.Response(
          jsonEncode({'profile_totals': 'nope'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(await client.profileSessionCounts(), isEmpty);
    });

    test('a refusal propagates', () async {
      final client = clientFor((_) async => http.Response('{}', 404));
      expect(
        client.profileSessionCounts(),
        throwsA(isA<DashboardRequestException>()),
      );
    });
  });

  group('profileHoldingVisibleChats', () {
    test('picks the one other profile when default shows no chats', () {
      expect(profileHoldingVisibleChats({'default': 0, 'delta': 26}), 'delta');
    });

    test('keeps the server default when it is unclear', () {
      expect(profileHoldingVisibleChats({'default': 3, 'delta': 26}), isNull);
      expect(
        profileHoldingVisibleChats({'default': 0, 'a': 1, 'b': 2}),
        isNull,
      );
      expect(profileHoldingVisibleChats({'default': 0, 'delta': 0}), isNull);
    });
  });

  group('DashboardApiClient authenticated profiles', () {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

    test('listProfiles reads the names from /api/profiles', () async {
      final client = clientFor((request) async {
        expect(request.url.path, '/api/profiles');
        return json({
          'profiles': [
            {'name': 'default', 'is_default': true},
            {'name': 'delta'},
          ],
        });
      });
      expect(await client.listProfiles(), ['default', 'delta']);
    });

    test(
      'visibleChatCounts ignores cron rows, as the NextGen list does',
      () async {
        final client = clientFor((request) async {
          expect(request.url.path, '/api/sessions');
          final cron = {'id': 'x', 'source': 'cron', 'title': 'run'};
          return json({
            'sessions': request.url.queryParameters['profile'] == 'delta'
                ? [
                    {'id': 'a', 'source': 'cli', 'title': 'hi'},
                    {'id': 'b', 'source': 'cli', 'title': 'yo'},
                  ]
                : [cron, cron],
          });
        });
        final counts = await client.visibleChatCounts(['default', 'delta']);
        expect(counts, {'default': 0, 'delta': 2});
        expect(profileHoldingVisibleChats(counts), 'delta');
      },
    );
  });
}
