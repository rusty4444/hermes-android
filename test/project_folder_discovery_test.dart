// Discovery of server folders that are not Projects yet (issue #232).
//
// Enumeration rides the dashboard's existing `GET /api/fs/list` route, reached
// through RemoteFilesClient.listDirectory. Nothing here invents an RPC: when
// the route is absent or forbidden the result is an honest "not supported on
// this connection", never an empty candidate list.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_project.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/project_folder_discovery.dart';
import 'package:hermes_android/core/services/projects_root_resolver.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/services/projects_root_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

HermesProject _project({
  required String id,
  required String name,
  String? primaryPath,
  List<String> folders = const [],
}) => HermesProject.fromJson({
  'id': id,
  'slug': name.toLowerCase(),
  'name': name,
  'primary_path': ?primaryPath,
  'folders': [
    for (final folder in folders)
      {'path': folder, 'is_primary': folder == primaryPath},
  ],
});

/// Serves `GET /api/files` (for the root) and `GET /api/fs/list` (for the
/// listing) exactly as the stock dashboard does, including the 200-with-error
/// shape used for an unreadable path.
class _FilesDashboard {
  final String? lockedRoot;
  final String home;

  /// Directory contents keyed by absolute path.
  final Map<String, List<Map<String, Object?>>> tree;

  /// HTTP status for `fs/list`, when overriding the success path.
  final int listStatus;

  /// 200-with-`error` body for `fs/list`, as the stock route answers for a
  /// path it cannot read.
  final String? listError;

  final List<String> listed = [];

  _FilesDashboard({
    this.lockedRoot,
    this.home = '/home/tester',
    Map<String, List<Map<String, Object?>>>? tree,
    this.listStatus = 200,
    this.listError,
  }) : tree = tree ?? {};

