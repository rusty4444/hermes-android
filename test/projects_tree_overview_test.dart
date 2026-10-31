/// Contract tests for the `projects.tree` overview RPC.
///
/// Phase 0 of `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` specifies the Projects
/// layer as wrapping `projects.list/create/update/archive/delete/set_active/
/// tree/project_sessions`. `tree` was the last method of that family with no
/// Android reader, and it is the only one that answers the two questions the
/// Projects pane actually asks on entry:
///
/// - *what does each project contain* — repo/lane structure and counts, with
///   a few preview chats, without paying for every session row;
/// - *which chats are already claimed by a project* — `scoped_session_ids`,
///   the set the desktop excludes from its flat Recents list so a chat is
///   never shown twice.
///
/// `projects.list` cannot answer either: it returns the projects database
/// records only, so it knows nothing about chats. Deriving the grouping on
/// device instead is exactly the mistake the roadmap forbids — the server owns
/// it in `tui_gateway/project_tree.py`, and two implementations would disagree.
///
/// The payload mirrors that builder:
/// `{projects: [<project node>], active_id, scoped_session_ids: [...]}` where a
/// project node has the same shape the drill-in returns, except lanes carry no
/// session rows (`hydrate=False`) while every count is preserved.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
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

/// A preview session row, exactly as the overview emits it.
Map<String, dynamic> _sessionRow({
  String id = 's1',
  String title = 'Chat',
  double lastActive = 1750000900,
}) {
  return {
    'id': id,
    'title': title,
    'preview': 'Ran flutter analyze',
    'started_at': 1750000000,
    'ended_at': null,
    'last_active': lastActive,
    'source': 'cli',
    'message_count': 12,
    'model': 'claude-opus-5',
    // The Projects RPC hardcodes `is_active: false` on every row; project
    // rows ignore it, so liveness comes from the recency window.
    'is_active': false,
    'cwd': '/home/carlos/dev/hermes-android',
  };
}

/// An overview project node: lanes present, session rows emptied, counts kept.
Map<String, dynamic> _overviewNode({
  String id = 'p1',
  String label = 'Hermes Android',
  bool isAuto = false,
  bool isNoProject = false,
  int sessionCount = 7,
  List<String> sessionIds = const ['s1'],
  List<Map<String, dynamic>>? repos,
  List<Map<String, dynamic>>? previewSessions,
}) {
  return {
    'id': id,
    'label': label,
    'path': '/home/carlos/dev/hermes-android',
    'color': '#D4AF37',
    'icon': 'phone',
    'isAuto': isAuto,
    'isNoProject': isNoProject,
    'sessionCount': sessionCount,
    'lastActive': 1750000900,
    'totalTokens': 1500,
    'totalCostUsd': 0.004,
    // The real gateway emits every claimed id on the node itself, even
    // with hydrate=False (project_tree.py::_project_node).
    'sessionIds': sessionIds,
    'repos':
        repos ??
        [
          {
            'id': '/home/carlos/dev/hermes-android',
            'label': 'hermes-android',
            'path': '/home/carlos/dev/hermes-android',
            'sessionCount': 7,
            'groups': [
              {
                'id': '/home/carlos/dev/hermes-android::branch::main',
                'label': 'main',
                'path': '/home/carlos/dev/hermes-android',
                'isMain': true,
                'isKanban': false,
                // hydrate=False: the overview carries no rows here.
                'sessions': const [],
              },
            ],
          },
        ],
    'previewSessions': previewSessions ?? [_sessionRow()],
  };
}

