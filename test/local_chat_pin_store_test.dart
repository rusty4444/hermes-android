import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _error(String code, int status) => _json({
  'error': {'code': code, 'message': code},
}, status);

/// A minimal API server that owns `pinned` per id, like `hermes_state`.
class _Server {
  final Map<String, Map<String, dynamic>> rows;
  final requests = <String>[];
  final patches = <String, Map<String, dynamic>>{};
  http.Response? Function(http.Request request)? override;

  _Server(this.rows);

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    final forced = override?.call(request);
    if (forced != null) return forced;
    final id = Uri.decodeComponent(request.url.pathSegments.last);
    final row = rows[id];
    if (row == null) return _error('session_not_found', 404);
    if (request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patches[id] = body;
      row.addAll(body);
    }
    return _json({
      'session': {'id': id, 'pinned': false, ...row},
    });
  }
}

ApiClient _client(_Server server) {
  final http = MockClient(server.handle);
  addTearDown(http.close);
  return ApiClient(
    baseUrl: 'https://gateway.example',
    apiKey: 'test-key',
    httpClient: http,
  );
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('legacy pins stay scoped by connection until removed', () async {
    final first = LocalChatPinStore(prefs, connectionId: 'a');
    final second = LocalChatPinStore(prefs, connectionId: 'b');
    await first.setPinned('old', pinned: true);
    await first.setPinned('new', pinned: true);
    expect(await first.load(), ['new', 'old']);
    expect(await second.load(), isEmpty);
    await first.removeSession('new');
    expect(await first.load(), ['old']);
    await LocalChatPinStore.removeConnection(prefs, 'a');
    expect(await first.load(), isEmpty);
  });

  test('parallel legacy writes retain both ids', () async {
    final first = LocalChatPinStore(prefs, connectionId: 'same');
    final second = LocalChatPinStore(prefs, connectionId: 'same');
    await Future.wait([
      first.setPinned('a', pinned: true),
      second.setPinned('b', pinned: true),
    ]);
    expect(await first.load(), ['b', 'a']);
  });

  test('backups still carry unmigrated legacy pins', () {
    expect(
      ConfigBackupService.isBackedUpKey('${LocalChatPinStore.keyPrefix}gw'),
      isTrue,
    );
  });

  test(
    'migration pins each legacy chat on the server, then forgets it',
    () async {
      final server = _Server({
        'plain': {},
        'already': {'pinned': true},
        'archived': {'archived': true},
        'hidden': {'hidden': true},
        'child': {'is_internal_child': true},
      });
      final store = LocalChatPinStore(prefs, connectionId: 'gw');
      for (final id in [
        'gone',
        'child',
        'hidden',
        'archived',
        'already',
        'plain',
      ]) {
        await store.setPinned(id, pinned: true);
      }

      expect(await migrateLegacyChatPins(_client(server), store), 1);

      expect(server.patches, {
        'plain': {'pinned': true},
      });
      expect(server.rows['plain']!['pinned'], isTrue);
      expect(
        server.requests,
        containsAllInOrder([
          'GET /api/sessions/plain',
          'PATCH /api/sessions/plain',
          'GET /api/sessions/plain',
        ]),
      );
      expect(await store.load(), isEmpty);
    },
  );

  test('failures keep legacy pins for a later attempt', () async {
    final server = _Server({'flaky': {}, 'mismatch': {}, 'bare404': {}});
    server.override = (request) {
      final id = request.url.pathSegments.last;
      if (id == 'flaky') return http.Response('offline', 503);
      if (id == 'bare404') return http.Response('Not Found', 404);
      if (id == 'mismatch' && request.method == 'PATCH') {
        return _json({
          'session': {'id': 'mismatch', 'pinned': false},
        });
      }
      return null;
    };
    final store = LocalChatPinStore(prefs, connectionId: 'gw');
    for (final id in ['bare404', 'mismatch', 'flaky']) {
      await store.setPinned(id, pinned: true);
    }

    expect(await migrateLegacyChatPins(_client(server), store), 0);
    expect(await store.load(), ['flaky', 'mismatch', 'bare404']);

    server.override = null;
    expect(await migrateLegacyChatPins(_client(server), store), 3);
    expect(await store.load(), isEmpty);
  });

  test('a gateway without synced pins keeps every legacy pin', () async {
    final server = _Server({'a': {}, 'b': {}});
    server.override = (request) => request.method == 'PATCH'
        ? _error('unsupported_session_field', 400)
        : null;
    final store = LocalChatPinStore(prefs, connectionId: 'gw');
    await store.setPinned('b', pinned: true);
    await store.setPinned('a', pinned: true);

    expect(await migrateLegacyChatPins(_client(server), store), 0);
    expect(await store.load(), ['a', 'b']);
    expect(
      server.requests.where((request) => request.startsWith('PATCH')),
      hasLength(1),
      reason: 'the first rejection proves the gateway lacks the field',
    );
  });

  test('concurrent screens share one migration', () async {
    final held = Completer<void>();
    final server = _Server({'a': {}});
    final store = LocalChatPinStore(prefs, connectionId: 'gw');
    await store.setPinned('a', pinned: true);
    final client = ApiClient(
      baseUrl: 'https://gateway.example',
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        await held.future;
        return server.handle(request);
      }),
    );
    addTearDown(client.close);

    final first = migrateLegacyChatPins(client, store);
    final second = migrateLegacyChatPins(client, store);
    expect(identical(first, second), isTrue);
    held.complete();
    expect(await first, 1);
    expect(server.patches.keys, ['a']);
  });
}
