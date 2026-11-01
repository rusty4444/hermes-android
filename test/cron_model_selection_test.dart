import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/cron_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _connection = SavedConnection(
  id: 'cron-test',
  label: 'Test',
  host: 'example.invalid',
  port: 8642,
  apiKey: 'unused',
  dashboardProxied: true,
  desktopGatewayUrl: 'https://gateway.invalid/hermes',
  gatewayProfile: 'work',
);

class _Rig {
  Map<String, dynamic> job = {
    'id': 'job-1',
    'name': 'Daily task',
    'prompt': 'Do work',
    'schedule': '0 9 * * *',
    'model': 'custom/model',
    'provider': 'custom:route',
  };
  final requests = <http.Request>[];
  Map<String, dynamic>? updates;
  bool discoveryFails = false;
  bool mismatch = false;
  bool reject = false;
  bool saveFails = false;
  bool readFails = false;
  bool wrongId = false;
  Completer<http.Response>? heldSave;
  Completer<http.Response>? heldRead;

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    Object body;
    if (path.endsWith('/model/options')) {
      if (discoveryFails) return http.Response('unavailable', 503);
      body = {
        'providers': [
          {
            'slug': 'openai',
            'models': ['gpt-old'],
          },
          {
            'slug': 'anthropic',
            'models': [
              'claude-new',
              {'id': 'other-model'},
            ],
          },
        ],
      };
    } else if (request.method == 'PUT') {
      updates = (jsonDecode(request.body)['updates'] as Map)
          .cast<String, dynamic>();
      if (heldSave != null) return heldSave!.future;
      if (saveFails) return http.Response('failed', 500);
      if (reject) return http.Response('{"ok":false}', 200);
      if (!mismatch) job = {...job, ...updates!};
      body = job;
    } else if (path.endsWith('/cron/jobs/job-1')) {
      if (heldRead != null) return heldRead!.future;
      if (readFails) return http.Response('unavailable', 503);
      body = {...job, if (wrongId) 'id': 'other-job'};
    } else if (path.endsWith('/cron/jobs')) {
      body = [job];
    } else {
      return http.Response('unexpected request', 404);
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> _open(WidgetTester tester, _Rig rig) async {
  tester.view.physicalSize = const Size(650, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: hermesTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CronScreen(
        connection: _connection,
        testDashboardHttpClient: rig.client,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void _assertScoped(_Rig rig) {
  expect(rig.requests, isNotEmpty);
  for (final request in rig.requests) {
    expect(request.url.origin, 'https://gateway.invalid');
    expect(request.url.path, startsWith('/hermes/api/'));
    expect(request.url.queryParameters['profile'], 'work');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.url.path, isNot(endsWith('/model/set')));
  }
}

void main() {
  testWidgets('provider-only legacy pin is not silently reset during edits', (
    tester,
  ) async {
    final rig = _Rig()..job['model'] = null;
    await _open(tester, rig);
    expect(find.text(' · custom:route'), findsOneWidget);
    await _save(tester);
    expect(rig.updates!.containsKey('model'), isFalse);
    expect(rig.updates!.containsKey('provider'), isFalse);
    expect(rig.job['provider'], 'custom:route');
  });

  testWidgets('failed model discovery does not prevent explicit reset', (
    tester,
  ) async {
    final rig = _Rig()..discoveryFails = true;
    await _open(tester, rig);
    await _choose(tester, 'Follow default');
    await _save(tester);
    expect(rig.updates!['model'], isNull);
    expect(rig.updates!['provider'], isNull);
    expect(find.text('Cron job updated'), findsOneWidget);
  });

  testWidgets('cancel does not write and discovery remains read-only', (
    tester,
  ) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _choose(tester, 'claude-new · anthropic');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rig.requests.every((r) => r.method == 'GET'), isTrue);
  });

  for (final phase in ['save', 'read']) {
    testWidgets('held $phase cannot notify or refresh replacement profile', (
      tester,
    ) async {
      final rig = _Rig();
      final held = Completer<http.Response>();
      if (phase == 'save') {
        rig.heldSave = held;
      } else {
        rig.heldRead = held;
      }
      await _open(tester, rig);
      await _choose(tester, 'claude-new · anthropic');
      await _save(tester);
      final replacementRequests = <http.Request>[];
      final replacement = MockClient((request) async {
        replacementRequests.add(request);
        return http.Response(
          jsonEncode([
            {...rig.job, 'name': 'Replacement'},
          ]),
          200,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CronScreen(
            connection: SavedConnection(
              id: 'replacement',
              label: 'Other',
              host: 'other.invalid',
              port: 8642,
              apiKey: 'unused',
              dashboardProxied: true,
              gatewayProfile: 'other',
            ),
            testDashboardHttpClient: replacement,
          ),
        ),
      );
      await tester.pumpAndSettle();
      held.complete(
        http.Response(
          jsonEncode({
            ...rig.job,
            'model': 'claude-new',
            'provider': 'anthropic',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(find.text('Cron job updated'), findsNothing);
      expect(replacementRequests, hasLength(1));
      expect(
        replacementRequests.single.url.queryParameters['profile'],
        'other',
      );
    });
  }

  testWidgets(
    'different provider/model saves wrapped per-job update and reads exact target',
    (tester) async {
      final rig = _Rig();
      await _open(tester, rig);
      await _choose(tester, 'claude-new · anthropic');
      await _save(tester);
      expect(rig.updates, containsPair('model', 'claude-new'));
      expect(rig.updates, containsPair('provider', 'anthropic'));
      expect(find.text('Cron job updated'), findsOneWidget);
      expect(
        rig.requests.any(
          (r) => r.method == 'GET' && r.url.path.endsWith('/cron/jobs/job-1'),
        ),
        isTrue,
      );
      _assertScoped(rig);
    },
  );

  testWidgets('Follow default explicitly clears both pin fields', (
    tester,
  ) async {
    final rig = _Rig();
    await _open(tester, rig);
    await _choose(tester, 'Follow default');
    await _save(tester);
    expect(rig.updates!.containsKey('model'), isTrue);
    expect(rig.updates!['model'], isNull);
    expect(rig.updates!.containsKey('provider'), isTrue);
    expect(rig.updates!['provider'], isNull);
    expect(find.text('Cron job updated'), findsOneWidget);
  });

  for (final discoveryFails in [false, true]) {
    testWidgets(
      'unrelated edit preserves exact custom pin, discovery failure=$discoveryFails',
      (tester) async {
        final rig = _Rig()..discoveryFails = discoveryFails;
        await _open(tester, rig);
        expect(find.text('custom/model · custom:route'), findsOneWidget);
        if (discoveryFails) {
          expect(
            find.textContaining('Could not load models for this profile'),
            findsOneWidget,
          );
        }
        await tester.enterText(find.byType(TextField).first, 'Renamed');
        await _save(tester);
        expect(rig.updates!['name'], 'Renamed');
        expect(rig.updates!.containsKey('model'), isFalse);
        expect(rig.updates!.containsKey('provider'), isFalse);
        expect(rig.job['model'], 'custom/model');
        expect(rig.job['provider'], 'custom:route');
        expect(find.text('Cron job updated'), findsOneWidget);
      },
    );
  }

  testWidgets('failed discovery can retry and still clear a pin', (
    tester,
  ) async {
    final rig = _Rig()..discoveryFails = true;
    await _open(tester, rig);
    rig.discoveryFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not load models for this profile'),
      findsNothing,
    );
    await _choose(tester, 'Follow default');
    await _save(tester);
    expect(rig.updates!['model'], isNull);
    expect(rig.updates!['provider'], isNull);
  });

  for (final failure in ['mismatch', 'reject', 'save', 'read', 'identity']) {
    testWidgets('$failure does not announce a successful update', (
      tester,
    ) async {
      final rig = _Rig()
        ..mismatch = failure == 'mismatch'
        ..reject = failure == 'reject'
        ..saveFails = failure == 'save'
        ..readFails = failure == 'read'
        ..wrongId = failure == 'identity';
      await _open(tester, rig);
      await _choose(tester, 'claude-new · anthropic');
      await _save(tester);
      expect(find.text('Cron job updated'), findsNothing);
      expect(find.textContaining('Failed to update job'), findsOneWidget);
      _assertScoped(rig);
    });
  }

  testWidgets(
    'script-only edit leaves pin untouched and disables model selection',
    (tester) async {
      final rig = _Rig()..job['no_agent'] = true;
      await _open(tester, rig);
      final field = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(field.onChanged, isNull);
      await _save(tester);
      expect(rig.updates!.containsKey('model'), isFalse);
      expect(rig.updates!.containsKey('provider'), isFalse);
    },
  );

  test('new cron copy is explicitly translated in every supported locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final suffix = locale.toString();
      final arb =
          jsonDecode(File('lib/l10n/app_$suffix.arb').readAsStringSync())
              as Map;
      for (final key in ['cron_model_default', 'cron_model_notice']) {
        expect(arb[key], isA<String>());
        expect((arb[key] as String).isNotEmpty, isTrue);
        if (suffix != 'en') {
          expect(
            arb[key],
            isNot(
              jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())[key],
            ),
          );
        }
      }
    }
  });
}
