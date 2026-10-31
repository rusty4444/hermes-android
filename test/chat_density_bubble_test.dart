import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';

import 'support/l10n_test_utils.dart';

Future<void> pumpBubble(
  WidgetTester tester, {
  required ChatDensity density,
  required bool isUser,
  String content = 'A short reply.',
}) {
  return tester.pumpWidget(
    testAppWithL10n(
      Scaffold(
        body: MessageBubble(content: content, isUser: isUser, density: density),
      ),
    ),
  );
}

/// The outer bubble container: the first [Container] under the keyed
/// [GestureDetector], before any markdown or code-block container.
Container bubbleContainer(WidgetTester tester) {
  return tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(const Key('message-bubble')),
          matching: find.byType(Container),
        )
        .first,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    chatDensitySelection.value = ChatDensity.comfortable;
  });

  testWidgets('comfortable keeps the sender labels', (tester) async {
    await pumpBubble(tester, density: ChatDensity.comfortable, isUser: true);
    expect(find.text('You'), findsOneWidget);

    await pumpBubble(tester, density: ChatDensity.comfortable, isUser: false);
    expect(find.text('Hermes'), findsOneWidget);
  });

  testWidgets('compact removes the You and Hermes labels', (tester) async {
    await pumpBubble(tester, density: ChatDensity.compact, isUser: true);
    expect(find.text('You'), findsNothing);

    await pumpBubble(tester, density: ChatDensity.compact, isUser: false);
    expect(find.text('Hermes'), findsNothing);
  });

  testWidgets('compact uses the density insets on the bubble', (tester) async {
    await pumpBubble(tester, density: ChatDensity.compact, isUser: false);
    final container = bubbleContainer(tester);
    expect(container.padding, ChatDensity.compact.bubblePadding);
    expect(container.margin, ChatDensity.compact.bubbleMargin);

    await pumpBubble(tester, density: ChatDensity.comfortable, isUser: false);
    final comfortable = bubbleContainer(tester);
    expect(comfortable.padding, ChatDensity.comfortable.bubblePadding);
    expect(comfortable.margin, ChatDensity.comfortable.bubbleMargin);
  });

  testWidgets('compact bubbles are wider for the same unwrapped line', (
    tester,
  ) async {
    const longLine =
        'One long unbroken sentence that never wraps inside the test surface '
        'because it is measured on a single line of prose.';

    await pumpBubble(
      tester,
      density: ChatDensity.comfortable,
      isUser: false,
      content: longLine,
    );
    final comfortableWidth = tester
        .getSize(find.byKey(const Key('message-bubble')))
        .width;

    await pumpBubble(
      tester,
      density: ChatDensity.compact,
      isUser: false,
      content: longLine,
    );
    final compactWidth = tester
        .getSize(find.byKey(const Key('message-bubble')))
        .width;

    expect(compactWidth, greaterThan(comfortableWidth));
  });

  testWidgets('compact fits the same conversation in less vertical space', (
    tester,
  ) async {
    Future<double> columnHeight(ChatDensity density) async {
      await tester.pumpWidget(
        testAppWithL10n(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                key: const Key('conversation'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 6; i++)
                    MessageBubble(
                      key: ValueKey(i),
                      content: 'Message number $i.',
                      isUser: i.isEven,
                      density: density,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('conversation'))).height;
    }

    final comfortable = await columnHeight(ChatDensity.comfortable);
    final compact = await columnHeight(ChatDensity.compact);

    expect(compact, lessThan(comfortable));
  });
}
