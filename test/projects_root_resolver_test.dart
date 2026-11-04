// Precedence for the server-side Projects root (issue #232).
//
// Only one server interface is involved: `GET /api/files`, which reports the
// dashboard's `locked_root` and browse home. The rules under test:
//
//  * a server lock always wins, even when the user configured a root;
//  * otherwise the configured root wins;
//  * otherwise `<home>/Projects` — the behaviour that shipped before #232;
//  * an unreadable dashboard yields no root, never a guessed one.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/project_folder_provisioner.dart';
import 'package:hermes_android/core/services/projects_root_resolver.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FilesDashboard {
  final String? lockedRoot;
  final String? home;
  final int status;
  int calls = 0;

  _FilesDashboard({
    this.lockedRoot,
    this.home = '/home/tester',
    this.status = 200,
  });

  DashboardClient client() => DashboardClient(
    host: 'localhost',
    port: 9119,
    proxied: true,
    httpClient: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request request) async {
    if (request.url.path == '/api/files' && request.method == 'GET') {
      calls++;
      if (status != 200) return http.Response('{"detail":"nope"}', status);
      return http.Response(
        jsonEncode({
          'path': home,
          'parent': null,
          'entries': <dynamic>[],
          'locked_root': lockedRoot,
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  }
}

void main() {
  group('resolve', () {
    test('an unconfigured unlocked server keeps <home>/Projects', () async {
      final dash = _FilesDashboard();
      final resolution = await ProjectsRootResolver(
        dashboard: dash.client(),
      ).resolve();

      expect(resolution.path, '/home/tester/Projects');
      expect(resolution.source, ProjectsRootSource.serverDefault);
      expect(resolution.serverDefault, '/home/tester/Projects');
      expect(resolution.isLocked, isFalse);
    });

    test('a configured root is used on an unlocked server', () async {
      final dash = _FilesDashboard();
      final resolution = await ProjectsRootResolver(
        dashboard: dash.client(),
        configuredRoot: '/root/.hermes/projects',
      ).resolve();

      expect(resolution.path, '/root/.hermes/projects');
      expect(resolution.source, ProjectsRootSource.configured);
      // The default stays reported so the editor can offer it as a reset.
      expect(resolution.serverDefault, '/home/tester/Projects');
    });

    test('locked_root outranks a configured root', () async {
      final dash = _FilesDashboard(lockedRoot: '/srv/hermes');
      final resolution = await ProjectsRootResolver(
        dashboard: dash.client(),
        configuredRoot: '/root/.hermes/projects',
      ).resolve();

      expect(resolution.path, '/srv/hermes');
      expect(resolution.source, ProjectsRootSource.locked);
      expect(resolution.lockedRoot, '/srv/hermes');
      expect(resolution.isLocked, isTrue);
    });

    test(
      'trailing slashes are trimmed from both lock and configuration',
      () async {
        final locked = await ProjectsRootResolver(
          dashboard: _FilesDashboard(lockedRoot: '/srv/hermes//').client(),
        ).resolve();
        expect(locked.path, '/srv/hermes');

        final configured = await ProjectsRootResolver(
          dashboard: _FilesDashboard(home: '/home/tester/').client(),
          configuredRoot: '/root/projects/',
        ).resolve();
        expect(configured.path, '/root/projects');
        expect(configured.serverDefault, '/home/tester/Projects');
      },
    );

    test(
      'an unreadable dashboard reports unavailable, not a guessed root',
      () async {
        final dash = _FilesDashboard(status: 403);
        final resolution = await ProjectsRootResolver(
          dashboard: dash.client(),
          configuredRoot: '/root/.hermes/projects',
        ).resolve();

        // Critically, the configured root is NOT used: without the dashboard
        // answer we cannot know whether the server is locked, and a local
        // preference must never outrank a lock we failed to read.
        expect(resolution.path, isNull);
        expect(resolution.source, ProjectsRootSource.unavailable);
        expect(resolution.error, isA<DashboardHttpException>());
      },
    );

    test(
      'a dashboard with neither lock nor home reports unavailable',
      () async {
        final dash = _FilesDashboard(home: '   ');
        final resolution = await ProjectsRootResolver(
          dashboard: dash.client(),
        ).resolve();

        expect(resolution.path, isNull);
        expect(resolution.source, ProjectsRootSource.unavailable);
        expect(resolution.serverDefault, isNull);
      },
    );
  });

  group('provisioner integration', () {
    // The provisioner is the only thing that creates folders, so this is the
    // test that proves creation actually lands under the configured root.
    test('a new project folder is created under the configured root', () async {
      final dash = _ProvisionDashboard();
      final folder = await DashboardFolderProvisioner(
        dash.client(),
        configuredRoot: '/root/.hermes/projects',
      ).provision('widget lab');

      expect(folder, isNotNull);
      expect(
        folder,
        matches(RegExp(r'^/root/\.hermes/projects/widget-lab-[0-9a-f]{16}$')),
      );
      expect(dash.mkdirs.single, folder);
    });

    test(
      'locked_root still wins over the configured root at create time',
      () async {
        final dash = _ProvisionDashboard(lockedRoot: '/srv/hermes');
        final folder = await DashboardFolderProvisioner(
          dash.client(),
          configuredRoot: '/root/.hermes/projects',
        ).provision('widget lab');

        expect(
          folder,
          matches(RegExp(r'^/srv/hermes/widget-lab-[0-9a-f]{16}$')),
        );
      },
    );

    test('an unconfigured provisioner is unchanged by #232', () async {
      final dash = _ProvisionDashboard();
      final folder = await DashboardFolderProvisioner(
        dash.client(),
      ).provision('widget lab');

      expect(
        folder,
        matches(RegExp(r'^/home/tester/Projects/widget-lab-[0-9a-f]{16}$')),
      );
    });
  });
}

/// Minimal stand-in for the managed-files routes the provisioner needs: the
/// existence probe, mkdir, and the ownership marker write/read-back.
class _ProvisionDashboard {
  final String? lockedRoot;
  final String home = '/home/tester';
  final Set<String> existing = {};
  final Map<String, String> files = {};
  final List<String> mkdirs = [];

  _ProvisionDashboard({this.lockedRoot});

  DashboardClient client() => DashboardClient(
    host: 'localhost',
    port: 9119,
    proxied: true,
    httpClient: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    if (uri.path == '/api/files' && request.method == 'GET') {
      final path = uri.queryParameters['path'];
      if (path == null) {
        return http.Response(
          jsonEncode({
            'path': home,
            'entries': <dynamic>[],
            'locked_root': lockedRoot,
          }),
          200,
        );
      }
      if (!existing.contains(path)) {
        return http.Response('{"detail":"Path not found"}', 404);
      }
      final entries = files.keys
          .where((key) => key.substring(0, key.lastIndexOf('/')) == path)
          .map(
            (key) => {
              'name': key.substring(key.lastIndexOf('/') + 1),
              'is_directory': false,
            },
          )
          .toList();
      return http.Response(jsonEncode({'path': path, 'entries': entries}), 200);
    }
    if (uri.path == '/api/files/mkdir' && request.method == 'POST') {
      final path = (jsonDecode(request.body) as Map)['path'] as String;
      mkdirs.add(path);
      existing.add(path);
      return http.Response(jsonEncode({'ok': true, 'path': path}), 200);
    }
    if (uri.path == '/api/fs/write-text' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map;
      files[body['path'] as String] = body['content'] as String;
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    if (uri.path == '/api/fs/read-text' && request.method == 'GET') {
      final content = files[uri.queryParameters['path']];
      if (content == null) {
        return http.Response('{"detail":"File not found"}', 404);
      }
      return http.Response(jsonEncode({'binary': false, 'text': content}), 200);
    }
    return http.Response('not found', 404);
  }
}
