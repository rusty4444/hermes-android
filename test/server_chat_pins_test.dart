import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/chat_pins.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';

const _now = 1750000000.0;

Session _session(
  String id,
  String title, {
  double activity = _now,
  bool pinned = false,
  String? root,
}) => Session(
  id: id,
  title: title,
  model: 'test',
  source: 'gateway',
  messageCount: 1,
  isActive: false,
  preview: '',
  startedAt: activity,
  lastActive: activity,
  pinned: pinned,
  lineageRootId: root,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

ApiClient _api(Future<http.Response> Function(http.Request) handler) {
  final client = MockClient(handler);
  addTearDown(client.close);
  return ApiClient(
    baseUrl: 'https://gateway.example',
    apiKey: 'test-key',
    httpClient: client,
  );
}

MaterialApp _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: child,
);

/// Server-side state shared with "Hermes Desktop": the `pinned` column.
class _Host {
  final rows = <String, Map<String, dynamic>>{};
  final requests = <String>[];

  void add(
    String id,
    String title, {
    double activity = _now,
    bool pinned = false,
  }) {
    rows[id] = {
      'id': id,
      'title': title,
      'model': 'test',
      'source': 'gateway',
      'message_count': 1,
      'preview': '',
      'started_at': activity,
      'last_active': activity,
      'pinned': pinned,
    };
  }

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    requests.add(
      '${request.method} $path${request.method == 'PATCH' ? ' ${request.body}' : ''}',
    );
    if (path == '/health') return _json({});
    if (path == '/api/sessions') {
      final offset = request.url.queryParameters['offset'];
      final page = offset == null || offset == '0'
          ? rows.values.toList()
          : <Map<String, dynamic>>[];
      return _json({'data': page, 'has_more': false});
    }
    if (path.startsWith('/api/sessions/')) {
      final id = Uri.decodeComponent(request.url.pathSegments.last);
      final row = rows[id];
      if (row == null) {
        return _json({
          'error': {'code': 'session_not_found'},
        }, 404);
      }
      if (request.method == 'PATCH') {
        row.addAll(jsonDecode(request.body) as Map<String, dynamic>);
      }
      return _json({'session': row});
    }
    return http.Response('unexpected', 404);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiClient.setSessionPinned', () {
    for (final pinned in [true, false]) {
      test(
        'PATCHes only `pinned`=$pinned and verifies the read-back',
        () async {
          final requests = <String>[];
          final api = _api((request) async {
            requests.add(
              '${request.method} ${request.url.path} ${request.body}',
            );
            return _json({
              'session': {'id': 'chat/1', 'pinned': pinned},
            });
          });
          expect(
            await api.setSessionPinned(sessionId: 'chat/1', pinned: pinned),
            pinned,
          );
          expect(requests, [
            'PATCH /api/sessions/chat%2F1 ${jsonEncode({'pinned': pinned})}',
            'GET /api/sessions/chat%2F1 ',
          ]);
        },
      );
    }

    test('a mismatched acknowledgement or read-back is not success', () async {
      for (final mismatch in ['patch', 'read']) {
        final api = _api((request) async {
          final stale = (mismatch == 'patch') == (request.method == 'PATCH');
          return _json({
            'session': {'id': 'chat', 'pinned': !stale},
          });
        });
        await expectLater(
          api.setSessionPinned(sessionId: 'chat', pinned: true),
          throwsFormatException,
          reason: mismatch,
        );
      }
      final wrongId = _api(
        (_) async => _json({
          'session': {'id': 'other', 'pinned': true},
        }),
      );
      await expectLater(
        wrongId.setSessionPinned(sessionId: 'chat', pinned: true),
        throwsFormatException,
      );
    });

    test('maps the gateway error codes', () async {
      final old = _api(
        (_) async => _json({
          'error': {'code': 'unsupported_session_field'},
        }, 400),
      );
      await expectLater(
        old.setSessionPinned(sessionId: 'chat', pinned: true),
        throwsA(isA<SyncedPinsUnsupportedException>()),
      );
      final gone = _api(
        (_) async => _json({
          'error': {'code': 'session_not_found'},
        }, 404),
      );
      await expectLater(
        gone.setSessionPinned(sessionId: 'chat', pinned: true),
        throwsA(isA<SessionNotFoundException>()),
      );
      final bare = _api((_) async => http.Response('Not Found', 404));
      await expectLater(
        bare.setSessionPinned(sessionId: 'chat', pinned: true),
        throwsA(isNot(isA<SessionNotFoundException>())),
      );
    });

