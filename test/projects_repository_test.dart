import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:hermes_android/core/services/project_folder_provisioner.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _projectJson({
  required String id,
  required String name,
  String? slug,
  bool archived = false,
  String? primaryPath,
  List<Map<String, dynamic>>? folders,
}) => {
  'id': id,
  'slug': slug ?? name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'archived': archived,
  'created_at': 1750000000,
  'primary_path': ?primaryPath,
  'folders': folders ?? const [],
};

/// A scriptable stand-in for the gateway `projects.*` family.
class _FakeGateway {
  final List<String> calls = [];
  List<Map<String, dynamic>> projects;
  String? activeId;

  /// When set, the next call throws this instead of answering.
  Object? failNext;

  /// When set, every call to this method throws (models a missing sibling).
  String? failMethod;

  /// Params of every `session.workspace.move` the repo issued.
  final List<Map<String, dynamic>> workspaceMoves = [];

  _FakeGateway({List<Map<String, dynamic>>? projects, this.activeId})
    : projects = projects ?? [];

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add(method);
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    if (failMethod == method) {
      throw JsonRpcError(method, 'unknown method');
    }
    switch (method) {
      case 'projects.list':
        return _ok({'projects': projects, 'active_id': activeId});
      case 'projects.create':
        final created = _projectJson(
          id: 'srv-${projects.length + 1}',
          name: params['name'] as String,
        );
        projects = [...projects, created];
        if (params['use'] == true) activeId = created['id'] as String;
        return _ok({'project': created});
      case 'projects.add_folder':
        final target = projects.firstWhere((p) => p['id'] == params['id']);
        final updated = {
          ...target,
          'folders': [
            ...((target['folders'] as List?) ?? const []),
            {
              'path': params['path'],
              'label': params['label'],
              'is_primary': params['is_primary'] == true,
              'added_at': 1750000001,
            },
          ],
        };
        projects = [
          for (final p in projects)
            if (p['id'] == params['id']) updated else p,
        ];
        return _ok({'project': updated});
      case 'projects.update':
        projects = [
          for (final project in projects)
            if (project['id'] == params['id'])
              {...project, 'name': params['name']}
            else
              project,
        ];
        return _ok({
          'project': projects.firstWhere((p) => p['id'] == params['id']),
        });
      case 'projects.archive':
        projects = [
          for (final project in projects)
            if (project['id'] == params['id'])
              {...project, 'archived': params['restore'] != true}
            else
              project,
        ];
        return _ok({'projects': projects, 'active_id': activeId});
      case 'projects.delete':
        projects = [
          for (final project in projects)
            if (project['id'] != params['id']) project,
        ];
        if (activeId == params['id']) activeId = null;
        return _ok({'projects': projects, 'active_id': activeId});
      case 'projects.set_active':
        activeId = params['id'] as String?;
        return _ok({'active_id': activeId});
      case 'session.workspace.move':
        workspaceMoves.add(Map<String, dynamic>.from(params));
        return _ok({
          'cwd': params['cwd'],
          'branch': null,
          'git_repo_root': null,
        });
      default:
        return _ok(const {});
    }
  }

  static Map<String, dynamic> _ok(Map<String, dynamic> result) => {
    'jsonrpc': '2.0',
    'id': 1,
    'result': result,
  };
}

ProjectsRepository _repository(
  _FakeGateway gateway,
  SharedPreferences prefs, {
  String connectionId = 'gateway-a',
}) {
  return ProjectsRepository(
    client: ProjectsGatewayClient(gateway.call),
    preferences: prefs,
    connectionId: connectionId,
  );
}

JsonRpcError get _offline => JsonRpcError(
  'projects.list',
  'Desktop gateway connection closed',
  reason: 'connection_closed',
);

/// A provisioner that always hands back [path] without touching a network.
class _StubProvisioner implements ProjectFolderProvisioner {
  final String path;
  _StubProvisioner(this.path);

  @override
  Future<String?> provision(String slug) async => path;
}

/// A provisioner that records the slugs it was asked about and provisions
/// nothing (models "the host refused / nothing was free").
class _RecordingProvisioner implements ProjectFolderProvisioner {
  final List<String> slugs;
  _RecordingProvisioner(this.slugs);

