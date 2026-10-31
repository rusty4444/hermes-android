import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/services/tool_activity_group_pins.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';

import 'support/l10n_test_utils.dart';

GatewayToolActivity _running(String name, String id) => GatewayToolActivity(
  name: name,
  phase: GatewayToolActivityPhase.running,
  toolId: id,
);

GatewayToolActivity _finished(String name, String? id) => GatewayToolActivity(
  name: name,
  phase: GatewayToolActivityPhase.completed,
  toolId: id,
  durationSeconds: 1.2,
);

Map<String, dynamic> _userMessage(String text) => {
  'role': 'user',
  'content': text,
};

Map<String, dynamic> _assistantMessage(String text) => {
  'role': 'assistant',
  'content': text,
};

/// What the screen is projecting at one moment of a turn.
class _Turn {
  const _Turn({required this.messages, required this.toolActivities});

  final List<Map<String, dynamic>> messages;
  final List<GatewayToolActivity> toolActivities;
}

/// Renders the projection the way `chat_screen.dart` does — a `ListView.builder`
/// over `buildChatDisplayItems`, with the activity card's expansion choice kept
/// in a [ToolActivityGroupPins] keyed by group id — so the regression below is
/// exercised through the real projection and the real card.
class _ChatList extends StatefulWidget {
  const _ChatList({required this.turn, required this.pins});