    test('archiving a pinned chat clears its pin in the same PATCH', () async {
      final bodies = <String>[];
      final api = _api((request) async {
        if (request.method == 'PATCH') bodies.add(request.body);
        return _json({
          'session': {'id': 'chat', 'archived': true, 'pinned': false},
        });
      });
      expect(
        await api.setSessionArchived(
          sessionId: 'chat',
          archived: true,
          clearPin: true,
        ),
        isTrue,
      );
      expect(
        await api.setSessionArchived(sessionId: 'chat', archived: true),
        isTrue,
      );
      expect(bodies, [
        jsonEncode({'archived': true, 'pinned': false}),
        jsonEncode({'archived': true}),
      ]);
    });
  });

  group('ConfirmedChatPins', () {
    test('overrides only reads that began before the confirmed write', () {
      final pins = ConfirmedChatPins();
      final row = _session('tip', 'Chat', root: 'root');
      pins.record(_session('root', 'Chat'), true, 2);
      expect(pins.apply(row, 1).pinned, isTrue, reason: 'stale read');
      expect(pins.apply(row, 2).pinned, isFalse, reason: 'fresh read wins');
      pins.record(row, false, 3);
      expect(pins.apply(row.withPinned(true), 1).pinned, isFalse);
      expect(pins.apply(_session('other', 'Other'), 0).pinned, isFalse);
    });

    test('orders pinned chats first without reordering each group', () {
      expect(
        orderPinnedChatsFirst([
          _session('a', 'a'),
          _session('b', 'b', pinned: true),
          _session('c', 'c'),
          _session('d', 'd', pinned: true),
        ]).map((row) => row.id),
        ['b', 'd', 'a', 'c'],
      );
    });
  });

  testWidgets(
    'Workspace Chats shows server pins first and writes the shared flag',
    (tester) async {
      final now = DateTime.fromMillisecondsSinceEpoch((_now * 1000).toInt());
      final server = <String, bool>{'old': true, 'recent': false};
      WorkspaceSessionsData data() => WorkspaceSessionsData(
        sessions: [
          _session('recent', 'Recent chat', pinned: server['recent']!),
          _session(
            'old',
            'Older chat',
            activity: _now - 86400 * 20,
            pinned: server['old']!,
          ),
        ],
      );
      final writes = <(String, bool)>[];
      Completer<WorkspaceSessionsData>? held;
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: WorkspaceSessionsScreen(
              key: key,
              title: 'Chats',
              view: WorkspaceSessionView.all,
              embedded: true,
              now: now,
              load: () {
                final snapshot = data();
                return held?.future ?? Future.value(snapshot);
              },
              onOpenSession: (_) {},
              onPin: (session, pinned) async {
                writes.add((session.id, pinned));
                server[session.id] = pinned;
                return pinned;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pinned on Hermes Desktop: it leads the date groups here too.
      expect(find.text('Pinned'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Older chat')).dy,
        lessThan(tester.getTopLeft(find.text('Recent chat')).dy),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Recent'));
      await tester.pumpAndSettle();
      expect(
        find.text('Older chat'),
        findsNothing,
        reason: 'pins must not bypass the active filter',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();

      // A list read already in flight cannot undo a confirmed unpin.
      held = Completer();
      final staleRead = data();
      unawaited(key.currentState!.refresh());
      await tester.pump();
      Future<void> menu(String title, String action) async {
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text(title),
              matching: find.byType(HermesCard),
            ),
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(action).last);
        await tester.pumpAndSettle();
      }

      await menu('Older chat', 'Unpin chat');
      expect(writes, [('old', false)]);
      expect(find.text('Pinned'), findsNothing);
      held.complete(staleRead);
      held = null;
      await tester.pumpAndSettle();
      expect(find.text('Pinned'), findsNothing);

      // A later read adopts a pin set elsewhere (another device).
      server['recent'] = true;
      await key.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Pinned'), findsOneWidget);
      await menu('Recent chat', 'Unpin chat');
      await menu('Older chat', 'Pin chat');
      expect(writes, [('old', false), ('recent', false), ('old', true)]);
      expect(
        tester.getTopLeft(find.text('Older chat')).dy,
        lessThan(tester.getTopLeft(find.text('Recent chat')).dy),
      );
    },
  );

  testWidgets('a failed server pin keeps the row and offers Retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            load: () async =>
                WorkspaceSessionsData(sessions: [_session('a', 'Chat A')]),
            onOpenSession: (_) {},
            onPin: (_, _) async => throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin chat').last);
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsNothing);
    expect(find.textContaining('Could not update chat pin'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  group('legacy Chats screen', () {
    late GatewayTurnApplicationController controller;
    final connection = SavedConnection(
      id: 'legacy',
      label: 'Local Gateway',
      host: 'fixture.test',
      port: 8642,
      apiKey: 'test-key',
    );
    setUp(() {
      controller = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
    });
    tearDown(() => controller.close());

    Widget screen(_Host host) => _app(
      SessionListScreen(
        connection: connection,
        turnApplicationController: controller,
        testHttpClient: MockClient(host.handle),
        testSessionPageSize: 2,
      ),
    );

    Future<void> menu(WidgetTester tester, String title, String action) async {
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text(title),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
    }

    double top(WidgetTester tester, String title) =>
        tester.getTopLeft(find.text(title)).dy;

    testWidgets('pins and unpins through the shared server flag', (
      tester,
    ) async {
      final host = _Host()
        ..add('recent', 'Recent chat')
        ..add('old', 'Older chat', activity: _now - 100);
      await tester.pumpWidget(screen(host));
      await tester.pumpAndSettle();
      expect(top(tester, 'Recent chat'), lessThan(top(tester, 'Older chat')));

      await menu(tester, 'Older chat', 'Pin chat');
      expect(host.rows['old']!['pinned'], isTrue);
      expect(
        host.requests,
        containsAllInOrder([
          'PATCH /api/sessions/old {"pinned":true}',
          'GET /api/sessions/old',
        ]),
      );
      expect(top(tester, 'Older chat'), lessThan(top(tester, 'Recent chat')));

      // Reopening reads the pin back from the server, not the device.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(host));
      await tester.pumpAndSettle();
      expect(top(tester, 'Older chat'), lessThan(top(tester, 'Recent chat')));
      expect(
        await LocalChatPinStore(
          await SharedPreferences.getInstance(),
          connectionId: connection.id,
        ).load(),
        isEmpty,
      );

      await menu(tester, 'Older chat', 'Unpin chat');
      expect(host.rows['old']!['pinned'], isFalse);
      expect(top(tester, 'Recent chat'), lessThan(top(tester, 'Older chat')));
    });

    testWidgets('a pin made on Hermes Desktop appears on refresh', (
      tester,
    ) async {
      final host = _Host()
        ..add('recent', 'Recent chat')
        ..add('old', 'Older chat', activity: _now - 100, pinned: true);
      await tester.pumpWidget(screen(host));
      await tester.pumpAndSettle();
      expect(top(tester, 'Older chat'), lessThan(top(tester, 'Recent chat')));
      expect(
        host.requests.where((request) => request.startsWith('PATCH')),
        isEmpty,
      );
    });

    testWidgets('device pins from older releases move to the server', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await LocalChatPinStore(
        prefs,
        connectionId: connection.id,
      ).setPinned('old', pinned: true);
      final host = _Host()
        ..add('recent', 'Recent chat')
        ..add('old', 'Older chat', activity: _now - 100);
      await tester.pumpWidget(screen(host));
      await tester.pumpAndSettle();

      expect(host.rows['old']!['pinned'], isTrue);
      expect(
        host.requests,
        contains('PATCH /api/sessions/old {"pinned":true}'),
      );
      expect(
        await LocalChatPinStore(prefs, connectionId: connection.id).load(),
        isEmpty,
      );
      expect(top(tester, 'Older chat'), lessThan(top(tester, 'Recent chat')));
    });
  });
}