  @override
  Future<String?> provision(String slug) async {
    slugs.add(slug);
    return null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('refresh', () {
    test('loads projects from the gateway and reports live data', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
        activeId: 'p1',
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());

      final view = await repo.refresh();

      expect(view.support, ProjectsSupport.native);
      expect(view.isStale, isFalse);
      expect(view.projects.single.name, 'Hermes Android');
      expect(view.activeId, 'p1');
    });

    test('excludes archived projects from the default listing', () async {
      final gateway = _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Live'),
          _projectJson(id: 'p2', name: 'Old', archived: true),
        ],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());

      final view = await repo.refresh();

      expect(view.projects.map((p) => p.id), ['p1']);
      expect(view.archived.map((p) => p.id), ['p2']);
    });

    test(
      'an old gateway degrades to compatibility mode, not an error',
      () async {
        final gateway = _FakeGateway()
          ..failNext = const ProjectsUnsupportedException(
            'projects.list',
            'unknown method',
          );
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );

        final view = await repo.refresh();

        expect(view.support, ProjectsSupport.unsupported);
        expect(view.projects, isEmpty);
        expect(view.error, isNull);
      },
    );
  });

  group('offline cache', () {
    test(
      'serves the last known projects when the gateway is unreachable',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final gateway = _FakeGateway(
          projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
          activeId: 'p1',
        );
        final repo = _repository(gateway, prefs);
        await repo.refresh();

        gateway.failNext = _offline;
        final view = await repo.refresh();

        expect(view.projects.single.name, 'Hermes Android');
        expect(view.isStale, isTrue);
        expect(view.error, isNotNull);
      },
    );

    test(
      'a fresh repository restores the cache before any network call',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final gateway = _FakeGateway(
          projects: [_projectJson(id: 'p1', name: 'Cached')],
        );
        await _repository(gateway, prefs).refresh();

        final restored = _repository(gateway, prefs);
        final view = await restored.loadCached();

        expect(view.projects.single.name, 'Cached');
        expect(view.isStale, isTrue);
        expect(gateway.calls, ['projects.list']);
      },
    );

    test('the cache is scoped per connection', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Gateway A')],
      );
      await _repository(gateway, prefs, connectionId: 'a').refresh();

      final other = _repository(_FakeGateway(), prefs, connectionId: 'b');

      expect((await other.loadCached()).projects, isEmpty);
    });

    test('an empty gateway result clears a stale cache', () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Gone')],
      );
      final repo = _repository(gateway, prefs);
      await repo.refresh();

      gateway.projects = [];
      final view = await repo.refresh();

      expect(view.projects, isEmpty);
      expect(
        (await _repository(gateway, prefs).loadCached()).projects,
        isEmpty,
      );
    });
  });

  group('optimistic mutations', () {
    test(
      'create shows the project immediately and keeps the server record',
      () async {
        final gateway = _FakeGateway();
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );
        await repo.refresh();

        final seen = <List<String>>[];
        repo.changes.listen(
          (view) => seen.add(view.projects.map((p) => p.name).toList()),
        );

        await repo.create('ScriptHive');
        await Future<void>.delayed(Duration.zero);

        expect(seen.first, ['ScriptHive']);
        expect(repo.current.projects.single.id, 'srv-1');
        expect(repo.current.projects.single.name, 'ScriptHive');
      },
    );

    test(
      'concurrent creates keep both server records and remove placeholders',
      () async {
        final creates = <Completer<Map<String, dynamic>>>[];
        final repo = ProjectsRepository(
          client: ProjectsGatewayClient((method, params) async {
            if (method == 'projects.list') {
              return _FakeGateway._ok({
                'projects': const <Map<String, dynamic>>[],
                'active_id': null,
              });
            }
            if (method == 'projects.create') {
              final response = Completer<Map<String, dynamic>>();
              creates.add(response);
              return response.future;
            }
            return _FakeGateway._ok(const {});
          }),
          preferences: await SharedPreferences.getInstance(),
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final first = repo.create('First');
        final second = repo.create('Second');

        expect(creates, hasLength(2));
        expect(repo.current.projects.map((project) => project.name), [
          'First',
          'Second',
        ]);
        expect(
          repo.current.projects.every(
            (project) => project.id.startsWith('pending:'),
          ),
          isTrue,
        );

        creates[0].complete(
          _FakeGateway._ok({
            'project': _projectJson(id: 'srv-1', name: 'First'),
          }),
        );
        await first;
        creates[1].complete(
          _FakeGateway._ok({
            'project': _projectJson(id: 'srv-2', name: 'Second'),
          }),
        );
        await second;

        expect(repo.current.projects.map((project) => project.id).toSet(), {
          'srv-1',
          'srv-2',
        });
        expect(
          repo.current.projects.where(
            (project) => project.id.startsWith('pending:'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'a failed concurrent create never persists its pending placeholder',
      () async {
        final creates = <Completer<Map<String, dynamic>>>[];
        final preferences = await SharedPreferences.getInstance();
        final client = ProjectsGatewayClient((method, params) {
          if (method == 'projects.list') {
            return Future.value(
              _FakeGateway._ok({
                'projects': const <Map<String, dynamic>>[],
                'active_id': null,
              }),
            );
          }
          if (method == 'projects.create') {
            final response = Completer<Map<String, dynamic>>();
            creates.add(response);
            return response.future;
          }
          return Future.value(_FakeGateway._ok(const {}));
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final first = repo.create('First');
        final second = repo.create('Second');
        creates[0].complete(
          _FakeGateway._ok({
            'project': _projectJson(id: 'srv-1', name: 'First'),
          }),
        );
        await first;
        creates[1].completeError(
          JsonRpcError('projects.create', 'second failed'),
        );
        await expectLater(second, throwsA(isA<JsonRpcError>()));

        final restarted = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        final cached = await restarted.loadCached();
        expect(cached.projects.map((project) => project.id), ['srv-1']);
        expect(
          cached.projects.where((project) => project.id.startsWith('pending:')),
          isEmpty,
        );
      },
    );

    test(
      'a rename completing after create preserves the created project',
      () async {
        final createResponse = Completer<Map<String, dynamic>>();
        final renameResponse = Completer<Map<String, dynamic>>();
        final preferences = await SharedPreferences.getInstance();
        final client = ProjectsGatewayClient((method, params) {
          switch (method) {
            case 'projects.list':
              return Future.value(
                _FakeGateway._ok({
                  'projects': [_projectJson(id: 'old', name: 'Old')],
                  'active_id': null,
                }),
              );
            case 'projects.create':
              return createResponse.future;
            case 'projects.update':
              return renameResponse.future;
            default:
              return Future.value(_FakeGateway._ok(const {}));
          }
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final create = repo.create('New');
        final rename = repo.rename('old', 'Renamed');
        createResponse.complete(
          _FakeGateway._ok({'project': _projectJson(id: 'new', name: 'New')}),
        );
        await create;
        renameResponse.complete(
          _FakeGateway._ok({
            'project': _projectJson(id: 'old', name: 'Renamed'),
          }),
        );
        await rename;

        expect(
          repo.current.projects.map(
            (project) => '${project.id}:${project.name}',
          ),
          ['old:Renamed', 'new:New'],
        );
        final restarted = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect(
          (await restarted.loadCached()).projects.map((project) => project.id),
          ['old', 'new'],
        );
      },
    );

    test(
      'an archive snapshot preserves a create that completed while in flight',
      () async {
        final createResponse = Completer<Map<String, dynamic>>();
        final archiveResponse = Completer<Map<String, dynamic>>();
        final client = ProjectsGatewayClient((method, params) {
          switch (method) {
            case 'projects.list':
              return Future.value(
                _FakeGateway._ok({
                  'projects': [_projectJson(id: 'old', name: 'Old')],
                  'active_id': null,
                }),
              );
            case 'projects.create':
              return createResponse.future;
            case 'projects.archive':
              return archiveResponse.future;
            default:
              return Future.value(_FakeGateway._ok(const {}));
          }
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: await SharedPreferences.getInstance(),
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final create = repo.create('New');
        final archive = repo.archive('old');
        createResponse.complete(
          _FakeGateway._ok({'project': _projectJson(id: 'new', name: 'New')}),
        );
        await create;
        archiveResponse.complete(
          _FakeGateway._ok({
            'projects': [
              {..._projectJson(id: 'old', name: 'Old'), 'archived': true},
            ],
            'active_id': null,
          }),
        );
        await archive;

        expect(repo.current.projects.map((project) => project.id), ['new']);
        expect(repo.current.archived.map((project) => project.id), ['old']);
      },
    );

    test(
      'a failed rename rolls back memory and cache after a concurrent create',
      () async {
        final createResponse = Completer<Map<String, dynamic>>();
        final renameResponse = Completer<Map<String, dynamic>>();
        final preferences = await SharedPreferences.getInstance();
        final client = ProjectsGatewayClient((method, params) {
          switch (method) {
            case 'projects.list':
              return Future.value(
                _FakeGateway._ok({
                  'projects': [_projectJson(id: 'old', name: 'Before')],
                  'active_id': null,
                }),
              );
            case 'projects.create':
              return createResponse.future;
            case 'projects.update':
              return renameResponse.future;
            default:
              return Future.value(_FakeGateway._ok(const {}));
          }
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final rename = repo.rename('old', 'After');
        final create = repo.create('New');
        createResponse.complete(
          _FakeGateway._ok({'project': _projectJson(id: 'new', name: 'New')}),
        );
        await create;
        final whilePending = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect(
          (await whilePending.loadCached()).projects.map(
            (project) => '${project.id}:${project.name}',
          ),
          ['old:Before', 'new:New'],
          reason: 'an optimistic rename must never become durable',
        );
        renameResponse.completeError(_offline);
        await expectLater(rename, throwsA(isA<JsonRpcError>()));

        expect(
          repo.current.projects.map(
            (project) => '${project.id}:${project.name}',
          ),
          ['old:Before', 'new:New'],
        );
        final restarted = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect(
          (await restarted.loadCached()).projects.map(
            (project) => '${project.id}:${project.name}',
          ),
          ['old:Before', 'new:New'],
        );
      },
    );

    test(
      'two failed renames serialize against the last confirmed baseline',
      () async {
        final renameResponses = <Completer<Map<String, dynamic>>>[];
        final client = ProjectsGatewayClient((method, params) {
          if (method == 'projects.list') {
            return Future.value(
              _FakeGateway._ok({
                'projects': [_projectJson(id: 'old', name: 'Original')],
                'active_id': null,
              }),
            );
          }
          if (method == 'projects.update') {
            final response = Completer<Map<String, dynamic>>();
            renameResponses.add(response);
            return response.future;
          }
          return Future.value(_FakeGateway._ok(const {}));
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: await SharedPreferences.getInstance(),
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final first = repo.rename('old', 'First optimistic');
        final second = repo.rename('old', 'Second optimistic');
        await Future<void>.delayed(Duration.zero);
        expect(renameResponses, hasLength(1));
        renameResponses.single.completeError(_offline);
        await expectLater(first, throwsA(isA<JsonRpcError>()));
        await Future<void>.delayed(Duration.zero);
        expect(renameResponses, hasLength(2));
        renameResponses.last.completeError(_offline);
        await expectLater(second, throwsA(isA<JsonRpcError>()));

        expect(repo.current.projects.single.name, 'Original');
      },
    );

    test(
      'a refresh cannot durably cache an optimistic delete that later fails',
      () async {
        final refreshResponse = Completer<Map<String, dynamic>>();
        final deleteResponse = Completer<Map<String, dynamic>>();
        var listCalls = 0;
        final preferences = await SharedPreferences.getInstance();
        final client = ProjectsGatewayClient((method, params) {
          if (method == 'projects.list') {
            listCalls++;
            if (listCalls > 1) return refreshResponse.future;
            return Future.value(
              _FakeGateway._ok({
                'projects': [_projectJson(id: 'p1', name: 'Kept')],
                'active_id': null,
              }),
            );
          }
          if (method == 'projects.delete') return deleteResponse.future;
          return Future.value(_FakeGateway._ok(const {}));
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final deletion = repo.delete('p1');
        final refresh = repo.refresh();
        refreshResponse.complete(
          _FakeGateway._ok({
            'projects': [_projectJson(id: 'p1', name: 'Kept')],
            'active_id': null,
          }),
        );
        await refresh;
        final whilePending = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect(
          (await whilePending.loadCached()).projects.map(
            (project) => project.id,
          ),
          ['p1'],
          reason: 'optimistic deletion must never become durable',
        );
        deleteResponse.completeError(_offline);
        await expectLater(deletion, throwsA(isA<JsonRpcError>()));

        final restarted = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect(
          (await restarted.loadCached()).projects.map((project) => project.id),
          ['p1'],
        );
      },
    );

    test(
      'a failed refresh keeps confirmed memory instead of an older cache',
      () async {
        var failList = false;
        final offline = _offline;
        final preferences = await SharedPreferences.getInstance();
        final client = ProjectsGatewayClient((method, params) {
          if (method == 'projects.list') {
            if (failList) return Future.error(offline);
            return Future.value(
              _FakeGateway._ok({
                'projects': [_projectJson(id: 'p1', name: 'Before')],
                'active_id': null,
              }),
            );
          }
          if (method == 'projects.update') {
            return Future.value(
              _FakeGateway._ok({
                'project': _projectJson(id: 'p1', name: 'After'),
              }),
            );
          }
          return Future.value(_FakeGateway._ok(const {}));
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await repo.refresh();
        final staleCache = preferences.getString('projects_cache_v1_gateway-a');
        expect(staleCache, isNotNull);
        await repo.rename('p1', 'After');
        await preferences.setString('projects_cache_v1_gateway-a', staleCache!);

        failList = true;
        final fallback = await repo.refresh();

        expect(fallback.projects.single.name, 'After');
        expect(fallback.isStale, isTrue);
        expect(fallback.error, same(offline));
      },
    );

    test(
      'a stale refresh cannot restore a project after delete succeeds',
      () async {
        final staleRefresh = Completer<Map<String, dynamic>>();
        final deleteResponse = Completer<Map<String, dynamic>>();
        var listCalls = 0;
        final preferences = await SharedPreferences.getInstance();
        final client = ProjectsGatewayClient((method, params) {
          if (method == 'projects.list') {
            listCalls++;
            if (listCalls > 1) return staleRefresh.future;
            return Future.value(
              _FakeGateway._ok({
                'projects': [_projectJson(id: 'p1', name: 'Old')],
                'active_id': 'p1',
              }),
            );
          }
          if (method == 'projects.delete') return deleteResponse.future;
          return Future.value(_FakeGateway._ok(const {}));
        });
        final repo = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await repo.refresh();

        final deletion = repo.delete('p1');
        await Future<void>.delayed(Duration.zero);
        final refresh = repo.refresh();
        deleteResponse.complete(
          _FakeGateway._ok({'projects': const [], 'active_id': null}),
        );
        await deletion;
        staleRefresh.complete(
          _FakeGateway._ok({
            'projects': [_projectJson(id: 'p1', name: 'Old')],
            'active_id': 'p1',
          }),
        );
        await refresh;

        expect(repo.current.projects, isEmpty);
        expect(repo.current.activeId, isNull);
        final restarted = ProjectsRepository(
          client: client,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect((await restarted.loadCached()).projects, isEmpty);
      },
    );

    test('a stale refresh cannot revert a completed rename', () async {
      final staleRefresh = Completer<Map<String, dynamic>>();
      final renameResponse = Completer<Map<String, dynamic>>();
      var listCalls = 0;
      final client = ProjectsGatewayClient((method, params) {
        if (method == 'projects.list') {
          listCalls++;
          if (listCalls > 1) return staleRefresh.future;
          return Future.value(
            _FakeGateway._ok({
              'projects': [_projectJson(id: 'p1', name: 'Before')],
              'active_id': null,
            }),
          );
        }
        if (method == 'projects.update') return renameResponse.future;
        return Future.value(_FakeGateway._ok(const {}));
      });
      final repo = ProjectsRepository(
        client: client,
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'gateway-a',
      );
      await repo.refresh();

      final rename = repo.rename('p1', 'After');
      await Future<void>.delayed(Duration.zero);
      final refresh = repo.refresh();
      renameResponse.complete(
        _FakeGateway._ok({'project': _projectJson(id: 'p1', name: 'After')}),
      );
      await rename;
      staleRefresh.complete(
        _FakeGateway._ok({
          'projects': [_projectJson(id: 'p1', name: 'Before')],
          'active_id': null,
        }),
      );
      await refresh;

      expect(repo.current.projects.single.name, 'After');
    });

    test(
      'a closed repository cannot overwrite a newer repository cache',
      () async {
        final staleRefresh = Completer<Map<String, dynamic>>();
        final preferences = await SharedPreferences.getInstance();
        final staleClient = ProjectsGatewayClient(
          (method, params) => staleRefresh.future,
        );
        final staleRepo = ProjectsRepository(
          client: staleClient,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        final staleResult = staleRepo.refresh();
        await staleRepo.close();

        final freshClient = ProjectsGatewayClient(
          (method, params) => Future.value(
            _FakeGateway._ok({
              'projects': [_projectJson(id: 'new', name: 'After')],
              'active_id': null,
            }),
          ),
        );
        final freshRepo = ProjectsRepository(
          client: freshClient,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        await freshRepo.refresh();
        staleRefresh.complete(
          _FakeGateway._ok({
            'projects': [_projectJson(id: 'old', name: 'Before')],
            'active_id': null,
          }),
        );
        await staleResult;

        final restarted = ProjectsRepository(
          client: freshClient,
          preferences: preferences,
          connectionId: 'gateway-a',
        );
        expect(
          (await restarted.loadCached()).projects.map((project) => project.id),
          ['new'],
        );
      },
    );

    test('a newer delete waits for a failed archive rollback', () async {
      final archiveResponse = Completer<Map<String, dynamic>>();
      final deleteResponse = Completer<Map<String, dynamic>>();
      var archiveCalls = 0;
      var deleteCalls = 0;
      final client = ProjectsGatewayClient((method, params) {
        switch (method) {
          case 'projects.list':
            return Future.value(
              _FakeGateway._ok({
                'projects': [_projectJson(id: 'old', name: 'Old')],
                'active_id': null,
              }),
            );
          case 'projects.archive':
            archiveCalls++;
            return archiveResponse.future;
          case 'projects.delete':
            deleteCalls++;
            return deleteResponse.future;
          default:
            return Future.value(_FakeGateway._ok(const {}));
        }
      });
      final repo = ProjectsRepository(
        client: client,
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'gateway-a',
      );
      await repo.refresh();

      final archive = repo.archive('old');
      final delete = repo.delete('old');
      await Future<void>.delayed(Duration.zero);
      expect(archiveCalls, 1);
      expect(deleteCalls, 0);
      archiveResponse.completeError(_offline);
      await expectLater(archive, throwsA(isA<JsonRpcError>()));
      await Future<void>.delayed(Duration.zero);
      expect(deleteCalls, 1);
      deleteResponse.complete(
        _FakeGateway._ok({'projects': const [], 'active_id': null}),
      );
      await delete;

      expect(repo.current.projects, isEmpty);
      expect(repo.current.archived, isEmpty);
    });

    test('a failed create rolls back to the previous list', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Kept')],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      gateway.failNext = JsonRpcError('projects.create', 'boom');

      await expectLater(repo.create('Doomed'), throwsA(isA<JsonRpcError>()));
      expect(repo.current.projects.map((p) => p.name), ['Kept']);
    });

    test(
      'a name-only create auto-provisions a folder and binds it primary',
      () async {
        final gateway = _FakeGateway();
        final prefs = await SharedPreferences.getInstance();
        final repo = ProjectsRepository(
          client: ProjectsGatewayClient(gateway.call),
          preferences: prefs,
          connectionId: 'gateway-a',
          folderProvisioner: _StubProvisioner('/srv/Projects/scripthive'),
        );
        await repo.refresh();

        final created = await repo.create('ScriptHive');

        expect(gateway.calls, contains('projects.add_folder'));
        expect(created.folders, hasLength(1));
        expect(created.workingDirectory, '/srv/Projects/scripthive');
        expect(
          repo.current.projects.single.workingDirectory,
          '/srv/Projects/scripthive',
        );
      },
    );

    test(
      'a project that already has folders is never re-provisioned',
      () async {
        final gateway = _FakeGateway();
        final provisioned = <String>[];
        final prefs = await SharedPreferences.getInstance();
        final repo = ProjectsRepository(
          client: ProjectsGatewayClient((method, params) async {
            if (method == 'projects.create') {
              return {
                'jsonrpc': '2.0',
                'id': 1,
                'result': {
                  'project': {
                    ..._projectJson(id: 'srv-1', name: 'ScriptHive'),
                    'folders': [
                      {
                        'path': '/srv/existing',
                        'label': 'existing',
                        'is_primary': true,
                        'added_at': 1,
                      },
                    ],
                  },
                },
              };
            }
            return gateway.call(method, params);
          }),
          preferences: prefs,
          connectionId: 'gateway-a',
          folderProvisioner: _RecordingProvisioner(provisioned),
        );
        await repo.refresh();

        final created = await repo.create('ScriptHive');

        expect(provisioned, isEmpty);
        expect(gateway.calls, isNot(contains('projects.add_folder')));
        expect(created.workingDirectory, '/srv/existing');
      },
    );

    test(
      'a failed folder bind keeps the created project, folderless',
      () async {
        final gateway = _FakeGateway();
        final prefs = await SharedPreferences.getInstance();
        gateway.failMethod = 'projects.add_folder';
        final repo = ProjectsRepository(
          client: ProjectsGatewayClient(gateway.call),
          preferences: prefs,
          connectionId: 'gateway-a',
          folderProvisioner: _StubProvisioner('/srv/Projects/scripthive'),
        );
        await repo.refresh();

        final created = await repo.create('ScriptHive');

        expect(created.folders, isEmpty);
        expect(repo.current.projects.single.name, 'ScriptHive');
      },
    );

    test(
      'rename applies immediately and survives the server round trip',
      () async {
        final gateway = _FakeGateway(
          projects: [_projectJson(id: 'p1', name: 'Before')],
        );
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );
        await repo.refresh();

        await repo.rename('p1', 'After');

        expect(repo.current.projects.single.name, 'After');
      },
    );

    test('a failed rename restores the previous name', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Before')],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      gateway.failNext = JsonRpcError('projects.update', 'nope');

      await expectLater(
        repo.rename('p1', 'After'),
        throwsA(isA<JsonRpcError>()),
      );
      expect(repo.current.projects.single.name, 'Before');
    });

    test('archiving removes a project from the active list', () async {
      final gateway = _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Keep'),
          _projectJson(id: 'p2', name: 'Retire'),
        ],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      await repo.archive('p2');

      expect(repo.current.projects.map((p) => p.id), ['p1']);
      expect(repo.current.archived.map((p) => p.id), ['p2']);
    });

    test('a failed archive puts the project back', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Keep')],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      gateway.failNext = JsonRpcError('projects.archive', 'nope');

      await expectLater(repo.archive('p1'), throwsA(isA<JsonRpcError>()));
      expect(repo.current.projects.map((p) => p.id), ['p1']);
    });

    test('delete removes the project and clears it as active', () async {
      final gateway = _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Delete me'),
          _projectJson(id: 'p2', name: 'Keep'),
        ],
        activeId: 'p1',
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      await repo.delete('p1');

      expect(gateway.calls.last, 'projects.delete');
      expect(repo.current.projects.map((p) => p.id), ['p2']);
      expect(repo.current.activeId, isNull);
    });

    test('a failed delete restores the project and active selection', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Keep')],
        activeId: 'p1',
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      gateway.failNext = JsonRpcError('projects.delete', 'nope');

      await expectLater(repo.delete('p1'), throwsA(isA<JsonRpcError>()));
      expect(repo.current.projects.map((p) => p.id), ['p1']);
      expect(repo.current.activeId, 'p1');
    });

    test('selecting a project updates the active id', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      await repo.setActive('p1');
      expect(repo.current.activeId, 'p1');

      await repo.setActive(null);
      expect(repo.current.activeId, isNull);
    });

    test(
      'move uses only the stock cwd re-home, never assign_session',
      () async {
        final gateway = _FakeGateway(
          projects: [
            _projectJson(
              id: 'p1',
              name: 'Hermes Android',
              primaryPath: '/home/dev/hermes-android',
            ),
          ],
        );
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );
        await repo.refresh();

        final reason = await repo.moveSessionToProject('s-1', 'p1');

        expect(reason, isNull);
        // Stock-only contract: projects.assign_session (never shipped
        // upstream) must not be attempted even when a fake would accept it.
        expect(gateway.calls, isNot(contains('projects.assign_session')));
        expect(gateway.workspaceMoves, [
          {'session_key': 's-1', 'cwd': '/home/dev/hermes-android'},
        ]);
      },
    );

    test('move re-homes the workspace to the target project folder', () async {
      final gateway = _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Hermes Android'),
          _projectJson(
            id: 'p2',
            name: 'ScriptHive',
            folders: [
              {
                'path': '/home/dev/scripthive',
                'label': 'main',
                'is_primary': true,
                'added_at': 1750000001,
              },
            ],
          ),
        ],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      final reason = await repo.moveSessionToProject(
        's-1',
        'p2',
        storedSessionKey: 'stored-9',
      );

      expect(reason, isNull);
      expect(gateway.workspaceMoves, [
        {'session_key': 'stored-9', 'cwd': '/home/dev/scripthive'},
      ]);
    });

    test(
      'moving back to Unassigned reports why (cwd-derived filing)',
      () async {
        final gateway = _FakeGateway();
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );
        await repo.refresh();

        final reason = await repo.moveSessionToProject('s-1', null);

        expect(reason, contains('cannot move a chat back to Unassigned'));
        expect(gateway.workspaceMoves, isEmpty);
      },
    );

    test('a folderless target asks for a folder', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Name Only')],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      final reason = await repo.moveSessionToProject('s-1', 'p1');

      expect(reason, contains('no folder'));
      expect(gateway.workspaceMoves, isEmpty);
    });

    test('the move uses the mobile id when no stored key is bound', () async {
      final gateway = _FakeGateway(
        projects: [
          _projectJson(
            id: 'p2',
            name: 'ScriptHive',
            primaryPath: '/home/dev/scripthive',
          ),
        ],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();

      await repo.moveSessionToProject('mob-7', 'p2');

      expect(gateway.workspaceMoves, [
        {'session_key': 'mob-7', 'cwd': '/home/dev/scripthive'},
      ]);
    });

    test(
      'mutations are refused in compatibility mode without a call',
      () async {
        final gateway = _FakeGateway()
          ..failNext = const ProjectsUnsupportedException(
            'projects.list',
            'unknown method',
          );
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );
        await repo.refresh();
        gateway.calls.clear();

        await expectLater(
          repo.create('Nope'),
          throwsA(isA<ProjectsUnsupportedException>()),
        );
        expect(gateway.calls, isEmpty);
      },
    );
  });

  group('spaces migration preview', () {
    test(
      'matches local spaces to server projects by normalized name',
      () async {
        final gateway = _FakeGateway(
          projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
        );
        final repo = _repository(
          gateway,
          await SharedPreferences.getInstance(),
        );
        await repo.refresh();

        final plan = repo.planMigration(
          const ChatSpaceState(
            spaces: [
              ChatSpace(id: 's1', name: '  hermes android ', createdAt: 1),
              ChatSpace(id: 's2', name: 'ScriptHive', createdAt: 2),
            ],
            assignments: {'chat-1': 's1', 'chat-2': 's2', 'chat-3': 's1'},
          ),
        );

        final matched = plan.entries.firstWhere(
          (e) => e.matchedProject != null,
        );
        final toCreate = plan.entries.firstWhere(
          (e) => e.matchedProject == null,
        );

        expect(matched.space.id, 's1');
        expect(matched.matchedProject!.id, 'p1');
        expect(matched.sessionCount, 2);
        expect(toCreate.space.name, 'ScriptHive');
        expect(toCreate.sessionCount, 1);
        expect(plan.projectsToCreate, 1);
        expect(plan.sessionsToLink, 3);
      },
    );

    test('planning performs no gateway call and mutates nothing', () async {
      final gateway = _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      );
      final repo = _repository(gateway, await SharedPreferences.getInstance());
      await repo.refresh();
      gateway.calls.clear();

      repo.planMigration(
        const ChatSpaceState(
          spaces: [ChatSpace(id: 's1', name: 'New', createdAt: 1)],
          assignments: {},
        ),
      );

      expect(gateway.calls, isEmpty);
      expect(repo.current.projects.map((p) => p.id), ['p1']);
    });

    test('an empty local store yields an empty, harmless plan', () async {
      final repo = _repository(
        _FakeGateway(),
        await SharedPreferences.getInstance(),
      );
      await repo.refresh();

      final plan = repo.planMigration(
        const ChatSpaceState(spaces: [], assignments: {}),
      );

      expect(plan.entries, isEmpty);
      expect(plan.isEmpty, isTrue);
      expect(plan.projectsToCreate, 0);
    });
  });
}
