import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_native_auth_security_test.dart' show MemoryStore, RealHttp;
import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

void main() {
  for (final auth in ['proxied', 'basic']) {
    for (final edit in ['URL', 'profile']) {
      testWidgets('legacy $auth $edit edit validates and saves', (
        tester,
      ) async {
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = RealHttp();
        addTearDown(() => HttpOverrides.global = previousOverrides);
        late HttpServer server;
        final modelRequests = <String>[];
        final logins = <String>[];
        final unexpectedAuth = <String>[];
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            request.response.headers.contentType = ContentType.json;
            if (request.uri.path.endsWith('/auth/password-login')) {
              logins.add(request.uri.path);
              request.response.headers.add(
                HttpHeaders.setCookieHeader,
                'hermes_session_at=legacy-cookie; Path=/',
              );
              request.response.write('{}');
            } else if (request.uri.path.endsWith('/api/model/info')) {
              modelRequests.add(request.uri.path);
              if (request.headers.value(HttpHeaders.authorizationHeader) !=
                      null ||
                  request.headers.value('x-hermes-session-token') != null ||
                  request.headers.value(HttpHeaders.cookieHeader) !=
                      (auth == 'basic'
                          ? 'hermes_session_at=legacy-cookie'
                          : null)) {
                unexpectedAuth.add(request.uri.path);
                request.response.statusCode = 401;
              }
              request.response.write('{}');
            } else {
              request.response.write(
                request.uri.path == '/api/sessions' ? '{"sessions":[]}' : '{}',
              );
            }
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
        final oldUrl = 'http://127.0.0.1:${server.port}/dash';
        final newUrl = 'http://127.0.0.1:${server.port}/new';
        final connection = SavedConnection(
          id: 'legacy-$auth-$edit',
          label: 'Legacy connection',
          host: '127.0.0.1',
          port: server.port,
          apiKey: 'gateway-only',
          desktopGatewayUrl: oldUrl,
          dashboardPortOverride: server.port,
          dashboardPrefix: '/dash',
          gatewayProfile: 'research',
          dashboardProxied: auth == 'proxied',
          dashboardUsername: auth == 'basic' ? 'legacy-user' : null,
          dashboardPassword: auth == 'basic' ? 'legacy-password' : null,
        );
        await manager.importConnections([connection], replaceExisting: true);
        expect(
          await manager.dashboardNativeAuthStatus(connection),
          DashboardNativeSessionStatus.notConfigured,
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
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit Connection'));
        await tester.pumpAndSettle();
        final field = find.widgetWithText(
          TextField,
          edit == 'URL' ? oldUrl : 'research',
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, edit == 'URL' ? newUrl : 'other');
        if (edit == 'URL') {
          final prefix = find.widgetWithText(TextField, '/dash');
          await tester.ensureVisible(prefix);
          await tester.enterText(prefix, '/new');
        }
        final save = find.widgetWithText(FilledButton, 'Save Changes');
        await tester.ensureVisible(save);
        await tester.runAsync(() async {
          await tester.tap(save);
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        final saved = manager.getConnections().single;
        expect(
          edit == 'URL' ? saved.desktopGatewayUrl : saved.gatewayProfile,
          edit == 'URL' ? newUrl : 'other',
          reason:
              'The real edit dialog must validate the changed legacy binding; '
              'model=$modelRequests logins=$logins auth=$unexpectedAuth '
              'text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
        );
        expect(find.byType(AlertDialog), findsNothing);
        final prefix = edit == 'URL' ? '/new' : '/dash';
        expect(modelRequests, ['$prefix/api/model/info']);
        expect(
          logins,
          auth == 'basic' ? ['$prefix/auth/password-login'] : isEmpty,
        );
        expect(unexpectedAuth, isEmpty);
        expect(
          await manager.dashboardNativeAuthStatus(saved),
          DashboardNativeSessionStatus.notConfigured,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final edit in [
    'label',
    'origin',
    'profile',
    'clear profile',
    'signed out',
  ]) {
    testWidgets(
      'OIDC $edit edit preserves or revokes the bound identity safely',
      (tester) async {
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = RealHttp();
        addTearDown(() => HttpOverrides.global = previousOverrides);
        late HttpServer server;
        final requests = <String>[];
        final dashboardRequests = <String>[];
        final fallbackRequests = <String>[];
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests.add(request.uri.toString());
            request.response.headers.contentType = ContentType.json;
            if (request.uri.path.startsWith('/dash')) {
              if (request.uri.path == '/dash/api/model/info' &&
                  request.headers.value('authorization') ==
                      'Bearer edit-access') {
                dashboardRequests.add(request.uri.path);
                request.response.write('{}');
              } else {
                fallbackRequests.add(request.uri.path);
                request.response.statusCode = 401;
              }
            } else {
              request.response.write(
                request.uri.path == '/api/sessions' ? '{"sessions":[]}' : '{}',
              );
            }
            await request.response.close();
          });
        });
        addTearDown(() => server.close(force: true));
        SharedPreferences.setMockInitialValues({});
        final secrets = MemoryStore();
        final manager = ConnectionManager(
          await SharedPreferences.getInstance(),
          credentialStore: secrets,
          nativePushSupported: false,
        );
        final connection = SavedConnection(
          id: 'oidc-edit',
          label: 'OIDC connection',
          host: '127.0.0.1',
          port: server.port,
          apiKey: 'gateway-only',
          dashboardPortOverride: server.port,
          dashboardPrefix: '/dash',
          desktopGatewayUrl: 'http://127.0.0.1:${server.port}/dash',
          gatewayProfile: 'research',
        );
        await manager.importConnections([connection], replaceExisting: true);
        await manager.saveDashboardNativeTokens(
          connection,
          accessToken: 'edit-access',
          refreshToken: 'edit-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: 'oidc',
          userId: 'edit-user',
        );
        if (edit == 'signed out') {
          await manager.clearDashboardNativeTokens(connection.id);
        }
        final before = Map<String, String>.of(secrets.values);
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
        final label = find.widgetWithText(TextField, 'OIDC connection');
        await tester.enterText(label, 'Renamed OIDC');
        if (edit != 'label' && edit != 'signed out') {
          final field = find.widgetWithText(
            TextField,
            edit == 'origin' ? '/dash' : 'research',
          );
          await tester.ensureVisible(field);
          await tester.enterText(
            field,
            edit == 'origin'
                ? '/dash-new'
                : edit == 'clear profile'
                ? ''
                : 'other',
          );
        }
        final save = find.widgetWithText(FilledButton, 'Save Changes');
        await tester.ensureVisible(save);
        await tester.runAsync(() async {
          await tester.tap(save);
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(
          manager.getConnections().single.label,
          'Renamed OIDC',
          reason:
              'requests=$requests fallback=$fallbackRequests dashboard=$dashboardRequests text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(" | ")}',
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          dashboardRequests,
          edit == 'label' ? ['/dash/api/model/info'] : isEmpty,
        );
        expect(fallbackRequests, isEmpty);
        if (edit == 'label') {
          expect(secrets.values, before);
        } else {
          expect(secrets.values.values.join(), isNot(contains('edit-access')));
          expect(secrets.values.values.join(), isNot(contains('edit-refresh')));
          final current = manager.getConnections().single;
          final client = DashboardClient.fromConnection(current);
          await expectLater(client.getModelInfo(), throwsA(isA<Exception>()));
          client.close();
          expect(fallbackRequests, isEmpty);
        }
        expect(
          await manager.dashboardNativeAuthStatus(
            manager.getConnections().single,
          ),
          edit == 'label'
              ? DashboardNativeSessionStatus.signedIn
              : DashboardNativeSessionStatus.signedOut,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
