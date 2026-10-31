import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester,
  List<GatewayToolActivity> activities, {
  bool verbose = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: Scaffold(
        body: ListView(
          children: [
            GatewayActivityCard(activities: activities, verbose: verbose),
          ],
        ),
      ),
    ),
  );
  // A running tool owns a live progress indicator, so pumpAndSettle would
  // correctly never settle. One animation frame is enough for assertions.
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('completed tool activity is collapsed with a compact summary', (
    tester,
  ) async {
    await _pump(tester, [
      GatewayToolActivity(
        name: 'terminal',
        phase: GatewayToolActivityPhase.completed,
        durationSeconds: 4.2,
        detail: 'Build finished',
      ),
    ]);

    expect(find.text('Tool activity'), findsOneWidget);
    expect(find.text('1 completed'), findsOneWidget);
    expect(find.text('Build finished'), findsNothing);

    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();

    expect(find.text('Build finished'), findsOneWidget);
    expect(find.text('Completed in 4.2 s'), findsOneWidget);
  });

  testWidgets(
    'collapsed header shows latest known time; expanded rows show both',
    (tester) async {
      final start = DateTime(2026, 10, 21, 1, 2, 3);
      final firstEnd = DateTime(2026, 10, 21, 1, 2, 9);
      final secondEnd = DateTime(2026, 10, 21, 4, 5, 6);
      await _pump(tester, [
        GatewayToolActivity(
          name: 'read_file',
          phase: GatewayToolActivityPhase.completed,
          startedAt: start,
          lastActivityAt: firstEnd,
          lastActivityTimeSource: GatewayToolTimeSource.observed,
        ),
        GatewayToolActivity(
          name: 'terminal',
          phase: GatewayToolActivityPhase.completed,
          lastActivityAt: secondEnd,
          lastActivityTimeSource: GatewayToolTimeSource.storedResult,
        ),
      ]);
      expect(find.text('Result recorded 04:05:06 (local)'), findsOneWidget);
      expect(find.text('Start observed 01:02:03 (local)'), findsNothing);
      await tester.tap(find.text('Tool activity'));
      await tester.pumpAndSettle();
      expect(find.text('Start observed 01:02:03 (local)'), findsOneWidget);
      expect(find.text('Last observed 01:02:09 (local)'), findsOneWidget);
      expect(find.text('Result recorded 04:05:06 (local)'), findsNWidgets(2));
      expect(find.textContaining('Start observed 04:05:06'), findsNothing);
    },
  );

  testWidgets('unknown times stay explicit in header and row semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, [
      GatewayToolActivity(
        name: 'terminal',
        phase: GatewayToolActivityPhase.completed,
      ),
    ]);
    expect(find.text('Time unavailable'), findsOneWidget);
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('Time unavailable'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel(RegExp('Terminal: Completed, Time unavailable')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('server instant is displayed in device-local time', (
    tester,
  ) async {
    final instant = DateTime.utc(2026, 10, 21, 1, 2, 3);
    final local = instant.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final clock =
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    await _pump(tester, [
      GatewayToolActivity.fromStoredResult(
        name: 'terminal',
        timestamp: instant.millisecondsSinceEpoch / 1000,
      ),
    ]);
    expect(find.text('Result recorded $clock (local)'), findsOneWidget);
  });

  testWidgets('running activity stays collapsed with a current-call summary', (
    tester,
  ) async {
    await _pump(tester, [
      GatewayToolActivity(
        name: 'browser_navigate',
        phase: GatewayToolActivityPhase.running,
        detail: 'Opening page',
      ),
    ]);

    expect(find.text('Opening page'), findsNothing);
    expect(find.text('Browser navigate: Running'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
  });

  testWidgets('failure summary is urgent and includes duration', (
    tester,
  ) async {
    await _pump(tester, [
      GatewayToolActivity(
        name: 'terminal',
        phase: GatewayToolActivityPhase.failed,
        durationSeconds: 2,
        detail: 'Command failed',
      ),
    ]);

    expect(find.text('1 failed • 1 total'), findsOneWidget);
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('Failed after 2.0 s'), findsOneWidget);
  });

  testWidgets('survives large text without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: ListView(
              children: [
                GatewayActivityCard(
                  activities: [
                    GatewayToolActivity(
                      name: 'a_very_long_tool_name_that_must_not_overflow',
                      phase: GatewayToolActivityPhase.running,
                      detail: 'A long operation is currently running.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
