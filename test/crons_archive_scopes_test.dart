import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';

import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _archive(int index) => {
  'id': 'archived-$index',
  'title': 'Archived run $index',
  'source': 'cron',
  'started_at': index,
  'archived': true,
};

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<Session>> Function() active,
  required http.Client dashboard,
}) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: SavedConnection(
          id: 'archive-scopes',
          label: 'Test',
          host: 'example.invalid',
          port: 8642,
          apiKey: 'test-key',
          dashboardProxied: true,
        ),
        sessionsLoader: active,
        testDashboardHttpClient: dashboard,
        turnSignalsLoader: (_) async => HomeTurnSignals.empty,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Crons').last);
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a complete cron archive expands while active history is still pending',
    (tester) async {
      final active = Completer<List<Session>>();
      await _pump(
        tester,
        active: () => active.future,
        dashboard: MockClient(
          (_) async => http.Response(
            jsonEncode({'sessions': List.generate(7, _archive), 'total': 7}),
            200,
          ),
        ),
      );
      expect(find.text('Archived run 0'), findsOneWidget);
      expect(find.text('Archived run 6'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      active.completeError(Exception('active history unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Archived run 0'), findsOneWidget);
      expect(find.text('Archived run 6'), findsOneWidget);
      expect(find.text('Could not load conversations'), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
    },
  );

  testWidgets(
    'a later archive failure keeps loaded cron rows and offers a working retry',
    (tester) async {
      final later = Completer<http.Response>();
      var retry = false;
      final dashboard = MockClient((request) async {
        if (retry) {
          return http.Response(
            jsonEncode({'sessions': List.generate(3, _archive), 'total': 3}),
            200,
          );
        }
        if (request.url.queryParameters['offset'] == '0') {
          return http.Response(
            jsonEncode({
              'sessions': [_archive(0), _archive(1)],
              'total': 101,
            }),
            200,
          );
        }
        return later.future;
      });
      await _pump(tester, active: () async => [], dashboard: dashboard);
      expect(find.text('Archived run 0'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      later.complete(http.Response('unavailable', 503));
      await tester.pumpAndSettle();
      expect(find.text('Archived run 0'), findsOneWidget);
      expect(find.text('Archived run 1'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      retry = true;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Archived run 2'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('cron archive rows never leak into the human Archived filter', (
    tester,
  ) async {
    await _pump(
      tester,
      active: () async => [],
      dashboard: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'sessions': [_archive(0)],
            'total': 1,
          }),
          200,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archived run 0'), findsOneWidget);
    await tester.tap(find.text('Chats').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Archived run 0'), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
