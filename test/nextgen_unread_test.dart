import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/data/seen_chats.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:hermes_android/nextgen/ui/sessions_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _row(
  String id,
  double lastActive, {
  String source = 'desktop',
  bool unread = false,
  double? lastReadAt,
  String title = '',
  bool active = false,
}) => Session(
  id: id,
  title: title.isEmpty ? 'Chat $id' : title,
  model: 'm',
  source: source,
  messageCount: 2,
  isActive: active,
  preview: '',
  startedAt: 1000,
  lastActive: lastActive,
  unread: unread,
  lastReadAt: lastReadAt,
);

SavedConnection _conn() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
);

void main() {
  group('seen chats', () {
    test('activity after the last look here is unread', () {
      final seen = NgSeenChats(since: 2000, chats: {'a': 3000});
      expect(seen.isUnread(_row('a', 2999)), isFalse);
      expect(seen.isUnread(_row('a', 3000.5)), isFalse, reason: 'slack');
      expect(seen.isUnread(_row('a', 3100)), isTrue);
      // Never looked at: anything since tracking began is news.
      expect(seen.isUnread(_row('b', 1500)), isFalse);
      expect(seen.isUnread(_row('b', 2500)), isTrue);
    });

    test('the gateway watermark wins, unless a later look here', () {
      final seen = NgSeenChats(since: 0, chats: {'a': 5000});
      expect(seen.isUnread(_row('a', 4000, lastReadAt: 3000)), isFalse);
      expect(
        seen.isUnread(_row('b', 4000, lastReadAt: 3000, unread: true)),
        isTrue,
      );
      expect(seen.isUnread(_row('b', 2000, lastReadAt: 3000)), isFalse);
      // Zero is an explicit mark-unread elsewhere: a look here doesn't hide it.
      expect(
        seen.isUnread(_row('a', 4000, lastReadAt: 0, unread: true)),
        isTrue,
      );
    });

    test('messaging-platform chats need a flag or a turn left running', () {
      final seen = NgSeenChats(since: 0, chats: {'t': 100});
      expect(seen.isUnread(_row('t', 500, source: 'telegram')), isFalse);
      expect(seen.isUnread(_row('t', 500, source: 'cron')), isTrue);
      seen.leftRunning.add('t');
      expect(seen.isUnread(_row('t', 500, source: 'telegram')), isTrue);
    });

    test(
      'the store persists looks and marks, and a look clears a mark',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = NgSeenStore(prefs, 'c1');
        store.markLooked('a', 9e9);
        store.markUnread('b');
        final again = NgSeenStore(prefs, 'c1');
        expect(again.chats.chats['a'], 9e9);
        expect(again.chats.isUnread(_row('b', 1)), isTrue);
        again.markLooked('b', 9e9);
        expect(again.chats.isUnread(_row('b', 1)), isFalse);
        expect(NgSeenStore(prefs, 'other').chats.chats, isEmpty);
      },
    );

    test('rows parse the gateway read state', () {
      final s = Session.fromJson({
        'id': 'x',
        'unread': true,
        'last_read_at': 12.5,
        'started_at': 1,
      });
      expect(s.unread, isTrue);
      expect(s.lastReadAt, 12.5);
      expect(s.withTitle('t').lastReadAt, 12.5);
      expect(Session.fromJson({'id': 'y'}).lastReadAt, isNull);
    });
  });

  testWidgets('sidebar highlights unread chats and badges its button', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    SharedPreferences.setMockInitialValues({
      'nextgen.seen_chats.c1':
          '{"since": ${now - 3600}, "chats": {"read": $now}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final conn = _conn();
    final gateway = NextGenGateway(conn);
    addTearDown(gateway.dispose);
    late NgSessionsModel model;
    await tester.pumpWidget(
      MaterialApp(
        theme: nextGenTheme(Brightness.light, NextGenLook.instance),
        home: NgScope(
          connManager: ConnectionManager(prefs),
          gateway: gateway,
          connections: [conn],
          switchTo: (_) async {},
          addGateway: () async {},
          signOut: (_) async {},
          reload: () async {},
          signInAgain: () async {},
          child: Builder(
            builder: (context) {
              model = NgSessionsModel(NgScope.of(context))
                ..sessions = [
                  _row('new', now - 10, title: 'Has news'),
                  _row('read', now - 20, title: 'Already read'),
                  _row('open', now - 5, title: 'On screen'),
                ]
                ..currentId = 'open';
              return Scaffold(
                body: NgSessionsSidebar(
                  model: model,
                  currentSessionId: 'open',
                  onOpen: (_) {},
                  onNewChat: () {},
                  onDestination: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ng-session-new-finished')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ng-session-read')), findsOneWidget);
    // The chat on screen is never unread.
    expect(find.byKey(const ValueKey('ng-session-open')), findsOneWidget);
    expect(model.unreadCount, 1);
    final title = tester.widget<Text>(find.text('Has news'));
    expect(title.style?.fontWeight, FontWeight.w700);

    // Needs you lists unread chats too.
    expect(find.text('Needs you · 1'), findsOneWidget);

    // Running with unread updates is blue; waiting on you is orange, read
    // or not.
    expect(
      model.attentionOf(_row('run', now - 1, active: true)),
      NgChatAttention.updates,
    );
    expect(
      model.attentionOf(_row('read', now - 20), needsYou: {'read'}),
      NgChatAttention.waiting,
    );
    expect(model.attentionOf(_row('read', now - 20)), NgChatAttention.none);
    expect(model.topAttention, NgChatAttention.finished);

    model.markRead('new');
    await tester.pump();
    expect(find.byKey(const ValueKey('ng-session-new')), findsOneWidget);
    expect(model.unreadCount, 0);

    // sessions.changed from the gateway reads the list again (debounced).
    gateway.debugEmit(StreamEvent(type: 'sessions.changed', data: const {}));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    model.dispose();
  });
}
