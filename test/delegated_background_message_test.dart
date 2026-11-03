import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:hermes_android/core/widgets/background_report_card.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'delegated_task_history_test.dart' show FakeHistory, task;
import 'support/internal_background_message_fixture.dart';

void main() {
  testWidgets(
    'delegated report pins survive real eviction without scroll storage collisions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = internalBackgroundMessageFixtures();
      final first = Map<String, dynamic>.from(
        fixture['model_switch']!['row'] as Map,
      )..['id'] = 2;
      final second = Map<String, dynamic>.from(
        fixture['internal_notification']!['row'] as Map,
      )..['id'] = 3;
      final history = FakeHistory()
        ..data = [
          {'id': 1, 'role': 'user', 'content': 'Actual request'},
          first,
          second,
          for (var id = 4; id <= 83; id++)
            {
              'id': id,
              'role': 'assistant',
              'content':
                  'Filler $id\n\n${'Scrollable recorded transcript. ' * 10}',
            },
        ];
      Future<DelegatedTaskController> open() async {
        final controller = DelegatedTaskController(
          task: task,
          history: history,
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: DelegatedTaskTimeline(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        return controller;
      }

      await open();
      Finder card(Map row) => find.byWidgetPredicate(
        (widget) =>
            widget is BackgroundReportCard &&
            widget.report.body == row['content'],
      );
      ExpansionTile tile(Map row) => tester.widget<ExpansionTile>(
        find.descendant(of: card(row), matching: find.byType(ExpansionTile)),
      );
      Future<void> toggle(Map row, String text) async {
        await tester.ensureVisible(card(row));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: card(row), matching: find.text(text)),
        );
        await tester.pumpAndSettle();
      }

      expect(tile(first).controller!.isExpanded, isFalse);
      await toggle(first, 'Expand report');
      await toggle(second, 'Expand report');
      await toggle(second, 'Collapse report');
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(card(first), findsNothing);
      expect(card(second), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tile(first).controller!.isExpanded, isTrue);
      await tester.ensureVisible(card(second));
      await tester.pumpAndSettle();
      expect(tile(second).controller!.isExpanded, isFalse);
      expect(tester.takeException(), isNull);
      final state = tester.state(find.byType(DelegatedTaskTimeline));
      await open();
      expect(tester.state(find.byType(DelegatedTaskTimeline)), same(state));
      expect(tile(first).controller!.isExpanded, isFalse);
      expect(tile(second).controller!.isExpanded, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await open();
      expect(tile(first).controller!.isExpanded, isFalse);
      expect(tile(second).controller!.isExpanded, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'delegated internal rows use collapsed tasks, never User labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = internalBackgroundMessageFixtures()['model_switch']!;
      final row = Map<String, dynamic>.from(fixture['row'] as Map)..['id'] = 2;
      final history = FakeHistory()
        ..data = [
          {'id': 1, 'role': 'user', 'content': 'Actual delegated request'},
          row,
        ];
      Future<DelegatedTaskController> open() async {
        final controller = DelegatedTaskController(
          task: task,
          history: history,
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: DelegatedTaskTimeline(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        return controller;
      }

      final controller = await open();
      final card = find.byType(BackgroundReportCard);
      expect(card, findsOneWidget);
      expect(find.text('User · row 1'), findsOneWidget);
      expect(find.text('User · row 2'), findsNothing);
      expect(find.text('Background task'), findsOneWidget);
      expect(find.text(row['content'] as String), findsNothing);
      ExpansionTile tile() => tester.widget<ExpansionTile>(
        find.descendant(of: card, matching: find.byType(ExpansionTile)),
      );
      expect(tile().controller!.isExpanded, isFalse);
      await tester.tap(find.text('Expand report'));
      await tester.pumpAndSettle();
      expect(tile().controller!.isExpanded, isTrue);
      expect(find.text(row['content'] as String), findsOneWidget);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(tile().controller!.isExpanded, isTrue);
      expect(controller.rows.singleWhere((row) => row['id'] == 2), row);
      await tester.pumpWidget(const SizedBox.shrink());
      await open();
      expect(tile().controller!.isExpanded, isFalse);
      expect(find.text(row['content'] as String), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