  final _Turn turn;
  final ToolActivityGroupPins pins;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  @override
  Widget build(BuildContext context) {
    final items = buildChatDisplayItems(
      messages: widget.turn.messages,
      toolActivities: widget.turn.toolActivities,
    );

    return Scaffold(
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is ChatToolActivityGroup) {
            return GatewayActivityCard(
              key: ValueKey<String>('tool-activity-${item.id}'),
              activities: item.activities,
              pinnedExpansion: widget.pins[item.id],
              onPinChanged: (expanded) => widget.pins.pin(item.id, expanded),
            );
          }
          if (item is Map<String, dynamic>) {
            return Text('bubble:${item['_display_content']}');
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

bool _cardIsOpen(WidgetTester tester) => tester
    .widget<ExpansionTile>(find.byType(ExpansionTile))
    .controller!
    .isExpanded;

List<GatewayToolActivity>? _activitiesAt(WidgetTester tester, int index) {
  final card = tester.widgetList<GatewayActivityCard>(
    find.byType(GatewayActivityCard),
  );
  return index < card.length ? card.elementAt(index).activities : null;
}

void main() {
  late ToolActivityGroupPins pins;

  setUp(() => pins = ToolActivityGroupPins());

  Future<void> pumpTurn(WidgetTester tester, _Turn turn) async {
    await tester.pumpWidget(testAppWithL10n(_ChatList(turn: turn, pins: pins)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapHeader(WidgetTester tester) async {
    await tester.tap(find.text('Tool activity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final streamingTools = [_running('terminal', 'call-1')];

  final turnToolsOnly = _Turn(
    messages: [_userMessage('go')],
    toolActivities: streamingTools,
  );

  // The same turn once assistant text starts streaming: the projection now puts
  // the bubble ahead of the trailing activity card, moving the card one index
  // down.
  final turnWithText = _Turn(
    messages: [_userMessage('go'), _assistantMessage('working on it')],
    toolActivities: streamingTools,
  );

  test('the group keeps its id when the projection moves it down the list', () {
    final before = buildChatDisplayItems(
      messages: turnToolsOnly.messages,
      toolActivities: turnToolsOnly.toolActivities,
    );
    final after = buildChatDisplayItems(
      messages: turnWithText.messages,
      toolActivities: turnWithText.toolActivities,
    );

    final beforeGroup = before.whereType<ChatToolActivityGroup>().single;
    final afterGroup = after.whereType<ChatToolActivityGroup>().single;

    expect(before.indexOf(beforeGroup), 1);
    expect(after.indexOf(afterGroup), 2);
    expect(afterGroup.id, beforeGroup.id);
  });

  test('the id is stable while the group grows', () {
    final first = buildChatDisplayItems(
      messages: turnToolsOnly.messages,
      toolActivities: streamingTools,
    ).whereType<ChatToolActivityGroup>().single;
    final grown = buildChatDisplayItems(
      messages: turnToolsOnly.messages,
      toolActivities: [
        _running('terminal', 'call-1'),
        _running('read_file', 'call-2'),
      ],
    ).whereType<ChatToolActivityGroup>().single;

    expect(grown.id, first.id);
  });

  test('a missing first tool id can arrive through a later merge', () {
    final started = GatewayToolActivity(
      name: 'terminal',
      phase: GatewayToolActivityPhase.running,
    );
    final before = buildChatDisplayItems(
      messages: [_userMessage('go')],
      toolActivities: [started],
    ).whereType<ChatToolActivityGroup>().single;
    final updated = started.merge(_finished('terminal', 'call-late'));
    final after = buildChatDisplayItems(
      messages: [_userMessage('go')],
      toolActivities: [updated],
    ).whereType<ChatToolActivityGroup>().single;

    expect(updated.toolId, 'call-late');
    expect(after.id, before.id);
  });

  test('stored row id stays fixed when its first tool gains an id', () {
    final row = {'id': 99, 'role': 'tool', 'content': 'result'};
    final started = GatewayToolActivity(
      name: 'terminal',
      phase: GatewayToolActivityPhase.running,
    );
    final before = buildChatDisplayItems(
      messages: [row],
      toolActivities: [started],
    ).whereType<ChatToolActivityGroup>().single;
    final after = buildChatDisplayItems(
      messages: [row],
      toolActivities: [started.merge(_finished('terminal', 'call-late'))],
    ).whereType<ChatToolActivityGroup>().single;

    expect(before.id, 'message:99');
    expect(after.id, before.id);
  });

  test(
    'same-name groups do not inherit a pin as the history window slides',
    () {
      final old = {'id': 11, 'role': 'tool', 'content': 'old result'};
      final retained = {'id': 14, 'role': 'tool', 'content': 'new result'};
      final firstPage = buildChatDisplayItems(
        messages: [old, _assistantMessage('old done'), retained],
        toolActivities: [
          _finished('terminal', null),
          _finished('terminal', null),
        ],
      ).whereType<ChatToolActivityGroup>().toList();
      pins.pin(firstPage.last.id, false);

      final laterPage = buildChatDisplayItems(
        messages: [
          retained,
          _assistantMessage('new done'),
          {'id': 17, 'role': 'tool', 'content': 'latest result'},
        ],
        toolActivities: [
          _finished('terminal', null),
          _finished('terminal', null),
        ],
      ).whereType<ChatToolActivityGroup>().toList();

      expect(laterPage.first.id, firstPage.last.id);
      expect(pins[laterPage.first.id], isFalse);
      expect(laterPage.last.id, isNot(firstPage.last.id));
      expect(pins[laterPage.last.id], isNull);
    },
  );

  test('unanchored groups never reuse an older name-based pin', () {
    final first = buildChatDisplayItems(
      messages: [_userMessage('go')],
      toolActivities: [
        GatewayToolActivity(
          name: 'terminal',
          phase: GatewayToolActivityPhase.completed,
        ),
      ],
    ).whereType<ChatToolActivityGroup>().single;
    pins.pin(first.id, true);
    final next = buildChatDisplayItems(
      messages: [_userMessage('next')],
      toolActivities: [
        GatewayToolActivity(
          name: 'terminal',
          phase: GatewayToolActivityPhase.completed,
        ),
      ],
    ).whereType<ChatToolActivityGroup>().single;

    expect(next.id, isNot(first.id));
    expect(pins[next.id], isNull);
  });

  test('late tool id aliases both earlier and later pin choices', () {
    const local = 'local:running';
    const persisted = 'tool:call-late';
    pins.pin(local, false);
    pins.alias(local, persisted);
    expect(pins[persisted], isFalse);
    pins.pin(local, true);
    expect(pins[persisted], isTrue);
  });

  test(
    'streaming pin follows tool id to stored row without overwriting it',
    () {
      pins.pin('local:running', false);
      pins.alias('local:running', 'tool:call-late');
      pins.alias('tool:call-late', 'message:99');
      expect(pins['message:99'], isFalse);

      pins.pin('message:99', true);
      pins.alias('tool:call-late', 'message:99');
      expect(pins['message:99'], isTrue);
    },
  );

  test('pin cache stays bounded during a long chat', () {
    for (var i = 0; i < 150; i++) {
      pins.pin('group-$i', false);
    }
    expect(pins.length, lessThanOrEqualTo(100));
    expect(pins['group-149'], isFalse);
  });

  testWidgets(
    'a collapsed card stays collapsed when text moves it down the list',
    (tester) async {
      await pumpTurn(tester, turnToolsOnly);
      expect(_cardIsOpen(tester), isFalse);
      expect(_activitiesAt(tester, 0), hasLength(1));

      await tapHeader(tester);
      expect(_cardIsOpen(tester), isTrue);
      await tapHeader(tester);
      expect(_cardIsOpen(tester), isFalse);
      expect(pins.length, 1);

      // Assistant text arrives; the card is now the third row instead of the second.
      await pumpTurn(tester, turnWithText);

      expect(find.text('bubble:working on it'), findsOneWidget);
      expect(_cardIsOpen(tester), isFalse);
      expect(find.text('Hermes is using a tool'), findsOneWidget);
    },
  );

  testWidgets('id-less first tool keeps the collapsed card after id merge', (
    tester,
  ) async {
    final initial = GatewayToolActivity(
      name: 'terminal',
      phase: GatewayToolActivityPhase.running,
    );
    await pumpTurn(
      tester,
      _Turn(messages: [_userMessage('go')], toolActivities: [initial]),
    );
    await tapHeader(tester);
    await tapHeader(tester);
    expect(_cardIsOpen(tester), isFalse);

    await pumpTurn(
      tester,
      _Turn(
        messages: [_userMessage('go'), _assistantMessage('working')],
        toolActivities: [initial.merge(_running('terminal', 'call-late'))],
      ),
    );
    expect(_cardIsOpen(tester), isFalse);
    expect(pins.length, 1);
  });

  testWidgets('window shift keeps retained pin off a new same-name group', (
    tester,
  ) async {
    final retained = {'id': 14, 'role': 'tool', 'content': 'retained'};
    await pumpTurn(
      tester,
      _Turn(
        messages: [
          {'id': 11, 'role': 'tool', 'content': 'old'},
          _assistantMessage('old done'),
          retained,
        ],
        toolActivities: [
          _finished('terminal', null),
          _finished('terminal', null),
        ],
      ),
    );
    await tester.tap(find.text('Tool activity').last);
    await tester.pump();
    expect(pins['message:14'], isTrue);

    await pumpTurn(
      tester,
      _Turn(
        messages: [
          retained,
          _assistantMessage('retained done'),
          {'id': 17, 'role': 'tool', 'content': 'new'},
        ],
        toolActivities: [
          _finished('terminal', null),
          _finished('terminal', null),
        ],
      ),
    );
    final retainedCard = tester.widget<GatewayActivityCard>(
      find.byKey(const ValueKey<String>('tool-activity-message:14')),
    );
    final newCard = tester.widget<GatewayActivityCard>(
      find.byKey(const ValueKey<String>('tool-activity-message:17')),
    );
    expect(retainedCard.pinnedExpansion, isTrue);
    expect(newCard.pinnedExpansion, isNull);
  });

  testWidgets(
    'a card pinned open stays open when it moves and the turn settles',
    (tester) async {
      final finishedOnly = _Turn(
        messages: [_userMessage('go')],
        toolActivities: [_finished('terminal', 'call-1')],
      );
      await pumpTurn(tester, finishedOnly);
      expect(_cardIsOpen(tester), isFalse);

      await tapHeader(tester);
      expect(_cardIsOpen(tester), isTrue);

      await pumpTurn(
        tester,
        _Turn(
          messages: [_userMessage('go'), _assistantMessage('done')],
          toolActivities: [
            _finished('terminal', 'call-1'),
            _finished('read_file', 'call-2'),
          ],
        ),
      );

      expect(_cardIsOpen(tester), isTrue);
      expect(find.text('2 completed'), findsOneWidget);
    },
  );

  testWidgets('the pin survives the row being evicted and rebuilt', (
    tester,
  ) async {
    await pumpTurn(tester, turnToolsOnly);
    await tapHeader(tester);
    await tapHeader(tester);
    expect(_cardIsOpen(tester), isFalse);

    // A scrolled-away row is discarded entirely, State included.
    await tester.pumpWidget(testAppWithL10n(const Scaffold(body: SizedBox())));
    await tester.pump();

    await pumpTurn(tester, turnToolsOnly);

    expect(_cardIsOpen(tester), isFalse);
  });

  testWidgets('each group keeps its own choice', (tester) async {
    // Two groups in one projection: a finished one, then a running one.
    final twoGroups = _Turn(
      messages: [
        _userMessage('go'),
        {'role': 'tool', 'content': 'first result'},
        _assistantMessage('first done'),
        {'role': 'tool', 'content': 'second result'},
        _assistantMessage('still going'),
      ],
      toolActivities: [
        _finished('terminal', 'call-1'),
        _running('read_file', 'call-2'),
      ],
    );

    await pumpTurn(tester, twoGroups);
    expect(find.byType(GatewayActivityCard), findsNWidgets(2));

    // Open and then collapse the second (running) card only.
    await tester.tap(find.text('Tool activity').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tool activity').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(pins.length, 1);
    expect(find.text('Read file: Running'), findsOneWidget);
    expect(find.text('Running'), findsNothing);

    // Re-projecting must not disturb either choice.
    await pumpTurn(tester, twoGroups);
    expect(pins.length, 1);
    expect(find.text('Read file: Running'), findsOneWidget);
    expect(find.text('Terminal: Completed in 1.2 s'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
  });
}
