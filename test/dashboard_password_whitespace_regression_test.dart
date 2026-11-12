import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'dashboard_auth_onboarding_test.dart' show selectMode;
import 'dashboard_native_auth_security_test.dart' show MemoryStore, RealHttp;
import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scrollable = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .last;
  await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  for (var i = 0; i < 8 && target.hitTestable().evaluate().isEmpty; i++) {
    final dy = tester.getCenter(target).dy < tester.getCenter(scrollable).dy
        ? 80.0
        : -80.0;
    await tester.drag(scrollable, Offset(0, dy));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late PathProviderPlatform paths;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('auth-mode-regression-');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await support.delete(recursive: true);
  });

  for (final route in ['Add', 'Edit', 'Settings']) {
    testWidgets('$route Basic preserves password whitespace on wire and disk', (
      tester,
    ) async {
      final oldHttp = HttpOverrides.current;
      HttpOverrides.global = RealHttp();
      addTearDown(() => HttpOverrides.global = oldHttp);
      late HttpServer server;
      final loginBodies = <Map<String, dynamic>>[];
      final modelCookies = <String?>[];
      final dashboardPaths = <String>[];
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path.startsWith('/dash/')) {
            dashboardPaths.add(request.uri.path);
          }
          if (request.uri.path.endsWith('/auth/password-login')) {
            loginBodies.add(
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>,
            );
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'hermes_session_at=basic-session; Path=/',
            );
          }
          if (request.uri.path.endsWith('/api/model/info')) {
            modelCookies.add(request.headers.value(HttpHeaders.cookieHeader));
          }
          request.response.write(
            request.uri.path == '/api/sessions' ? '{"sessions":[]}' : '{}',
          );
          await request.response.close();
        });
      });
      addTearDown(() => server.close(force: true));
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: MemoryStore(),
        nativePushSupported: false,
      );
      if (route != 'Add') {
        await manager.saveConnection(
          'Saved',
          '127.0.0.1',
          server.port,
          '',
          dashboardPort: server.port,
          dashboardPrefix: '/dash',
          dashboardProxied: true,
        );
      }
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
      if (route == 'Add') {
        await tester.tap(find.byIcon(Icons.add).first);
      } else {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            route == 'Edit' ? 'Edit Connection' : 'Dashboard / Proxy Settings',
          ),
        );
      }
      await tester.pumpAndSettle();
      if (route == 'Settings') {
        expect(find.text('Sign in with browser'), findsNothing);
      }
      if (route == 'Add') {
        await tester.enterText(
          find.widgetWithText(TextField, 'Host'),
          '127.0.0.1',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Port'),
          '${server.port}',
        );
        await reveal(tester, find.text('Custom proxy and dashboard details'));
        await tester.tap(find.text('Custom proxy and dashboard details'));
        await tester.pumpAndSettle();
        final port = find.widgetWithText(TextField, 'Dashboard Port');
        await reveal(tester, port);
        await tester.enterText(port, '${server.port}');
        await tester.enterText(
          find.widgetWithText(TextField, 'Dashboard path prefix'),
          '/dash',
        );
        final proxy = find.widgetWithText(
          SwitchListTile,
          'Dashboard behind proxy',
        );
        await reveal(tester, proxy);
        await tester.tap(proxy);
        await tester.pumpAndSettle();
      }
      await selectMode(tester, 'Basic');
      if (route == 'Settings') {
        expect(find.text('Sign in with browser'), findsNothing);
      }
      final proxyControl = find.widgetWithText(
        SwitchListTile,
        'Dashboard behind proxy',
      );
      if (proxyControl.evaluate().isNotEmpty) {
        expect(tester.widget<SwitchListTile>(proxyControl).value, isFalse);
        expect(tester.widget<SwitchListTile>(proxyControl).onChanged, isNull);
      }
      final save = find.widgetWithText(
        FilledButton,
        route == 'Edit'
            ? 'Save Changes'
            : route == 'Add'
            ? 'Connect'
            : 'Save',
      );
      for (final missing in ['both', 'password', 'username']) {
        final user = find.widgetWithText(
          TextField,
          'Dashboard Username (optional)',
        );
        final pass = find.widgetWithText(
          TextField,
          'Dashboard Password (optional)',
        );
        await reveal(tester, user);
        await tester.enterText(user, missing == 'password' ? 'alice' : '');
        await tester.enterText(pass, missing == 'username' ? '  secret  ' : '');
        await reveal(tester, save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          find.text('Basic requires both a username and password.'),
          findsOneWidget,
        );
        expect(dashboardPaths, isEmpty);
        expect(manager.getConnections().length, route == 'Add' ? 0 : 1);
      }
      await reveal(
        tester,
        find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dashboard Username (optional)'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dashboard Password (optional)'),
        '  secret  ',
      );
      final portField = find.widgetWithText(TextField, 'Dashboard Port');
      for (final invalid in ['not-a-port', '0', '65536']) {
        await reveal(tester, portField);
        await tester.enterText(portField, invalid);
        await reveal(tester, save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Invalid port number.'), findsOneWidget);
        expect(dashboardPaths, isEmpty);
      }
      await reveal(tester, portField);
      await tester.enterText(portField, '${server.port}');
      await reveal(
        tester,
        find.widgetWithText(TextField, 'Dashboard Username (optional)'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dashboard Username (optional)'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dashboard Password (optional)'),
        '  secret  ',
      );
      await reveal(tester, save);
      await tester.runAsync(() async {
        await tester.tap(save);
        for (var i = 0; i < 80; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(loginBodies, [
        {'provider': 'basic', 'username': 'alice', 'password': '  secret  '},
      ]);
      expect(modelCookies, ['hermes_session_at=basic-session']);
      final saved = manager.getConnections().single;
      expect(saved.dashboardProxied, isFalse);
      expect(saved.dashboardUsername, 'alice');
      expect(saved.dashboardPassword, '  secret  ');
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
