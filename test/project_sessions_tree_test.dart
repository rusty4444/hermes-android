/// Contract tests for the `projects.project_sessions` drill-in RPC.
///
/// Phase 0 of `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` requires the Projects
/// layer to wrap the native `projects.*` family, including
/// `project_sessions` — the call that answers "which chats live in this
/// project", grouped the way the server already groups them (project → repo →
/// lane). Android must read that grouping rather than invent a second one, or
/// the phone and the desktop will disagree about where a chat belongs.
///
/// The payload shape mirrors `tui_gateway/project_tree.py`:
/// `{project: {id, label, path, sessionCount, lastActive, repos: [{id, label,
/// path, sessionCount, groups: [{id, label, path, isMain, isKanban,
/// sessions: [...]}]}], previewSessions: [...]}}`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/project_sessions_tree.dart';
import 'package:hermes_android/core/services/capability_registry.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';

class _RecordingRpc {
  final List<({String method, Map<String, dynamic> params})> calls = [];
  final List<Map<String, dynamic>> responses;

  _RecordingRpc(this.responses);

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add((method: method, params: params));
    if (responses.isEmpty) {
      throw StateError('no canned response for $method');
    }
    return responses.removeAt(0);
  }
}

Map<String, dynamic> _ok(Map<String, dynamic> result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};

Map<String, dynamic> _error(int code, String message) => {
  'jsonrpc': '2.0',
  'id': 1,
  'error': {'code': code, 'message': message},
};

/// One session row exactly as `_project_tree_row` emits it.
Map<String, dynamic> _sessionRow({
  String id = 's1',
  String title = 'Wire the Projects pane',
  double startedAt = 1750000000,
  double lastActive = 1750000900,
  double? endedAt,
  int messageCount = 12,
  bool isActive = false,
}) {
  return {
    'id': id,
    'parent_session_id': null,
    'title': title,
    'preview': 'Ran flutter analyze',
    'started_at': startedAt,
    'ended_at': endedAt,
    'last_active': lastActive,
    'source': 'cli',
    'archived': false,
    'message_count': messageCount,
    'tool_call_count': 4,
    'input_tokens': 1200,
    'output_tokens': 300,
    'actual_cost_usd': null,
    'estimated_cost_usd': 0.004,
    'model': 'claude-opus-5',
    // The Projects RPC hardcodes `is_active: false` on every row (placeholder);
    // project rows ignore it, so liveness comes from the recency window.
    'is_active': isActive,
    'cwd': '/home/carlos/dev/hermes-android',
    'git_branch': 'main',
    'git_repo_root': '/home/carlos/dev/hermes-android',
  };
}

Map<String, dynamic> _projectNode({
  String id = 'p1',
  List<Map<String, dynamic>>? repos,
  List<Map<String, dynamic>>? previewSessions,
  int sessionCount = 2,
}) {
  return {
    'id': id,
    'label': 'Hermes Android',
    'path': '/home/carlos/dev/hermes-android',
    'color': '#D4AF37',
    'icon': 'phone',
    'isAuto': false,
    'isNoProject': false,
    'sessionCount': sessionCount,
    'lastActive': 1750000900,
    'totalTokens': 1500,
    'totalCostUsd': 0.004,
    'repos':
        repos ??
        [
          {
            'id': '/home/carlos/dev/hermes-android',
            'label': 'hermes-android',
            'path': '/home/carlos/dev/hermes-android',
            'sessionCount': 2,
            'groups': [
              {
                'id': 'main',
                'label': 'main',
                'path': '/home/carlos/dev/hermes-android',
                'isMain': true,
                'isKanban': false,
                'sessions': [
                  // Recent activity keeps this row live through the recency
                  // window; the fixed `is_active: false` placeholder is ignored.
                  _sessionRow(
                    lastActive:
                        DateTime.now().millisecondsSinceEpoch / 1000.0 - 30,
                  ),
                  _sessionRow(
                    id: 's2',
                    title: 'Activity timeline',
                    lastActive: 1749999000,
                    endedAt: 1749999500,
                  ),
                ],
              },
            ],
          },
        ],
    'previewSessions': previewSessions ?? [_sessionRow()],
  };
}

