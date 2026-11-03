import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Credentials implements CredentialStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  String? readCached(String key) => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Push extends MobilePushService {
  _Push() : super(supported: false);
  final queue = <MobilePushRoute>[];
  ConnectionManager? initializedWith;
  bool current = true;
  int takes = 0;
  int checks = 0;
  int rootListeners = 0;

  @override
  void addListener(VoidCallback listener) {
    rootListeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    rootListeners--;
    super.removeListener(listener);
  }

  @override
  Future<void> initialize(ConnectionManager manager) async {
    initializedWith = manager;
    notifyListeners();
  }

  @override
  bool get hasPendingTap => queue.isNotEmpty;

  void ping() => notifyListeners();

  void tap(SavedConnection connection, String session, String event) {
    queue.add(MobilePushRoute(connection, session, event, const {}));
    notifyListeners();
  }

  @override
  Future<MobilePushRoute?> takePendingNotificationRoute() async {
    takes++;
    return queue.isEmpty ? null : queue.removeAt(0);
  }

  @override
  Future<bool> isRouteCurrent(MobilePushRoute route) async {
    checks++;
    return current;
  }
}

Session _session(String id) => Session(
  id: id,
  title: 'Push $id',
  model: '',
  source: 'mobile',
  messageCount: 0,
  isActive: false,
  preview: '',
  startedAt: 1,
);

Future<ConnectionManager> _manager() async {
  final manager = await ConnectionManager.create(
    await SharedPreferences.getInstance(),
    credentialStore: _Credentials(),
  );
  for (final profile in ['alpha', 'beta']) {
    await manager.saveConnection(
      profile,
      'fixture.invalid',
      8642,
      'fixture-key',
      gatewayProfile: profile,
    );
  }
  return manager;
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pendingNotificationApprovals.value = const [];
  });

  testWidgets(
    'newer warm push tap supersedes held cold lookup with exact saved profile',
    (tester) async {
      final manager = await _manager();
      final beta = manager.getConnections().singleWhere(
        (c) => c.gatewayProfile == 'beta',
      );
      final push = _Push()..tap(beta, 'first', 'event-1');
      addTearDown(push.dispose);
      final first = Completer<Session?>();
      final lookups = <(String, String?, String)>[];
      await tester.pumpWidget(
        HermesApp(
          connManager: manager,
          mobilePush: push,
          testNotificationSessionLookup: (connection, id) async {
            lookups.add((connection.id, connection.gatewayProfile, id));
            return id == 'first' ? first.future : _session(id);
          },
        ),
      );
      await _pump(tester);
      expect(identical(push.initializedWith, manager), isTrue);
      expect(lookups, [(beta.id, 'beta', 'first')]);
      push.tap(beta, 'second', 'event-2');
      push.ping();
      await _pump(tester);
      expect(push.takes, 1);
      expect(lookups, hasLength(1));
      first.complete(_session('first'));
      await _pump(tester);
      expect(lookups, [
        (beta.id, 'beta', 'first'),
        (beta.id, 'beta', 'second'),
      ]);
      expect(push.takes, 2);
      expect(push.checks, greaterThanOrEqualTo(6));
      final chats = tester
          .widgetList<ChatScreen>(find.byType(ChatScreen, skipOffstage: false))
          .toList();
      expect(chats.map((c) => c.session.id), ['second']);
      // Newer tap owns focus; the older held lookup must not create a stale route.
      expect(
        chats.every(
          (c) =>
              c.connection.id == beta.id &&
              c.connection.gatewayProfile == beta.gatewayProfile,
        ),
        isTrue,
      );
      expect(pendingNotificationApprovals.value, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      expect(push.rootListeners, 0);
      push.tap(beta, 'third', 'event-3');
      await _pump(tester);
      expect(lookups, hasLength(2));
    },
  );

  testWidgets(
    'cold and warm push taps serialize exact saved-profile navigation',
    (tester) async {
      final manager = await _manager();
      final beta = manager.getConnections().singleWhere(
        (c) => c.gatewayProfile == 'beta',
      );
      final push = _Push()..tap(beta, 'first', 'event-1');
      addTearDown(push.dispose);
      final lookups = <(String, String?, String)>[];
      await tester.pumpWidget(
        HermesApp(
          connManager: manager,
          mobilePush: push,
          testNotificationSessionLookup: (connection, id) async {
            lookups.add((connection.id, connection.gatewayProfile, id));
            return _session(id);
          },
        ),
      );
      await _pump(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        tester.widget<ChatScreen>(find.byType(ChatScreen)).session.id,
        'first',
      );
      final coldTakes = push.takes;
      push.tap(beta, 'second', 'event-2');
      await _pump(tester);
      final chats = tester.widgetList<ChatScreen>(
        find.byType(ChatScreen, skipOffstage: false),
      );
      expect(chats.map((c) => c.session.id), ['first', 'second']);
      expect(
        chats.every(
          (c) =>
              c.connection.id == beta.id &&
              c.connection.gatewayProfile == 'beta',
        ),
        isTrue,
      );
      expect(lookups, [
        (beta.id, 'beta', 'first'),
        (beta.id, 'beta', 'second'),
      ]);
      expect(push.takes, coldTakes + 1);
      expect(pendingNotificationApprovals.value, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
      expect(push.rootListeners, 0);
    },
  );

  for (final boundary in [
    'revocation',
    'disposal',
    'foreign-session',
    'configuration',
  ]) {
    testWidgets(
      '$boundary during held session lookup cannot open an authorised chat',
      (tester) async {
        final manager = await _manager();
        final beta = manager.getConnections().singleWhere(
          (c) => c.gatewayProfile == 'beta',
        );
        final push = _Push()..tap(beta, 'exact', 'event-1');
        addTearDown(push.dispose);
        final lookup = Completer<Session?>();
        var reads = 0;
        await tester.pumpWidget(
          HermesApp(
            connManager: manager,
            mobilePush: push,
            testNotificationSessionLookup: (_, _) {
              reads++;
              return lookup.future;
            },
          ),
        );
        await _pump(tester);
        expect(reads, 1);
        if (boundary == 'revocation') push.current = false;
        if (boundary == 'configuration') {
          await manager.updateConnection(
            beta.id,
            beta.label,
            beta.host,
            beta.port,
            'changed-key',
            gatewayProfile: 'other-profile',
          );
        }
        if (boundary == 'disposal') {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        lookup.complete(
          _session(boundary == 'foreign-session' ? 'foreign' : 'exact'),
        );
        await _pump(tester);
        expect(find.byType(ChatScreen, skipOffstage: false), findsNothing);
        expect(pendingNotificationApprovals.value, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester);
        expect(push.rootListeners, 0);
      },
    );
  }
}
