import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'dashboard_native_auth_security_test.dart' show MemoryStore, RealHttp;
import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<ConnectionManager> openAdd(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final manager = ConnectionManager(
    await SharedPreferences.getInstance(),
    credentialStore: MemoryStore(),
    nativePushSupported: false,
  );
  final turns = GatewayTurnApplicationController(
    sessionFactory: (_) => InertTurnApplicationSession(),
  );
  addTearDown(turns.close);
  await tester.pumpWidget(
    testAppWithL10n(
      HomeScreen(connManager: manager, turnApplicationController: turns),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add).first);
  await tester.pumpAndSettle();
  return manager;
}

Future<void> selectMode(WidgetTester tester, String label) async {
  final selector = find.byKey(const Key('dashboard_auth_mode'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('dashboard-onboarding-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await support.delete(recursive: true);
  });
  testWidgets('OIDC onboarding rejects insecure dashboard before saving', (
    tester,
  ) async {
    final manager = await openAdd(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Host'), '127.0.0.1');
    await selectMode(tester, 'OIDC');
    final save = find.widgetWithText(
      FilledButton,
      'Save & sign in with browser',
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('requires an HTTPS'), findsOneWidget);
    expect(manager.getConnections(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'OIDC onboarding durably saves before launch and retries without duplication',
    (tester) async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = RealHttp();
      addTearDown(() => HttpOverrides.global = previous);
      late HttpServer api;
      final requests = <String>[];
      await tester.runAsync(() async {
        api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        api.listen((request) async {
          requests.add(request.uri.path);
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        });
      });
      addTearDown(() => api.close(force: true));
      final manager = await openAdd(tester);
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final launches = <String>[];
      final statuses = <DashboardNativeSessionStatus>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(launcher, (call) async {
        launches.add((call.arguments as Map)['url'] as String);
        final saved = manager.getConnections().single;
        statuses.add(await manager.dashboardNativeAuthStatus(saved));
        expect(saved.id, isNotEmpty);
        expect(saved.gatewayProfile, 'research');
        expect(saved.apiKey, 'api-only');
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
      await tester.enterText(
        find.widgetWithText(TextField, 'Host'),
        '127.0.0.1',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Port'),
        '${api.port}',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'API Key'),
        'api-only',
      );
      await selectMode(tester, 'OIDC');
      await tester.enterText(
        find.widgetWithText(TextField, 'Hermes profile (optional)'),
        'research',
      );
      final url = find.widgetWithText(
        TextField,
        'Desktop Gateway URL (optional)',
      );
      expect(
        url,
        findsOneWidget,
        reason: 'OIDC URL belongs in onboarding, not hidden advanced settings',
      );
      await tester.ensureVisible(url);
      await tester.enterText(url, 'https://dashboard.example.test/proxy');
      final save = find.widgetWithText(
        FilledButton,
        'Save & sign in with browser',
      );
      expect(save, findsOneWidget);
      await tester.ensureVisible(save);
      await tester.runAsync(() async {
        await tester.tap(save);
        for (var i = 0; i < 60; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      for (
        var i = 0;
        i < 200 &&
            (launches.isEmpty ||
                find.byType(CircularProgressIndicator).evaluate().isNotEmpty);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        launches,
        hasLength(1),
        reason:
            'requests=$requests text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
      );
      expect(statuses, [DashboardNativeSessionStatus.signedOut]);
      expect(Uri.parse(launches.single).path, '/proxy/auth/native/authorize');
      expect(
        requests.any(
          (path) => path.contains('auth/') || path.contains('model/info'),
        ),
        isFalse,
      );
      final retry = find.widgetWithText(FilledButton, 'Sign in with browser');
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.runAsync(() async {
        await tester.tap(retry);
        for (var i = 0; i < 40; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(launches, hasLength(2));
      expect(manager.getConnections(), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Add offers conditional None Basic OIDC with a common profile', (
    tester,
  ) async {
    await openAdd(tester);
    expect(find.byKey(const Key('dashboard_auth_mode')), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Hermes profile (optional)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      findsNothing,
    );
    await selectMode(tester, 'Basic');
    expect(
      find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Dashboard Password (optional)'),
      findsOneWidget,
    );
    await selectMode(tester, 'OIDC');
    expect(
      find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      findsNothing,
    );
    expect(find.text('Save & sign in with browser'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Hermes profile (optional)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'API Key'), findsOneWidget);
    await selectMode(tester, 'None (no manual sign-in)');
    expect(
      find.widgetWithText(TextField, 'Hermes profile (optional)'),
      findsOneWidget,
    );
    expect(find.text('Save & sign in with browser'), findsNothing);
  });
  testWidgets('saved Dashboard settings share the authentication selector', (
    tester,
  ) async {
    final manager = await openAdd(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await manager.saveConnection('Saved', 'https://api.example.test', 443, '');
    await tester.pumpWidget(const SizedBox.shrink());
    final turns = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(turns.close);
    await tester.pumpWidget(
      testAppWithL10n(
        HomeScreen(connManager: manager, turnApplicationController: turns),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard / Proxy Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard_auth_mode')), findsOneWidget);
    await selectMode(tester, 'Basic');
    expect(
      find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      findsOneWidget,
    );
    await selectMode(tester, 'OIDC');
    expect(
      find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      findsNothing,
    );
    expect(
      find.widgetWithText(TextField, 'Hermes profile (optional)'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Edit offers explicit save and browser sign-in without hiding profile',
    (tester) async {
      final manager = await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await manager.saveConnection(
        'Saved',
        'https://api.example.test',
        443,
        '',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final turns = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(turns.close);
      await tester.pumpWidget(
        testAppWithL10n(
          HomeScreen(connManager: manager, turnApplicationController: turns),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Connection'));
      await tester.pumpAndSettle();
      await selectMode(tester, 'OIDC');
      expect(
        find.widgetWithText(TextField, 'Hermes profile (optional)'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Save Changes'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Save & sign in with browser'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
