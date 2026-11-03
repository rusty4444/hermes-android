import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_message_time.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';

import 'support/l10n_test_utils.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('de')]) {
    for (final use24 in [false, true]) {
      testWidgets(
        'footer respects locale=$locale 24-hour=$use24 and provenance',
        (tester) async {
          final at = DateTime.utc(2024, 6, 15, 13, 5);
          for (final source in ['sent', 'received', 'recorded']) {
            await tester.pumpWidget(
              testAppWithL10n(
                Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(
                      size: const Size(800, 600),
                      alwaysUse24HourFormat: use24,
                    ),
                    child: MessageBubble(
                      content: 'Timed message',
                      isUser: true,
                      density: ChatDensity.compact,
                      metadata: {
                        ChatMessageTime.observedAtKey:
                            at.millisecondsSinceEpoch,
                        ChatMessageTime.sourceKey: source == 'recorded'
                            ? 'sent'
                            : source,
                        if (source == 'recorded')
                          'timestamp': at.millisecondsSinceEpoch / 1000,
                      },
                    ),
                  ),
                ),
                locale: locale,
              ),
            );
            final footer = find.byKey(const Key('message-timestamp'));
            final context = tester.element(footer);
            expect(
              tester.widget<Text>(footer).data,
              MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay.fromDateTime(at.toLocal()),
                alwaysUse24HourFormat: use24,
              ),
            );
            final tooltip = tester.widget<Tooltip>(
              find.ancestor(of: footer, matching: find.byType(Tooltip)).first,
            );
            expect(
              tooltip.message,
              contains(switch (source) {
                'sent' => 'Send observed on this device',
                'received' => 'First received on this device',
                _ => 'Recorded by server',
              }),
            );
            expect(
              tooltip.message,
              contains(
                MaterialLocalizations.of(context).formatFullDate(at.toLocal()),
              ),
            );
          }
        },
      );
    }
  }

  for (final verbose in [false, true]) {
    for (final isUser in [false, true]) {
      for (final density in ChatDensity.values) {
        testWidgets('recorded footer user=$isUser verbose=$verbose $density', (
          tester,
        ) async {
          final at = DateTime.utc(2024, 6, 15, 13, 5);
          await tester.pumpWidget(
            testAppWithL10n(
              Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(800, 600),
                    alwaysUse24HourFormat: true,
                  ),
                  child: MessageBubble(
                    content: 'An ordinary message',
                    isUser: isUser,
                    verbose: verbose,
                    density: density,
                    metadata: {
                      'role': isUser ? 'user' : 'assistant',
                      'timestamp': at.millisecondsSinceEpoch / 1000,
                      'completed': true,
                    },
                  ),
                ),
              ),
            ),
          );
          final footer = find.byKey(const Key('message-timestamp'));
          expect(footer, findsOneWidget);
          final context = tester.element(footer);
          final expected = MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(at.toLocal()),
            alwaysUse24HourFormat: true,
          );
          expect(tester.widget<Text>(footer).data, expected);
          await tester.pump(const Duration(hours: 3));
          expect(tester.widget<Text>(footer).data, expected);
        });
      }
    }
  }

  testWidgets('missing, malformed and unfinished timestamps stay absent', (
    tester,
  ) async {
    for (final value in [
      null,
      'yesterday',
      true,
      0,
      -1,
      double.nan,
      double.infinity,
      1e30,
      {},
      [],
    ]) {
      await tester.pumpWidget(
        testAppWithL10n(
          Scaffold(
            body: MessageBubble(
              content: 'Untimed history',
              isUser: true,
              metadata: {'timestamp': value},
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('message-timestamp')), findsNothing);
      expect(tester.takeException(), isNull);
    }
    for (final flags in [
      <String, dynamic>{},
      {'completed': true, '_gateway_pending_response': true},
      {'completed': true, '_gateway_interim': true},
      {'completed': true, '_chat_response_complete': false},
      {'completed': true, 'partial': true},
    ]) {
      await tester.pumpWidget(
        testAppWithL10n(
          Scaffold(
            body: MessageBubble(
              content: 'Not a completed reply',
              isUser: false,
              verbose: true,
              metadata: {
                'role': 'assistant',
                'timestamp': 1718456700,
                ...flags,
              },
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('message-timestamp')), findsNothing);
    }
  });
}
