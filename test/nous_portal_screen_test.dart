import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/screens/nous_portal_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/mtls_fixture.dart';

final _connection = SavedConnection(
  id: 'test',
  label: 'Test',
  host: 'gateway.test',
  port: 8642,
  apiKey: '',
  dashboardProxied: true,
  dashboardPrefix: '/hermes',
  gatewayProfile: 'research & development',
);

Map<String, dynamic> _fixture(String path) {
  if (path.endsWith('/portal')) {
    return {
      'logged_in': true,
      'free_tier': false,
      'account_tier': 'pro',
      'provider': 'openrouter',
      'features': [
        {'label': 'Web search', 'state': 'via Nous Portal'},
      ],
    };
  }
  if (path.endsWith('/usage')) {
    return {
      'period_days': 7,
      'totals': {
        'total_sessions': 12,
        'total_input': 1234,
        'total_output': 567,
        'total_estimated_cost': 1.25,
        'total_actual_cost': 0,
      },
    };
  }
  return {
    'period_days': 7,
    'models': [
      {
        'model': 'same-model',
        'provider': 'nous',
        'sessions': 2,
        'input_tokens': 10,
        'output_tokens': 20,
        'estimated_cost': 0,
        'actual_cost': 0,
      },
      {
        'model': 'same-model',
        'provider': 'openrouter',
        'sessions': 3,
        'input_tokens': 30,
        'output_tokens': 40,
        'estimated_cost': 2.5,
        'actual_cost': null,
      },
    ],
  };
}

Future<void> _pump(
  WidgetTester tester,
  http.Client? client, {
  SavedConnection? connection,
  Brightness brightness = Brightness.light,
  HermesPalette palette = HermesPalette.gold,
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness, palette: palette),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: NousPortalScreen(
        connection: connection ?? _connection,
        testHttpClient: client,
      ),
    ),
  );
  await tester.pump();
}

class _RemovalPrefs extends SharedPreferencesStorePlatform {
  _RemovalPrefs({this.fail = false, this.throws = false});
  bool fail;
  final bool throws;
  final values = <String, Object>{
    'flutter.nous_api_key': 'synthetic-unused-fixture',
    'flutter.unrelated': 'keep',
  };
  final removed = <String>[];
  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> remove(String key) async {
    removed.add(key);
    if (throws) throw StateError('fixture removal failed');
    if (fail) return false;
    values.remove(key);
    return true;
  }
}

