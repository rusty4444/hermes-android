import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_detail_visibility.dart';
import 'package:hermes_android/core/widgets/chat_detail_visibility_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> pumpCard(
    WidgetTester tester,
    Map<String, Object> initial,
  ) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [ChatDetailVisibilityCard(preferences: prefs)],
          ),
        ),
      ),
    );
    return prefs;
  }

  testWidgets('defaults to automatic for both cards', (tester) async {
    final prefs = await pumpCard(tester, const {});
    final store = ChatDetailVisibilityStore(prefs);

    expect(store.readToolActivity(), ChatDetailVisibility.automatic);
    expect(store.readReasoning(), ChatDetailVisibility.automatic);
    expect(find.text('Tool activity'), findsOneWidget);
    expect(find.text('Reasoning'), findsOneWidget);
  });

  testWidgets('persists each card choice independently', (tester) async {
    final prefs = await pumpCard(tester, const {});

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('chat-tool-activity-visibility')),
        matching: find.text('Hidden'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('chat-reasoning-visibility')),
        matching: find.text('Collapsed'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      prefs.getString(ChatDetailVisibilityStore.toolActivityKey),
      'hidden',
    );
    expect(
      prefs.getString(ChatDetailVisibilityStore.reasoningKey),
      'collapsed',
    );
  });

  testWidgets('restores stored choices', (tester) async {
    await pumpCard(tester, const {
      ChatDetailVisibilityStore.toolActivityKey: 'collapsed',
      ChatDetailVisibilityStore.reasoningKey: 'hidden',
    });

    SegmentedButton<ChatDetailVisibility> segmented(String key) =>
        tester.widget<SegmentedButton<ChatDetailVisibility>>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(SegmentedButton<ChatDetailVisibility>),
          ),
        );

    expect(segmented('chat-tool-activity-visibility').selected, {
      ChatDetailVisibility.collapsed,
    });
    expect(segmented('chat-reasoning-visibility').selected, {
      ChatDetailVisibility.hidden,
    });
  });
}
