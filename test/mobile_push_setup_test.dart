import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/widgets/mobile_push_settings.dart';
import 'package:http/http.dart' as http;

import 'mobile_push_service_test.dart' as fixture;
import 'support/l10n_test_utils.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');
const _guide =
    'https://github.com/rusty4444/hermes-android/blob/main/docs/mobile-push-server.md'
    '#operator-installation-not-performed-by-this-implementation';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  final launches = <MethodCall>[];
  late Future<bool> Function() launch;

  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
    launches.clear();
    launch = () async => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, (call) async {
          expect(call.method, 'launch');
          launches.add(call);
          return launch();
        });
  });
  tearDown(() {
    f.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, null);
  });

  Widget card({SavedConnection? connection, Key? key}) => SingleChildScrollView(
    child: MobilePushSettings(
      key: key,
      connection: connection ?? f.connection,
      connectionManager: f.manager,
      service: f.service,
    ),
  );

  Future<void> show(WidgetTester tester, {SavedConnection? connection}) async {
    await tester.runAsync(() => f.service.initialize(f.manager));
    await tester.pumpWidget(
      testAppWithL10n(Scaffold(body: card(connection: connection))),
    );
    await tester.runAsync(() => f.service.transportOptions());
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  }

  void expectNoConsent() {
    expect(f.service.enabled, isFalse);
    for (final method in ['permission', 'enable', 'retryDistributor']) {
      expect(f.methods, isNot(contains(method)));
    }
    expect(
      f.requests.where(
        (r) =>
            r.method != 'GET' && !r.url.path.endsWith('/auth/password-login'),
      ),
      isEmpty,
    );
  }

  Future<void> openGuide(WidgetTester tester) async {
    final guide = find.text('Server setup guide');
    await tester.ensureVisible(guide);
    await tester.tap(guide);
    await tester.pumpAndSettle();
  }

  http.Response capabilities() => http.Response(
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
  );

  Future<SavedConnection> otherConnection() async {
    await f.manager.saveConnection(
      'Other profile',
      'https://fixture.invalid',
      443,
      'other-key',
      dashboardPrefix: '/dash',
      dashboardUsername: 'fixture-user',
      dashboardPassword: 'fixture-password',
      gatewayProfile: 'other-profile',
    );
    return f.manager.getConnections().firstWhere(
      (c) => c.id != f.connection.id,
    );
  }

  Future<void> startCheck(
    WidgetTester tester,
    Completer<void> requested, {
    Finder? owner,
  }) async {
    final retry = owner == null
        ? find.text('Refresh / retry')
        : find.descendant(of: owner, matching: find.text('Refresh / retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.runAsync(() => f.service.transportOptions());
    await tester.pump();
    expect(requested.isCompleted, isTrue);
  }

  for (final switched in [false, true]) {
    for (final olderFails in [true, false]) {
      testWidgets(
        'off availability ignores disposed ${switched ? 'switched' : 'reopened'} '
        'Settings ${olderFails ? 'failure after success' : 'success after failure'}',
        (tester) async {
          final older = Completer<http.Response>();
          final newer = Completer<http.Response>();
          final olderRequested = Completer<void>();
          final newerRequested = Completer<void>();
          addTearDown(() {
            if (!older.isCompleted) older.complete(capabilities());
            if (!newer.isCompleted) newer.complete(capabilities());
          });
          var checks = 0;
          f.onCapabilities = (_) {
            if (++checks == 1) {
              olderRequested.complete();
              return older.future;
            }
            expect(checks, 2);
            newerRequested.complete();
            return newer.future;
          };
          final nextConnection = switched
              ? await otherConnection()
              : f.connection;
          await show(tester);
          final retry = find.text('Refresh / retry');
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.runAsync(() => f.service.transportOptions());
          await tester.pump();
          expect(
            olderRequested.isCompleted,
            isTrue,
            reason: 'methods=${f.methods}; error=${f.service.error}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await show(tester, connection: nextConnection);
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.runAsync(() => f.service.transportOptions());
          await tester.pump();
          expect(newerRequested.isCompleted, isTrue);
          newer.complete(
            olderFails
                ? capabilities()
                : http.Response('new-private-body', 404),
          );
          await tester.pumpAndSettle();
          expect(find.byType(LinearProgressIndicator), findsNothing);
          older.complete(
            olderFails
                ? http.Response('old-private-body', 404)
                : capabilities(),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('server API ready'),
            olderFails ? findsOneWidget : findsNothing,
          );
          expect(
            find.textContaining('may be missing or disabled'),
            olderFails ? findsNothing : findsOneWidget,
          );
          expect(find.textContaining('private-body'), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(checks, 2);
          expectNoConsent();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final olderFails in [true, false]) {
    testWidgets('off availability fences retained Settings connection switch '
        '${olderFails ? 'failure' : 'success'} while newer check is pending', (
      tester,
    ) async {
      final nextConnection = await otherConnection();
      final older = Completer<http.Response>();
      final newer = Completer<http.Response>();
      final olderRequested = Completer<void>();
      final newerRequested = Completer<void>();
      addTearDown(() {
        if (!older.isCompleted) older.complete(capabilities());
        if (!newer.isCompleted) newer.complete(capabilities());
      });
      var checks = 0;
      f.onCapabilities = (_) {
        if (++checks == 1) {
          olderRequested.complete();
          return older.future;
        }
        expect(checks, 2);
        newerRequested.complete();
        return newer.future;
      };
      await show(tester);
      final original = tester.state(find.byType(MobilePushSettings));
      await startCheck(tester, olderRequested);
      await show(tester, connection: nextConnection);
      expect(tester.state(find.byType(MobilePushSettings)), same(original));
      expect(find.text('Status: Off'), findsOneWidget);
      await startCheck(tester, newerRequested);
      older.complete(
        olderFails ? http.Response('old-private-body', 404) : capabilities(),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('server API ready'), findsNothing);
      expect(find.textContaining('may be missing or disabled'), findsNothing);
      newer.complete(
        olderFails ? capabilities() : http.Response('new-private-body', 404),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('server API ready'),
        olderFails ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('may be missing or disabled'),
        olderFails ? findsNothing : findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(f.service.status, 'Off');
      expect(f.service.error, isNull);
      expect(checks, 2);
      expectNoConsent();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'off availability old same-connection owner disposal cannot cancel newer '
      '${olderFails ? 'failure' : 'success'} diagnosis',
      (tester) async {
        final older = Completer<http.Response>();
        final newer = Completer<http.Response>();
        final olderRequested = Completer<void>();
        final newerRequested = Completer<void>();
        addTearDown(() {
          if (!older.isCompleted) older.complete(capabilities());
          if (!newer.isCompleted) newer.complete(capabilities());
        });
        var checks = 0;
        f.onCapabilities = (_) {
          if (++checks == 1) {
            olderRequested.complete();
            return older.future;
          }
          expect(checks, 2);
          newerRequested.complete();
          return newer.future;
        };
        final olderKey = GlobalKey();
        final newerKey = GlobalKey();
        await tester.runAsync(() => f.service.initialize(f.manager));
        await tester.pumpWidget(
          testAppWithL10n(Scaffold(body: card(key: olderKey))),
        );
        await tester.runAsync(() => f.service.transportOptions());
        await tester.pumpAndSettle();
        await startCheck(tester, olderRequested);
        await tester.pumpWidget(
          testAppWithL10n(
            Scaffold(
              body: Stack(
                children: [
                  Offstage(child: card(key: olderKey)),
                  card(key: newerKey),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(() => f.service.transportOptions());
        await tester.pump();
        expect(olderKey.currentState, isNotNull);
        await startCheck(tester, newerRequested, owner: find.byKey(newerKey));
        await tester.pumpWidget(
          testAppWithL10n(Scaffold(body: card(key: newerKey))),
        );
        expect(olderKey.currentState, isNull);
        older.complete(
          olderFails ? capabilities() : http.Response('old-private-body', 404),
        );
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.textContaining('server API ready'), findsNothing);
        expect(find.textContaining('may be missing or disabled'), findsNothing);
        newer.complete(
          olderFails ? http.Response('new-private-body', 404) : capabilities(),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('server API ready'),
          olderFails ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining('may be missing or disabled'),
          olderFails ? findsOneWidget : findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(f.service.error, isNull);
        expect(checks, 2);
        expectNoConsent();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('off availability never clears a consent permission error', (
    tester,
  ) async {
    f.permission = false;
    await show(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final consentError = f.service.error;
    expect(consentError, contains('Allow Android notifications'));
    final retry = find.text('Refresh / retry');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.runAsync(() => f.service.transportOptions());
    await tester.pumpAndSettle();
    expect(find.textContaining('server API ready'), findsOneWidget);
    expect(f.service.error, consentError);
    expect(find.text(consentError!), findsOneWidget);
    expect(f.methods.where((method) => method == 'permission'), hasLength(1));
    expect(f.methods, isNot(contains('enable')));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('off settings explains separate server setup without opting in', (
    tester,
  ) async {
    await show(tester);
    expect(
      find.textContaining('server-side mobile-push companion'),
      findsOneWidget,
    );
    expect(find.textContaining('Android cannot install'), findsOneWidget);
    expect(find.textContaining('Updating the APK alone'), findsOneWidget);
    expect(find.text('Server setup guide'), findsOneWidget);
    expect(find.textContaining('rechecks'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(launches, isEmpty);
    expect(f.requests, isEmpty);
    expectNoConsent();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    '404 keeps guide available and refresh only rechecks capabilities',
    (tester) async {
      f.onCapabilities = (_) async => http.Response('secret-server-body', 404);
      await show(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('may be missing or disabled'), findsOneWidget);
      expect(find.textContaining('wrong dashboard'), findsOneWidget);
      expect(find.textContaining('Install or enable'), findsOneWidget);
      expect(find.textContaining('secret-server-body'), findsNothing);
      expect(find.text('Server setup guide'), findsOneWidget);
      expectNoConsent();
      await openGuide(tester);
      expect(launches, hasLength(1));

      final before = f.requests
          .where((r) => r.url.path.endsWith('/capabilities'))
          .length;
      final retry = find.text('Refresh / retry');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.runAsync(() => f.service.transportOptions());
      await tester.pumpAndSettle();
      expect(
        f.requests.where((r) => r.url.path.endsWith('/capabilities')),
        hasLength(before + 1),
      );
      expectNoConsent();

      f.onCapabilities = null;
      await tester.tap(retry);
      await tester.runAsync(() => f.service.transportOptions());
      await tester.pumpAndSettle();
      // A read-only diagnosis must not erase the failed enable's consent error.
      expect(f.service.error, contains('may be missing or disabled'));
      expect(find.textContaining('server API ready'), findsOneWidget);
      expectNoConsent();
      await openGuide(tester);
      expect(launches, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'off refresh still retries pending revocation without opting in',
    (tester) async {
      f.seed(active: true);
      await show(tester);
      f.failRevoke = true;
      await tester.runAsync(f.service.disable);
      await tester.pumpAndSettle();
      expect(f.service.pendingRevocations, 1);
      f.failRevoke = false;
      final retry = find.text('Refresh / retry');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.runAsync(() => f.service.transportOptions());
      await tester.pumpAndSettle();
      expect(f.service.pendingRevocations, 0);
      expect(f.service.enabled, isFalse);
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
      expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(find.textContaining('server API ready'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('guide opens exact public URI externally on explicit tap only', (
    tester,
  ) async {
    await show(tester);
    expect(launches, isEmpty);
    await openGuide(tester);
    final args = launches.single.arguments as Map;
    expect(args['url'], _guide);
    expect(args['useWebView'], isFalse);
    expect(args['useSafariVC'], isFalse);
    expect(args['headers'], isEmpty);
    final uri = Uri.parse(args['url'] as String);
    expect(uri.scheme, 'https');
    expect(uri.userInfo, isEmpty);
    expect(uri.hasQuery, isFalse);
    expect(f.requests, isEmpty);
    expectNoConsent();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('guide fragment matches the current operator heading', () {
    final doc = File('docs/mobile-push-server.md').readAsStringSync();
    expect(
      doc,
      contains(
        '## Operator installation (not performed by this implementation)',
      ),
    );
    expect(
      Uri.parse(_guide).fragment,
      'operator-installation-not-performed-by-this-implementation',
    );
  });

  for (final throws in [false, true]) {
    testWidgets(
      'guide launch ${throws ? 'throw' : 'failure'} shows safe feedback',
      (tester) async {
        launch = () async {
          if (throws) throw PlatformException(code: 'private-platform-detail');
          return false;
        };
        await show(tester);
        await openGuide(tester);
        expect(find.text('Could not open this link.'), findsOneWidget);
        expect(find.textContaining('private-platform-detail'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'late guide ${throws ? 'throw' : 'failure'} after disposal is inert',
      (tester) async {
        final release = Completer<bool>();
        launch = () => release.future;
        await show(tester);
        await openGuide(tester);
        expect(launches, hasLength(1));
        await tester.pumpWidget(
          testAppWithL10n(const Scaffold(body: Text('Other route'))),
        );
        if (throws) {
          release.completeError(PlatformException(code: 'late-private-detail'));
        } else {
          release.complete(false);
        }
        await tester.pumpAndSettle();
        expect(find.text('Other route'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
