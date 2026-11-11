import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

class _MemoryCredentials implements CredentialStore {
  final values = <String, String>{};

  @override
  String? readCached(String key) => values[key];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _ApiLoopbackOverrides extends HttpOverrides {
  _ApiLoopbackOverrides(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (_, _, _) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, port);
}

class _TrustedFixtureOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(
        SecurityContext(withTrustedRoots: true)
          ..setTrustedCertificates('test/fixtures/mtls-ca-cert.pem'),
      );
}

Finder _enabledButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate(
    (widget) => widget is ButtonStyleButton && widget.onPressed != null,
  ),
);

Finder _browserSignInButton() => _enabledButton('Sign in with browser');

Future<void> _openDashboardSettings(
  WidgetTester tester,
  ConnectionManager manager,
) async {
  final turns = GatewayTurnApplicationController(
    sessionFactory: (_) => InertTurnApplicationSession(),
  );
  addTearDown(turns.close);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
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
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<(ConnectionManager, _MemoryCredentials, SavedConnection)>
_createSignedInManager({
  required DateTime expiresAt,
  String? refreshToken,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secrets = _MemoryCredentials();
  final manager = ConnectionManager(
    prefs,
    credentialStore: secrets,
    nativePushSupported: false,
  );
  final connection = SavedConnection(
    id: 'native-dashboard-account',
    label: 'OIDC dashboard',
    host: 'api.example.test',
    port: 443,
    useHttps: true,
    apiKey: 'synthetic-api-server-only',
    desktopGatewayUrl: 'https://dashboard.example.test:9443/proxy',
    gatewayProfile: 'research',
  );
  await manager.importConnections([connection], replaceExisting: true);
  // Seed only through the real secure-storage API, not a widget fake or the
  // store's private serialization. These are synthetic regression fixtures.
  await manager.saveDashboardNativeTokens(
    connection,
    accessToken: 'synthetic-native-access',
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    provider: 'oidc',
    userId: 'synthetic-subject',
  );
  return (manager, secrets, connection);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dashboard browser sign-in uses its own origin and permits retry '
      'when the external browser cannot open', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = _MemoryCredentials();
    final manager = ConnectionManager(
      prefs,
      credentialStore: secrets,
      nativePushSupported: false,
    );
    final connection = SavedConnection(
      id: 'browser-sign-in',
      label: 'Separate OIDC dashboard',
      host: 'api.example.test',
      port: 443,
      useHttps: true,
      apiKey: 'synthetic-api-server-only',
      gatewayPrefix: '/gateway',
      // The browser must use this dashboard origin/path, not the API server
      // or the legacy dashboard prefix. No username/password is configured.
      desktopGatewayUrl: 'https://dashboard.example.test:9443/proxy',
      dashboardPrefix: '/legacy-dashboard',
      gatewayProfile: 'research',
    );
    await manager.importConnections([connection], replaceExisting: true);
    final initialSecrets = Map<String, String>.of(secrets.values);
    final initialMetadata = prefs.getStringList('saved_connections');

    final launches = <MethodCall>[];
    var browserAttempted = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_launcher, (call) async {
      expect(call.method, 'launch');
      launches.add(call);
      if (!browserAttempted.isCompleted) browserAttempted.complete();
      // Exercise the real authorization/UI error path, without opening a
      // real browser, approving an account, or inventing bearer tokens.
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_launcher, null));

    await _openDashboardSettings(tester, manager);
    expect(launches, isEmpty, reason: 'Opening settings is not consent.');

    final signIn = _browserSignInButton();
    expect(
      signIn,
      findsOneWidget,
      reason:
          'An OIDC-only dashboard needs an enabled browser sign-in '
          'action; optional password fields are not an OIDC login flow.',
    );
    await tester.ensureVisible(signIn);
    await tester.runAsync(() async {
      await tester.tap(signIn);
      await tester.pump();
      await browserAttempted.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();

    expect(launches, hasLength(1));
    final arguments = launches.single.arguments as Map<dynamic, dynamic>;
    final authorize = Uri.parse(arguments['url'] as String);
    expect(authorize.origin, 'https://dashboard.example.test:9443');
    expect(authorize.path, '/proxy/auth/native/authorize');
    expect(authorize.queryParameters['code_challenge_method'], 'S256');
    expect(authorize.queryParameters['code_challenge'], isNotEmpty);
    expect(authorize.queryParameters['state'], isNotEmpty);
    final callback = Uri.parse(authorize.queryParameters['redirect_uri']!);
    expect(callback.scheme, 'http');
    expect(callback.host, '127.0.0.1');
    expect(callback.port, greaterThan(0));
    expect(arguments['useWebView'], isFalse);
    expect(arguments['useSafariVC'], isFalse);
    expect(arguments['headers'], isEmpty);
    expect(authorize.toString(), isNot(contains(connection.apiKey)));
    expect(authorize.queryParameters, isNot(contains('code_verifier')));

    // A launcher failure is not sign-in, must not damage API-server access,
    // and must leave a usable retry action rather than a stuck spinner.
    expect(_browserSignInButton(), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(manager.getConnections().single.apiKey, connection.apiKey);
    expect(secrets.values, initialSecrets);
    expect(prefs.getStringList('saved_connections'), initialMetadata);
    browserAttempted = Completer<void>();
    await tester.ensureVisible(_browserSignInButton());
    await tester.runAsync(() async {
      await tester.tap(_browserSignInButton());
      await tester.pump();
      await browserAttempted.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(launches, hasLength(2), reason: 'Retry must launch a new login.');
    final retriedArguments = launches.last.arguments as Map<dynamic, dynamic>;
    final retry = Uri.parse(retriedArguments['url'] as String);
    expect(
      retry.queryParameters['state'],
      isNot(authorize.queryParameters['state']),
    );
    expect(_browserSignInButton(), findsOneWidget);
    expect(secrets.values, initialSecrets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard sign-out clears native tokens but preserves API access',
    (tester) async {
      final (manager, secrets, connection) = await _createSignedInManager(
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        refreshToken: 'synthetic-native-refresh',
      );
      final initialMetadata = manager.prefs.getStringList('saved_connections');
      expect(
        secrets.values.values.join(),
        contains('synthetic-native-refresh'),
      );
      await _openDashboardSettings(tester, manager);

      final signOut = _enabledButton('Sign out');
      expect(
        signOut,
        findsOneWidget,
        reason:
            'A securely saved dashboard session needs a user-visible '
            'sign-out action, not an API-key edit or connection deletion.',
      );
      expect(_browserSignInButton(), findsNothing);
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await tester.pumpAndSettle();

      expect(
        secrets.values.values.join(),
        isNot(contains('synthetic-native-access')),
      );
      expect(
        secrets.values.values.join(),
        isNot(contains('synthetic-native-refresh')),
      );
      expect(manager.getConnections().single.apiKey, connection.apiKey);
      expect(manager.prefs.getStringList('saved_connections'), initialMetadata);
      expect(
        _browserSignInButton(),
        findsOneWidget,
        reason: 'Sign-out must update this dialog, not require an app restart.',
      );
      // Re-open from storage to ensure sign-out was persisted, not a local-only
      // visual state change. The dashboard must once again offer browser sign-in.
      await tester.pumpWidget(const SizedBox.shrink());
      await _openDashboardSettings(tester, manager);
      expect(_browserSignInButton(), findsOneWidget);
      expect(_enabledButton('Sign out'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expired nonrenewable dashboard session offers sign-in again', (
    tester,
  ) async {
    final (manager, secrets, connection) = await _createSignedInManager(
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final initialMetadata = manager.prefs.getStringList('saved_connections');
    await _openDashboardSettings(tester, manager);

    expect(
      _enabledButton('Sign in again'),
      findsOneWidget,
      reason:
          'An expired dashboard token without a refresh token requires '
          'explicit browser reauthentication, not a password or API-key edit.',
    );
    expect(_enabledButton('Sign out'), findsNothing);
    expect(manager.getConnections().single.apiKey, connection.apiKey);
    expect(manager.prefs.getStringList('saved_connections'), initialMetadata);
    for (final token in [
      'synthetic-native-access',
      'synthetic-native-refresh',
    ]) {
      expect(find.textContaining(token), findsNothing);
      expect(
        manager.prefs.getStringList('saved_connections').toString(),
        isNot(contains(token)),
      );
    }
    expect(secrets.values.values.join(), contains(connection.apiKey));
    expect(tester.takeException(), isNull);
  });

  for (final interruption in [
    'none',
    'dismiss',
    'cancel',
    'signOut',
    'replace',
  ]) {
    testWidgets(
      'browser callback with $interruption interruption respects attempt authority',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final manager = ConnectionManager(
          await SharedPreferences.getInstance(),
          credentialStore: _MemoryCredentials(),
          nativePushSupported: false,
        );
        final previous = HttpOverrides.current;
        HttpOverrides.global = _TrustedFixtureOverrides();
        late HttpServer server;
        final redemption = Completer<void>();
        final respond = Completer<void>();
        await tester.runAsync(() async {
          final tls = SecurityContext()
            ..useCertificateChain('test/fixtures/mtls-server-cert.pem')
            ..usePrivateKey('test/fixtures/mtls-server-key.pem');
          server = await HttpServer.bindSecure(
            InternetAddress.loopbackIPv4,
            0,
            tls,
          );
          server.listen((request) async {
            expect(request.uri.path, '/proxy/auth/native/token');
            expect(request.headers.value('authorization'), isNull);
            expect(request.headers.value('cookie'), isNull);
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            expect(body['code'], 'synthetic-broker-code');
            expect(body['code_verifier'], isNotEmpty);
            if (!redemption.isCompleted) redemption.complete();
            await respond.future;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'access_token': 'synthetic-browser-access',
                'refresh_token': 'synthetic-browser-refresh',
                'token_type': 'Bearer',
                'expires_at':
                    DateTime.now()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch ~/
                    1000,
                'provider': 'oidc',
                'user_id': 'synthetic-subject',
              }),
            );
            await request.response.close();
          });
        });
        addTearDown(() async {
          if (!respond.isCompleted) respond.complete();
          HttpOverrides.global = previous;
          await server.close(force: true);
        });
        final connection = SavedConnection(
          id: 'browser-callback',
          label: 'OIDC callback',
          host: 'api.example.test',
          port: 443,
          useHttps: true,
          apiKey: 'synthetic-api-only',
          desktopGatewayUrl: 'https://127.0.0.1:${server.port}/proxy',
          gatewayProfile: 'research',
        );
        await manager.importConnections([connection], replaceExisting: true);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(_launcher, (call) async {
          final authorize = Uri.parse((call.arguments as Map)['url'] as String);
          final callback = Uri.parse(authorize.queryParameters['redirect_uri']!)
              .replace(
                queryParameters: {
                  'state': authorize.queryParameters['state']!,
                  'code': 'synthetic-broker-code',
                },
              );
          final client = HttpClient();
          try {
            final response = await (await client.getUrl(callback)).close();
            await response.drain<void>();
            expect(response.statusCode, 200);
          } finally {
            client.close(force: true);
          }
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(_launcher, null));
        await _openDashboardSettings(tester, manager);
        await tester.ensureVisible(_browserSignInButton());
        await tester.runAsync(() async {
          await tester.tap(_browserSignInButton());
          await tester.pump();
        });
        // Platform-channel replies and real sockets cross the fake-async zone
        // repeatedly. Pump between real I/O turns rather than starving it.
        for (var i = 0; i < 100 && !redemption.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(redemption.isCompleted, isTrue);
        if (interruption == 'dismiss') {
          // Pop without pumping the reverse transition: the widget is still
          // mounted, but this route no longer has authority to save credentials.
          Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        } else if (interruption == 'cancel') {
          await tester.ensureVisible(_enabledButton('Cancel').first);
          await tester.tap(_enabledButton('Cancel').first);
          await tester.pump();
        } else if (interruption == 'signOut') {
          await manager.clearDashboardNativeTokens(connection.id);
        } else if (interruption == 'replace') {
          await manager.importConnections([
            connection.copyWith(apiKey: 'synthetic-replacement-api'),
          ], replaceExisting: true);
        }
        final statusBefore = await manager.dashboardNativeAuthStatus(
          connection,
        );
        await tester.runAsync(() async {
          respond.complete();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        for (var i = 0; i < 100; i++) {
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.pumpAndSettle();
        expect(
          await manager.dashboardNativeAuthStatus(connection),
          interruption == 'none'
              ? DashboardNativeSessionStatus.signedIn
              : statusBefore,
        );
        if (interruption == 'none') {
          expect(_enabledButton('Sign out'), findsOneWidget);
          expect(find.textContaining('synthetic-browser-access'), findsNothing);
          expect(
            manager.prefs.getStringList('saved_connections').toString(),
            isNot(contains('synthetic-browser-access')),
          );
        }
        expect(
          manager.getConnections().single.apiKey,
          interruption == 'replace'
              ? 'synthetic-replacement-api'
              : 'synthetic-api-only',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'new OIDC users can defer dashboard details and save API access',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final manager = ConnectionManager(
        prefs,
        credentialStore: _MemoryCredentials(),
        nativePushSupported: false,
      );
      final turns = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(turns.close);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        testAppWithL10n(
          HomeScreen(connManager: manager, turnApplicationController: turns),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Connection'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('save the API connection first'),
        findsOneWidget,
        reason: 'OIDC onboarding must explain the API-first path.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Host'),
        'http://api.example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'API Key'),
        'synthetic-api-only',
      );
      final requests = <String>[];
      final previous = HttpOverrides.current;
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await request.drain<void>();
          requests.add(request.uri.path);
          expect(
            request.headers.value('authorization'),
            'Bearer synthetic-api-only',
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        });
      });
      HttpOverrides.global = _ApiLoopbackOverrides(server.port);
      addTearDown(() async {
        HttpOverrides.global = previous;
        await server.close(force: true);
      });
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(manager.getConnections().single.desktopGatewayUrl, isNull);
      expect(manager.getConnections().single.apiKey, 'synthetic-api-only');
      expect(requests, isNotEmpty);
      expect(requests, everyElement(anyOf('/health', '/api/sessions')));
      await _openDashboardSettings(tester, manager);
      expect(
        find.widgetWithText(TextField, 'Dashboard URL / trusted origin'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved API connection can configure an OIDC dashboard before login',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = _MemoryCredentials();
      final manager = ConnectionManager(
        prefs,
        credentialStore: secrets,
        nativePushSupported: false,
      );
      await manager.saveConnection(
        'API first',
        'https://api.example.test',
        443,
        'synthetic-api-only',
      );
      await _openDashboardSettings(tester, manager);
      final origin = find.widgetWithText(
        TextField,
        'Dashboard URL / trusted origin',
      );
      expect(
        origin,
        findsOneWidget,
        reason:
            'Dashboard settings must configure a distinct OIDC origin after API save.',
      );
      await tester.ensureVisible(origin);
      await tester.enterText(
        origin,
        'https://dashboard.example.test:9443/proxy',
      );
      final oidc = find.byKey(const Key('dashboard_native_mode'));
      expect(oidc, findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(oidc);
      if (!toggle.value) {
        await tester.ensureVisible(oidc);
        await tester.tap(oidc);
        await tester.pumpAndSettle();
      }
      expect(
        find.textContaining('Saving does not authenticate'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final saved = manager.getConnections().single;
      expect(
        saved.desktopGatewayUrl,
        'https://dashboard.example.test:9443/proxy',
      );
      expect(saved.apiKey, 'synthetic-api-only');
      expect(
        await manager.dashboardNativeAuthStatus(saved),
        DashboardNativeSessionStatus.signedOut,
      );
      await _openDashboardSettings(tester, manager);
      expect(_browserSignInButton(), findsOneWidget);
      expect(_enabledButton('Sign out'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
