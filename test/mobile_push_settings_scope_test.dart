import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/widgets/mobile_push_settings.dart';
import 'package:http/http.dart' as http;

import 'mobile_push_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
  });
  tearDown(() => f.close());

  Future<void> show(
    WidgetTester tester, {
    SavedConnection? connection,
    bool expectSwitchEnabled = true,
  }) async {
    await tester.runAsync(() => f.service.initialize(f.manager));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MobilePushSettings(
              connection: connection ?? f.connection,
              connectionManager: f.manager,
              service: f.service,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await f.service.transportOptions();
    });
    await tester.pumpAndSettle();
    if (expectSwitchEnabled) {
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    }
  }

  for (final failure in ['old', 'missing', 'disabled']) {
    testWidgets('$failure server rejects automatic toggle before permission', (
      tester,
    ) async {
      if (failure == 'old') f.scopeModes = ['explicit'];
      if (failure == 'missing') f.capsStatus = 404;
      if (failure == 'disabled') f.capsEnabled = false;
      await show(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        find.textContaining(failure == 'missing' ? 'unavailable' : 'server'),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('toggle off cancels enable while capabilities is pending', (
    tester,
  ) async {
    final release = Completer<http.Response>();
    f.onCapabilities = (_) => release.future;
    await show(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(f.methods, contains('disable'));
    release.complete(
      http.Response(
        jsonEncode({
          'schema': 1,
          'registration_fence': 1,
          'enabled': true,
          'session_scope_modes': ['explicit', 'authorized'],
          'transports': ['webpush'],
          'vapid_public_key': base64Url
              .encode([4, ...List<int>.filled(64, 1)])
              .replaceAll('=', ''),
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(f.methods, isNot(contains('permission')));
    expect(f.methods, isNot(contains('enable')));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'legacy explicit scope remains visible and is never expanded by opening settings',
    (tester) async {
      f.seed(active: true);
      await show(tester);
      expect(find.textContaining('Legacy subscription'), findsOneWidget);
      expect(find.textContaining('1 selected session'), findsOneWidget);
      expect(f.native['sessions'], ['durable-session']);
      expect(f.methods, isNot(contains('enable')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final failure in {
    'push_transport_unavailable': 'No push transport is available.',
    'push_transport_choice': 'Choose one in Advanced transport',
    'push_transport_missing': 'selected UnifiedPush distributor is unavailable',
  }.entries) {
    testWidgets(
      'readable ${failure.key} failure does not claim active consent',
      (tester) async {
        f.enableFailureCode = failure.key;
        await show(tester);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.textContaining(failure.value), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
        expect(f.service.active, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'advanced optional readable transport preserves explicit override',
    (tester) async {
      await show(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.text('Advanced transport'));
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test distributor').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(f.native['distributor'], 'test.distributor');
      expect(f.native['session_scope'], 'authorized');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disable remains actionable while native enable reply is held', (
    tester,
  ) async {
    final release = Completer<void>();
    f.afterCommand = (method, _) async {
      if (method == 'enable') await release.future;
    };
    await show(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(f.native['enabled'], isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(f.native['enabled'], isFalse);
    release.complete();
    await tester.pumpAndSettle();
    expect(f.service.enabled, isFalse);
    expect(f.methods, isNot(contains('beginRegistration')));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'another connection binding must be disabled before opting in here',
    (tester) async {
      await f.manager.saveConnection(
        'Another',
        'https://fixture.invalid',
        443,
        'test-key',
      );
      final another = f.manager.getConnections().firstWhere(
        (c) => c.id != f.connection.id,
      );
      f.seed(active: true);
      await show(tester, connection: another, expectSwitchEnabled: false);
      expect(find.byKey(const Key('mobile-push-switch')), findsOneWidget);
      expect(find.byKey(const Key('mobile-push-status')), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-push-disable-revoke')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-push-refresh-retry')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Bound to another saved connection (Fixture). Disable and revoke that binding before enabling for this connection.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Status: Bound to Fixture (not active for Another; handshake: Active)',
        ),
        findsOneWidget,
      );
      expect(find.text('Disable and revoke Fixture'), findsOneWidget);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);
      expect(switchWidget.onChanged, isNull);
      expect(f.methods, isNot(contains('enable')));
      await tester.tap(find.byKey(const Key('mobile-push-disable-revoke')));
      await tester.pumpAndSettle();
      expect(f.native['enabled'], isFalse);
      expect(f.methods, isNot(contains('permission')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'another connection binding falls back to generic label when connection is missing',
    (tester) async {
      await f.manager.saveConnection(
        '   ',
        'https://fixture.invalid',
        443,
        'test-key',
        dashboardPrefix: '/dash',
        dashboardUsername: 'fixture-user',
        dashboardPassword: 'fixture-password',
      );
      final blankLabelConn = f.manager.getConnections().firstWhere(
        (c) => c.id != f.connection.id,
      );
      f.seed(active: true);
      f.native['connection'] = blankLabelConn.id;
      f.native['binding'] = MobilePushService.binding(blankLabelConn);
      await show(tester, connection: f.connection, expectSwitchEnabled: false);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        find.text(
          'Bound to another saved connection. Disable and revoke that binding before enabling for this connection.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Status: Bound to another saved connection (not active for Fixture; handshake: Active)',
        ),
        findsOneWidget,
      );
      expect(find.text('Disable and revoke other connection'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pending challenge status explains silent verification push and local mute warning reacts immediately',
    (tester) async {
      f.seed(active: false);
      f.native['generation'] = 7;
      f.native['session_scope'] = 'authorized';
      f.native['sessions'] = <String>[];
      await show(tester);
      expect(
        find.text(
          'Status: Pending encrypted challenge (waiting for silent server verification push)',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-push-local-mute-warning')),
        findsNothing,
      );

      notificationPrefs.value = NotificationPrefs.defaults.copyWith(
        enabled: false,
      );
      await tester.pump();
      expect(f.service.active, isFalse);
      expect(
        find.byKey(const Key('mobile-push-local-mute-warning')),
        findsOneWidget,
      );
      expect(find.textContaining('Enrollment stays active'), findsNothing);
      expect(
        find.textContaining('ordinary background activity hints are muted'),
        findsOneWidget,
      );
      expect(f.service.enabled, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'status, progress, errors and recovery actions render above static setup prose',
    (tester) async {
      f.onCapabilities = (_) async => http.Response('err', 404);
      await show(tester);
      await tester.tap(find.byKey(const Key('mobile-push-switch')));
      await tester.pumpAndSettle();

      final statusY = tester
          .getTopLeft(find.byKey(const Key('mobile-push-status')))
          .dy;
      final errorY = tester
          .getTopLeft(find.byKey(const Key('mobile-push-error')))
          .dy;
      final retryY = tester
          .getTopLeft(find.byKey(const Key('mobile-push-refresh-retry')))
          .dy;
      final guideY = tester.getTopLeft(find.text('Server setup guide')).dy;
      final advancedY = tester.getTopLeft(find.text('Advanced transport')).dy;

      expect(statusY, lessThan(errorY));
      expect(errorY, lessThan(retryY));
      expect(retryY, lessThan(guideY));
      expect(guideY, lessThan(advancedY));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  // Keep exact explicit parsing validation at the service boundary even though
  // automatic Settings deliberately no longer accepts manual scope text.
  final invalid = <String, List<String>>{
    'empty': [],
    'blank': [''],
    'leading whitespace': [' session-a'],
    'trailing whitespace': ['session-a '],
    'internal blank': ['a', '', 'b'],
    'CR': ['a\rb'],
    'non ASCII': ['session-é'],
    'URL': ['https://bad'],
    'too long': ['x' * 201],
    'too many': List.generate(129, (i) => 's$i'),
  };
  for (final entry in invalid.entries) {
    test(
      'explicit service rejects ${entry.key} before setup effects',
      () async {
        await f.service.initialize(f.manager);
        await expectLater(
          f.service.enable(f.connection, 'test.distributor', entry.value),
          throwsStateError,
        );
        expect(f.requests, isEmpty);
        expect(f.methods, isNot(contains('permission')));
        expect(f.methods, isNot(contains('enable')));
      },
    );
  }
  for (final ids in [
    ['a'],
    ['AZaz09_.:@-'],
    ['x' * 200],
    List.generate(128, (i) => 's$i'),
  ]) {
    test(
      'explicit service preserves exact valid scope of ${ids.length} IDs',
      () async {
        await f.service.initialize(f.manager);
        await f.service.enable(f.connection, 'test.distributor', ids);
        expect(f.native['sessions'], ids);
        expect(f.native['session_scope'], 'explicit');
      },
    );
  }
}
