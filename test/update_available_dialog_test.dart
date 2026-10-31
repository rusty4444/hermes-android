import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:hermes_android/core/widgets/update_available_dialog.dart';

import 'support/l10n_test_utils.dart';

const _release = AppReleaseInfo(
  version: '2.1.20',
  tagName: 'v2.1.20',
  name: 'Hermes Android 2.1.20',
  notes: 'Fixes the chat stream teardown.',
  releaseUrl:
      'https://github.com/rusty4444/hermes-android/releases/tag/v2.1.20',
);

/// Pumps a button that opens the prompt and records the action it resolved to.
Future<List<Object?>> pumpPrompt(
  WidgetTester tester, {
  AppReleaseInfo release = _release,
  ReleaseLauncher? launcher,
}) async {
  final opened = <Object?>[];
  final actions = <Object?>[];
  await tester.pumpWidget(
    testAppWithL10n(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              actions.add(
                await showUpdateAvailableDialog(
                  context,
                  release: release,
                  launcher:
                      launcher ??
                      (url) async {
                        opened.add(url);
                        return true;
                      },
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return [opened, actions];
}

void main() {
  testWidgets('shows the release, its version and its notes', (tester) async {
    await pumpPrompt(tester);

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Hermes Android 2.1.20'), findsOneWidget);
    expect(find.text('Version 2.1.20'), findsOneWidget);
    expect(
      find.text('A newer Hermes Android build is available on GitHub.'),
      findsOneWidget,
    );
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(
      find.text('Fixes the chat stream teardown.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('View release'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('a release without notes renders without a notes section', (
    tester,
  ) async {
    await pumpPrompt(
      tester,
      release: const AppReleaseInfo(
        version: '2.1.20',
        tagName: 'v2.1.20',
        releaseUrl: 'https://example.invalid/release',
      ),
    );

    // The tag stands in for the missing title.
    expect(find.text('v2.1.20'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('remote release-note images render as text, not network images', (
    tester,
  ) async {
    await pumpPrompt(
      tester,
      release: const AppReleaseInfo(
        version: '2.1.20',
        tagName: 'v2.1.20',
        releaseUrl: 'https://github.com/rusty4444/hermes-android/releases',
        notes: '![Preview](https://tracker.example/pixel.png)',
      ),
    );
    expect(find.text('Preview', findRichText: true), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('View release opens the release page and reports it', (
    tester,
  ) async {
    final state = await pumpPrompt(tester);

    await tester.tap(find.text('View release'));
    await tester.pumpAndSettle();

    final opened = state[0]! as List<Object?>;
    final actions = state[1]! as List<Object?>;
    expect(opened, [Uri.parse(_release.releaseUrl)]);
    expect(actions, [UpdatePromptAction.viewRelease]);
  });

  testWidgets('Skip this version reports the skip and opens nothing', (
    tester,
  ) async {
    final state = await pumpPrompt(tester);

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();

    final opened = state[0]! as List<Object?>;
    final actions = state[1]! as List<Object?>;
    expect(opened, isEmpty);
    expect(actions, [UpdatePromptAction.skipVersion]);
  });

  testWidgets('Later dismisses without a decision', (tester) async {
    final state = await pumpPrompt(tester);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    final actions = state[1]! as List<Object?>;
    expect(actions, [UpdatePromptAction.later]);
  });

  testWidgets('a launcher that fails dismisses as Later instead of crashing', (
    tester,
  ) async {
    final state = await pumpPrompt(
      tester,
      launcher: (url) async => throw Exception('no browser'),
    );

    await tester.tap(find.text('View release'));
    await tester.pumpAndSettle();

    expect(state[1]! as List<Object?>, [UpdatePromptAction.later]);
    expect(tester.takeException(), isNull);
  });
}
