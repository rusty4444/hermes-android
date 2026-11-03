import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _label =
    'Emulator-R4-Quality-Assurance-Connection-with-a-very-long-name-for-small-phone-accessibility-testing-234';

void _expectInside(Rect outer, Rect inner) {
  expect(inner.left, greaterThanOrEqualTo(outer.left));
  expect(inner.right, lessThanOrEqualTo(outer.right));
  expect(inner.top, greaterThanOrEqualTo(outer.top));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT']!;
    final bytes = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    '320dp 2x workspace retains title, search, chips, FAB and navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var newChats = 0;
      final theme = hermesTheme(Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: child!,
          ),
          home: const Scaffold(body: Text('Connections')),
        ),
      );
      Navigator.of(tester.element(find.text('Connections'))).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceScreen(
            connection: SavedConnection(
              id: 'compact-234',
              label: _label,
              host: 'example.invalid',
              port: 8642,
              apiKey: 'test',
            ),
            sessionsLoader: () async => <Session>[],
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
            installedVersionLoader: () async => null,
            activityFeedLoader: (_, _) async => const ActivityFeed(
              groups: [
                ActivityGroup(
                  kind: ActivityGroupKind.needsYou,
                  items: [],
                  totalCount: 1,
                ),
              ],
              blockedCount: 1,
              runningCount: 0,
            ),
            onNewChat: (_) => newChats++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsOneWidget,
      );
      final titleFinder = find.text(_label);
      final title = tester.renderObject<RenderParagraph>(titleFinder);
      expect(title.size.width, greaterThan(40));
      final titleBoxes = title.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(titleBoxes, isNotEmpty);
      final appBar = tester.getRect(find.byType(AppBar));
      _expectInside(appBar, tester.getRect(titleFinder));

      final searchFinder = find.byKey(kWorkspaceSessionSearchKey);
      final fabFinder = find.byKey(kWorkspaceNewChatButtonKey);
      final search = tester.getRect(searchFinder);
      final fab = tester.getRect(fabFinder);
      final nav = tester.getRect(find.byType(NavigationBar));
      const usable = Rect.fromLTRB(0, 24, 320, 616);
      _expectInside(usable, search);
      _expectInside(usable, fab);
      expect(fab.overlaps(search), isFalse);
      expect(fab.bottom, lessThanOrEqualTo(nav.top));
      for (final label in ['Chats', 'Crons', 'Projects', 'Activity', 'More']) {
        final finder = find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        );
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(
          boxes.map((box) => box.top.round()).toSet(),
          hasLength(1),
          reason: label,
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        _expectInside(usable, tester.getRect(finder));
      }
      final chips = find
          .byType(SingleChildScrollView)
          .evaluate()
          .where(
            (element) =>
                (element.widget as SingleChildScrollView).scrollDirection ==
                Axis.horizontal,
          );
      final chipStrip = find.byWidget(chips.single.widget);
      _expectInside(usable, tester.getRect(chipStrip));
      expect(tester.getRect(chipStrip).overlaps(fab), isFalse);
      for (final label in ['All', 'Recent', 'Unassigned', 'Archived']) {
        final chip = find.widgetWithText(ChoiceChip, label);
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        expect(chip.hitTestable(), findsOneWidget, reason: label);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(searchFinder, 'query');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(searchFinder).onChanged, isNotNull);
      await tester.tap(fabFinder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final projectOption = find.widgetWithText(ListTile, 'Project chat');
      await tester.ensureVisible(projectOption);
      await tester.pumpAndSettle();
      expect(projectOption.hitTestable(), findsOneWidget);
      expect(tester.widget<ListTile>(projectOption).enabled, isFalse);
      final quickOption = find.widgetWithText(ListTile, 'Quick chat');
      await tester.ensureVisible(quickOption);
      await tester.pumpAndSettle();
      await tester.tap(quickOption);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(newChats, 1);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Crons'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.byKey(kWorkspaceNewChatButtonKey), findsNothing);
      expect(
        find.byKey(kWorkspaceSessionSearchKey).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
