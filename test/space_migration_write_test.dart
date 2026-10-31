import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The migration *write* path: turning the validated preview into real server
/// Projects.
///
/// Step 7 of Phase 0 (real Gateway smoke test on a device) gated this path and
/// has now passed: the preview rendered against a live gateway and reported
/// "1 space · 0 chats · 1 project to create" for a real local Space.
///
/// The contract these tests pin, in one line: **migration only ever creates
/// projects that are missing, and never destroys local state.** The local
/// Spaces store is the user's only record of their grouping until the server
/// carries it; deleting it on a partial migration would lose data that cannot
/// be reconstructed.

Map<String, dynamic> _projectJson({
  required String id,
  required String name,
  bool archived = false,
  List<Map<String, dynamic>>? folders,
}) => {
  'id': id,
  'slug': name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'archived': archived,
  'created_at': 1750000000,
  'folders': folders ??
      [
        {
          'path': '/home/test/${name.toLowerCase().replaceAll(' ', '-')}',
          'label': name,
          'is_primary': true,
          'added_at': 1750000001,
        },
      ],
};

class _FakeGateway {
  final List<String> calls = [];
  final List<Map<String, dynamic>> createParams = [];
  final List<Map<String, dynamic>> assignmentParams = [];
  List<Map<String, dynamic>> projects;
  String? activeId;

  /// Method name → error to throw the next time it is called.
  final Map<String, Object> failOn = {};

  /// When set, the nth `projects.create` fails as a transport error would.
  int? failCreateOnNth;
  int _creates = 0;

  /// Methods the gateway answers with a JSON-RPC "unknown method" error, the
  /// way a real legacy gateway reports a missing RPC family.
  final Set<String> unknownMethods = {};

  _FakeGateway({List<Map<String, dynamic>>? projects, this.activeId})
    : projects = projects ?? [];

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add(method);
    final failure = failOn.remove(method);
    if (failure != null) throw failure;
    if (unknownMethods.contains(method)) {
      return {
        'jsonrpc': '2.0',
        'id': 1,
        'error': {'code': -32601, 'message': 'Unknown method: $method'},
      };
    }

    switch (method) {
      case 'projects.list':
        return _ok({'projects': projects, 'active_id': activeId});
      case 'projects.create':
        _creates++;
        if (_creates == failCreateOnNth) {
          throw JsonRpcError(
            'projects.create',
            'Desktop gateway connection closed',
            reason: 'connection_closed',
          );
        }
        createParams.add(params);
        final created = _projectJson(
          id: 'srv-${projects.length + 1}',
          name: params['name'] as String,
        );
        projects = [...projects, created];
        if (params['use'] == true) activeId = created['id'] as String;
        return _ok({'project': created});
      case 'session.workspace.move':
        assignmentParams.add(Map<String, dynamic>.from(params));
        return _ok(const {'ok': true});
      case 'projects.set_active':
        activeId = params['id'] as String?;
        return _ok({'active_id': activeId});
      default:
        return _ok(const {});
    }
  }

  int get createCount =>
      calls.where((method) => method == 'projects.create').length;

  static Map<String, dynamic> _ok(Map<String, dynamic> result) => {
    'jsonrpc': '2.0',
    'id': 1,
    'result': result,
  };
}

ProjectsRepository _repository(_FakeGateway gateway, SharedPreferences prefs) =>
    ProjectsRepository(
      client: ProjectsGatewayClient(gateway.call),
      preferences: prefs,
      connectionId: 'gateway-a',
    );

