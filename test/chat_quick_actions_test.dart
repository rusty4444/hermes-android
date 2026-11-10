import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/l10n_test_utils.dart';

/// The quick-action row is the always-visible affordance under the newest
/// completed assistant reply (M3 Expressive pass). The long-press sheet keeps
/// the full set; this covers the row's visibility rules and its wiring.
void main() {
  Future<AppLocalizations> l10n() => loadTestL10n();

  Future<void> pump(
    WidgetTester tester, {
    required bool showQuickActions,
    bool withReadAloud = true,
    bool withRetry = true,
    Future<void> Function()? onRetry,
  }) async {
    await tester.pumpWidget(
      testAppWithL10n(
        Scaffold(
          body: MessageBubble(
            content: 'A finished answer',
            isUser: false,
            showQuickActions: showQuickActions,
            onReadAloud: withReadAloud ? () async {} : null,
            onRetry: withRetry ? (onRetry ?? () async {}) : null,
          ),
        ),
      ),
    );
  }

  testWidgets('no quick actions by default', (tester) async {
    await pump(tester, showQuickActions: false);
    expect(find.byKey(const Key('message-action-copy')), findsNothing);
    expect(find.byKey(const Key('message-action-retry')), findsNothing);
  });

  testWidgets('opt-in shows copy, select, read aloud and regenerate', (
    tester,
  ) async {
    await pump(tester, showQuickActions: true);
    expect(find.byKey(const Key('message-action-copy')), findsOneWidget);
    expect(find.byKey(const Key('message-action-select')), findsOneWidget);
    expect(find.byKey(const Key('message-action-read')), findsOneWidget);
    expect(find.byKey(const Key('message-action-retry')), findsOneWidget);
    final l = await l10n();
    expect(find.byTooltip(l.copy_message), findsOneWidget);
    expect(find.byTooltip(l.regenerate_response), findsOneWidget);
  });

  testWidgets('row drops actions whose callbacks are absent', (tester) async {
    await pump(
      tester,
      showQuickActions: true,
      withReadAloud: false,
      withRetry: false,
    );
    expect(find.byKey(const Key('message-action-read')), findsNothing);
    expect(find.byKey(const Key('message-action-retry')), findsNothing);
    expect(find.byKey(const Key('message-action-copy')), findsOneWidget);
  });

  testWidgets('regenerate action invokes onRetry', (tester) async {
    var retries = 0;
    await pump(tester, showQuickActions: true, onRetry: () async => retries++);
    await tester.tap(find.byKey(const Key('message-action-retry')));
    expect(retries, 1);
  });

  testWidgets('copy action writes the message to the clipboard', (
    tester,
  ) async {
    final clips = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clips.add((call.arguments as Map)['text']);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester, showQuickActions: true);
    await tester.tap(find.byKey(const Key('message-action-copy')));
    await tester.pump();
    expect(clips, ['A finished answer']);
    final l = await l10n();
    expect(find.text(l.message_copied), findsOneWidget);
  });
}
