// Registering an existing server folder as a Project (issue #232).
//
// Adoption uses only the existing creation contract: `projects.create` with
// `primary_path`, plus `projects.add_folder` when the gateway's create does not
// echo the folder back. Nothing provisions a directory, and a destination that
// ends up folderless is reported rather than claimed as a success, because
// stock Project membership follows the working folder.

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _projectJson({
  required String id,
  required String name,
  String? primaryPath,
  List<Map<String, dynamic>> folders = const [],
}) => {
  'id': id,
  'slug': name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'archived': false,
  'created_at': 1750000000,
  'primary_path': ?primaryPath,
  'folders': folders,
};

class _AdoptionGateway {
  final List<String> calls = [];
  final List<Map<String, dynamic>> createParams = [];
  final List<Map<String, dynamic>> addFolderParams = [];
  List<Map<String, dynamic>> projects;

  /// When false, `projects.create` ignores `primary_path`/`folders` the way an
  /// older gateway does, forcing the add_folder fallback.
  final bool createHonoursPrimaryPath;

  /// When set, this method always fails.
  String? failMethod;

  _AdoptionGateway({
    List<Map<String, dynamic>>? projects,
    this.createHonoursPrimaryPath = true,
  }) : projects = projects ?? [];

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add(method);
    if (failMethod == method) {
      throw JsonRpcError(method, 'server said no');
    }
    switch (method) {
      case 'projects.list':
        return _ok({'projects': projects, 'active_id': null});
      case 'projects.create':
        createParams.add(Map<String, dynamic>.from(params));
        final path = params['primary_path'] as String?;
        final created = _projectJson(
          id: 'srv-${projects.length + 1}',
          name: params['name'] as String,
          primaryPath: createHonoursPrimaryPath ? path : null,
          folders: createHonoursPrimaryPath && path != null
              ? [
                  {'path': path, 'is_primary': true, 'added_at': 1},
                ]
              : const [],
        );
        projects = [...projects, created];
        return _ok({'project': created});
      case 'projects.add_folder':
        addFolderParams.add(Map<String, dynamic>.from(params));
        final target = projects.firstWhere((p) => p['id'] == params['id']);
        final updated = {
          ...target,
          'primary_path': params['is_primary'] == true
              ? params['path']
              : target['primary_path'],
          'folders': [
            ...((target['folders'] as List?) ?? const []),
            {
              'path': params['path'],
              'label': params['label'],
              'is_primary': params['is_primary'] == true,
              'added_at': 1,
            },
          ],
        };
        projects = [
          for (final p in projects)
            if (p['id'] == params['id']) updated else p,
        ];
        return _ok({'project': updated});
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

Future<ProjectsRepository> _repository(_AdoptionGateway gateway) async =>
    ProjectsRepository(
      client: ProjectsGatewayClient(gateway.call),
      preferences: await SharedPreferences.getInstance(),
      connectionId: 'gateway-a',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('adoptFolder', () {
    test('registers the existing folder through projects.create', () async {
      final gateway = _AdoptionGateway();
      final repo = await _repository(gateway);
      await repo.refresh();

      final adopted = await repo.adoptFolder(
        name: 'Ledger',
        path: '/root/.hermes/projects/ledger',
      );

      expect(
        gateway.createParams.single['primary_path'],
        '/root/.hermes/projects/ledger',
      );
      expect(gateway.createParams.single['folders'], [
        '/root/.hermes/projects/ledger',
      ]);
      // No provisioning: the folder already exists, so nothing is created.
      expect(gateway.calls, isNot(contains('files/mkdir')));
      expect(adopted.workingDirectory, '/root/.hermes/projects/ledger');
      expect(
        repo.current.projects.single.workingDirectory,
        '/root/.hermes/projects/ledger',
      );
    });

    test('falls back to add_folder when create ignores primary_path', () async {
      final gateway = _AdoptionGateway(createHonoursPrimaryPath: false);
      final repo = await _repository(gateway);
      await repo.refresh();

      final adopted = await repo.adoptFolder(
        name: 'Ledger',
        path: '/root/.hermes/projects/ledger',
      );

      expect(
        gateway.addFolderParams.single['path'],
        '/root/.hermes/projects/ledger',
      );
      expect(gateway.addFolderParams.single['is_primary'], isTrue);
      expect(adopted.workingDirectory, '/root/.hermes/projects/ledger');
    });

    test(
      'a folderless destination is reported, never claimed as success',
      () async {
        final gateway = _AdoptionGateway(createHonoursPrimaryPath: false)
          ..failMethod = 'projects.add_folder';
        final repo = await _repository(gateway);
        await repo.refresh();

        await expectLater(
          repo.adoptFolder(name: 'Ledger', path: '/root/ledger'),
          throwsA(isA<ProjectFolderAdoptionException>()),
        );
        // The Project really was created, so the list stays honest about it.
        expect(repo.current.projects.single.name, 'Ledger');
        expect(repo.current.projects.single.workingDirectory, isNull);
      },
    );

    test(
      'a failed create keeps the prior state and surfaces the server error',
      () async {
        final gateway = _AdoptionGateway(
          projects: [_projectJson(id: 'p1', name: 'Kept')],
        )..failMethod = 'projects.create';
        final repo = await _repository(gateway);
        await repo.refresh();

        await expectLater(
          repo.adoptFolder(name: 'Ledger', path: '/root/ledger'),
          throwsA(isA<JsonRpcError>()),
        );
        expect(repo.current.projects.map((p) => p.name), ['Kept']);
      },
    );

    test(
      'rejects a relative or empty path before touching the gateway',
      () async {
        final gateway = _AdoptionGateway();
        final repo = await _repository(gateway);
        await repo.refresh();
        gateway.calls.clear();

        for (final path in ['', '   ', 'projects/ledger', './ledger']) {
          expect(
            () => repo.adoptFolder(name: 'Ledger', path: path),
            throwsA(isA<ArgumentError>()),
            reason: path,
          );
        }
        expect(gateway.calls, isEmpty);
      },
    );

    test('can select the adopted project as active', () async {
      final gateway = _AdoptionGateway();
      final repo = await _repository(gateway);
      await repo.refresh();

      final adopted = await repo.adoptFolder(
        name: 'Ledger',
        path: '/root/ledger',
        select: true,
      );
      expect(gateway.createParams.single['use'], isTrue);
      expect(repo.current.activeId, adopted.id);
    });

    test(
      'an ordinary name-only create is unchanged by adoption support',
      () async {
        final gateway = _AdoptionGateway();
        final repo = await _repository(gateway);
        await repo.refresh();

        await repo.create('Plain');

        expect(
          gateway.createParams.single.containsKey('primary_path'),
          isFalse,
        );
        expect(gateway.createParams.single.containsKey('folders'), isFalse);
      },
    );
  });
}