/// Builds a local Spaces store holding [names], each with [chatsPerSpace] chats.
Future<ChatSpaceStore> _storeWith(
  SharedPreferences prefs,
  List<String> names, {
  int chatsPerSpace = 0,
}) async {
  final store = ChatSpaceStore(prefs, connectionId: 'gateway-a');
  var chatSeq = 0;
  for (final name in names) {
    final space = await store.createSpace(name);
    for (var i = 0; i < chatsPerSpace; i++) {
      await store.assignSession('chat-${chatSeq++}', space.id);
    }
  }
  return store;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('migrateSpaces', () {
    test('creates one project per unmatched space', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = await _storeWith(prefs, ['Alpha', 'Beta']);

      final result = await repo.migrateSpaces(await store.load());

      expect(result.createdProjects, 2);
      expect(gateway.createCount, 2);
      expect(
        gateway.createParams.map((p) => p['name']),
        containsAll(['Alpha', 'Beta']),
      );
      expect(
        repo.current.projects.map((p) => p.name),
        containsAll(['Alpha', 'Beta']),
      );
    });

    test(
      'skips a space the server already carries, by normalized name',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final gateway = _FakeGateway(
          projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
        );
        final repo = _repository(gateway, prefs);
        await repo.refresh();
        // Same project, different casing/spacing than the local Space.
        final store = await _storeWith(prefs, [
          '  hermes   android ',
          'New One',
        ]);

        final result = await repo.migrateSpaces(await store.load());

        expect(result.createdProjects, 1);
        expect(result.alreadyLinked, 1);
        expect(gateway.createParams.single['name'], 'New One');
      },
    );

    test('running it twice creates nothing the second time', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = await _storeWith(prefs, ['Alpha']);

      await repo.migrateSpaces(await store.load());
      final second = await repo.migrateSpaces(await store.load());

      expect(second.createdProjects, 0);
      expect(second.alreadyLinked, 1);
      expect(gateway.createCount, 1);
    });

    test('never steals the active project', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Existing')],
        activeId: 'p1',
      );
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = await _storeWith(prefs, ['Alpha']);

      await repo.migrateSpaces(await store.load());

      // Migrating is bookkeeping, not navigation: the user's active project
      // must survive it untouched.
      expect(repo.current.activeId, 'p1');
      expect(gateway.createParams.single['use'], isNot(true));
      expect(gateway.calls, isNot(contains('projects.set_active')));
    });

    test('a failure part-way keeps what already succeeded', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();
      // Fail the second create; the first must stay, the rest must be reported.
      gateway.failCreateOnNth = 2;
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = await _storeWith(prefs, ['Alpha', 'Beta', 'Gamma']);

      final result = await repo.migrateSpaces(await store.load());

      // Alpha and Gamma succeed, Beta is reported rather than silently lost.
      expect(result.createdProjects, 2);
      expect(result.failures.keys, contains('Beta'));
      expect(result.isComplete, isFalse);
      // The successful write survives the failure of its neighbour.
      expect(repo.current.projects.map((p) => p.name), contains('Alpha'));
    });

    test('leaves the local spaces store untouched', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = await _storeWith(prefs, ['Alpha'], chatsPerSpace: 3);

      await repo.migrateSpaces(await store.load());

      // The local store is the only record of the grouping until the server
      // can hold chat→project links. Migration must not clear it.
      final after = await store.load();
      expect(after.spaces.single.name, 'Alpha');
      expect(after.assignments.length, 3);
    });

    test(
      'links every local chat to its matched or created server Project',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final gateway = _FakeGateway(
          projects: [_projectJson(id: 'p-existing', name: 'Alpha')],
        );
        final repo = _repository(gateway, prefs);
        await repo.refresh();
        final store = await _storeWith(prefs, [
          'Alpha',
          'Beta',
        ], chatsPerSpace: 2);

        final result = await repo.migrateSpaces(await store.load());

        expect(result.createdProjects, 1);
        expect(result.linkedSessions, 4);
        expect(result.unlinkedSessions, 0);
        expect(result.isComplete, isTrue);
        expect(
          gateway.assignmentParams,
          containsAll([
            {'session_key': 'chat-0', 'cwd': '/home/test/alpha'},
            {'session_key': 'chat-1', 'cwd': '/home/test/alpha'},
            {'session_key': 'chat-2', 'cwd': '/home/test/beta'},
            {'session_key': 'chat-3', 'cwd': '/home/test/beta'},
          ]),
        );
      },
    );

    test(
      'a folderless target leaves its chats unlinked without disowning Projects',
      () async {
        // Stock filing is cwd-derived: a Project with no folder cannot
        // receive chats. They are reported unlinked (honest), the local
        // store stays intact, and the Projects family stays supported.
        final prefs = await SharedPreferences.getInstance();
        final gateway = _FakeGateway();
        gateway.unknownMethods.add('session.workspace.move');
        final repo = _repository(gateway, prefs);
        await repo.refresh();
        final store = await _storeWith(prefs, ['Alpha'], chatsPerSpace: 2);

        final result = await repo.migrateSpaces(await store.load());

        expect(result.createdProjects, 1);
        expect(result.linkedSessions, 0);
        expect(result.unlinkedSessions, 2);
        expect(result.isComplete, isFalse);
        expect(repo.current.support, ProjectsSupport.native);
      },
    );

    test('an empty plan performs no writes at all', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = ChatSpaceStore(prefs, connectionId: 'gateway-a');

      final result = await repo.migrateSpaces(await store.load());

      expect(result.createdProjects, 0);
      expect(result.isComplete, isTrue);
      expect(gateway.createCount, 0);
    });

    test('refuses to write against a gateway without projects.*', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway();
      gateway.unknownMethods.add('projects.list');
      final repo = _repository(gateway, prefs);
      await repo.refresh();
      final store = await _storeWith(prefs, ['Alpha']);

      // A legacy gateway must fail loudly here rather than silently no-op and
      // let the UI report a migration that never happened.
      final state = await store.load();
      expect(
        () => repo.migrateSpaces(state),
        throwsA(isA<ProjectsUnsupportedException>()),
      );
      expect(gateway.createCount, 0);
    });
  });
}
