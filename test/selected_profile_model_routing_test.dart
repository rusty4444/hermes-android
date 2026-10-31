import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/widgets/auxiliary_models.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_test_utils.dart';

class _TrackedClient extends MockClient {
  final void Function() onClose;
  _TrackedClient(super.handler, this.onClose);
  @override
  void close() {
    onClose();
    super.close();
  }
}

const secondary = 'research & development';

// Real TCP fixture follows archived host bf0203a's model route contract:
// GET query.profile; POST body.profile (then query); omitted = launch profile.
// Distinct stores deliberately make an accidentally unscoped read/write visible.
class ProfileModelWire {
  final requests = <Map<String, dynamic>>[];
  final assignments = <String, String>{
    'launch': 'launch-model',
    secondary: 'old',
  };
  late HttpServer server;
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      final body = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      final profile =
          body['profile'] ?? request.uri.queryParameters['profile'] ?? 'launch';
      requests.add({
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'body': body,
        'authorization': request.headers.value(HttpHeaders.authorizationHeader),
      });
      request.response.headers.contentType = ContentType.json;
      if (!assignments.containsKey(profile)) {
        request.response.statusCode = 404;
        request.response.write('{"detail":"Unknown profile"}');
      } else {
        final model = assignments[profile]!;
        final path = request.uri.path;
        Object result;
        if (path.endsWith('/model/set')) {
          assignments[profile as String] = body['model'] as String;
          result = {'ok': true};
        } else if (path.endsWith('/model/auxiliary')) {
          result = {
            'tasks': [
              {
                'task': 'vision',
                'provider': 'openai',
                'model': model,
                'base_url': '',
              },
            ],
          };
        } else if (path.endsWith('/model/info')) {
          result = {'provider': 'openai', 'model': model};
        } else {
          result = {
            'providers': [
              {
                'slug': 'openai',
                'models': [model, 'new-model'],
              },
            ],
          };
        }
        request.response.write(jsonEncode(result));
      }
      await request.response.close();
    });
  }

  Future<void> close() => server.close(force: true);
}

