import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dashboard_auth_onboarding_test.dart' show openAdd;
import 'dashboard_native_auth_security_test.dart' show RealHttp;
import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> openEdit(WidgetTester tester, ConnectionManager manager) async {
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
}

Future<void> drain(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 80; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late PathProviderPlatform paths;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('oidc-edit-security-');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await support.delete(recursive: true);
  });
  testWidgets(
    'new explicit OIDC URL shows and uses exact HTTPS authority despite legacy fields',
    (tester) async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = RealHttp();
      addTearDown(() => HttpOverrides.global = overrides);
      late HttpServer api;
      await tester.runAsync(() async {
        api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        api.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        });
      });
      addTearDown(() => api.close(force: true));
      final manager = await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final old = await manager.saveConnection(
        'Legacy',
        '127.0.0.1',
        api.port,
        '',
        dashboardPrefix: '/legacy',
        dashboardPort: 8765,
        requireDashboardNativeSignIn: true,
      );
      final launches = <String>[];
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(launcher, (call) async {
        launches.add((call.arguments as Map)['url'] as String);
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
      await openEdit(tester, manager);
      final url = find.widgetWithText(
        TextField,
        'Desktop Gateway URL (optional)',
      );
      await tester.ensureVisible(url);
      await tester.enterText(url, 'https://127.0.0.1:9443/proxy');
      await tester.pump();
      expect(
        find.byKey(const Key('dashboard_resolved_destination')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dashboard_resolved_destination')),
            )
            .data,
        contains('https://127.0.0.1:9443/proxy'),
      );
      final save = find.widgetWithText(
        OutlinedButton,
        'Save & sign in with browser',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(launches, hasLength(1));
      expect(Uri.parse(launches.single).origin, 'https://127.0.0.1:9443');
      expect(Uri.parse(launches.single).path, '/proxy/auth/native/authorize');
      expect(manager.getConnections().single.id, old.id);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'unchanged legacy HTTPS override cannot save a different resolved authority',
    (tester) async {
      final manager = await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final old = await manager.saveConnection(
        'Legacy',
        '127.0.0.1',
        8642,
        '',
        dashboardPrefix: '/legacy',
        dashboardPort: 8765,
        desktopGatewayUrl: 'https://127.0.0.1:9443/proxy',
        requireDashboardNativeSignIn: true,
      );
      await openEdit(tester, manager);
      final save = find.widgetWithText(
        OutlinedButton,
        'Save & sign in with browser',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('requires an HTTPS'), findsOneWidget);
      final saved = manager.getConnections().single;
      expect(saved.id, old.id);
      expect(saved.dashboardUrlAuthoritative, isFalse);
      expect(saved.desktopGatewayUrl, old.desktopGatewayUrl);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Dashboard settings rejects unchanged legacy authority mismatch before save',
    (tester) async {
      final manager = await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final old = await manager.saveConnection(
        'Legacy',
        '127.0.0.1',
        8642,
        '',
        dashboardPrefix: '/legacy',
        dashboardPort: 8765,
        desktopGatewayUrl: 'https://127.0.0.1:9443/proxy',
        requireDashboardNativeSignIn: true,
      );
      await openEdit(tester, manager);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard / Proxy Settings'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('requires an HTTPS'), findsOneWidget);
      expect(manager.getConnections().single.toMap(), old.toMap());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final ordinaryFirst in [false, true]) {
    testWidgets(
      'explicit browser reauth with expired bearer, ordinary save first: $ordinaryFirst',
      (tester) async {
        final overrides = HttpOverrides.current;
        HttpOverrides.global = RealHttp();
        addTearDown(() => HttpOverrides.global = overrides);
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
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        final connection = await manager.saveConnection(
          'Expired',
          '127.0.0.1',
          api.port,
          'api-only',
          desktopGatewayUrl: 'https://dashboard.example.test:9443/proxy',
          gatewayProfile: 'research',
        );
        await manager.saveDashboardNativeTokens(
          connection,
          accessToken: 'expired-native',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
          provider: 'oidc',
          userId: 'subject',
        );
        final launches = <String>[];
        const launcher = MethodChannel('plugins.flutter.io/url_launcher');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(launcher, (call) async {
          launches.add((call.arguments as Map)['url'] as String);
          return false;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
        await openEdit(tester, manager);
        if (ordinaryFirst) {
          await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
          await drain(tester);
          expect(find.textContaining('Gateway connected, but'), findsOneWidget);
          expect(launches, isEmpty);
        }
        final reauth = find.widgetWithText(
          OutlinedButton,
          'Save & sign in with browser',
        );
        await tester.ensureVisible(reauth);
        await tester.tap(reauth);
        await drain(tester);
        expect(launches, hasLength(1));
        final target = Uri.parse(launches.single);
        expect(target.origin, 'https://dashboard.example.test:9443');
        expect(target.path, '/proxy/auth/native/authorize');
        final saved = manager.getConnections().single;
        expect(saved.id, connection.id);
        expect(saved.apiKey, 'api-only');
        expect(saved.gatewayProfile, 'research');
        expect(
          requests.where(
            (p) => p.contains('auth/') || p.contains('model/info'),
          ),
          isEmpty,
        );
        expect(
          await manager.dashboardNativeAuthStatus(saved),
          ordinaryFirst
              ? DashboardNativeSessionStatus.signedOut
              : DashboardNativeSessionStatus.expired,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
