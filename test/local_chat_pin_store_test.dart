import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _session(String id, {bool serverPinned = false}) => Session(
  id: id,
  title: id,
  model: 'test',
  source: 'gateway',
  messageCount: 1,
  isActive: false,
  preview: '',
  startedAt: 1,
  pinned: serverPinned,
);

Map<String, dynamic> _metadata(
  String id, {
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'title': id,
  'model': 'test',
  'source': 'gateway',
  'message_count': 1,
  'started_at': 1,
  ...extra,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'pins are ordered, scoped by connection, and independent of server pins',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final first = LocalChatPinStore(prefs, connectionId: 'a');
      final second = LocalChatPinStore(prefs, connectionId: 'b');
      final serverPinned = _session('server', serverPinned: true);

      await first.setPinned('old', pinned: true);
      await first.setPinned('new', pinned: true);
      expect(await first.load(), ['new', 'old']);
      expect(await second.load(), isEmpty);
      expect(
        orderLocalPinnedChats([
          serverPinned,
          _session('old'),
          _session('new'),
        ], await first.load()).map((row) => row.id),
        ['new', 'old', 'server'],
      );
      expect(serverPinned.pinned, isTrue);

      await first.removeSession('new');
      expect(await first.load(), ['old']);
      await LocalChatPinStore.removeConnection(prefs, 'a');
      expect(await first.load(), isEmpty);
    },
  );

  test('parallel writes from two screens retain both pins', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = LocalChatPinStore(prefs, connectionId: 'same');
    final second = LocalChatPinStore(prefs, connectionId: 'same');

    await Future.wait([
      first.setPinned('a', pinned: true),
      second.setPinned('b', pinned: true),
    ]);
    expect(await first.load(), ['b', 'a']);
  });

  test('backups include the device-local pin list', () {
    expect(
      ConfigBackupService.isBackedUpKey(
        '${LocalChatPinStore.keyPrefix}gateway',
      ),
      isTrue,
    );
  });

  test(
    'rich title lookup restores old pins without modifying the server',
    () async {
      final requests = <String>[];
      final client = ApiClient(
        baseUrl: 'https://example.test',
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/sessions') {
            final title = request.url.queryParameters['title'];
            final row = title == 'old'
                ? _metadata(
                    'old',
                    extra: {'preview': 'searchable text', 'last_active': 50},
                  )
                : _metadata('different');
            return http.Response(
              jsonEncode({
                'data': [row],
              }),
              200,
            );
          }
          final id = request.url.pathSegments.last;
          if (id == 'gone') return http.Response('', 404);
          final extra = switch (id) {
            'hidden' => {'hidden': true},
            'archived' => {'archived': true},
            'child' => {'is_internal_child': true},
            'mismatch' => {'id': 'different'},
            _ => <String, dynamic>{},
          };
          return http.Response(
            jsonEncode({'session': _metadata(id, extra: extra)}),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final result = await loadUnlistedLocalPins(
        client,
        [_session('recent')],
        ['recent', 'old', 'gone', 'hidden', 'archived', 'child', 'mismatch'],
      );
      expect(result.map((s) => s.id), ['old']);
      expect(result.single.preview, 'searchable text');
      expect(result.single.lastActive, 50);
      expect(requests, contains('GET /api/sessions/old'));
      expect(requests.every((request) => request.startsWith('GET ')), isTrue);
    },
  );

  test('a pin on a compression root follows the rich live tip once', () async {
    final requests = <String>[];
    final client = ApiClient(
      baseUrl: 'https://example.test',
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url}');
        if (request.url.path == '/api/sessions/root') {
          return http.Response(
            jsonEncode({
              'session': _metadata(
                'root',
                extra: {'title': 'Research', 'end_reason': 'compression'},
              ),
            }),
            200,
          );
        }
        if (request.url.queryParameters['title'] == 'Research') {
          return http.Response(
            jsonEncode({
              'data': [
                _metadata(
                  'tip',
                  extra: {
                    'title': 'Research',
                    '_lineage_root_id': 'root',
                    'preview': 'current reply',
                    'last_active': 500,
                  },
                ),
              ],
            }),
            200,
          );
        }
        return http.Response('', 404);
      }),
    );
    addTearDown(client.close);
    final pins = ['root'];
    final recovered = await loadUnlistedLocalPins(client, [
      _session('recent'),
    ], pins);
    expect(recovered.map((s) => s.id), ['tip']);
    expect(recovered.single.preview, 'current reply');
    expect(recovered.single.lastActive, 500);
    expect(recovered.single.lineageRootId, 'root');
    expect(localPinIdForSession(recovered.single, pins), 'root');
    expect(
      orderLocalPinnedChats([
        _session('recent'),
        ...recovered,
      ], pins).map((s) => s.id),
      ['tip', 'recent'],
    );
    final previousCalls = requests.length;
    expect(await loadUnlistedLocalPins(client, recovered, pins), isEmpty);
    expect(
      requests.length,
      previousCalls,
      reason: 'the projected tip already represents the pinned root',
    );
  });
}