void main() {
  group('ProjectSessionsTree', () {
    test('parses the server project → repo → lane grouping', () {
      final tree = ProjectSessionsTree.fromJson(_projectNode());

      expect(tree.id, 'p1');
      expect(tree.label, 'Hermes Android');
      expect(tree.path, '/home/carlos/dev/hermes-android');
      expect(tree.sessionCount, 2);
      expect(tree.lastActive, 1750000900);

      expect(tree.repos, hasLength(1));
      final repo = tree.repos.single;
      expect(repo.id, '/home/carlos/dev/hermes-android');
      expect(repo.label, 'hermes-android');
      expect(repo.sessionCount, 2);

      expect(repo.lanes, hasLength(1));
      final lane = repo.lanes.single;
      expect(lane.id, 'main');
      expect(lane.label, 'main');
      expect(lane.isMain, isTrue);
      expect(lane.isKanban, isFalse);
      expect(lane.sessions.map((s) => s.id), ['s1', 's2']);
      // Rows are the same Session records the chat list already renders, so a
      // project chat opens through the existing route with no second model.
      expect(lane.sessions.first.title, 'Wire the Projects pane');
      expect(lane.sessions.first.model, 'claude-opus-5');
      expect(lane.sessions.first.messageCount, 12);
      expect(lane.sessions.first.isActive, isTrue);
      expect(lane.sessions.last.isActive, isFalse);
    });

    test(
      'project rows ignore the is_active placeholder and use the recency window',
      () {
        final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final tree = ProjectSessionsTree.fromJson(
          _projectNode(
            repos: [
              {
                'id': '/home/carlos/dev/hermes-android',
                'label': 'hermes-android',
                'path': '/home/carlos/dev/hermes-android',
                'sessionCount': 2,
                'groups': [
                  {
                    'id': 'main',
                    'label': 'main',
                    'path': '/home/carlos/dev/hermes-android',
                    'isMain': true,
                    'isKanban': false,
                    'sessions': [
                      _sessionRow(id: 'fresh', lastActive: nowSeconds - 30),
                      _sessionRow(id: 'stale', lastActive: nowSeconds - 172800),
                    ],
                  },
                ],
              },
            ],
          ),
        );

        final fresh = tree.allSessions.firstWhere((s) => s.id == 'fresh');
        final stale = tree.allSessions.firstWhere((s) => s.id == 'stale');
        // The real wire shape (`is_active: false` on every row) must not mask
        // a fresh/in-flight session as Done — the recency window decides.
        expect(fresh.isActive, isTrue);
        expect(stale.isActive, isFalse);
      },
    );

    test('keeps a repo the server seeded with no lanes', () {
      // A brand-new project has declared folders but no sessions yet. The
      // server seeds those folders as empty repos on purpose; dropping them
      // here would render an entered project as a blank screen.
      final tree = ProjectSessionsTree.fromJson(
        _projectNode(
          sessionCount: 0,
          repos: [
            {
              'id': '/home/carlos/dev/new-thing',
              'label': 'new-thing',
              'path': '/home/carlos/dev/new-thing',
              'sessionCount': 0,
              'groups': const [],
            },
          ],
          previewSessions: const [],
        ),
      );

      expect(tree.repos, hasLength(1));
      expect(tree.repos.single.lanes, isEmpty);
      expect(tree.repos.single.sessionCount, 0);
      expect(tree.isEmpty, isTrue);
    });

    test('tolerates a sparse row rather than dropping the chat', () {
      // The gateway compacts rows; an older build may omit optional fields.
      // A project view that crashes on one thin row is worse than one that
      // shows the row with defaults.
      final tree = ProjectSessionsTree.fromJson(
        _projectNode(
          repos: [
            {
              'id': 'r1',
              'label': 'r1',
              'groups': [
                {
                  'id': 'lane',
                  'label': 'lane',
                  'sessions': [
                    {'id': 's9'},
                  ],
                },
              ],
            },
          ],
        ),
      );

      final lane = tree.repos.single.lanes.single;
      expect(lane.sessions.single.id, 's9');
      expect(lane.sessions.single.title, 'Untitled');
      expect(lane.isMain, isFalse);
      expect(lane.path, isNull);
      // No `sessionCount` key: fall back to the rows actually present rather
      // than reporting zero chats under a lane that has some.
      expect(tree.repos.single.sessionCount, 1);
    });

    test('flattens every lane into one server-ordered chat list', () {
      final tree = ProjectSessionsTree.fromJson(
        _projectNode(
          repos: [
            {
              'id': 'r1',
              'label': 'r1',
              'groups': [
                {
                  'id': 'main',
                  'label': 'main',
                  'sessions': [_sessionRow(id: 'a')],
                },
                {
                  'id': 'feature',
                  'label': 'feature',
                  'sessions': [
                    _sessionRow(id: 'b'),
                    // The same chat listed twice must not become two rows.
                    _sessionRow(id: 'a'),
                  ],
                },
              ],
            },
          ],
        ),
      );

      // Server order is authoritative: it already ranks trunk first and then
      // by recency. Re-sorting on device would make Android disagree with
      // Desktop about the same project.
      expect(tree.allSessions.map((s) => s.id), ['a', 'b']);
      expect(tree.isEmpty, isFalse);
    });

    test('drops a row with no usable id instead of inventing one', () {
      final tree = ProjectSessionsTree.fromJson(
        _projectNode(
          repos: [
            {
              'id': 'r1',
              'label': 'r1',
              'groups': [
                {
                  'id': 'main',
                  'label': 'main',
                  'sessions': [
                    {'title': 'ghost'},
                    _sessionRow(id: 'real'),
                  ],
                },
              ],
            },
          ],
        ),
      );

      expect(tree.allSessions.map((s) => s.id), ['real']);
    });

    test('falls back to the project id when the server sends no label', () {
      final tree = ProjectSessionsTree.fromJson({'id': 'p7'});

      expect(tree.label, 'p7');
      expect(tree.repos, isEmpty);
      expect(tree.previewSessions, isEmpty);
      expect(tree.sessionCount, 0);
      expect(tree.isEmpty, isTrue);
    });

    test('rejects a node without an identity', () {
      expect(
        () => ProjectSessionsTree.fromJson({'label': 'no id'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ProjectsGatewayClient.projectSessions', () {
    test('calls the native RPC with the project id', () async {
      final rpc = _RecordingRpc([
        _ok({'project': _projectNode()}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      final tree = await client.projectSessions('p1');

      expect(rpc.calls.single.method, 'projects.project_sessions');
      expect(rpc.calls.single.params, {'project_id': 'p1'});
      expect(tree?.allSessions.map((s) => s.id), ['s1', 's2']);
    });

    test('passes a session limit only when one is requested', () async {
      final rpc = _RecordingRpc([
        _ok({'project': _projectNode()}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      await client.projectSessions('p1', sessionLimit: 50);

      expect(rpc.calls.single.params, {
        'project_id': 'p1',
        'session_limit': 50,
      });
    });

    test('returns null when the gateway knows no such project', () async {
      // The server answers `{"project": null}` for an unknown id or a profile
      // with no database. That is an empty result, not an error: the caller
      // shows "this project has no chats yet", never a red failure screen.
      final rpc = _RecordingRpc([
        _ok(const {'project': null}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      expect(await client.projectSessions('p1'), isNull);
    });

    test('refuses a blank id without spending a request', () async {
      final rpc = _RecordingRpc([]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.projectSessions('  '),
        throwsA(isA<ArgumentError>()),
      );
      expect(rpc.calls, isEmpty);
    });

    test('reports an older gateway as unsupported, not as a failure', () async {
      final registry = CapabilityRegistry();
      final rpc = _RecordingRpc([
        _error(-32601, 'unknown method: projects.project_sessions'),
      ]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await expectLater(
        client.projectSessions('p1'),
        throwsA(isA<ProjectsUnsupportedException>()),
      );
      expect(
        registry.supportFor('projects.project_sessions'),
        CapabilitySupport.unsupported,
      );
    });

    test('surfaces a real project error as a JSON-RPC error', () async {
      // 5063 means the server understood the call and rejected the arguments.
      // Reporting that as "unsupported gateway" would send the UI into
      // compatibility mode on a gateway that supports projects perfectly.
      final rpc = _RecordingRpc([_error(5063, 'project_id required')]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.projectSessions('p1'),
        throwsA(isA<JsonRpcError>()),
      );
      expect(client.cachedSupport, isTrue);
    });

    test(
      'a missing drill-in never disowns the whole projects family',
      () async {
        // A gateway can ship `projects.list` and predate
        // `projects.project_sessions`. Letting one missing sub-method flip the
        // family verdict would drop the entire Projects pane into compatibility
        // mode — losing server-owned projects the gateway serves perfectly —
        // and, worse, would keep it there: the verdict is cached, so no later
        // `projects.list` would be attempted to disprove it.
        final registry = CapabilityRegistry();
        final rpc = _RecordingRpc([
          _ok({'projects': const [], 'active_id': null}),
          _error(-32601, 'unknown method: projects.project_sessions'),
          _ok({'projects': const [], 'active_id': null}),
        ]);
        final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

        await client.list();
        await expectLater(
          client.projectSessions('p1'),
          throwsA(isA<ProjectsUnsupportedException>()),
        );

        // Only the drill-in is unavailable; the family still is.
        expect(client.cachedSupport, isTrue);
        expect(await client.isSupported(), isTrue);
        expect(
          registry.supportFor('projects.project_sessions'),
          CapabilitySupport.unsupported,
        );
        expect(
          registry.supportFor('projects.list'),
          CapabilitySupport.supported,
        );
      },
    );

    test('a missing projects.list still disowns the family', () async {
      // The inverse guard: the probe method genuinely defines the family, so
      // its absence must keep switching the app to local organization.
      final rpc = _RecordingRpc([_error(-32601, 'unknown method')]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.list(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );
      expect(client.cachedSupport, isFalse);
    });
  });
}
