import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/android_share_intent_service.dart';
import 'package:hermes_android/core/utils/new_chat_options.dart';
import 'package:hermes_android/core/widgets/share_text_review_sheet.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';


void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  test(
    'favorite actions produce explicit prompts without losing source text',
    () {
      const source = 'https://example.com/article';

      expect(buildSharedPrompt(ShareFavoriteAction.useAsIs, source, l10n: l10n), source);
      expect(
        buildSharedPrompt(ShareFavoriteAction.summarize, source, l10n: l10n),
        contains('Summarize'),
      );
      expect(
        buildSharedPrompt(ShareFavoriteAction.extractTasks, source, l10n: l10n),
        allOf(contains('action items'), contains(source)),
      );
      expect(
        buildSharedPrompt(
          ShareFavoriteAction.useAsIs,
          '',
          hasAttachments: true, l10n: l10n),
        'Review the attached content.',
      );
      expect(
        buildSharedPrompt(
          ShareFavoriteAction.summarize,
          '',
          hasAttachments: true, l10n: l10n),
        'Summarize the attached content.',
      );
    },
  );

  testWidgets('lists shared attachments for confirmation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShareTextReviewSheet(
            sharedText: '',
            sharedFiles: const [
              AndroidSharedFile(
                path: '/cache/report.pdf',
                name: 'report.pdf',
                mediaType: 'application/pdf',
                byteLength: 2048,
              ),
              AndroidSharedFile(
                path: '/cache/photo.jpg',
                name: 'photo.jpg',
                mediaType: 'image/jpeg',
                byteLength: 1024,
              ),
            ],
            projectChatEnabled: true,
          ),
        ),
      ),
    );

    expect(find.text('2 attachments'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('No text shared'), findsOneWidget);
  });

  testWidgets('requires confirmation and returns action plus destination', (
    tester,
  ) async {
    ShareTextDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                decision = await showModalBottomSheet<ShareTextDecision>(
                  context: context,
                  builder: (_) => const ShareTextReviewSheet(
                    sharedText: 'https://example.com/article',
                    projectChatEnabled: true,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Share to Hermes'), findsOneWidget);
    expect(find.text('Summarize'), findsOneWidget);
    expect(find.text('Quick chat'), findsOneWidget);
    expect(find.text('Project chat'), findsOneWidget);

    await tester.tap(find.text('Summarize'));
    await tester.ensureVisible(find.text('Project chat'));
    await tester.tap(find.text('Project chat'));
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(decision?.action, ShareFavoriteAction.summarize);
    expect(decision?.mode, NewChatMode.projectChat);
  });

  testWidgets('explains when Project chat is unavailable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShareTextReviewSheet(
            sharedText: 'Shared text',
            projectChatEnabled: false,
          ),
        ),
      ),
    );

    expect(find.text('No active Projects on this Gateway'), findsOneWidget);
    final projectChoice = tester.widget<RadioListTile<NewChatMode>>(
      find.widgetWithText(RadioListTile<NewChatMode>, 'Project chat'),
    );
    expect(projectChoice.enabled, isFalse);
  });
}