void main() {
  group('ProjectsTreeOverview.fromJson', () {
    test('keeps counts even though the overview carries no session rows', () {
      // The whole point of the overview tier: a project card must be able to
      // say "7 chats" without the server shipping 7 rows. If the count were
      // derived from the (empty) lanes, every card would read zero.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [_overviewNode()],
        'active_id': 'p1',
        'scoped_session_ids': const ['s1', 's2'],
      });

      final project = overview.projects.single;
      expect(project.sessionCount, 7);
      expect(project.repos.single.sessionCount, 7);
      expect(project.repos.single.lanes.single.sessions, isEmpty);
      expect(project.repos.single.lanes.single.isMain, isTrue);
    });

    test('preserves the previews the overview does ship', () {
      // `previewSessions` is the only place the overview carries real chats,
      // so a card that shows recent activity depends entirely on it.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [
          _overviewNode(
            previewSessions: [
              _sessionRow(id: 'a', title: 'First'),
              _sessionRow(id: 'b', title: 'Second'),
            ],
          ),
        ],
      });

      expect(overview.projects.single.previewSessions.map((s) => s.title), [
        'First',
        'Second',
      ]);
    });

    test(
      'preview rows ignore the is_active placeholder and use the recency window',
      () {
        final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final overview = ProjectsTreeOverview.fromJson({
          'projects': [
            _overviewNode(
              previewSessions: [
                _sessionRow(id: 'fresh', lastActive: nowSeconds - 30),
                _sessionRow(id: 'stale', lastActive: nowSeconds - 172800),
              ],
            ),
          ],
        });

        final sessions = overview.projects.single.previewSessions;
        // The real wire shape (`is_active: false` on every row) must not
        // mask a fresh/in-flight session as Done — the recency window
        // decides.
        expect(sessions.firstWhere((s) => s.id == 'fresh').isActive, isTrue);
        expect(sessions.firstWhere((s) => s.id == 'stale').isActive, isFalse);
      },
    );

    test('distinguishes explicit, auto and Home projects', () {
      // A user-created project can be renamed, archived and deleted. A
      // discovered repo and the synthetic Home bucket cannot — they have no
      // record in the projects database, so offering those actions would
      // produce a server error the user cannot act on.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [
          _overviewNode(id: '__no_project__', label: 'Home', isNoProject: true),
          _overviewNode(id: 'p1'),
          _overviewNode(id: '/home/carlos/dev/scripthive', isAuto: true),
        ],
      });

      expect(overview.projects.map((p) => p.isNoProject), [true, false, false]);
      expect(overview.projects.map((p) => p.isAuto), [false, false, true]);
      expect(overview.userProjects.map((p) => p.id), ['p1']);
    });

    test('carries the totals the server already summed', () {
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [_overviewNode()],
      });

      expect(overview.projects.single.totalTokens, 1500);
      expect(overview.projects.single.totalCostUsd, closeTo(0.004, 1e-9));
    });

    test('reads an empty profile as an empty overview, not a failure', () {
      // The server answers this for a profile with no projects database at
      // all. It is the designed "no projects yet" state, not an error.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': const [],
        'active_id': null,
        'scoped_session_ids': const [],
      });

      expect(overview.projects, isEmpty);
      expect(overview.activeId, isNull);
      expect(overview.scopedSessionIds, isEmpty);
      expect(overview.isEmpty, isTrue);
    });

    test('drops one malformed node instead of blanking the whole pane', () {
      // A single id-less node could only ever be a dead card. Letting it throw
      // would take down every other project with it, which is a far worse
      // failure than one missing row.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [
          const {'label': 'No id here'},
          _overviewNode(id: 'p1'),
        ],
      });

      expect(overview.projects.map((p) => p.id), ['p1']);
    });

    test('ignores an active_id naming no listed project', () {
      // Matches ProjectsSnapshot: a dangling selection would highlight a card
      // that is not on screen, or none at all while claiming one is active.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [_overviewNode(id: 'p1')],
        'active_id': 'p-deleted',
      });

      expect(overview.activeId, isNull);
      expect(overview.activeProject, isNull);
    });

    test('resolves the active project when the id does match', () {
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [_overviewNode(id: 'p1'), _overviewNode(id: 'p2')],
        'active_id': 'p2',
      });

      expect(overview.activeId, 'p2');
      expect(overview.activeProject?.id, 'p2');
    });

    test('cleans scoped session ids without reordering them', () {
      // These ids exist to be subtracted from a flat chat list. A blank or
      // duplicated entry would either match nothing or hide a chat twice;
      // server order is kept because nothing on device may re-rank it.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': const [],
        'scoped_session_ids': const ['s2', '  ', 's1', 's2', 42, ' s3 '],
      });

      expect(overview.scopedSessionIds, ['s2', 's1', 's3']);
      expect(overview.claimsSession('s1'), isTrue);
      expect(overview.claimsSession('s9'), isFalse);
    });

    test('treats a missing scoped list as claiming nothing', () {
      // An older or partial payload must not make every chat look claimed —
      // that would empty the unfiled view rather than degrade it.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [_overviewNode()],
      });

      expect(overview.scopedSessionIds, isEmpty);
      expect(overview.claimsSession('s1'), isFalse);
    });

    test('placement map names the owner of every claimed chat', () {
      // The row label bug this pins: labels built from previewSessions only
      // covered the top-N window, so a correctly-filed chat rendered as
      // "Unassigned". The map must derive from each node's full
      // `sessionIds` — the ONLY per-chat ownership the wire carries —
      // never from a top-level map the gateway does not emit.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [
          _overviewNode(
            id: 'p1',
            label: 'Email Assistant',
            sessionIds: const ['s1'],
          ),
          _overviewNode(
            id: '__no_project__',
            isNoProject: true,
            sessionIds: const ['s2'],
          ),
        ],
        'scoped_session_ids': const ['s1', 's2'],
      });

      expect(overview.sessionProjects['s1'], 'p1');
      expect(overview.ownerLabelOf('s1'), 'Email Assistant');
      // Home is not a filing: an unfiled chat stays unlabeled ("Unassigned").
      expect(overview.ownerLabelOf('s2'), isNull);
      expect(overview.ownerLabelOf('s9'), isNull);
    });

    test('a node with no sessionIds contributes no labels, not failure', () {
      // An older backend may omit the per-node `sessionIds`; parsing must
      // yield an empty placement map so labels fall back, never throw.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [_overviewNode()],
        'scoped_session_ids': const ['s1'],
      });
      // The default helper node carries s1; rebuild without any sessionIds.
      final bare = ProjectsTreeOverview.fromJson({
        'projects': [
          _overviewNode()..remove('sessionIds'),
        ],
        'scoped_session_ids': const ['s1'],
      });

      expect(overview.sessionProjects['s1'], 'p1');
      expect(bare.sessionProjects, isEmpty);
      expect(bare.claimsSession('s1'), isTrue);
      expect(bare.ownerLabelOf('s1'), isNull);
    });

    test('preserves server order across every tier', () {
      // The server emits Home first, then explicit projects, then auto ones.
      // Re-sorting on device would make Android rank projects differently
      // from Desktop for the same account.
      final overview = ProjectsTreeOverview.fromJson({
        'projects': [
          _overviewNode(id: '__no_project__', isNoProject: true),
          _overviewNode(id: 'p9'),
          _overviewNode(id: 'p2'),
          _overviewNode(id: '/repo', isAuto: true),
        ],
      });

      expect(overview.projects.map((p) => p.id), [
        '__no_project__',
        'p9',
        'p2',
        '/repo',
      ]);
    });
  });

  group('ProjectsGatewayClient.tree', () {
    test('calls projects.tree and parses the overview', () async {
      final rpc = _RecordingRpc([
        _ok({
          'projects': [_overviewNode()],
          'active_id': 'p1',
          'scoped_session_ids': const ['s1'],
        }),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      final overview = await client.tree();

      expect(rpc.calls.single.method, 'projects.tree');
      expect(overview.projects.single.label, 'Hermes Android');
      expect(overview.activeId, 'p1');
      expect(overview.scopedSessionIds, ['s1']);
    });

    test('sends no limits unless the caller asked for them', () async {
      // The server defaults preview_limit to 3 and session_limit to 2000.
      // Echoing those from the client would freeze them into the app and
      // silently override a future server default.
      final rpc = _RecordingRpc([
        _ok({'projects': const []}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      await client.tree();

      expect(rpc.calls.single.params, isEmpty);
    });

    test('forwards the limits it was given', () async {
      final rpc = _RecordingRpc([
        _ok({'projects': const []}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      await client.tree(previewLimit: 5, sessionLimit: 400);

      expect(rpc.calls.single.params, {
        'preview_limit': 5,
        'session_limit': 400,
      });
    });

    test('a missing projects.tree never disowns the projects family', () async {
      // Same guard the drill-in already carries, asserted independently: a
      // gateway that serves `projects.list` but predates the overview must
      // keep its server projects rather than dropping the pane into
      // device-local compatibility mode — permanently, since verdicts cache.
      final registry = CapabilityRegistry();
      final rpc = _RecordingRpc([
        _ok({'projects': const [], 'active_id': null}),
        _error(-32601, 'unknown method: projects.tree'),
      ]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await client.list();
      await expectLater(
        client.tree(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );

      expect(client.cachedSupport, isTrue);
      expect(registry.supportFor('projects.list'), CapabilitySupport.supported);
      expect(
        registry.supportFor('projects.tree'),
        CapabilitySupport.unsupported,
      );
    });

    test('spends no request once projects.tree is known missing', () async {
      // The registry already proved it absent; calling again would cost a
      // round trip on every pane build for an answer that cannot change
      // without a reconnect.
      final registry = CapabilityRegistry();
      final rpc = _RecordingRpc([
        _error(-32601, 'unknown method: projects.tree'),
      ]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await expectLater(
        client.tree(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );
      await expectLater(
        client.tree(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );

      expect(rpc.calls, hasLength(1));
    });

    test('surfaces a real tree error as a JSON-RPC error', () async {
      // 5061 means the server ran the builder and it failed. Reading that as
      // "old gateway" would hide server projects behind compatibility mode.
      final rpc = _RecordingRpc([_error(5061, 'projects db locked')]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(client.tree(), throwsA(isA<JsonRpcError>()));
      expect(client.cachedSupport, isTrue);
    });
  });
}
