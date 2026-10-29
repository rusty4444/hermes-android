import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';

void main() {
  group('GatewayReasoningUpdate', () {
    test('appends deltas and replaces them with reasoning.available', () {
      final first = GatewayReasoningUpdate.fromGatewayEvent('reasoning.delta', {
        'text': 'Check the ',
      })!;
      final second = GatewayReasoningUpdate.fromGatewayEvent(
        'reasoning.delta',
        {'text': 'gateway contract.'},
      )!;
      final available = GatewayReasoningUpdate.fromGatewayEvent(
        'reasoning.available',
        {'text': 'Verified the complete gateway contract.', 'verbose': true},
      )!;

      final streamed = second.applyTo(first.applyTo(''));
      expect(streamed, 'Check the gateway contract.');
      expect(
        available.applyTo(streamed),
        'Verified the complete gateway contract.',
      );
      expect(available.verbose, isTrue);
    });

    test('ignores unrelated, empty, and NUL-only events', () {
      expect(
        GatewayReasoningUpdate.fromGatewayEvent('thinking.delta', {
          'text': 'not reasoning',
        }),
        isNull,
      );
      expect(
        GatewayReasoningUpdate.fromGatewayEvent('reasoning.delta', {
          'text': '\u0000',
        }),
        isNull,
      );
    });
  });

  group('GatewayNotice', () {
    test('parses background completion and review summary', () {
      final background = GatewayNotice.fromGatewayEvent('background.complete', {
        'task_id': 'bg-7',
        'text': 'Indexed the selected files.',
      })!;
      final review = GatewayNotice.fromGatewayEvent('review.summary', {
        'text': 'Two changes require review.',
      })!;

      expect(background.kind, GatewayNoticeKind.background);
      expect(background.title, 'Background task bg-7 completed');
      expect(review.kind, GatewayNoticeKind.review);
      expect(review.title, 'Hermes review');
    });
  });

  group('Gateway Desktop activity events', () {
    test('parses notification level, stable key, and TTL', () {
      final notification = GatewayNotification.fromEventData({
        'key': 'usage',
        'level': 'warn',
        'text': 'Context usage is high.',
        'ttl_ms': 2500,
      })!;

      expect(notification.key, 'usage');
      expect(notification.level, GatewayNotificationLevel.warning);
      expect(notification.ttl, const Duration(milliseconds: 2500));
    });

    test('merges subagent progress into its stable activity', () {
      final started =
          GatewaySubagentActivity.fromGatewayEvent('subagent.start', {
            'subagent_id': 'child-1',
            'goal': 'Inspect Android transport',
            'task_index': 1,
            'task_count': 2,
          })!;
      final completed =
          GatewaySubagentActivity.fromGatewayEvent('subagent.complete', {
            'subagent_id': 'child-1',
            'goal': 'Inspect Android transport',
            'summary': 'Transport inspected.',
          })!;

      final merged = started.merge(completed);
      expect(merged.id, 'child-1');
      expect(merged.isComplete, isTrue);
      expect(merged.detail, 'Transport inspected.');
      expect(merged.taskIndex, 1);
    });
  });

  group('GatewayInterimTransition', () {
    test('does not duplicate text that was already streamed', () {
      final result = GatewayInterimTransition.resolve(
        currentText: 'Interim result.',
        interimText: 'Interim result.',
        alreadyStreamed: true,
      );

      expect(result.sealedText, 'Interim result.');
      expect(result.startsNewMessage, isTrue);
    });

    test('repairs a partially streamed interim from authoritative text', () {
      final result = GatewayInterimTransition.resolve(
        currentText: 'Interim ',
        interimText: 'Interim result.',
        alreadyStreamed: true,
      );

      expect(result.sealedText, 'Interim result.');
    });

    test('adds an interim that was not previously streamed', () {
      final result = GatewayInterimTransition.resolve(
        currentText: '',
        interimText: 'Fresh interim.',
        alreadyStreamed: false,
      );

      expect(result.sealedText, 'Fresh interim.');
      expect(result.startsNewMessage, isTrue);
    });
  });

  testWidgets('reasoning and notices expose selectable content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              GatewayReasoningCard(
                text: 'Verified the complete gateway contract.',
                initiallyExpanded: true,
              ),
              GatewayNoticeCard(
                notice: GatewayNotice(
                  kind: GatewayNoticeKind.background,
                  taskId: 'bg-7',
                  text: 'Indexed the selected files.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Reasoning'), findsOneWidget);
    expect(
      find.text('Verified the complete gateway contract.'),
      findsOneWidget,
    );
    expect(find.text('Background task bg-7 completed'), findsOneWidget);

    final expansionTileFinder = find.byType(ExpansionTile);
    expect(expansionTileFinder, findsNWidgets(2));
    await tester.tap(expansionTileFinder.at(1));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNWidgets(2));
  });

  testWidgets('subagent card exposes delegated progress', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GatewaySubagentCard(
            activities: [
              GatewaySubagentActivity(
                id: 'child-1',
                goal: 'Inspect Android transport',
                phase: GatewaySubagentPhase.running,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('1 delegated task(s) active'), findsOneWidget);
    expect(find.text('Inspect Android transport'), findsOneWidget);
  });
}
