import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'delegated_task_history_test.dart' show FakeHistory;

Widget app(Widget body, {double textScale = 1}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

void main() {
  for (final width in [320.0, 800.0]) {
    for (final textScale in [1.0, 2.0]) {
      for (final completed in [false, true]) {
        testWidgets(
          'task label stays one line at width $width, scale $textScale, completed $completed',
          (tester) async {
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final phase = completed
                ? GatewaySubagentPhase.completed
                : GatewaySubagentPhase.running;
            final status = completed ? 'completed' : 'running';
            final label = completed ? 'Completed' : 'Running';
            final longGoal =
                'Inspect Android transport.\n${'Instructions. ' * 80}';
            final detail = 'Progress or result.\n' * 80;
            final row = find.byKey(const ValueKey('delegated-task-child'));

            Widget card(String goal, String? detail) => app(
              ListView(
                children: [
                  GatewaySubagentCard(
                    activities: [
                      GatewaySubagentActivity(
                        id: 'child',
                        goal: goal,
                        detail: detail,
                        model: 'test-model',
                        phase: phase,
                        status: status,
                      ),
                    ],
                    onOpenTask: (_) {},
                  ),
                ],
              ),
              textScale: textScale,
            );

            await tester.pumpWidget(card('Inspect', null));
            expect(row, findsNothing);
            await tester.tap(find.byType(ExpansionTile));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final shortHeight = tester.getSize(row).height;

            await tester.pumpWidget(card(longGoal, detail));
            await tester.pump(const Duration(milliseconds: 300));
            final tile = tester.widget<ListTile>(row);
            final title = tile.title! as Text;
            expect(title.data, longGoal);
            expect(title.maxLines, 1);
            expect(title.overflow, TextOverflow.ellipsis);
            expect((tile.subtitle! as Text).data, '$label • test-model');
            expect(find.text(detail), findsNothing);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(longGoal),
                matching: find.byType(RichText),
              ),
            );
            expect(paragraph.didExceedMaxLines, isTrue);
            expect(tester.getSize(row).height, shortHeight);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final width in [390.0, 1000.0]) {
    testWidgets('tap opens full task details at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const task = GatewaySubagentActivity(
        id: 'child',
        goal:
            'Inspect Android transport\n'
            'Check reconnection, message ordering and model metadata.\n'
            'Report every finding without changing the parent chat.',
        detail: 'The transport review is in progress.',
        model: 'test-model',
        phase: GatewaySubagentPhase.running,
        status: 'running',
        childSessionId: 'stored-child',
      );
      final history = FakeHistory();
      GatewaySubagentActivity? opened;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ListView(
              children: [
                GatewaySubagentCard(
                  activities: const [task],
                  onOpenTask: (activity) {
                    opened = activity;
                    showDelegatedTaskTimeline(
                      context,
                      DelegatedTaskController(task: activity, history: history),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text(task.detail!), findsNothing);
      expect(find.byKey(const ValueKey('delegated-task-child')), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('delegated-task-child')).hitTestable(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(opened, same(task));
      expect(find.byType(DelegatedTaskTimeline), findsOneWidget);
      final overlay = find.byType(DelegatedTaskTimeline);
      final goal = find.descendant(of: overlay, matching: find.text(task.goal));
      expect(tester.widget<Text>(goal).maxLines, isNull);
      expect(
        find.descendant(of: overlay, matching: find.text(task.detail!)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: overlay, matching: find.text(task.model!)),
        findsOneWidget,
      );
      expect(find.text('Status: Running'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(DelegatedTaskTimeline), findsNothing);
      expect(find.text('Running • test-model'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('running task retains its compact label when it finishes', (
    tester,
  ) async {
    const task = GatewaySubagentActivity(
      id: 'child',
      goal: 'Inspect Android transport',
      model: 'test-model',
      phase: GatewaySubagentPhase.running,
      status: 'running',
    );
    final finished = task.merge(
      const GatewaySubagentActivity(
        id: 'child',
        goal: '',
        phase: GatewaySubagentPhase.completed,
        status: 'completed',
        detail: 'Full findings.\nFull findings.\nFull findings.',
      ),
    );
    Widget card(GatewaySubagentActivity activity) => app(
      ListView(
        children: [
          GatewaySubagentCard(activities: [activity]),
        ],
      ),
    );
    await tester.pumpWidget(card(task));
    final row = find.byKey(const ValueKey('delegated-task-child'));
    expect(row, findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final runningHeight = tester.getSize(row).height;
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(card(finished));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(task.goal), findsOneWidget);
    expect(find.text('Completed • test-model'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.text(finished.detail!), findsNothing);
    expect(tester.getSize(row).height, runningHeight);
  });
}