SavedConnection connection({int port = 9119, String? profile = secondary}) =>
    SavedConnection(
      id: 'profile-routing',
      label: 'Profile',
      host: '127.0.0.1',
      port: 8642,
      apiKey: 'synthetic-api-key',
      dashboardPortOverride: port,
      dashboardPrefix: '/proxy',
      dashboardProxied: true,
      gatewayProfile: profile,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real secondary-profile TCP discovery write and fresh-client readback across clients',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final wire = ProfileModelWire();
      await wire.start();
      final dashboard = DashboardClient(
        host: '127.0.0.1',
        port: wire.server.port,
        pathPrefix: '/proxy',
        proxied: true,
        gatewayProfile: secondary,
      );
      final api = ApiClient(
        baseUrl: wire.baseUrl,
        pathPrefix: '/p/secondary',
        apiKey: 'synthetic-api-key',
        gatewayProfile: secondary,
      );
      final desktop = DesktopGatewayClient.fromConnection(
        connection(port: wire.server.port),
      );
      try {
        expect(
          (await dashboard.getAuxiliaryModels())['tasks'][0]['model'],
          'old',
        );
        expect(
          (await dashboard.getModelOptions())['providers'][0]['models'],
          contains('old'),
        );
        expect((await desktop.getModelInfo())['model'], 'old');
        expect(
          (await desktop.getModelOptions())['providers'][0]['models'],
          contains('old'),
        );
        expect((await api.getModelInfo())['model'], 'old');
        expect(
          (await api.getModelOptions())['providers'][0]['models'],
          contains('old'),
        );
        await dashboard.setAuxiliaryModel(
          task: 'vision',
          provider: 'openai',
          model: 'new-model',
        );
        final reader = DashboardClient(
          host: '127.0.0.1',
          port: wire.server.port,
          pathPrefix: '/proxy',
          proxied: true,
          gatewayProfile: secondary,
        );
        try {
          expect(
            (await reader.getAuxiliaryModels())['tasks'][0]['model'],
            'new-model',
          );
        } finally {
          reader.close();
        }
        await dashboard.setModel('main', 'openai', 'dashboard-main');
        expect((await dashboard.getModelInfo())['model'], 'dashboard-main');
        await api.setModel('main', 'openai', 'api-main');
        expect((await desktop.getModelInfo())['model'], 'api-main');
        expect(wire.assignments['launch'], 'launch-model');
        for (final request in wire.requests) {
          if (request['method'] == 'GET') {
            expect(request['query'], {'profile': secondary});
          } else {
            expect(request['body']['profile'], secondary);
            expect(request['body'].containsKey('api_key'), isFalse);
            expect(request['body'].containsKey('base_url'), isFalse);
          }
          if ((request['path'] as String).startsWith('/proxy/')) {
            expect(request['authorization'], isNull);
          } else {
            expect(request['path'], startsWith('/p/secondary/api/model/'));
            expect(request['authorization'], 'Bearer synthetic-api-key');
          }
        }
        final auxiliaryWrite = wire.requests.firstWhere(
          (r) => r['body']['scope'] == 'auxiliary',
        );
        expect(auxiliaryWrite['body']['confirm_expensive_model'], isFalse);
      } finally {
        dashboard.close();
        api.close();
        desktop.close();
        await wire.close();
        HttpOverrides.global = overrides;
      }
    },
  );

  test(
    'omitted launch profile stays omitted; unknown profile never retries unscoped',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final wire = ProfileModelWire();
      await wire.start();
      final launch = DashboardClient(
        host: '127.0.0.1',
        port: wire.server.port,
        proxied: true,
      );
      final unknown = DashboardClient(
        host: '127.0.0.1',
        port: wire.server.port,
        proxied: true,
        gatewayProfile: 'missing',
      );
      final api = ApiClient(baseUrl: wire.baseUrl, apiKey: 'synthetic-api-key');
      try {
        expect((await launch.getModelInfo())['model'], 'launch-model');
        await launch.getModelOptions();
        await launch.getAuxiliaryModels();
        await launch.setAuxiliaryModel(
          task: 'vision',
          provider: 'auto',
          model: 'launch-updated',
        );
        await api.getModelInfo();
        await api.getModelOptions();
        await api.setModel('main', 'openai', 'launch-api');
        expect(
          wire.requests.every(
            (r) =>
                !r['query'].containsKey('profile') &&
                !r['body'].containsKey('profile'),
          ),
          isTrue,
        );
        final start = wire.requests.length;
        await expectLater(unknown.getModelOptions(), throwsException);
        await expectLater(unknown.getAuxiliaryModels(), throwsException);
        await expectLater(
          unknown.setAuxiliaryModel(
            task: 'vision',
            provider: 'auto',
            model: '',
          ),
          throwsException,
        );
        expect(wire.requests.length - start, 3);
        expect(wire.assignments, {'launch': 'launch-api', secondary: 'old'});
      } finally {
        launch.close();
        unknown.close();
        api.close();
        await wire.close();
        HttpOverrides.global = overrides;
      }
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'auxiliary replacement fences held old write (failure=$fail) and readback',
      (tester) async {
        final held = Completer<http.Response>();
        var oldReads = 0;
        DashboardClient client(String profile) => DashboardClient(
          host: 'fixture.invalid',
          proxied: true,
          gatewayProfile: profile,
          httpClient: MockClient((request) async {
            expect(
              request.method == 'POST'
                  ? jsonDecode(request.body)['profile']
                  : request.url.queryParameters['profile'],
              profile,
            );
            if (request.method == 'POST') return held.future;
            if (request.url.path.endsWith('/options')) {
              return http.Response('{"providers":[]}', 200);
            }
            if (profile == 'old') oldReads++;
            return http.Response(
              jsonEncode({
                'tasks': [
                  {
                    'task': 'vision',
                    'provider': 'auto',
                    'model': profile,
                    'base_url': '',
                  },
                ],
              }),
              200,
            );
          }),
        );
        final old = client('old');
        final fresh = client('fresh');
        Widget view(DashboardClient c) =>
            testAppWithL10n(Scaffold(body: AuxiliaryModels(client: c)));
        await tester.pumpWidget(view(old));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpWidget(view(fresh));
        await tester.pumpAndSettle();
        held.complete(
          http.Response(fail ? '{}' : '{"ok":true}', fail ? 500 : 200),
        );
        await tester.pumpAndSettle();
        expect(
          oldReads,
          1,
        ); // No successor-client or departed-profile readback.
        expect(find.text('auto / fresh'), findsOneWidget);
        expect(find.text('auto / old'), findsNothing);
        expect(find.text('Auxiliary settings are unavailable.'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        old.close();
        fresh.close();
      },
    );
  }

  for (final phase in ['load', 'write', 'readback']) {
    testWidgets(
      'Settings replacement fences held old $phase and owns no injected client',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final held = Completer<http.Response>();
        var reads = 0;
        var closed = 0;
        final oldTransport = _TrackedClient((request) async {
          if (request.url.path.endsWith('/auxiliary')) {
            return http.Response('{"tasks":[]}', 200);
          }
          if (request.method == 'POST') {
            if (phase == 'write') return held.future;
            return http.Response('{"ok":true}', 200);
          }
          if (request.url.path.endsWith('/options')) {
            return http.Response(
              '{"providers":[{"slug":"openai","models":["old-model"]}]}',
              200,
            );
          }
          reads++;
          if (phase == 'load' || phase == 'readback' && reads > 1) {
            return held.future;
          }
          return http.Response(
            '{"provider":"openai","model":"old-model"}',
            200,
          );
        }, () => closed++);
        final old = DashboardClient(
          host: 'fixture.invalid',
          proxied: true,
          gatewayProfile: 'old',
          httpClient: oldTransport,
        );
        final fresh = DashboardClient(
          host: 'fixture.invalid',
          proxied: true,
          gatewayProfile: 'fresh',
          httpClient: MockClient(
            (request) async => http.Response(
              request.url.path.endsWith('/auxiliary')
                  ? '{"tasks":[]}'
                  : request.url.path.endsWith('/options')
                  ? '{"providers":[{"slug":"openai","models":["fresh-model"]}]}'
                  : '{"provider":"openai","model":"fresh-model"}',
              200,
            ),
          ),
        );
        final current = ValueNotifier(false);
        await tester.pumpWidget(
          HermesApp(connManager: ConnectionManager(prefs)),
        );
        await tester.pumpAndSettle();
        unawaited(
          Navigator.of(tester.element(find.byType(HomeScreen))).push(
            MaterialPageRoute<void>(
              builder: (_) => ValueListenableBuilder<bool>(
                valueListenable: current,
                builder: (_, replacement, _) => SettingsScreen(
                  connection: connection(
                    profile: replacement ? 'fresh' : 'old',
                  ),
                  dashboardClient: replacement ? fresh : old,
                ),
              ),
            ),
          ),
        );
        if (phase == 'load') {
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        } else {
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Set profile default'),
            300,
            scrollable: find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          // The OAuth settings tile adds vertical space. Settle the lazy-list
          // layout, then reveal the whole target before dispatching the write.
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Set profile default'));
          await tester.pumpAndSettle();
          expect(
            find.text('Set profile default').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.text('Set profile default'));
          await tester.pump();
          if (phase == 'readback') expect(reads, 2);
        }
        current.value = true;
        await tester.pumpAndSettle();
        held.complete(
          http.Response(
            phase == 'write'
                ? '{"ok":true}'
                : '{"provider":"openai","model":"old-model"}',
            200,
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('fresh-model  \nvia `openai`'),
          phase == 'load' ? 300 : -300,
          scrollable: find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.textContaining('fresh-model  \nvia `openai`'),
          findsOneWidget,
        );
        expect(find.textContaining('old-model  \nvia `openai`'), findsNothing);
        expect(reads, phase == 'readback' ? 2 : 1);
        await tester.pumpWidget(const SizedBox());
        expect(closed, 0);
        old.close();
        fresh.close();
        current.dispose();
      },
    );
  }

  testWidgets(
    'Settings default factory passes selected profile to retained auxiliary consumer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(tester.element(find.byType(HomeScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(connection: connection()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(AuxiliaryModels),
        400,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<AuxiliaryModels>(find.byType(AuxiliaryModels))
            .client
            .gatewayProfile,
        secondary,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
