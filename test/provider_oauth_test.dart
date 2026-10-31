import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/provider_oauth.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/screens/provider_oauth_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> device({
  String url = 'https://auth.openai.com/codex/device',
  num expires = 30,
  num interval = 2,
}) => {
  'session_id': 'session-id',
  'flow': 'device_code',
  'user_code': 'ABCD-EFGH',
  'verification_url': url,
  'expires_in': expires,
  'poll_interval': interval,
};

final connection = SavedConnection(
  id: 'oauth',
  label: 'Test',
  host: 'example.test',
  port: 8642,
  apiKey: '',
  useHttps: true,
  dashboardProxied: true,
  gatewayProfile: 'selected',
);

class OAuthDashboard extends DashboardClient {
  OAuthDashboard() : super(host: 'example.test', useHttps: true, proxied: true);
  int starts = 0,
      polls = 0,
      cancels = 0,
      catalogs = 0,
      inventories = 0,
      usages = 0,
      closes = 0;
  bool failCatalog = false,
      failStart = false,
      failPoll = false,
      failCancel = false;
  String status = 'pending';
  String providerId = 'openai-codex';
  String? accountEmail;
  String? readbackEmail;
  bool loggedIn = false;
  bool omitLoginStatus = false;
  bool omitProvider = false;
  bool failIdentityReadback = false;
  Completer<Map<String, dynamic>>? heldIdentityReadback;
  Map<String, dynamic> response = device();
  Completer<Map<String, dynamic>>? heldStart, heldPoll, heldCatalog;
  @override
  Future<Map<String, dynamic>> getProviderOAuthCatalog() async {
    catalogs++;
    if (heldCatalog != null) return heldCatalog!.future;
    if (failCatalog) throw StateError('secret error detail');
    return {
      'providers': [
        if (!omitProvider)
          {
            'id': providerId,
            'name': 'Codex',
            'flow': 'device_code',
            'status': {
              if (!omitLoginStatus) 'logged_in': loggedIn,
              'token_preview': 'do-not-display',
            },
          },
        {'id': 'anthropic', 'name': 'Claude', 'flow': 'external'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> startProviderOAuth(String providerId) async {
    starts++;
    if (heldStart != null) return heldStart!.future;
    if (failStart) throw StateError('secret start detail');
    return response;
  }

  @override
  Future<Map<String, dynamic>> pollProviderOAuth(
    String providerId,
    String sessionId,
  ) async {
    polls++;
    if (polls > 1 && status == 'approved') {
      if (failIdentityReadback) throw StateError('secret identity error');
      if (heldIdentityReadback != null) return heldIdentityReadback!.future;
    }
    if (heldPoll != null) return heldPoll!.future;
    if (failPoll) throw StateError('secret poll detail');
    return {
      'session_id': sessionId,
      'status': status,
      'account_email': polls > 1 ? readbackEmail : accountEmail,
      'error_message': 'secret detail',
    };
  }

  @override
  Future<void> cancelProviderOAuth(String sessionId) async {
    cancels++;
    if (failCancel) throw StateError('secret cancel detail');
  }

  @override
  Future<Map<String, dynamic>> getModelOptions() async {
    inventories++;
    return {};
  }

  @override
  Future<Map<String, dynamic>> getModelsAnalytics({int days = 30}) async {
    usages++;
    return {};
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

Widget screen(
  OAuthDashboard client, {
  SavedConnection? selected,
  Future<bool> Function(Uri)? browser,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: ProviderOAuthScreen(
    key: const ValueKey('oauth'),
    connection: selected ?? connection,
    dashboardClient: client,
    openBrowser: browser,
  ),
);

Future<void> start(WidgetTester tester, OAuthDashboard client) async {
  await tester.pumpWidget(screen(client));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sign in').first);
  await tester.pump();
}

void main() {
  testWidgets('invalid mTLS fails closed and retry does not bypass identity', (
    tester,
  ) async {
    final invalid = connection.copyWith(
      clientCertificate: const ClientCertificateConfig(
        label: 'Synthetic',
        certificatePemPath: 'test/fixtures/no-oauth-cert.pem',
        privateKeyPemPath: 'test/fixtures/no-oauth-key.pem',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ProviderOAuthScreen(connection: invalid),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('secure dashboard transport'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('secure dashboard transport'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('no-oauth-cert'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('resume with held poll never duplicates host requests', (
    tester,
  ) async {
    final client = OAuthDashboard()..heldPoll = Completer();
    await start(tester, client);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 4));
    expect(client.polls, 1);
    client.heldPoll!.complete({
      'session_id': 'session-id',
      'status': 'pending',
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(client.polls, 1);
    await tester.tap(find.text('Cancel sign-in'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
  testWidgets('start and poll failures are safe and permit explicit retry', (
    tester,
  ) async {
    final client = OAuthDashboard()..failStart = true;
    await start(tester, client);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not start secure'), findsOneWidget);
    expect(find.textContaining('secret start'), findsNothing);
    client.failStart = false;
    client.failPoll = true;
    await tester.tap(find.text('Sign in').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not check sign-in status'),
      findsOneWidget,
    );
    expect(client.cancels, 1);
    expect(find.textContaining('secret poll'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
  testWidgets(
    'large text narrow layout keeps external providers noninteractive',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = OAuthDashboard();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ProviderOAuthScreen(
              connection: connection,
              dashboardClient: client,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(client.starts, 0);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
  group('OAuth public contract', () {
    test('only audited Nous account_email establishes identity', () {
      for (final value in [
        null,
        '',
        ' ',
        ' account@example.test',
        'account@example.test\n',
        42,
      ]) {
        expect(oauthAccountEmail('nous', {'account_email': value}), isNull);
      }
      expect(
        oauthAccountEmail('nous', {'account_email': 'account@example.test'}),
        'account@example.test',
      );
      for (final provider in ['openai-codex', 'minimax-oauth', 'xai-oauth']) {
        expect(
          oauthAccountEmail(provider, {
            'account_email': 'account@example.test',
          }),
          isNull,
        );
      }
      expect(
        oauthAccountEmail('nous', {
          'source_label': 'account@example.test',
          'token_preview': 'secret',
        }),
        isNull,
      );
      expect(
        OAuthProvider.fromJson({
          'id': 'nous',
          'name': 'Nous',
          'flow': 'device_code',
          'status': {'logged_in': 'true'},
        }).statusKnown,
        isFalse,
      );
    });
    test('catalog is capability driven and drops sensitive status fields', () {
      final p = OAuthProvider.fromJson({
        'id': 'plugin-provider',
        'name': 'Plugin',
        'flow': 'browser_pkce',
        'status': {'logged_in': true, 'access_token': 'secret'},
      });
      expect(p.loggedIn, isTrue);
      expect(p.disabledReason, isNotNull);
      expect(
        OAuthProvider.fromJson({
          'id': 'codex',
          'name': 'Codex',
          'flow': 'device_code',
        }).disabledReason,
        isNull,
      );
      for (final id in [
        '../x',
        'https://evil.test',
        '',
        'a/b',
        'x?profile=y',
      ]) {
        expect(
          () => OAuthProvider.fromJson({
            'id': id,
            'name': 'X',
            'flow': 'device_code',
          }),
          throwsFormatException,
        );
      }
    });
    test(
      'only strict HTTPS verification links without userinfo are accepted',
      () {
        for (final url in [
          'javascript:alert(1)',
          'file:///tmp/x',
          'http://provider.test',
          'https://user:pass@provider.test',
          'https://provider.test:444/x',
          'https://provider.test/#fragment',
          '//provider.test/x',
          ' https://provider.test',
          'https://provider.test/\nx',
          'https://provider.test\\@evil.test',
        ]) {
          expect(safeProviderOAuthUrl(url), isNull, reason: url);
          expect(
            () => OAuthDeviceSession.fromJson(device(url: url)),
            throwsFormatException,
          );
        }
        expect(
          safeProviderOAuthUrl('https://provider.test/verify?user_code=ABC'),
          isNotNull,
        );
      },
    );
    test('session timing is finite positive, bounded by backend TTL', () {
      expect(
        OAuthDeviceSession.fromJson(device(expires: 9999)).lifetime,
        const Duration(minutes: 15),
      );
      expect(
        OAuthDeviceSession.fromJson(device(interval: 2.5)).pollInterval,
        const Duration(milliseconds: 2500),
      );
      for (final invalid in [0, -1, double.infinity, double.nan]) {
        expect(
          () => OAuthDeviceSession.fromJson(device(expires: invalid)),
          throwsFormatException,
        );
        expect(
          () => OAuthDeviceSession.fromJson(device(interval: invalid)),
          throwsFormatException,
        );
      }
    });
    test(
      'status requires exact session identity and known terminal states',
      () {
        for (final status in OAuthLoginStatus.values) {
          expect(
            parseOAuthStatus({'session_id': 's', 'status': status.name}, 's'),
            status,
          );
        }
        expect(
          () => parseOAuthStatus({
            'session_id': 'other',
            'status': 'approved',
          }, 's'),
          throwsFormatException,
        );
        expect(
          () => parseOAuthStatus({'session_id': 's', 'status': 'success'}, 's'),
          throwsFormatException,
        );
      },
    );
  });

  group('OAuth dashboard wire', () {
    test(
      'preserves prefix profile proxy authority on every audited endpoint',
      () async {
        final requests = <http.Request>[];
        final client = DashboardClient(
          host: 'gateway.test',
          port: 9443,
          useHttps: true,
          pathPrefix: '/hermes/team',
          gatewayProfile: 'work & play',
          proxied: true,
          username: 'unused',
          password: 'unused',
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response('{"ok":true}', 200);
          }),
        );
        await client.getProviderOAuthCatalog();
        await client.startProviderOAuth('openai-codex');
        await client.pollProviderOAuth('openai-codex', 'session-id');
        await client.cancelProviderOAuth('session-id');
        expect(requests.map((r) => '${r.method} ${r.url.path}'), [
          'GET /hermes/team/api/providers/oauth',
          'POST /hermes/team/api/providers/oauth/openai-codex/start',
          'GET /hermes/team/api/providers/oauth/openai-codex/poll/session-id',
          'DELETE /hermes/team/api/providers/oauth/sessions/session-id',
        ]);
        for (final r in requests) {
          expect(r.url.queryParameters, {'profile': 'work & play'});
          expect(r.url.host, 'gateway.test');
          expect(r.headers['authorization'], isNull);
          expect(r.headers['cookie'], isNull);
          expect(r.followRedirects, isFalse);
          expect(r.body, isEmpty);
        }
        client.close();
      },
    );
    test(
      'password cookie authentication reused and 401 retry bounded',
      () async {
        var logins = 0, oauth = 0;
        final client = DashboardClient(
          host: 'gateway.test',
          useHttps: true,
          username: 'test',
          password: 'fake-fixture',
          gatewayProfile: 'secondary',
          httpClient: MockClient((r) async {
            if (r.url.path == '/auth/password-login') {
              logins++;
              expect(jsonDecode(r.body)['provider'], 'basic');
              return http.Response(
                '{}',
                200,
                headers: {
                  'set-cookie': 'hermes_session_at=fake-$logins; Path=/',
                },
              );
            }
            oauth++;
            expect(r.headers['cookie'], 'hermes_session_at=fake-$logins');
            expect(r.url.queryParameters['profile'], 'secondary');
            return http.Response('sensitive error', 401);
          }),
        );
        await expectLater(client.getProviderOAuthCatalog(), throwsStateError);
        expect(logins, 2);
        expect(oauth, 2);
        client.close();
      },
    );
    test(
      'redirects and unsupported hosts fail closed, identifiers cannot inject routes',
      () async {
        var calls = 0;
        final mock = MockClient((r) async {
          calls++;
          return http.Response(
            'private-body',
            302,
            headers: {'location': 'https://provider.test'},
          );
        });
        final client = DashboardClient(
          host: 'gateway.test',
          useHttps: true,
          proxied: true,
          httpClient: mock,
        );
        await expectLater(client.startProviderOAuth('codex'), throwsStateError);
        expect(calls, 1);
        expect(() => client.startProviderOAuth('../x'), throwsArgumentError);
        final plain = DashboardClient(
          host: 'gateway.test',
          proxied: true,
          httpClient: mock,
        );
        expect(
          plain.providerOAuthUnavailableReason,
          OAuthTransportUnavailableReason.httpsRequired,
        );
        await expectLater(plain.getProviderOAuthCatalog(), throwsStateError);
        expect(calls, 1);
        final unauthenticated = DashboardClient(
          host: 'gateway.test',
          useHttps: true,
          httpClient: mock,
        );
        expect(
          unauthenticated.providerOAuthUnavailableReason,
          OAuthTransportUnavailableReason.authenticationRequired,
        );
        await expectLater(
          unauthenticated.getProviderOAuthCatalog(),
          throwsStateError,
        );
        expect(calls, 1);
        client.close();
        plain.close();
        unauthenticated.close();
      },
    );
  });

  testWidgets(
    'approval polls at host interval and refreshes only safe catalog; Codex identity unavailable',
    (tester) async {
      final client = OAuthDashboard();
      final launched = <Uri>[];
      await tester.pumpWidget(
        screen(
          client,
          browser: (uri) async {
            launched.add(uri);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('do-not-display'), findsNothing);
      expect(find.textContaining('provider CLI'), findsOneWidget);
      await tester.tap(find.text('Sign in').first);
      await tester.pump();
      expect(client.starts, 1);
      expect(client.polls, 0);
      expect(launched, isEmpty);
      expect(find.text('ABCD-EFGH'), findsOneWidget);
      await tester.tap(find.text('Open provider in browser'));
      await tester.pump();
      expect(
        launched.single.toString(),
        'https://auth.openai.com/codex/device',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(client.polls, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(client.polls, 1);
      client.status = 'approved';
      client.loggedIn = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(client.inventories, 0);
      expect(client.usages, 0);
      expect(client.catalogs, 2);
      expect(
        find.textContaining(
          'Approval received; account verification unavailable',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Signed in'), findsNothing);
      expect(find.text('ABCD-EFGH'), findsNothing);
      expect(client.cancels, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(client.closes, 0);
      client.close();
    },
  );
  testWidgets(
    'Nous success waits for catalog and matching scoped account readback',
    (tester) async {
      final client = OAuthDashboard()
        ..providerId = 'nous'
        ..status = 'approved'
        ..accountEmail = 'account@example.test'
        ..readbackEmail = 'account@example.test'
        ..heldIdentityReadback = Completer();
      await start(tester, client);
      client.loggedIn = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(client.catalogs, 2);
      expect(client.polls, 2);
      expect(find.textContaining('Signed in'), findsNothing);
      expect(find.textContaining('Checking host account'), findsOneWidget);
      client.heldIdentityReadback!.complete({
        'session_id': 'session-id',
        'status': 'approved',
        'account_email': 'account@example.test',
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Signed in on the Hermes host as account@example.test',
        ),
        findsOneWidget,
      );
      expect(client.inventories, 0);
      expect(client.usages, 0);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  for (final failure in [
    'logged-out',
    'missing-status',
    'missing-provider',
    'catalog-error',
    'changed-account',
    'missing-email',
    'readback-error',
    'no-identity',
  ]) {
    testWidgets('approval cannot claim success with $failure', (tester) async {
      final client = OAuthDashboard()
        ..providerId = 'nous'
        ..status = 'approved'
        ..accountEmail = 'account@example.test'
        ..readbackEmail = 'account@example.test';
      await start(tester, client);
      client.loggedIn = failure != 'logged-out';
      client.omitLoginStatus = failure == 'missing-status';
      client.omitProvider = failure == 'missing-provider';
      client.failCatalog = failure == 'catalog-error';
      client.failIdentityReadback = failure == 'readback-error';
      if (failure == 'changed-account') {
        client.readbackEmail = 'other@example.test';
      }
      if (failure == 'missing-email') client.readbackEmail = null;
      if (failure == 'no-identity') client.accountEmail = null;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('Signed in'), findsNothing);
      expect(
        find.textContaining(
          'Approval received; account verification unavailable',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('secret'), findsNothing);
      expect(find.textContaining('other@example.test'), findsNothing);
      expect(client.inventories, 0);
      expect(client.usages, 0);
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
  }

  for (final stage in ['catalog', 'identity']) {
    for (final replace in [false, true]) {
      testWidgets(
        'held $stage readback ignored after ${replace ? 'profile replacement' : 'disposal'}',
        (tester) async {
          final old = OAuthDashboard()
            ..providerId = 'nous'
            ..status = 'approved'
            ..accountEmail = 'old@example.test'
            ..readbackEmail = 'old@example.test';
          await start(tester, old);
          old.loggedIn = true;
          final held = Completer<Map<String, dynamic>>();
          if (stage == 'catalog') {
            old.heldCatalog = held;
          } else {
            old.heldIdentityReadback = held;
          }
          await tester.pump(const Duration(seconds: 2));
          await tester.pump();
          final replacement = OAuthDashboard();
          if (replace) {
            await tester.pumpWidget(
              screen(
                replacement,
                selected: connection.copyWith(gatewayProfile: 'other'),
              ),
            );
          } else {
            await tester.pumpWidget(const SizedBox());
          }
          held.complete(
            stage == 'catalog'
                ? {
                    'providers': [
                      {
                        'id': 'nous',
                        'name': 'Nous',
                        'flow': 'device_code',
                        'status': {'logged_in': true},
                      },
                    ],
                  }
                : {
                    'session_id': 'session-id',
                    'status': 'approved',
                    'account_email': 'old@example.test',
                  },
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('old@example.test'), findsNothing);
          expect(find.textContaining('Signed in'), findsNothing);
          expect(old.polls, stage == 'catalog' ? 1 : 2);
          expect(replacement.polls, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          old.close();
          replacement.close();
        },
      );
    }
  }

  testWidgets(
    'post-approval catalog redirect rejects cookie forwarding and unsafe refresh endpoints',
    (tester) async {
      final requests = <http.Request>[];
      var catalogs = 0;
      final client = DashboardClient(
        host: 'gateway.test',
        useHttps: true,
        pathPrefix: '/team',
        gatewayProfile: 'selected',
        username: 'fixture',
        password: 'fixture-password',
        httpClient: MockClient((r) async {
          requests.add(r);
          expect(r.url.host, 'gateway.test');
          if (r.url.path == '/team/auth/password-login') {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'hermes_session_at=fixture; Path=/'},
            );
          }
          expect(r.url.queryParameters, {'profile': 'selected'});
          expect(r.headers['cookie'], 'hermes_session_at=fixture');
          expect(r.followRedirects, isFalse);
          if (r.url.path == '/team/api/providers/oauth') {
            catalogs++;
            if (catalogs == 2) {
              return http.Response(
                'private redirect',
                307,
                headers: {'location': 'https://attacker.test/collect'},
              );
            }
            return http.Response(
              jsonEncode({
                'providers': [
                  {
                    'id': 'nous',
                    'name': 'Nous',
                    'flow': 'device_code',
                    'status': {'logged_in': false},
                  },
                ],
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/start')) {
            return http.Response(jsonEncode(device()), 200);
          }
          if (r.url.path.contains('/poll/')) {
            return http.Response(
              jsonEncode({
                'session_id': 'session-id',
                'status': 'approved',
                'account_email': 'account@example.test',
              }),
              200,
            );
          }
          fail('Unexpected post-approval request: ${r.url.path}');
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProviderOAuthScreen(
            connection: connection,
            dashboardClient: client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(catalogs, 2);
      expect(requests.length, 5);
      expect(requests.where((r) => r.url.host == 'attacker.test'), isEmpty);
      expect(find.textContaining('Signed in'), findsNothing);
      expect(
        find.textContaining(
          'Approval received; account verification unavailable',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private redirect'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  for (final status in ['denied', 'expired', 'cancelled', 'error']) {
    testWidgets(
      '$status ends pending flow without showing raw backend detail',
      (tester) async {
        final client = OAuthDashboard()..status = status;
        await start(tester, client);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('ABCD-EFGH'), findsNothing);
        expect(find.textContaining('secret detail'), findsNothing);
        expect(client.inventories, 0);
        await tester.pump(const Duration(seconds: 10));
        expect(client.polls, 1);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
  }
  testWidgets(
    'expiry is bounded even while poll hangs, late success cannot refresh',
    (tester) async {
      final client = OAuthDashboard()..heldPoll = Completer();
      await start(tester, client);
      await tester.pump(const Duration(seconds: 2));
      expect(client.polls, 1);
      await tester.pump(const Duration(seconds: 28));
      await tester.pump();
      expect(client.cancels, 1);
      expect(find.textContaining('expired'), findsOneWidget);
      client.heldPoll!.complete({
        'session_id': 'session-id',
        'status': 'approved',
      });
      await tester.pumpAndSettle();
      expect(client.inventories, 0);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
  testWidgets(
    'duplicate start prevented; dispose cancels late start on old authority',
    (tester) async {
      final client = OAuthDashboard()..heldStart = Completer();
      await start(tester, client);
      await tester.tap(find.text('Sign in').first);
      await tester.pump();
      expect(client.starts, 1);
      await tester.pumpWidget(const SizedBox());
      client.heldStart!.complete(device());
      await tester.pumpAndSettle();
      expect(client.cancels, 1);
      expect(client.polls, 0);
      expect(client.closes, 0);
      client.close();
    },
  );
  testWidgets(
    'profile replacement cancels old session and ignores held old poll',
    (tester) async {
      final old = OAuthDashboard()..heldPoll = Completer();
      await start(tester, old);
      await tester.pump(const Duration(seconds: 2));
      final replacement = OAuthDashboard();
      await tester.pumpWidget(screen(replacement));
      await tester.pumpAndSettle();
      expect(old.cancels, 1);
      expect(replacement.starts, 0);
      old.heldPoll!.complete({
        'session_id': 'session-id',
        'status': 'approved',
      });
      await tester.pumpAndSettle();
      expect(old.inventories, 0);
      expect(replacement.inventories, 0);
      await tester.pumpWidget(const SizedBox());
      old.close();
      replacement.close();
    },
  );
  testWidgets(
    'background pauses polling; resume obeys interval and cancellation stops it',
    (tester) async {
      final client = OAuthDashboard();
      await start(tester, client);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(client.polls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(client.polls, 1);
      await tester.tap(find.text('Cancel sign-in'));
      await tester.pumpAndSettle();
      expect(client.cancels, 1);
      expect(find.text('ABCD-EFGH'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(client.polls, 1);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
  testWidgets(
    'unsafe provider URL cancels minted session without opening browser',
    (tester) async {
      final client = OAuthDashboard()
        ..response = device(url: 'http://unsafe.test');
      await start(tester, client);
      await tester.pumpAndSettle();
      expect(client.cancels, 1);
      expect(client.polls, 0);
      expect(find.text('ABCD-EFGH'), findsNothing);
      expect(find.textContaining('Could not start secure'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
  testWidgets('unsupported backend shows explicit reason and no sign-in', (
    tester,
  ) async {
    final client = OAuthDashboard()..failCatalog = true;
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(find.textContaining('unavailable on this host'), findsOneWidget);
    expect(find.textContaining('secret error'), findsNothing);
    expect(client.starts, 0);
    client.failCatalog = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    client.close();
  });
  testWidgets(
    'browser failure is safe and cancel failure is explicitly uncertain',
    (tester) async {
      final client = OAuthDashboard()..failCancel = true;
      await tester.pumpWidget(screen(client, browser: (_) async => false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in').first);
      await tester.pump();
      await tester.tap(find.text('Open provider in browser'));
      await tester.pump();
      expect(
        find.textContaining('Could not open the external browser'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel sign-in'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancellation could not be confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('secret cancel'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
}