void main() {
  test(
    'initialization deletes obsolete plaintext preference without a consumer',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RemovalPrefs();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      });
      final prefs = await SharedPreferences.getInstance();
      await ConnectionManager(prefs, nativePushSupported: false).initialize();
      expect(store.removed, ['flutter.nous_api_key']);
      expect(store.values.containsKey('flutter.nous_api_key'), isFalse);
      expect(prefs.containsKey('nous_api_key'), isFalse);
      expect(prefs.getString('unrelated'), 'keep');
    },
  );

  for (final throws in [false, true]) {
    test(
      'obsolete preference removal ${throws ? 'exception' : 'rejection'} fails honestly',
      () async {
        final original = SharedPreferencesStorePlatform.instance;
        final store = _RemovalPrefs(fail: !throws, throws: throws);
        SharedPreferencesStorePlatform.instance = store;
        SharedPreferences.resetStatic();
        addTearDown(() {
          SharedPreferencesStorePlatform.instance = original;
          SharedPreferences.resetStatic();
        });
        final prefs = await SharedPreferences.getInstance();
        await expectLater(
          ConnectionManager(prefs, nativePushSupported: false).initialize(),
          throwsStateError,
        );
        expect(store.values.containsKey('flutter.nous_api_key'), isTrue);
        if (!throws) {
          // SharedPreferences already evicted its cache despite false. A retry
          // must still delete the persisted entry, not trust containsKey.
          store.fail = false;
          await ConnectionManager(
            prefs,
            nativePushSupported: false,
          ).initialize();
          expect(store.removed, [
            'flutter.nous_api_key',
            'flutter.nous_api_key',
          ]);
          expect(store.values.containsKey('flutter.nous_api_key'), isFalse);
        }
      },
    );
  }

  testWidgets(
    'missing mTLS identity is localized, retryable and safe to dispose',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('portal-missing-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final connection = _connection.copyWith(
        clientCertificate: ClientCertificateConfig(
          label: 'synthetic-sensitive-label',
          certificatePemPath: '${directory.path}/synthetic-sensitive-cert.pem',
          privateKeyPemPath: '${directory.path}/synthetic-sensitive-key.pem',
        ),
      );
      // No HTTP injection: exercise the production synchronous TLS constructor.
      await _pump(
        tester,
        null,
        connection: connection,
        locale: const Locale('de'),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NousPortalScreen)),
      )!;
      expect(find.text(l10n.portal_unavailable), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('synthetic-sensitive'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text(l10n.retry), 200);
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.portal_unavailable), findsNWidgets(3));
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production mTLS replacement failure and same-profile retry recover',
    (tester) async {
      final fixture = MutualTlsFixture();
      var authenticatedRequests = 0;
      await tester.runAsync(
        () => fixture.start((request) async {
          expect(request.certificate, isNotNull);
          authenticatedRequests++;
          fixture.json(request, _fixture(request.uri.path));
          await request.response.close();
        }),
      );
      addTearDown(() => tester.runAsync(fixture.close));
      final directory = Directory.systemTemp.createTempSync('portal-repair-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final connection = SavedConnection(
        id: 'loopback',
        label: 'Loopback',
        host: '127.0.0.1',
        port: 8642,
        apiKey: '',
        dashboardPortOverride: fixture.server.port,
        dashboardProxied: true,
        useHttps: true,
        gatewayProfile: 'research & development',
        clientCertificate: loopbackIdentity,
      );
      Future<void> realNetwork(Future<void> Function() action) async {
        await tester.runAsync(
          () => withLoopbackTrust(() async {
            await action();
            await tester.pump();
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
                DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump();
            }
          }),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      }

      await realNetwork(() => _pump(tester, null, connection: connection));
      expect(find.text('Signed in'), findsOneWidget);
      expect(fixture.requests, hasLength(3));
      final broken = connection.copyWith(
        clientCertificate: ClientCertificateConfig(
          label: 'repaired identity',
          certificatePemPath: '${directory.path}/certificate.pem',
          privateKeyPemPath: '${directory.path}/key.pem',
        ),
      );
      await _pump(tester, null, connection: broken);
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsNothing);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NousPortalScreen)),
      )!;
      expect(find.text(l10n.portal_unavailable), findsNWidgets(3));
      expect(fixture.requests, hasLength(3));
      expect(fixture.anonymousRequests, 0);
      expect(tester.takeException(), isNull);

      // Repair files without changing the widget/connection: Retry must construct
      // a fresh client, not dereference null or reuse the closed previous client.
      File(
        loopbackIdentity.certificatePemPath,
      ).copySync(broken.clientCertificate!.certificatePemPath);
      File(
        loopbackIdentity.privateKeyPemPath,
      ).copySync(broken.clientCertificate!.privateKeyPemPath);
      await tester.scrollUntilVisible(find.text('Retry'), 200);
      await realNetwork(() => tester.tap(find.text('Retry')));
      await tester.scrollUntilVisible(find.text('Signed in'), -200);
      expect(find.text('Signed in'), findsOneWidget);
      expect(fixture.requests, hasLength(6));
      expect(authenticatedRequests, 6);
      for (final request in fixture.requests) {
        expect(request.method, 'GET');
        expect(
          request.uri.queryParameters['profile'],
          'research & development',
        );
      }
      expect(fixture.anonymousRequests, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual flat portal and analytics contracts; only scoped GETs, no fake pricing',
    (tester) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(_fixture(request.url.path)), 200);
      });
      await _pump(tester, client);
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.path, startsWith('/hermes/api/'));
        expect(
          request.url.queryParameters['profile'],
          'research & development',
        );
        if (request.url.path.contains('/analytics/')) {
          expect(request.url.queryParameters['days'], '30');
        }
      }
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Account tier: pro'), findsOneWidget);
      expect(find.text('Web search: via Nous Portal'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.scrollUntilVisible(find.text('Sessions: 12'), 250);
      expect(find.text('Input tokens: 1234'), findsOneWidget);
      expect(find.text('Estimated recorded cost: USD 1.2500'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Provider: nous'), 250);
      expect(find.text('same-model'), findsWidgets);
      expect(find.text('Free'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Actual recorded cost: —'),
        250,
      );
      expect(find.text('Provider: openrouter'), findsWidgets);
      expect(requests, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('free tier is not presented as a signed-in account', (
    tester,
  ) async {
    final client = MockClient(
      (r) async => http.Response(
        jsonEncode({
          ..._fixture(r.url.path),
          if (r.url.path.endsWith('/portal')) 'free_tier': true,
        }),
        200,
      ),
    );
    await _pump(tester, client);
    await tester.pumpAndSettle();
    expect(
      find.text('Free-tier access (not a signed-in account)'),
      findsOneWidget,
    );
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets(
    'partial failure preserves independent sections and retry clears stale data',
    (tester) async {
      var failPortal = false;
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/models') || failPortal) {
          return http.Response('secret-error-body', 404);
        }
        return http.Response(jsonEncode(_fixture(r.url.path)), 200);
      });
      await _pump(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Retry'), 300);
      expect(find.textContaining('secret-error-body'), findsNothing);
      failPortal = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gateway Portal status'), -300);
      expect(find.text('Signed in'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed and absent values remain unknown, never zero or logged out',
    (tester) async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode({
            'totals': [],
            'models': [
              null,
              'bad',
              {'model': 'unknown-cost'},
            ],
            'features': 'invalid',
          }),
          200,
        ),
      );
      await _pump(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('Not signed in'), findsNothing);
      await tester.scrollUntilVisible(find.text('Sessions: —').first, 200);
      expect(find.textContaining('USD 0.0000'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('held old connection and disposal cannot publish late results', (
    tester,
  ) async {
    final held = Completer<http.Response>();
    final old = MockClient((r) => held.future);
    await _pump(tester, old);
    final fresh = MockClient(
      (r) async => http.Response(
        jsonEncode({
          ..._fixture(r.url.path),
          if (r.url.path.endsWith('/portal')) 'logged_in': false,
        }),
        200,
      ),
    );
    await _pump(
      tester,
      fresh,
      connection: SavedConnection(
        id: 'new',
        label: 'New',
        host: 'new.test',
        port: 8642,
        apiKey: '',
        dashboardProxied: true,
      ),
    );
    await tester.pumpAndSettle();
    held.complete(
      http.Response(jsonEncode({'logged_in': true, 'provider': 'stale'}), 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.textContaining('stale'), findsNothing);
    final disposed = Completer<http.Response>();
    await _pump(tester, MockClient((r) => disposed.future));
    await tester.pumpWidget(const SizedBox());
    disposed.complete(http.Response('{}', 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final palette in HermesPalette.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'narrow scaled localized layout ${palette.name} ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var calls = 0;
          final client = MockClient((r) async {
            calls++;
            return http.Response(jsonEncode(_fixture(r.url.path)), 200);
          });
          await _pump(
            tester,
            client,
            palette: palette,
            brightness: brightness,
            scale: 2,
            locale: const Locale('de'),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Angemeldet'), 200);
          expect(find.text('Angemeldet'), findsOneWidget);
          await _pump(
            tester,
            client,
            palette: HermesPalette.purple,
            brightness: brightness,
            scale: 2,
            locale: const Locale('de'),
          );
          await tester.pumpAndSettle();
          expect(calls, 3);
          await tester.scrollUntilVisible(
            find.text('Tatsächlich erfasste Kosten: —'),
            300,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
