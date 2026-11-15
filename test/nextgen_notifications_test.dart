import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/main_page.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_turn_notification_sink.dart';

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
  late RecordingTurnNotificationSink sink;
  late NextGenGateway gateway;

  Future<void> pumpMain(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      '${NextGenPreferences.lastSessionKeyPrefix}c1': 's1',
    });
    final prefs = await SharedPreferences.getInstance();
    sink = RecordingTurnNotificationSink()..permissionResult = true;
    final service = TurnNotificationService(sink: sink);
    await service.ensureInitialized();
    TurnNotificationService.debugShared = service;
    addTearDown(() => TurnNotificationService.debugShared = null);
    notificationPrefs.value = NotificationPrefs.defaults;
    final conn = _conn();
    gateway = NextGenGateway(conn);
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
          child: const NgMainPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    gateway.dispose();
    await tester.pump(const Duration(seconds: 30));
  }

  StreamEvent ev(String type, [Map<String, dynamic> data = const {}]) =>
      StreamEvent(type: type, data: data, sessionId: 's1');

  Future<void> background(WidgetTester tester) async {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
  }

  testWidgets('a reply that lands out of sight notifies; back in sight '
      'takes it down', (tester) async {
    await pumpMain(tester);
    gateway.debugEmit(ev('message.start'));
    await tester.pump();
    expect(nextGenTurnActive.value, isTrue, reason: 'keeps the process up');
    await background(tester);
    gateway.debugEmit(ev('message.delta', {'text': 'All done here'}));
    gateway.debugEmit(ev('message.complete', {'status': 'complete'}));
    await tester.pump();
    await tester.pump();
    expect(nextGenTurnActive.value, isFalse);
    final posted = sink.shown.where((n) => n.body == 'All done here').toList();
    expect(posted, hasLength(1), reason: '${sink.shown.map((n) => n.body)}');

    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(sink.cancelled, contains(posted.single.id));
    expect(
      TurnNotificationService.recentAttempts.value.first.outcome,
      'posted',
      reason: 'Settings can show what was posted',
    );
    await unmount(tester);
  });

  testWidgets('a reply in sight, or a stopped turn, does not notify', (
    tester,
  ) async {
    await pumpMain(tester);
    gateway.debugEmit(ev('message.start'));
    gateway.debugEmit(ev('message.delta', {'text': 'Seen'}));
    gateway.debugEmit(ev('message.complete', {'status': 'complete'}));
    await tester.pump();
    await background(tester);
    gateway.debugEmit(ev('message.start'));
    gateway.debugEmit(ev('message.complete', {'status': 'interrupted'}));
    await tester.pump();
    expect(sink.shown, isEmpty);
    expect(
      TurnNotificationService.recentAttempts.value
          .take(2)
          .map((a) => a.detail),
      ['the turn was stopped', 'Ares was on screen'],
    );
    await unmount(tester);
  });

  testWidgets('a failed turn out of sight notifies as a failure', (
    tester,
  ) async {
    await pumpMain(tester);
    gateway.debugEmit(ev('message.start'));
    await background(tester);
    gateway.debugEmit(ev('turn.error', {'message': 'Provider down'}));
    await tester.pump();
    expect(sink.shown.map((n) => n.body), contains('Provider down'));
    await unmount(tester);
  });
}
