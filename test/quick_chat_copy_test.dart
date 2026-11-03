import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/new_chat_options.dart';
import 'package:hermes_android/core/widgets/new_chat_sheet.dart';
import 'package:hermes_android/core/widgets/share_text_review_sheet.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Widget app(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: Scaffold(body: child),
);

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('Quick Chat does not promise auto-archive in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = await AppLocalizations.delegate.load(locale);
      final options = buildNewChatOptions(
        l10n: l10n,
        support: ProjectsSupport.unsupported,
        projects: const [],
      );
      await tester.pumpWidget(app(locale, NewChatSheet(options: options)));
      await tester.pumpAndSettle();
      final quick = tester.widget<ListTile>(
        find.widgetWithText(ListTile, l10n.quick_chat),
      );
      expect(quick.enabled, isTrue);
      expect(quick.onTap, isNotNull);
      expect((quick.subtitle! as Text).data, l10n.quick_chat_description);
      expect(l10n.quick_chat_description, isNot(contains('72')));

      await tester.pumpWidget(
        app(
          locale,
          const ShareTextReviewSheet(
            sharedText: 'A question',
            projectChatEnabled: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shareQuick = tester.widget<RadioListTile<NewChatMode>>(
        find.widgetWithText(RadioListTile<NewChatMode>, l10n.quick_chat),
      );
      expect(shareQuick.value, NewChatMode.quickChat);
      expect(shareQuick.subtitle, isNull);
      expect(find.textContaining('72'), findsNothing);
    });
  }
}
