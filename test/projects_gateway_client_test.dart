import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_project.dart';
import 'package:hermes_android/core/services/capability_registry.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';

/// Records the JSON-RPC calls a test makes and replays canned envelopes.
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

Map<String, dynamic> _projectJson({
  String id = 'p1',
  String slug = 'hermes-android',
  String name = 'Hermes Android',
  bool archived = false,
  List<Map<String, dynamic>>? folders,
}) {
  return {
    'id': id,
    'slug': slug,
    'name': name,
    'description': 'Android daily driver',
    'icon': 'phone',
    'color': '#D4AF37',
    'board_slug': null,
    'primary_path': '/home/carlos/dev/hermes-android',
    'archived': archived,
    'created_at': 1750000000,
    'folders':
        folders ??
        [
          {
            'path': '/home/carlos/dev/hermes-android',
            'label': 'app',
            'is_primary': true,
            'added_at': 1750000000,
          },
        ],
  };
}

void main() {
  group('HermesProject', () {
    test('parses the Gateway projects.* record shape', () {
      final project = HermesProject.fromJson(_projectJson());

      expect(project.id, 'p1');
      expect(project.slug, 'hermes-android');
      expect(project.name, 'Hermes Android');
      expect(project.description, 'Android daily driver');
      expect(project.primaryPath, '/home/carlos/dev/hermes-android');
      expect(project.archived, isFalse);
      expect(project.folders, hasLength(1));
      expect(project.folders.single.isPrimary, isTrue);
      expect(project.folders.single.label, 'app');
    });

    test('tolerates a minimal record without optional metadata', () {
      final project = HermesProject.fromJson({
        'id': 'p2',
        'slug': 'scripthive',
        'name': 'ScriptHive',
        'created_at': 1750000001,
      });

      expect(project.description, isNull);
      expect(project.icon, isNull);
      expect(project.color, isNull);
      expect(project.primaryPath, isNull);
      expect(project.archived, isFalse);
      expect(project.folders, isEmpty);
    });

    test('rejects a record without a usable identity', () {
      expect(
        () => HermesProject.fromJson({'slug': 'no-id', 'name': 'No id'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('snapshot separates active from archived projects', () {
      final snapshot = ProjectsSnapshot.fromJson({
        'projects': [
          _projectJson(),
          _projectJson(id: 'p2', slug: 'old', name: 'Old', archived: true),
        ],
        'active_id': 'p1',
      });

      expect(snapshot.projects, hasLength(2));
      expect(snapshot.activeId, 'p1');
      expect(snapshot.active.map((p) => p.id), ['p1']);
      expect(snapshot.archived.map((p) => p.id), ['p2']);
      expect(snapshot.activeProject?.name, 'Hermes Android');
    });

    test('snapshot ignores an active id that no longer exists', () {
      final snapshot = ProjectsSnapshot.fromJson({
        'projects': [_projectJson()],
        'active_id': 'deleted',
      });

      expect(snapshot.activeId, isNull);
      expect(snapshot.activeProject, isNull);
    });
  });

  group('ProjectsGatewayClient', () {
    test('lists projects through the native projects.list RPC', () async {
      final rpc = _RecordingRpc([
        _ok({
          'projects': [_projectJson()],
          'active_id': 'p1',
        }),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      final snapshot = await client.list();

      expect(rpc.calls.single.method, 'projects.list');
      expect(rpc.calls.single.params, isEmpty);
      expect(snapshot.projects.single.name, 'Hermes Android');
      expect(snapshot.activeId, 'p1');
    });

    test('reports an unsupported gateway instead of crashing', () async {
      final rpc = _RecordingRpc([
        _error(-32601, 'unknown method: projects.list'),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.list(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );
      expect(await client.isSupported(), isFalse);
    });

    test(
      'caches the unsupported verdict without repeating the probe',
      () async {
        final rpc = _RecordingRpc([
          _error(-32601, 'unknown method: projects.list'),
        ]);
        final client = ProjectsGatewayClient(rpc.call);

        expect(await client.isSupported(), isFalse);
        expect(await client.isSupported(), isFalse);
        expect(rpc.calls, hasLength(1));
      },
    );

    test('a transport failure is not treated as unsupported', () async {
      var calls = 0;
      final client = ProjectsGatewayClient((method, params) async {
        calls++;
        throw JsonRpcError(
          method,
          'Desktop gateway connection closed',
          reason: 'connection_closed',
        );
      });

      await expectLater(client.list(), throwsA(isA<JsonRpcError>()));
      // The verdict stays unknown, so a later probe still asks the gateway.
      await expectLater(client.isSupported(), throwsA(isA<JsonRpcError>()));
      expect(calls, 2);
    });

    test('surfaces a real projects error as a JsonRpcError', () async {
      final rpc = _RecordingRpc([_error(5062, 'no such project')]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.get('missing'),
        throwsA(
          isA<JsonRpcError>()
              .having((e) => e.code, 'code', 5062)
              .having((e) => e.method, 'method', 'projects.get'),
        ),
      );
    });

    test('creates a project and can select it in one call', () async {
      final rpc = _RecordingRpc([
        _ok({'project': _projectJson(id: 'p9', name: 'New')}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      final project = await client.create(name: 'New', use: true);

      expect(rpc.calls.single.method, 'projects.create');
      expect(rpc.calls.single.params['name'], 'New');
      expect(rpc.calls.single.params['use'], isTrue);
      expect(project.id, 'p9');
    });

    test('create refuses a blank name before touching the gateway', () async {
      final rpc = _RecordingRpc([]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.create(name: '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(rpc.calls, isEmpty);
    });

    test('renames a project through projects.update', () async {
      final rpc = _RecordingRpc([
        _ok({'project': _projectJson(name: 'Renamed')}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      final project = await client.rename(id: 'p1', name: 'Renamed');

      expect(rpc.calls.single.method, 'projects.update');
      expect(rpc.calls.single.params, {'id': 'p1', 'name': 'Renamed'});
      expect(project.name, 'Renamed');
    });

    test(
      'archive and restore use the same RPC with an explicit flag',
      () async {
        final rpc = _RecordingRpc([
          _ok({'projects': const [], 'active_id': null}),
          _ok({'projects': const [], 'active_id': null}),
        ]);
        final client = ProjectsGatewayClient(rpc.call);

        await client.archive('p1');
        await client.archive('p1', restore: true);

        expect(rpc.calls.map((c) => c.method), [
          'projects.archive',
          'projects.archive',
        ]);
        expect(rpc.calls.first.params, {'id': 'p1'});
        expect(rpc.calls.last.params, {'id': 'p1', 'restore': true});
      },
    );

    test('clearing the active project sends no id', () async {
      final rpc = _RecordingRpc([
        _ok({'active_id': null}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      final activeId = await client.setActive(null);

      expect(rpc.calls.single.method, 'projects.set_active');
      expect(rpc.calls.single.params, isEmpty);
      expect(activeId, isNull);
    });

    test('re-homes a session workspace via session.workspace.move', () async {
      final rpc = _RecordingRpc([_ok({'ok': true})]);
      final client = ProjectsGatewayClient(rpc.call);

      await client.moveSessionWorkspace(
        sessionKey: '20260829_stored_42',
        cwd: '/srv/projects/app',
      );

      expect(rpc.calls.single.method, 'session.workspace.move');
      expect(rpc.calls.single.params, {
        'session_key': '20260829_stored_42',
        'cwd': '/srv/projects/app',
      });
    });

    test('workspace move rejects blank key or cwd before touching the gateway',
    () async {
      final rpc = _RecordingRpc([]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(
        client.moveSessionWorkspace(sessionKey: ' ', cwd: '/x'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        client.moveSessionWorkspace(sessionKey: 'k', cwd: ' '),
        throwsA(isA<ArgumentError>()),
      );
      expect(rpc.calls, isEmpty);
    });

    test('a successful call marks the gateway as supported', () async {
      final rpc = _RecordingRpc([
        _ok({'projects': const [], 'active_id': null}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      await client.list();

      expect(await client.isSupported(), isTrue);
      expect(rpc.calls, hasLength(1));
    });
  });

  group('ProjectsGatewayClient capability reporting', () {
    test('a successful call teaches the shared registry', () async {
      final registry = CapabilityRegistry();
      final rpc = _RecordingRpc([
        _ok({'projects': const [], 'active_id': null}),
      ]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await client.list();

      expect(registry.supportFor('projects.list'), CapabilitySupport.supported);
    });

    test('an unknown-method error is reported to the registry', () async {
      final registry = CapabilityRegistry();
      final rpc = _RecordingRpc([
        _error(-32601, 'unknown method: projects.list'),
      ]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await expectLater(
        client.list(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );

      expect(
        registry.supportFor('projects.list'),
        CapabilitySupport.unsupported,
      );
    });

    test('a transport failure teaches the registry nothing', () async {
      final registry = CapabilityRegistry();
      final client = ProjectsGatewayClient((method, params) async {
        throw JsonRpcError(
          method,
          'Desktop gateway connection closed',
          reason: 'connection_closed',
        );
      }, capabilities: registry);

      await expectLater(client.list(), throwsA(isA<JsonRpcError>()));

      expect(registry.supportFor('projects.list'), CapabilitySupport.unknown);
    });

    test('a domain error still proves the method exists', () async {
      final registry = CapabilityRegistry();
      final rpc = _RecordingRpc([_error(5062, 'no such project')]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await expectLater(client.get('p9'), throwsA(isA<JsonRpcError>()));

      expect(registry.supportFor('projects.get'), CapabilitySupport.supported);
    });

    test('an already-unsupported registry short-circuits the call', () async {
      final registry = CapabilityRegistry()
        ..recordFailure(
          'projects.list',
          JsonRpcError('projects.list', 'unknown method', code: -32601),
        );
      final rpc = _RecordingRpc([]);
      final client = ProjectsGatewayClient(rpc.call, capabilities: registry);

      await expectLater(
        client.list(),
        throwsA(isA<ProjectsUnsupportedException>()),
      );
      // An old gateway must not be re-probed on every screen build.
      expect(rpc.calls, isEmpty);
    });

    test('works without a registry', () async {
      final rpc = _RecordingRpc([
        _ok({'projects': const [], 'active_id': null}),
      ]);
      final client = ProjectsGatewayClient(rpc.call);

      await expectLater(client.list(), completes);
    });
  });
}
