import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> row(int index, {bool pinned = false}) => {
  'id': 'archive-$index',
  'title': 'Archived chat $index',
  'source': 'gateway',
  'archived': true,
  'pinned': pinned,
  'message_count': 2,
  'started_at': 1700000000 - index,
};

http.Response page(int offset, int limit, int total) => http.Response(
  jsonEncode({
    'sessions': [
      for (var i = offset; i < offset + limit && i < total; i++) row(i),
    ],
    'total': total,
  }),
  200,
);

void main() {
  for (final total in [0, 1, 3]) {
    test(
      'underreported total=$total cannot truncate archived rows (#207 L2)',
      () async {
        final offsets = <int>[];
        final client = DashboardClient(
          host: 'dashboard.invalid',
          proxied: true,
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/sessions');
            expect(request.url.queryParameters['archived'], 'only');
            expect(request.url.queryParameters['order'], 'recent');
            expect(request.url.queryParameters['profile'], 'work/exact');
            final offset = int.parse(request.url.queryParameters['offset']!);
            final limit = int.parse(request.url.queryParameters['limit']!);
            offsets.add(offset);
            return http.Response(
              jsonEncode({
                'sessions': [
                  for (var i = offset; i < offset + limit && i < 6; i++) row(i),
                ],
                'total': total,
              }),
              200,
            );
          }),
        );
        addTearDown(client.close);
        final all = await client.getArchivedSessions(
          firstPageSize: 1,
          pageSize: 2,
          gatewayProfile: 'work/exact',
        );
        expect(all.map((s) => s.id), [
          for (var i = 0; i < 6; i++) 'archive-$i',
        ]);
        expect(offsets, [0, 1, 3, 5, 7]);
      },
    );
  }

  test(
    'archive emits five before a held older page and supports thousands',
    () async {
      final later = Completer<http.Response>();
      final requested = <Uri>[];
      final progress = <List<Session>>[];
      final client = DashboardClient(
        host: 'dashboard.invalid',
        proxied: true,
        httpClient: MockClient((request) async {
          requested.add(request.url);
          expect(request.url.queryParameters['archived'], 'only');
          expect(request.url.queryParameters['profile'], 'work');
          final offset = int.parse(request.url.queryParameters['offset']!);
          final limit = int.parse(request.url.queryParameters['limit']!);
          if (offset == 5) return later.future;
          return page(offset, limit, 2506);
        }),
      );
      addTearDown(client.close);
      final result = client.getArchivedSessions(
        firstPageSize: 5,
        gatewayProfile: 'work',
        onProgress: progress.add,
      );
      // Let the first request complete without releasing the second.
      await Future<void>.delayed(Duration.zero);
      expect(requested.first.queryParameters['limit'], '5');
      expect(progress.single, hasLength(5));
      expect(requested.last.queryParameters['offset'], '5');
      later.complete(page(5, 100, 2506));
      final all = await result;
      expect(all, hasLength(2506));
      expect(all.map((s) => s.id).toSet(), hasLength(2506));
      expect(all.last.id, 'archive-2505');
      expect(progress.first, hasLength(5), reason: 'immutable snapshots');
      expect(progress.last, hasLength(2506));
    },
  );

  test('a later archive failure retains the emitted first five', () async {
    final progress = <List<Session>>[];
    final client = DashboardClient(
      host: 'dashboard.invalid',
      proxied: true,
      httpClient: MockClient((request) async {
        if (request.url.queryParameters['offset'] == '0') {
          return page(0, 5, 1000);
        }
        return http.Response('unavailable', 503);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.getArchivedSessions(firstPageSize: 5, onProgress: progress.add),
      throwsA(isA<DashboardHttpException>()),
    );
    expect(progress.single, hasLength(5));
  });

  test(
    'cancelled archive read ignores late response and stops paging',
    () async {
      var active = true;
      var requests = 0;
      final response = Completer<http.Response>();
      final progress = <List<Session>>[];
      final client = DashboardClient(
        host: 'dashboard.invalid',
        proxied: true,
        httpClient: MockClient((_) async {
          requests++;
          return response.future;
        }),
      );
      addTearDown(client.close);
      final read = client.getArchivedSessions(
        firstPageSize: 5,
        onProgress: progress.add,
        shouldContinue: () => active,
      );
      final assertion = expectLater(read, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      active = false;
      response.complete(page(0, 5, 1000));
      await assertion;
      expect(progress, isEmpty);
      expect(requests, 1);
    },
  );

  test('variable first page preserves pin-only-window fallback', () async {
    final offsets = <int>[];
    final client = DashboardClient(
      host: 'dashboard.invalid',
      proxied: true,
      httpClient: MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset']!);
        final limit = int.parse(request.url.queryParameters['limit']!);
        offsets.add(offset);
        final pins = [for (var i = 1; i <= 3; i++) row(i, pinned: true)];
        final rows = [
          for (var i = offset; i < offset + limit && i < 6; i++) row(i),
        ];
        return http.Response(
          jsonEncode({
            'sessions': [
              ...rows,
              ...pins.where((pin) => !rows.any((r) => r['id'] == pin['id'])),
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final all = await client.getArchivedSessions(firstPageSize: 1, pageSize: 2);
    expect(offsets, contains(3));
    expect(all.map((s) => s.id).toSet(), hasLength(6));
  });
}
