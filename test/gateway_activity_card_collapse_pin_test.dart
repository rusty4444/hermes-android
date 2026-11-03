import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';

import 'support/l10n_test_utils.dart';

GatewayToolActivity _running(String name, String id) => GatewayToolActivity(
  name: name,
  phase: GatewayToolActivityPhase.running,
  toolId: id,
);

GatewayToolActivity _finished(String name, String id) => GatewayToolActivity(
  name: name,
  phase: GatewayToolActivityPhase.completed,
  toolId: id,
  durationSeconds: 1.5,
);

bool _isExpanded(WidgetTester tester) => tester
    .widget<ExpansionTile>(find.byType(ExpansionTile))
    .controller!
    .isExpanded;

Future<void> _pumpCard(
  WidgetTester tester,
  List<GatewayToolActivity> activities, {
  bool verbose = false,
}) async {
  await tester.pumpWidget(
    testAppWithL10n(
      Scaffold(
        body: ListView(
          children: [
            GatewayActivityCard(activities: activities, verbose: verbose),
          ],
        ),
      ),
    ),
  );
  // Running tools have an indeterminate progress indicator.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapHeader(WidgetTester tester) async {
  await tester.tap(find.text('Tool activity'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('running tools start collapsed with only the current call', (
    tester,
  ) async {
    await _pumpCard(tester, [
      _finished('terminal', 'call-1'),
      _running('read_file', 'call-2'),
    ]);

    expect(_isExpanded(tester), isFalse);
    expect(find.text('Read file: Running'), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _tapHeader(tester);
    expect(_isExpanded(tester), isTrue);
    expect(find.textContaining('Terminal'), findsOneWidget);
    expect(find.textContaining('Read file'), findsOneWidget);
  });

  testWidgets('a card the user collapsed stays collapsed as tools arrive', (
    tester,
  ) async {
    await _pumpCard(tester, [_running('terminal', 'call-1')]);
    await _tapHeader(tester);
    expect(_isExpanded(tester), isTrue);
    await _tapHeader(tester);
    expect(_isExpanded(tester), isFalse);

    await _pumpCard(tester, [
      _finished('terminal', 'call-1'),
      _running('read_file', 'call-2'),
    ]);

    expect(_isExpanded(tester), isFalse);
    expect(find.text('Read file: Running'), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
    expect(find.text('Hermes is using 2 tools'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a running call takes priority over a newer completed call', (
    tester,
  ) async {
    await _pumpCard(tester, [
      _running('terminal', 'call-1'),
      _finished('read_file', 'call-2'),
    ]);
    expect(_isExpanded(tester), isFalse);
    expect(find.text('Terminal: Running'), findsOneWidget);
    expect(find.textContaining('Read file'), findsNothing);

    await _pumpCard(tester, [
      _finished('terminal', 'call-1'),
      _finished('read_file', 'call-2'),
    ]);
    expect(find.text('Read file: Completed in 1.5 s'), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
  });

  testWidgets('the latest of parallel running calls is shown', (tester) async {
    await _pumpCard(tester, [
      _running('terminal', 'call-1'),
      _running('read_file', 'call-2'),
    ]);
    expect(find.text('Read file: Running'), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
  });

  testWidgets(
    'a pinned-closed card updates progress and time without reopening',
    (tester) async {
      final start = DateTime(2026, 10, 21, 1, 2, 3);
      final progress = start.add(const Duration(seconds: 5));
      final running = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'tool_id': 'call-1',
        'name': 'terminal',
      }, observedAt: start)!;
      await _pumpCard(tester, [running]);
      await _tapHeader(tester);
      await _tapHeader(tester);
      expect(_isExpanded(tester), isFalse);
      await _pumpCard(tester, [
        running.merge(
          GatewayToolActivity.fromGatewayEvent('tool.progress', {
            'tool_id': 'call-1',
            'name': 'terminal',
          }, observedAt: progress)!,
        ),
      ]);
      expect(_isExpanded(tester), isFalse);
      expect(find.text('Terminal: Working'), findsOneWidget);
      expect(find.text('Last observed 01:02:08 (local)'), findsOneWidget);
    },
  );

  testWidgets('a collapsed card reports the turn finishing', (tester) async {
    await _pumpCard(tester, [_running('terminal', 'call-1')]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpCard(tester, [_finished('terminal', 'call-1')]);

    expect(_isExpanded(tester), isFalse);
    expect(find.text('Terminal: Completed in 1.5 s'), findsOneWidget);
    expect(find.text('1 completed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an untouched card stays collapsed across turns', (tester) async {
    await _pumpCard(tester, [_running('terminal', 'call-1')]);
    expect(_isExpanded(tester), isFalse);

    await _pumpCard(tester, [_finished('terminal', 'call-1')]);
    expect(_isExpanded(tester), isFalse);

    await _pumpCard(tester, [
      _finished('terminal', 'call-1'),
      _running('read_file', 'call-2'),
    ]);
    expect(_isExpanded(tester), isFalse);
    expect(find.text('Read file: Running'), findsOneWidget);
  });

  testWidgets('a card the user expanded stays expanded when tools settle', (
    tester,
  ) async {
    await _pumpCard(tester, [_running('terminal', 'call-1')]);
    await _tapHeader(tester);
    expect(_isExpanded(tester), isTrue);

    await _pumpCard(tester, [
      _finished('terminal', 'call-1'),
      _finished('read_file', 'call-2'),
    ]);

    expect(_isExpanded(tester), isTrue);
    expect(find.text('2 completed'), findsOneWidget);
  });

  testWidgets('verbose changes neither the collapsed default nor manual pins', (
    tester,
  ) async {
    await _pumpCard(tester, [_finished('terminal', 'call-1')], verbose: true);
    expect(_isExpanded(tester), isFalse);

    await _pumpCard(tester, [_finished('terminal', 'call-1')]);
    expect(_isExpanded(tester), isFalse);
    await _tapHeader(tester);
    expect(_isExpanded(tester), isTrue);
    await _pumpCard(tester, [_finished('terminal', 'call-1')], verbose: true);
    expect(_isExpanded(tester), isTrue);
    await _tapHeader(tester);
    expect(_isExpanded(tester), isFalse);
    await _pumpCard(tester, [_finished('terminal', 'call-1')]);
    expect(_isExpanded(tester), isFalse);
  });

  testWidgets('a collapsed failed call remains visible', (tester) async {
    await _pumpCard(tester, [
      _finished('read_file', 'call-1'),
      GatewayToolActivity(
        name: 'terminal',
        toolId: 'call-2',
        phase: GatewayToolActivityPhase.failed,
        detail: 'Command failed',
      ),
    ]);
    expect(_isExpanded(tester), isFalse);
    expect(find.text('Terminal: Failed'), findsOneWidget);
    expect(find.text('1 failed • 2 total'), findsOneWidget);
    expect(find.text('Command failed'), findsNothing);
  });

  testWidgets('an empty group has no current-call preview', (tester) async {
    await _pumpCard(tester, []);
    expect(_isExpanded(tester), isFalse);
    expect(find.text('0 completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
