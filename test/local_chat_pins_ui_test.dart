import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';

const _now = 1750000000.0;

Session _session(String id, String title, {double activity = _now}) => Session(
  id: id,
  title: title,
  model: 'test',
  source: 'gateway',
  messageCount: 1,
  isActive: false,
  preview: '',
  startedAt: activity,
  lastActive: activity,
);

Map<String, dynamic> _row(String id, String title) => {
  'id': id,
  'title': title,
  'model': 'test',
  'source': 'gateway',
  'message_count': 1,
  'preview': '',
  'started_at': _now,
  'last_active': _now,
};

MaterialApp _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: child,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Workspace pins are device-only, above date groups, and survive reopening',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalChatPinStore(prefs, connectionId: 'workspace');
      final now = DateTime.fromMillisecondsSinceEpoch((_now * 1000).toInt());
      final old = _session('old', 'Older chat', activity: _now - 86400 * 20);
      final recent = _session('recent', 'Recent chat');
      final data = WorkspaceSessionsData(sessions: [recent, old]);
      Widget screen() => WorkspaceSessionsScreen(
        title: 'Chats',
        view: WorkspaceSessionView.all,
        embedded: true,
        now: now,
        pinStore: store,
        load: () async => data,
        onOpenSession: (_) {},
      );

      await tester.pumpWidget(_app(screen()));
      await tester.pumpAndSettle();
      final oldRow = find.ancestor(
        of: find.text('Older chat'),
        matching: find.byType(HermesCard),
      );
      await tester.tap(
        find.descendant(
          of: oldRow,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin on this device').last);
      await tester.pumpAndSettle();

      expect(await store.load(), ['old']);
      expect(old.pinned, isFalse);
      expect(find.text('Pinned on this device'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Older chat')).dy,
        lessThan(tester.getTopLeft(find.text('Recent chat')).dy),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Recent'));
      await tester.pumpAndSettle();
      expect(
        find.text('Older chat'),
        findsNothing,
        reason: 'local pins must not bypass the active filter',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(screen()));
      await tester.pumpAndSettle();
      expect(find.text('Pinned on this device'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Older chat')).dy,
        lessThan(tester.getTopLeft(find.text('Recent chat')).dy),
      );

      final reopenedRow = find.ancestor(
        of: find.text('Older chat'),
        matching: find.byType(HermesCard),
      );
      await tester.tap(
        find.descendant(
          of: reopenedRow,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin on this device').last);
      await tester.pumpAndSettle();
      expect(await store.load(), isEmpty);
      expect(find.text('Pinned on this device'), findsNothing);
    },
  );

  testWidgets('a retained Chats pane reloads a pin on a compressed chat', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = LocalChatPinStore(prefs, connectionId: 'shared');
    final tip = Session(
      id: 'tip',
      lineageRootId: 'root',
      title: 'Continued chat',
      model: 'test',
      source: 'gateway',
      messageCount: 1,
      isActive: false,
      preview: '',
      startedAt: _now - 100,
      lastActive: _now - 100,
    );
    Widget pane(bool active) => _app(
      HermesPaneVisibility(
        active: active,
        child: WorkspaceSessionsScreen(
          title: 'Chats',
          view: WorkspaceSessionView.all,
          embedded: true,
          pinStore: store,
          load: () async => WorkspaceSessionsData(
            sessions: [_session('new', 'Newer chat'), tip],
          ),
          onOpenSession: (_) {},
        ),
      ),
    );

    await tester.pumpWidget(pane(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(pane(false));
    await tester.pumpAndSettle();
    await LocalChatPinStore(
      prefs,
      connectionId: 'shared',
    ).setPinned('root', pinned: true);
    await tester.pumpWidget(pane(true));
    await tester.pumpAndSettle();
    expect(find.text('Pinned on this device'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Continued chat')).dy,
      lessThan(tester.getTopLeft(find.text('Newer chat')).dy),
    );

    final tipRow = find.ancestor(
      of: find.text('Continued chat'),
      matching: find.byType(HermesCard),
    );
    await tester.tap(
      find.descendant(
        of: tipRow,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unpin on this device'), findsOneWidget);
    await tester.tap(find.text('Unpin on this device'));
    await tester.pumpAndSettle();
    expect(await store.load(), isEmpty);
  });

  testWidgets('legacy Chats keeps an old local pin above newer paged chats', (
    tester,
  ) async {
    var refreshed = false;
    final requests = <String>[];
    final httpClient = MockClient((request) async {
      requests.add('${request.method} ${request.url}');
      if (request.url.path == '/health') return http.Response('{}', 200);
      if (request.url.path == '/api/sessions') {
        if (request.url.queryParameters['title'] == 'Older chat') {
          return http.Response(
            jsonEncode({
              'data': [_row('old', 'Older chat')],
            }),
            200,
          );
        }
        final offset = request.url.queryParameters['offset'];
        if (offset == null) return http.Response('{"data":[]}', 200);
        final rows = offset == '0'
            ? refreshed
                  ? [_row('recent', 'Recent chat'), _row('new', 'Newest chat')]
                  : [_row('old', 'Older chat'), _row('recent', 'Recent chat')]
            : <Map<String, dynamic>>[];
        return http.Response(
          jsonEncode({'data': rows, 'has_more': false}),
          200,
        );
      }
      if (request.url.path == '/api/sessions/old') {
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response(
          jsonEncode({'session': _row('old', 'Older chat')}),
          200,
        );
      }
      return http.Response('unexpected request', 404);
    });
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(controller.close);
    final connection = SavedConnection(
      id: 'legacy',
      label: 'Local Gateway',
      host: 'fixture.test',
      port: 8642,
      apiKey: 'test-key',
    );
    Widget screen() => SessionListScreen(
      connection: connection,
      turnApplicationController: controller,
      testHttpClient: httpClient,
      testSessionPageSize: 2,
    );
    await tester.pumpWidget(_app(screen()));
    await tester.pumpAndSettle();
    final oldTile = find.ancestor(
      of: find.text('Older chat'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: oldTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin on this device').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(await LocalChatPinStore(prefs, connectionId: 'legacy').load(), [
      'old',
    ]);
    refreshed = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(screen()));
    await tester.pumpAndSettle();

    expect(find.text('Older chat'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Older chat')).dy,
      lessThan(tester.getTopLeft(find.text('Recent chat')).dy),
    );
    expect(requests.any((r) => r.contains('/api/sessions/old')), isTrue);
    expect(
      requests.every((r) => r.startsWith('GET ')),
      isTrue,
      reason: 'pinning must not PATCH the remote session',
    );
    final pinnedTile = find.ancestor(
      of: find.text('Older chat'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: pinnedTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(
      await LocalChatPinStore(prefs, connectionId: 'legacy').load(),
      isEmpty,
    );
    expect(find.text('Older chat'), findsNothing);
  });
}
