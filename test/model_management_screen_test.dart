import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/screens/model_management_screen.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/auxiliary_models.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_test_utils.dart';

final connection = SavedConnection(
  id: 'models',
  label: 'Research',
  host: 'example.test',
  port: 8642,
  apiKey: 'synthetic',
  gatewayProfile: 'research & development',
  dashboardPrefix: '/proxy',
  dashboardProxied: true,
);

class ModelFixture {
  final requests = <http.Request>[];
  final writes = <Map<String, dynamic>>[];
  bool accepted = true;
  bool persist = true;
  bool fail = false;
  int closes = 0;
  Completer<http.Response>? heldWrite;
  Map<String, dynamic> main = {'provider': 'openai', 'model': 'old-model'};
  List<Map<String, dynamic>> tasks = [
    for (final id in [
      'vision',
      'compression',
      'web_extract',
      'session_search',
      'skills',
      'flush_memories',
      'future_custom_task',
    ])
      {
        'task': id,
        'label': id,
        'provider': 'auto',
        'model': '',
        'base_url': '',
      },
    {
      'task': 'custom_route',
      'provider': 'custom',
      'model': 'private-model',
      'base_url': 'https://private.example/v1',
    },
  ];
  late final DashboardClient client = DashboardClient.fromConnection(
    connection,
    httpClient: MockClient((request) async {
      requests.add(request);
      if (fail) throw Exception('offline');
      final path = request.url.path;
      if (path.endsWith('/set')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        writes.add(body);
        if (heldWrite != null) return heldWrite!.future;
        if (accepted && persist) {
          if (body['scope'] == 'main') {
            main = {'provider': body['provider'], 'model': body['model']};
          } else {
            tasks = [
              for (final task in tasks)
                if (task['task'] == body['task'])
                  {
                    ...task,
                    'provider': body['provider'],
                    'model': body['model'],
                  }
                else
                  task,
            ];
          }
        }
        return http.Response(jsonEncode({'ok': accepted}), 200);
      }
      return http.Response(
        jsonEncode(
          path.endsWith('/info')
              ? main
              : path.endsWith('/auxiliary')
              ? {'tasks': tasks}
              : {
                  'providers': [
                    {
                      'slug': 'openai',
                      'models': ['old-model', 'new-model'],
                    },
                    {
                      'slug': 'other',
                      'models': ['other-model'],
                    },
                  ],
                },
        ),
        200,
      );
    }),
  );
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> changeMain(WidgetTester tester) async {
  final provider = find.byType(DropdownButtonFormField<String>).first;
  await tester.tap(provider);
  await tester.pumpAndSettle();
  await tester.tap(find.text('other').last);
  await tester.pumpAndSettle();
  await reveal(tester, find.text('Set profile default'));
  await tester.tap(find.text('Set profile default'));
}

void main() {
  testWidgets('auxiliary save locks main and refresh through readback', (
    tester,
  ) async {
    final fixture = ModelFixture()..heldWrite = Completer<http.Response>();
    addTearDown(fixture.client.close);
    await tester.pumpWidget(
      testAppWithL10n(
        ModelManagementScreen(
          connection: connection,
          dashboardClient: fixture.client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final task = find.byKey(const ValueKey('vision'));
    final save = find.descendant(of: task, matching: find.text('Save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pump();
    final main = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Set profile default'),
    );
    expect(main.onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
          .onPressed,
      isNull,
    );
    fixture.heldWrite!.complete(http.Response('{"ok":true}', 200));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Set profile default'),
          )
          .onPressed,
      isNotNull,
    );
    expect(fixture.writes.single['scope'], 'auxiliary');
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery failure retries without assignment writes', (
    tester,
  ) async {
    final fixture = ModelFixture()..fail = true;
    addTearDown(fixture.client.close);
    await tester.pumpWidget(
      testAppWithL10n(
        ModelManagementScreen(
          connection: connection,
          dashboardClient: fixture.client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.text('Retry').first;
    expect(retry, findsOneWidget);
    fixture.fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.textContaining('old-model  \nvia `openai`'), findsOneWidget);
    expect(fixture.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['saved', 'rejected', 'mismatch']) {
    testWidgets(
      'main changed provider/model $outcome requires exact readback',
      (tester) async {
        final fixture = ModelFixture()
          ..accepted = outcome != 'rejected'
          ..persist = outcome != 'mismatch';
        addTearDown(fixture.client.close);
        await tester.pumpWidget(
          testAppWithL10n(
            ModelManagementScreen(
              connection: connection,
              dashboardClient: fixture.client,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await changeMain(tester);
        await tester.pumpAndSettle();
        expect(fixture.writes.single, {
          'scope': 'main',
          'provider': 'other',
          'model': 'other-model',
          'profile': 'research & development',
        });
        for (final request in fixture.requests.where(
          (r) => r.method == 'GET',
        )) {
          expect(request.url.path, startsWith('/proxy/api/model/'));
          expect(
            request.url.queryParameters['profile'],
            'research & development',
          );
        }
        if (outcome == 'saved') {
          await reveal(tester, find.textContaining('Profile default set to'));
          expect(find.textContaining('Profile default set to'), findsOneWidget);
          expect(fixture.main, {'provider': 'other', 'model': 'other-model'});
        } else {
          expect(find.textContaining('Profile default set to'), findsNothing);
          expect(fixture.main, {'provider': 'openai', 'model': 'old-model'});
          final l10n = await loadTestL10n();
          await reveal(tester, find.text(l10n.model_management_unavailable));
          expect(find.text(l10n.model_management_unavailable), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'all server auxiliary tasks including unknown IDs are exposed and editable',
    (tester) async {
      final fixture = ModelFixture();
      addTearDown(fixture.client.close);
      await tester.pumpWidget(
        testAppWithL10n(
          ModelManagementScreen(
            connection: connection,
            dashboardClient: fixture.client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final task in fixture.tasks) {
        await reveal(
          tester,
          find.byKey(ValueKey<String>(task['task'] as String)),
        );
        expect(
          find.byKey(ValueKey<String>(task['task'] as String)),
          findsOneWidget,
        );
      }
      final task = find.byKey(const ValueKey('future_custom_task'));
      await reveal(tester, task);
      await tester.tap(
        find
            .descendant(
              of: task,
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('other').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: task,
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('other-model').last);
      await tester.pumpAndSettle();
      final save = find.descendant(of: task, matching: find.text('Save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fixture.writes.single, {
        'scope': 'auxiliary',
        'task': 'future_custom_task',
        'provider': 'other',
        'model': 'other-model',
        'confirm_expensive_model': false,
        'profile': 'research & development',
      });
      expect(
        fixture.tasks.singleWhere(
          (t) => t['task'] == 'future_custom_task',
        )['model'],
        'other-model',
      );
      final custom = find.byKey(const ValueKey('custom_route'));
      await reveal(tester, custom);
      expect(
        find.descendant(of: custom, matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: custom,
          matching: find.text('custom / private-model'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact viewport large text and unknown current main remain safe',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = ModelFixture()
        ..main = {
          'provider': 'retired-provider',
          'model': 'unlisted-model-with-a-very-long-name',
        };
      addTearDown(fixture.client.close);
      await tester.pumpWidget(
        testAppWithL10n(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: ModelManagementScreen(
                connection: connection,
                dashboardClient: fixture.client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Set profile default'));
      await reveal(tester, find.byKey(const ValueKey('future_custom_task')));
      expect(tester.takeException(), isNull);
      expect(fixture.writes, isEmpty);
    },
  );

  testWidgets('custom main endpoint is preserved read-only', (tester) async {
    final fixture = ModelFixture()
      ..main = {
        'provider': 'custom',
        'model': 'private-model',
        'base_url': 'https://private.example/v1',
      };
    addTearDown(fixture.client.close);
    await tester.pumpWidget(
      testAppWithL10n(
        ModelManagementScreen(
          connection: connection,
          dashboardClient: fixture.client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set profile default'), findsNothing);
    expect(find.text('private-model  \nvia `custom`'), findsOneWidget);
    expect(fixture.writes, isEmpty);
  });

  testWidgets(
    'disposal fences a held main write without closing injected client',
    (tester) async {
      final fixture = ModelFixture()..heldWrite = Completer<http.Response>();
      addTearDown(fixture.client.close);
      await tester.pumpWidget(
        testAppWithL10n(
          ModelManagementScreen(
            connection: connection,
            dashboardClient: fixture.client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await changeMain(tester);
      await tester.pump();
      final reads = fixture.requests
          .where((r) => r.url.path.endsWith('/info'))
          .length;
      await tester.pumpWidget(const SizedBox());
      fixture.heldWrite!.complete(http.Response('{"ok":true}', 200));
      await tester.pumpAndSettle();
      expect(
        fixture.requests.where((r) => r.url.path.endsWith('/info')),
        hasLength(reads),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing mTLS identity is safely retryable and disposable', (
    tester,
  ) async {
    final missing = connection.copyWith(
      clientCertificate: const ClientCertificateConfig(
        label: 'Missing test identity',
        certificatePemPath: '/nonexistent-model-test/cert.pem',
        privateKeyPemPath: '/nonexistent-model-test/key.pem',
      ),
    );
    await tester.pumpWidget(
      testAppWithL10n(ModelManagementScreen(connection: missing)),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Settings no longer builds model editors or performs model discovery',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fixture = ModelFixture();
      addTearDown(fixture.client.close);
      await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(tester.element(find.byType(HomeScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              connection: connection,
              dashboardClient: fixture.client,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 12; i++) {
        expect(find.byType(AuxiliaryModels), findsNothing);
        expect(find.text('Set profile default'), findsNothing);
        expect(find.text('Profile default model'), findsNothing);
        await tester.drag(scroll, const Offset(0, -350));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