  DashboardClient client() => DashboardClient(
    host: 'localhost',
    port: 9119,
    proxied: true,
    httpClient: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    if (uri.path == '/api/files' && request.method == 'GET') {
      return http.Response(
        jsonEncode({
          'path': home,
          'entries': <dynamic>[],
          'locked_root': lockedRoot,
        }),
        200,
      );
    }
    if (uri.path == '/api/fs/list' && request.method == 'GET') {
      final path = uri.queryParameters['path'] ?? '';
      listed.add(path);
      if (listStatus != 200) {
        return http.Response('{"detail":"no"}', listStatus);
      }
      if (listError != null) {
        return http.Response(
          jsonEncode({
            'path': path,
            'entries': <dynamic>[],
            'error': listError,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'path': path, 'entries': tree[path] ?? const []}),
        200,
      );
    }
    return http.Response('not found', 404);
  }
}

Map<String, Object?> _dir(String root, String name) => {
  'name': name,
  'path': '$root/$name',
  'isDirectory': true,
};

Map<String, Object?> _file(String root, String name) => {
  'name': name,
  'path': '$root/$name',
  'isDirectory': false,
};

ProjectFolderDiscovery _discovery(
  _FilesDashboard dash, {
  String? configuredRoot,
  RemoteDirectoryLister? lister,
}) {
  final client = dash.client();
  return DashboardProjectFolderDiscovery(
    listDirectory: lister ?? RemoteFilesClient(dashboard: client).listDirectory,
    roots: ProjectsRootResolver(
      dashboard: client,
      configuredRoot: configuredRoot,
    ),
  );
}

void main() {
  group('scan', () {
    test('retained discovery follows preference saves and resets', () async {
      SharedPreferences.setMockInitialValues({});
      final preference = await ProjectsRootPreference.open();
      final dash = _FilesDashboard();
      final client = dash.client();
      final discovery = DashboardProjectFolderDiscovery(
        listDirectory: RemoteFilesClient(dashboard: client).listDirectory,
        roots: ProjectsRootResolver(
          dashboard: client,
          readConfiguredRoot: () =>
              preference.read(connectionIdentity: 'saved'),
        ),
      );
      await discovery.scan(registered: const []);
      await preference.save(
        connectionIdentity: 'saved',
        path: '/root/.hermes/projects',
      );
      await discovery.scan(registered: const []);
      await preference.clear(connectionIdentity: 'saved');
      await discovery.scan(registered: const []);
      expect(dash.listed, [
        '/home/tester/Projects',
        '/root/.hermes/projects',
        '/home/tester/Projects',
      ]);
    });
    test('separates registered folders from adoption candidates', () async {
      const root = '/root/.hermes/projects';
      final dash = _FilesDashboard(
        tree: {
          root: [
            _dir(root, 'scripthive'),
            _dir(root, 'ledger'),
            _dir(root, 'already-known'),
            _file(root, 'notes.md'),
            _dir(root, '.cache'),
          ],
        },
      );

      final result = await _discovery(dash, configuredRoot: root).scan(
        registered: [
          _project(
            id: 'p1',
            name: 'Already Known',
            primaryPath: '$root/already-known',
            folders: ['$root/already-known'],
          ),
        ],
      );

      expect(result.status, ProjectFolderDiscoveryStatus.ready);
      expect(result.root, root);
      expect(result.rootSource, ProjectsRootSource.configured);
      // Files and dotfolders are not Project candidates.
      expect(result.folders.map((folder) => folder.name), [
        'already-known',
        'ledger',
        'scripthive',
      ]);
      expect(result.unregistered.map((folder) => folder.path), [
        '$root/ledger',
        '$root/scripthive',
      ]);
      final known = result.folders.first;
      expect(known.registered, isTrue);
      expect(known.registeredProjectName, 'Already Known');
      expect(dash.listed, [root]);
    });

    test('matches a registered folder despite a trailing slash', () async {
      const root = '/srv/projects';
      final dash = _FilesDashboard(
        lockedRoot: root,
        tree: {
          root: [_dir(root, 'ledger')],
        },
      );

      final result = await _discovery(dash).scan(
        registered: [
          _project(id: 'p1', name: 'Ledger', folders: ['$root/ledger/']),
        ],
      );

      expect(result.rootSource, ProjectsRootSource.locked);
      expect(result.unregistered, isEmpty);
      expect(result.folders.single.registered, isTrue);
    });

    test('an absent fs/list route reports unsupported, not empty', () async {
      final dash = _FilesDashboard(listStatus: 404);
      final result = await _discovery(
        dash,
        configuredRoot: '/root/.hermes/projects',
      ).scan(registered: const []);

      expect(result.status, ProjectFolderDiscoveryStatus.unsupported);
      expect(result.folders, isEmpty);
      expect(result.root, '/root/.hermes/projects');
    });

    test('a forbidden listing reports unsupported', () async {
      final dash = _FilesDashboard(listStatus: 403);
      final result = await _discovery(dash).scan(registered: const []);
      expect(result.status, ProjectFolderDiscoveryStatus.unsupported);
    });

    test(
      'an unreadable dashboard reports unsupported with the root unknown',
      () async {
        final client = DashboardClient(
          host: 'localhost',
          port: 9119,
          proxied: true,
          httpClient: MockClient(
            (_) async => http.Response('{"detail":"nope"}', 500),
          ),
        );
        final discovery = DashboardProjectFolderDiscovery(
          listDirectory: (_) async =>
              fail('the root must be resolved before listing'),
          roots: ProjectsRootResolver(dashboard: client),
        );

        final result = await discovery.scan(registered: const []);
        expect(result.status, ProjectFolderDiscoveryStatus.unsupported);
        expect(result.root, isNull);
        expect(result.rootSource, ProjectsRootSource.unavailable);
      },
    );

    test(
      'a 200-with-error listing is a failure, not an unsupported route',
      () async {
        final dash = _FilesDashboard(listError: 'Permission denied');
        final result = await _discovery(dash).scan(registered: const []);

        expect(result.status, ProjectFolderDiscoveryStatus.failed);
        expect('${result.error}', contains('Permission denied'));
        expect(result.root, '/home/tester/Projects');
      },
    );

    test('an entry without a path falls back to root/name', () async {
      const root = '/home/tester/Projects';
      final dash = _FilesDashboard(
        tree: {
          root: [
            {'name': 'ledger', 'path': '', 'isDirectory': true},
          ],
        },
      );
      final result = await _discovery(dash).scan(registered: const []);
      expect(result.unregistered.single.path, '$root/ledger');
    });
  });

  group('connection replacement', () {
    test(
      'a held listing completing later does not leak into a new scan',
      () async {
        // A slow read from the previous connection must not be mistaken for the
        // new connection's answer. The discovery object is per-connection, so
        // the proof is that each instance only ever reports its own listing.
        const rootA = '/a/projects';
        const rootB = '/b/projects';
        final gate = Completer<void>();

        final slow = DashboardProjectFolderDiscovery(
          listDirectory: (path) async {
            await gate.future;
            return [
              RemoteFileEntry(
                name: 'stale',
                path: '$path/stale',
                isDirectory: true,
              ),
            ];
          },
          roots: ProjectsRootResolver(
            dashboard: _FilesDashboard(home: '/a').client(),
            configuredRoot: rootA,
          ),
        );
        final fresh = _discovery(
          _FilesDashboard(
            home: '/b',
            tree: {
              rootB: [_dir(rootB, 'fresh')],
            },
          ),
          configuredRoot: rootB,
        );

        final held = slow.scan(registered: const []);
        final current = await fresh.scan(registered: const []);
        expect(current.root, rootB);
        expect(current.unregistered.single.name, 'fresh');

        gate.complete();
        final stale = await held;
        expect(stale.root, rootA);
        expect(stale.unregistered.single.name, 'stale');
      },
    );
  });
}
