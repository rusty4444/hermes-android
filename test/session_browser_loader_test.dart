import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/session_browser_loader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _row(int id, {bool archived = false}) => {
  'id': 's-$id',
  'title': 'Run $id',
  'source': 'cron',
  'started_at': id,
  'ended_at': id + 1,
  'archived': archived,
};

http.Response _page(List<Map<String, Object?>> rows) =>
    http.Response(jsonEncode({'data': rows, 'has_more': false}), 200);

ApiClient _api(http.Client client) => ApiClient(
  baseUrl: 'https://example.invalid',
  apiKey: 'test-key',
  httpClient: client,
);

void main() {
  test(
    'the source partition also recognises legacy cron IDs and compressed roots',
    () {
      Session session(String id, String source, {String? root}) =>
          Session.fromJson({
            'id': id,
            'source': source,
            '_lineage_root_id': root,
          });
      final rows = [
        session('ordinary', 'gateway'),
        session('arbitrary-run-id', 'cron'),
        session('cron_job-1_20261024_123456', ''),
        session(
          'compressed-tip',
          'gateway',
          root: 'cron_legacy.name_20261024_123456',
        ),
        session('cron_not-a-real-scheduler-id', 'gateway'),
        session('worker', 'kanban'),
        session('one-shot', 'oneshot'),
      ];
      expect(rows.where(isCronSession).map((row) => row.id), [
        'arbitrary-run-id',
        'cron_job-1_20261024_123456',
        'compressed-tip',
      ]);
      for (final filter in WorkspaceChatsFilter.values) {
        final human = filterChats(
          sessions: rows,
          filter: filter,
          query: 'cron',
        );
        expect(human.any(isCronSession), isFalse, reason: filter.name);
        final crons = filterChats(
          sessions: rows,
          filter: filter,
          kind: WorkspaceSessionKind.crons,
        );
        expect(crons.every(isCronSession), isTrue, reason: filter.name);
      }
      for (final view in WorkspaceSessionView.values) {
        expect(
          filterWorkspaceSessions(
            sessions: rows,
            view: view,
          ).any(isCronSession),
          isFalse,
        );
      }
    },
  );

  test(
    'live history continues beyond the old twenty-page cap despite false has_more',
    () async {
      final offsets = <int>[];
      final loader = SessionBrowserLoader(
        api: _api(
          MockClient((request) async {
            final limit = int.parse(request.url.queryParameters['limit']!);
            final offset = int.parse(request.url.queryParameters['offset']!);
            offsets.add(offset);
            return _page([
              for (var id = offset; id < offset + limit && id < 2101; id++)
                _row(id),
            ]);
          }),
        ),
        loadPins: () async => [],
      );
      addTearDown(loader.close);
      final sessions = await loader.load();
      expect(sessions, hasLength(2101));
      expect(sessions.last.id, 's-2100');
      expect(offsets, containsAllInOrder([1900, 2000, 2100, 2200]));
      expect(sessions.every((row) => row.endedAt != null), isTrue);
    },
  );

  test(
    'late subscribers share a scan and receive its cumulative progress',
    () async {
      final held = Completer<http.Response>();
      var previews = 0;
      final loader = SessionBrowserLoader(
        api: _api(
          MockClient((request) async {
            if (request.url.queryParameters['limit'] == '5') {
              previews++;
              return _page([_row(0)]);
            }
            if (request.url.queryParameters['offset'] == '0') {
              return held.future;
            }
            return _page([]);
          }),
        ),
        loadPins: () async => [],
      );
      addTearDown(loader.close);
      final firstProgress = Completer<void>();
      final first = loader.load(
        onProgress: (_) {
          if (!firstProgress.isCompleted) firstProgress.complete();
        },
      );
      await firstProgress.future;
      final received = <List<Session>>[];
      final second = loader.load(onProgress: received.add);
      expect(received.single.single.id, 's-0');
      held.complete(_page([_row(0), _row(1)]));
      expect(await first, hasLength(2));
      expect(await second, hasLength(2));
      expect(previews, 1);
      await loader.load();
      expect(
        previews,
        2,
        reason: 'settled scans must never be a permanent cache',
      );
    },
  );

  test(
    'a failed later page retains progress and permits a fresh retry',
    () async {
      var fail = true;
      final progress = <List<Session>>[];
      final loader = SessionBrowserLoader(
        api: _api(
          MockClient((request) async {
            if (request.url.queryParameters['limit'] == '5') {
              return _page([_row(0)]);
            }
            if (fail) return http.Response('offline', 503);
            if (request.url.queryParameters['offset'] == '0') {
              return _page([_row(0), _row(1)]);
            }
            return _page([]);
          }),
        ),
        loadPins: () async => [],
      );
      addTearDown(loader.close);
      await expectLater(loader.load(onProgress: progress.add), throwsException);
      expect(progress.single.single.id, 's-0');
      fail = false;
      expect(await loader.load(), hasLength(2));
    },
  );

  test(
    'disposal stops a held active scan before it can fetch another page',
    () async {
      final held = Completer<http.Response>();
      final entered = Completer<void>();
      var requests = 0;
      final loader = SessionBrowserLoader(
        api: _api(
          MockClient((request) async {
            requests++;
            if (request.url.queryParameters['limit'] == '5') {
              return _page([_row(0)]);
            }
            entered.complete();
            return held.future;
          }),
        ),
        loadPins: () async => [],
      );
      final pending = loader.load();
      final rejected = expectLater(pending, throwsStateError);
      await entered.future;
      loader.close();
      held.complete(_page(List.generate(100, _row)));
      await rejected;
      expect(requests, 2);
    },
  );

  test(
    'progressive archives cover more than twenty pages with profile and prefix intact',
    () async {
      final snapshots = <int>[];
      final client = DashboardClient(
        host: 'example.invalid',
        port: 9443,
        useHttps: true,
        pathPrefix: '/hermes',
        proxied: true,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/hermes/api/sessions');
          expect(request.url.port, 9443);
          expect(request.url.scheme, 'https');
          expect(request.url.queryParameters['profile'], 'work');
          expect(request.url.queryParameters['archived'], 'only');
          final offset = int.parse(request.url.queryParameters['offset']!);
          return http.Response(
            jsonEncode({
              'sessions': [
                for (var id = offset; id < offset + 100 && id < 2101; id++)
                  _row(id, archived: true),
              ],
              'total': 2101,
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final rows = await client.getArchivedSessions(
        maxPages: null,
        gatewayProfile: 'work',
        onProgress: (rows) => snapshots.add(rows.length),
      );
      expect(rows, hasLength(2101));
      expect(snapshots.first, 100);
      expect(snapshots.last, 2101);
      expect(snapshots, hasLength(22));
    },
  );
}
