import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Future<void> _pumpPane(
  WidgetTester tester, {
  required List<MoreSection> sections,
  ValueChanged<MoreEntry>? onSelect,
  // Tall by default so assertions are about content, not scroll position; the
  // narrow-phone tests below set a real phone height explicitly.
  Size size = const Size(360, 1600),
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: MorePane(sections: sections, onSelect: onSelect ?? (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  group('buildMoreSections', () {
    test('exposes the supported More destinations exactly once', () {
      final sections = buildMoreSections(dashboardReachable: true, l10n: l10n);
      final ids = [
        for (final section in sections)
          for (final entry in section.entries) entry.id,
      ];

      expect(ids.toSet(), hasLength(ids.length), reason: 'ids must be unique');
      expect(
        ids,
        unorderedEquals(<String>[
          'files',
          'assets',
          'unassigned',
          'cron',
          'skills',
          'memory',
          'nous-portal',
          'settings',
          'dashboard',
        ]),
      );
    });

    test('archive access stays in Chats rather than More', () {
      for (final dashboardReachable in [true, false]) {
        final entries = buildMoreSections(
          dashboardReachable: dashboardReachable,
          l10n: l10n,
        ).expand((section) => section.entries);

        expect(
          entries.map((entry) => entry.id),
          isNot(contains('archived-quick')),
        );
        expect(
          entries.map((entry) => entry.title),
          isNot(contains(l10n.archived_quick_chats)),
        );
      }
    });

    test('Unassigned chats is not mislabeled as the action Inbox', () {
      final entry = buildMoreSections(dashboardReachable: true, l10n: l10n)
          .expand((section) => section.entries)
          .firstWhere((candidate) => candidate.id == 'unassigned');

      expect(entry.title, 'Unassigned chats');
      expect(entry.subtitle, contains('not assigned to a Project'));
    });

    test('every section has a title and at least one entry', () {
      for (final section in buildMoreSections(
        dashboardReachable: true,
        l10n: l10n,
      )) {
        expect(section.title, isNotEmpty);
        expect(section.entries, isNotEmpty);
      }
    });

    test('dashboard-backed entries are available when the dashboard is', () {
      final entries = {
        for (final section in buildMoreSections(
          dashboardReachable: true,
          l10n: l10n,
        ))
          for (final entry in section.entries) entry.id: entry,
      };

      for (final id in ['cron', 'skills', 'memory', 'dashboard', 'settings']) {
        expect(
          entries[id]!.availability,
          MoreEntryAvailability.available,
          reason: '$id must be usable on a reachable dashboard',
        );
      }
    });

    test('a missing dashboard disables its entries with a reason', () {
      final entries = {
        for (final section in buildMoreSections(
          dashboardReachable: false,
          l10n: l10n,
        ))
          for (final entry in section.entries) entry.id: entry,
      };

      for (final id in ['cron', 'skills', 'memory', 'dashboard']) {
        final entry = entries[id]!;
        expect(
          entry.availability,
          MoreEntryAvailability.unavailable,
          reason: '$id needs the dashboard',
        );
        expect(
          entry.unavailableReason,
          isNotNull,
          reason: '$id must explain why it is disabled, not just grey out',
        );
        expect(entry.unavailableReason, isNotEmpty);
      }
    });

    test('local settings stay reachable without a dashboard', () {
      final entries = {
        for (final section in buildMoreSections(
          dashboardReachable: false,
          l10n: l10n,
        ))
          for (final entry in section.entries) entry.id: entry,
      };

      expect(
        entries['settings']!.availability,
        MoreEntryAvailability.available,
      );
    });

    for (final dashboardReachable in [true, false]) {
      test(
        'omits Organisation placeholders (dashboard: $dashboardReachable)',
        () {
          final sections = buildMoreSections(
            dashboardReachable: dashboardReachable,
            l10n: l10n,
          );
          final ids = sections
              .expand((section) => section.entries)
              .map((e) => e.id);

          expect(sections.map((section) => section.title), [
            'Workspace',
            'Agent',
            'Nous Portal',
            'System',
          ]);
          expect(ids, isNot(contains('pin-batch-undo')));
          expect(ids, isNot(contains('ai-filing')));
        },
      );
    }

    test(
      'groups Cron, Skills and Memory under Agent in every locale',
      () async {
        const titles = {
          'de': 'Agent',
          'en': 'Agent',
          'es': 'Agente',
          'fr': 'Agent',
          'ja': 'エージェント',
          'ko': '에이전트',
          'pt': 'Agente',
          'pt_BR': 'Agente',
          'ru': 'Агент',
          'zh': '智能体',
          'zh_Hans': '智能体',
        };
        expect(
          titles.keys,
          unorderedEquals(
            AppLocalizations.supportedLocales.map((l) => l.toString()),
          ),
        );

        for (final locale in AppLocalizations.supportedLocales) {
          final localized = await loadTestL10n(locale);
          final sections = buildMoreSections(
            dashboardReachable: true,
            l10n: localized,
          );
          final agent = sections.singleWhere(
            (section) => section.entries.any((entry) => entry.id == 'cron'),
          );

          expect(agent.title, titles[locale.toString()], reason: '$locale');
          expect(agent.entries.map((entry) => entry.id), [
            'cron',
            'skills',
            'memory',
          ]);
        }
      },
    );

    test(
      'native Smart Views are available and only contract gaps are disabled',
      () {
        final entries = {
          for (final section in buildMoreSections(
            dashboardReachable: true,
            l10n: l10n,
          ))
            for (final entry in section.entries) entry.id: entry,
        };

        expect(entries['files']!.availability, MoreEntryAvailability.available);
        expect(
          entries['unassigned']!.availability,
          MoreEntryAvailability.available,
        );
      },
    );

    test('Files and Assets follow the dashboard they depend on', () {
      final entries = {
        for (final section in buildMoreSections(
          dashboardReachable: false,
          l10n: l10n,
        ))
          for (final entry in section.entries) entry.id: entry,
      };

      expect(entries['files']!.availability, MoreEntryAvailability.unavailable);
      expect(entries['files']!.unavailableReason, isNotNull);
      expect(
        entries['assets']!.availability,
        MoreEntryAvailability.unavailable,
      );
      expect(entries['assets']!.unavailableReason, isNotNull);
    });
  });

  group('MorePane', () {
    List<MoreSection> sections({bool dashboardReachable = true}) =>
        buildMoreSections(dashboardReachable: dashboardReachable, l10n: l10n);

    testWidgets('renders every section title and entry', (tester) async {
      final built = sections();
      await _pumpPane(tester, sections: built);

      for (final section in built) {
        await tester.scrollUntilVisible(
          find.text(section.title),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(section.title), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('Cron'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cron'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Settings'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('does not render the redundant archive card', (tester) async {
      await _pumpPane(tester, sections: sections());

      expect(find.text(l10n.archived_quick_chats), findsNothing);
      expect(
        find.text(
          l10n.review_or_promote_quick_chats_past_their_retention_period,
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.archive_outlined), findsNothing);
      expect(find.text(l10n.unassigned_chats), findsOneWidget);
      expect(find.text(l10n.files), findsOneWidget);
      expect(find.text(l10n.assets), findsOneWidget);
    });

    for (final dashboardReachable in [true, false]) {
      testWidgets(
        'renders Agent without Organisation (dashboard: $dashboardReachable)',
        (tester) async {
          await _pumpPane(
            tester,
            sections: sections(dashboardReachable: dashboardReachable),
            size: const Size(360, 2400),
          );

          expect(find.text('Agent'), findsOneWidget);
          expect(find.text('Automation'), findsNothing);
          expect(find.text(l10n.organization), findsNothing);
          expect(find.text(l10n.pin_batch_and_undo), findsNothing);
          expect(find.text(l10n.ai_assisted_filing), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Agent entries retain their selection IDs', (tester) async {
      final picked = <String>[];
      final agent = sections().singleWhere(
        (section) => section.entries.any((entry) => entry.id == 'cron'),
      );
      await _pumpPane(
        tester,
        sections: sections(),
        onSelect: (entry) => picked.add(entry.id),
      );

      for (final entry in agent.entries) {
        await tester.scrollUntilVisible(
          find.text(entry.title),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(entry.title));
        await tester.pumpAndSettle();
      }

      expect(picked, ['cron', 'skills', 'memory']);
    });

    testWidgets('selecting an available entry reports it once', (tester) async {
      final picked = <String>[];
      await _pumpPane(
        tester,
        sections: sections(),
        onSelect: (entry) => picked.add(entry.id),
      );

      await tester.ensureVisible(find.text('Cron'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cron'));
      await tester.pumpAndSettle();

      expect(picked, ['cron']);
    });

    testWidgets('an unavailable entry cannot be selected', (tester) async {
      final picked = <String>[];
      await _pumpPane(
        tester,
        sections: sections(dashboardReachable: false),
        onSelect: (entry) => picked.add(entry.id),
      );

      await tester.scrollUntilVisible(
        find.text('Cron'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Cron'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
    });

    testWidgets('an unavailable entry explains why on screen', (tester) async {
      final built = sections(dashboardReachable: false);
      await _pumpPane(tester, sections: built);

      final cron = built
          .expand((section) => section.entries)
          .firstWhere((entry) => entry.id == 'cron');

      expect(find.text(cron.unavailableReason!), findsWidgets);
    });

    testWidgets('Assets is selectable and describes its recent-chat scope', (
      tester,
    ) async {
      final picked = <String>[];
      await _pumpPane(
        tester,
        sections: sections(),
        onSelect: (entry) => picked.add(entry.id),
      );

      await tester.tap(find.text('Assets'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.text('Find files shared by Hermes in saved chats'),
        findsOneWidget,
      );
      expect(picked, ['assets']);
    });

    testWidgets('survives a large text scale on a narrow phone', (
      tester,
    ) async {
      await _pumpPane(
        tester,
        sections: sections(),
        size: const Size(320, 640),
        textScale: 1.8,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Unassigned chats'), findsOneWidget);
    });

    testWidgets('scrolls to the last entry on a real phone height', (
      tester,
    ) async {
      await _pumpPane(tester, sections: sections(), size: const Size(360, 720));

      await tester.scrollUntilVisible(
        find.text('Settings'),
        160,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in the light theme', (tester) async {
      await _pumpPane(
        tester,
        sections: sections(),
        brightness: Brightness.light,
      );

      await tester.scrollUntilVisible(
        find.text('Settings'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('every entry is reachable by a screen reader', (tester) async {
      final built = sections();
      await _pumpPane(tester, sections: built);

      for (final section in built) {
        for (final entry in section.entries) {
          await tester.scrollUntilVisible(
            find.text(entry.title),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.bySemanticsLabel(RegExp(entry.title)),
            findsWidgets,
            reason: '${entry.title} must be announced',
          );
        }
      }
    });
  });
}
