import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Session _session(
  String id,
  String title, {
  double? lastActive,
  bool archived = false,
  bool isActive = false,
  bool pinned = false,
  String source = 'gateway',
}) => Session(
  id: id,
  title: title,
  model: 'claude-opus-5',
  source: source,
  messageCount: 1,
  isActive: isActive,
  preview: 'preview $title',
  startedAt: 1750000000,
  lastActive: lastActive ?? 1750000000,
  archived: archived,
  pinned: pinned,
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  test('Unassigned excludes every server-scoped session', () {
    final result = filterWorkspaceSessions(
      sessions: [_session('s1', 'Filed'), _session('s2', 'Inbox')],
      view: WorkspaceSessionView.unassigned,
      claimedSessionIds: const {'s1'},
    );
    expect(result.map((session) => session.id), ['s2']);
  });

  group('WorkspaceChatsFilter', () {
    test('declares the four validated chip filters in order', () {
      expect(WorkspaceChatsFilter.values, [
        WorkspaceChatsFilter.all,
        WorkspaceChatsFilter.recent,
        WorkspaceChatsFilter.unassigned,
        WorkspaceChatsFilter.archived,
      ]);
      for (final filter in WorkspaceChatsFilter.values) {
        expect(filter.label(l10n), isNotEmpty);
      }
    });

    test('All keeps every non-archived session', () {
      final result = filterChats(
        sessions: [_session('s1', 'A'), _session('s2', 'B')],
        filter: WorkspaceChatsFilter.all,
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s1', 's2']);
    });

    test('All, Recent and Unassigned hide server-archived sessions', () {
      // The Chats browser feeds the filter the union of the gateway's
      // active list and the dashboard's archived list; the non-archived
      // chips must therefore exclude archived rows explicitly or the
      // union would leak them.
      final live = _session('s1', 'Live');
      final archived = _session('s2', 'Archived', archived: true);
      final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

      for (final filter in [
        WorkspaceChatsFilter.all,
        WorkspaceChatsFilter.recent,
        WorkspaceChatsFilter.unassigned,
      ]) {
        final result = filterChats(
          sessions: [live, archived],
          filter: filter,
          now: now,
        );
        expect(result.map((s) => s.id), ['s1'], reason: filter.label(l10n));
      }
    });

    test('Recent keeps only sessions active within seven days', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
      final recent = _session('s1', 'Fresh', lastActive: 1750000000);
      final old = _session('s2', 'Stale', lastActive: 1745000000);

      final result = filterChats(
        sessions: [old, recent],
        filter: WorkspaceChatsFilter.recent,
        now: now,
      );

      expect(result.map((s) => s.id), ['s1']);
    });

    test('Unassigned excludes claimed sessions', () {
      final result = filterChats(
        sessions: [_session('s1', 'Filed'), _session('s2', 'Inbox')],
        filter: WorkspaceChatsFilter.unassigned,
        claimedSessionIds: const {'s1'},
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s2']);
    });

    test('Unassigned hides machine-generated sessions', () {
      // projects.tree never claims cron/kanban/oneshot rows, so without
      // this exclusion every automated run piles up as unfilable
      // "unassigned" noise the filing engine can never answer for.
      final human = _session('s1', 'Human chat');
      final cron = _session('s2', 'Cron run', source: 'cron');
      final kanban = _session('s3', 'Kanban run', source: 'kanban');
      final oneshot = _session('s4', 'Oneshot run', source: 'oneshot');

      final result = filterChats(
        sessions: [human, cron, kanban, oneshot],
        filter: WorkspaceChatsFilter.unassigned,
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s1']);
    });

    test('All and Recent hide machine sessions (desktop parity)', () {
      // Cron/kanban/oneshot runs are excluded from every chat chip, not
      // just Unassigned — the desktop sidebar drops these sources from
      // recents entirely so the scheduler's always-newest sessions can't
      // crowd human chats out. Cron runs are browsed per-job from the
      // Cron screen instead.
      final human = _session('s1', 'Human chat');
      final cron = _session('s2', 'Cron run', source: 'cron');
      final kanban = _session('s3', 'Kanban run', source: 'kanban');
      final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

      final all = filterChats(
        sessions: [human, cron, kanban],
        filter: WorkspaceChatsFilter.all,
        now: now,
      );
      expect(all.map((s) => s.id).toSet(), {'s1'});

      final recent = filterChats(
        sessions: [human, cron, kanban],
        filter: WorkspaceChatsFilter.recent,
        now: now,
      );
      expect(recent.map((s) => s.id).toSet(), {'s1'});
    });

    test('Archived merges server-archived and quick-chat archived ids', () {
      final server = _session('s1', 'Server archived', archived: true);
      final quick = _session('s2', 'Quick archived');
      final live = _session('s3', 'Live');

      final result = filterChats(
        sessions: [live, server, quick],
        filter: WorkspaceChatsFilter.archived,
        archivedQuickChatIds: const {'s2'},
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );

      expect(result.map((s) => s.id).toSet(), {'s1', 's2'});
    });

    test('query narrows the active filter', () {
      final result = filterChats(
        sessions: [_session('s1', 'Migration'), _session('s2', 'Taxes')],
        filter: WorkspaceChatsFilter.all,
        query: 'migration',
        now: DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000),
      );
      expect(result.map((s) => s.id), ['s1']);
    });
  });

  group('chatDateBucket', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
    final today = now.millisecondsSinceEpoch / 1000.0;
    final yesterday =
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch / 1000.0;
    final thisWeek =
        now.subtract(const Duration(days: 3)).millisecondsSinceEpoch / 1000.0;
    final earlier =
        now.subtract(const Duration(days: 20)).millisecondsSinceEpoch / 1000.0;

    test('buckets by age', () {
      expect(chatDateBucket(now, today), ChatDateBucket.today);
      expect(chatDateBucket(now, yesterday), ChatDateBucket.yesterday);
      expect(chatDateBucket(now, thisWeek), ChatDateBucket.thisWeek);
      expect(chatDateBucket(now, earlier), ChatDateBucket.earlier);
    });

    test('groupChatsByDate returns buckets in order with labels', () {
      final groups = groupChatsByDate(now, [
        _session('s1', 'old', lastActive: earlier),
        _session('s2', 'fresh', lastActive: today),
      ]);
      expect(groups.length, 2);
      expect(groups[0].key, ChatDateBucket.today);
      expect(groups[0].value.map((s) => s.id), ['s2']);
      expect(groups[1].key, ChatDateBucket.earlier);
      expect(groups[1].value.map((s) => s.id), ['s1']);
    });

    test('bucket labels are human readable', () {
      expect(ChatDateBucket.today.label(l10n), 'Today');
      expect(ChatDateBucket.yesterday.label(l10n), 'Yesterday');
      expect(ChatDateBucket.thisWeek.label(l10n), 'This week');
      expect(ChatDateBucket.earlier.label(l10n), 'Earlier');
    });
  });

  test(
    'Archived Quick shows only archived quick chats and stays searchable',
    () {
      final sessions = [
        _session('s1', 'Old research'),
        _session('s2', 'Current'),
      ];
      final result = filterWorkspaceSessions(
        sessions: sessions,
        view: WorkspaceSessionView.archivedQuick,
        archivedQuickChatIds: const {'s1'},
        query: 'research',
      );
      expect(result.map((session) => session.id), ['s1']);
    },
  );

  testWidgets('embedded mode reuses the browser without a nested scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Chats',
          view: WorkspaceSessionView.all,
          embedded: true,
          load: () async =>
              WorkspaceSessionsData(sessions: [_session('s1', 'Daily driver')]),
          onOpenSession: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(kWorkspaceSessionSearchKey), findsOneWidget);
    expect(find.text('Daily driver'), findsOneWidget);
  });

  testWidgets('cached chats render while metadata is still loading', (
    tester,
  ) async {
    final metadata = Completer<WorkspaceSessionsData>();
    final chat = _session('s1', 'Cached conversation');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Chats',
          view: WorkspaceSessionView.all,
          embedded: true,
          initialData: WorkspaceSessionsData(
            sessions: [chat],
            projectsKnown: false,
            isPartial: true,
          ),
          load: () => metadata.future,
          onOpenSession: (_) {},
        ),
      ),
    );

    expect(find.text('Cached conversation'), findsOneWidget);
    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
    await tester.pump();
    expect(find.text('Cached conversation'), findsNothing);
    expect(find.byType(EmptyState), findsNothing);

    metadata.complete(
      WorkspaceSessionsData(sessions: [chat], claimedSessionIds: const {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cached conversation'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('late preview appears but cannot replace completed Chats data', (
    tester,
  ) async {
    final complete = Completer<WorkspaceSessionsData>();
    final preview = WorkspaceSessionsData(
      sessions: [_session('s1', 'First chat')],
      projectsKnown: false,
      isPartial: true,
    );
    Widget browser(WorkspaceSessionsData? initialData) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceSessionsScreen(
        key: const ValueKey('chats'),
        title: 'Chats',
        view: WorkspaceSessionView.all,
        embedded: true,
        initialData: initialData,
        load: () => complete.future,
        onOpenSession: (_) {},
      ),
    );

    await tester.pumpWidget(browser(null));
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    await tester.pumpWidget(browser(preview));
    expect(find.text('First chat'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    complete.complete(
      WorkspaceSessionsData(
        sessions: [_session('s1', 'First chat'), _session('s2', 'Older chat')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Older chat'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(browser(preview));
    expect(find.text('Older chat'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  group('the Chats chip filters', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
    final recent = _session('s1', 'Fresh', lastActive: 1750000000);
    final old = _session('s2', 'Stale', lastActive: 1745000000);
    final claimed = _session('s3', 'Filed');
    final quickArchived = _session('s4', 'Quick archived');

    Future<void> pumpChats(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: now,
            load: () async => WorkspaceSessionsData(
              sessions: [recent, old, claimed, quickArchived],
              claimedSessionIds: const {'s3'},
              archivedQuickChatIds: const {'s4'},
            ),
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers the four validated chips in embedded mode', (
      tester,
    ) async {
      await pumpChats(tester);

      for (final filter in WorkspaceChatsFilter.values) {
        expect(
          find.widgetWithText(ChoiceChip, filter.label(l10n)),
          findsOneWidget,
        );
      }
    });

    testWidgets('Recent shows only sessions active within the window', (
      tester,
    ) async {
      await pumpChats(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Recent'));
      await tester.pumpAndSettle();

      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Stale'), findsNothing);
    });

    testWidgets('Unassigned shows only non-claimed sessions', (tester) async {
      await pumpChats(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
      await tester.pumpAndSettle();

      expect(find.text('Filed'), findsNothing);
      expect(find.text('Fresh'), findsOneWidget);
    });

    testWidgets('Archived shows quick-archived sessions', (tester) async {
      await pumpChats(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();

      expect(find.text('Quick archived'), findsOneWidget);
      expect(find.text('Fresh'), findsNothing);
    });

    testWidgets('Archived shows server-archived sessions from the dashboard', (
      tester,
    ) async {
      // The gateway's active list never contains archived rows, so the
      // dashboard-sourced archivedSessions list is the only way an
      // explicitly archived chat reaches the chip. It must show under
      // Archived and stay hidden under All.
      final serverArchived = _session(
        's9',
        'Archived on server',
        archived: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: now,
            load: () async => WorkspaceSessionsData(
              sessions: [recent],
              archivedSessions: [serverArchived],
            ),
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Archived on server'), findsNothing);
      expect(find.text('Fresh'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();

      expect(find.text('Archived on server'), findsOneWidget);
      expect(find.text('Fresh'), findsNothing);
    });

    testWidgets('groups rows under date headers', (tester) async {
      await pumpChats(tester);

      expect(find.text(ChatDateBucket.today.label(l10n)), findsOneWidget);
      expect(find.text(ChatDateBucket.earlier.label(l10n)), findsOneWidget);
    });
  });

  group('rename conversation', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);
    const richSession = Session(
      id: 's1',
      title: 'Original title',
      model: 'custom-model',
      source: 'mobile',
      messageCount: 42,
      isActive: true,
      preview: 'A preview that stays unchanged',
      startedAt: 1749999000,
      endedAt: 1750000001,
      lastActive: 1750000000,
      pinned: true,
      lineageRootId: 'root-s1',
      isLocalDraft: true,
    );

    Future<void> pumpBrowser(
      WidgetTester tester, {
      required WorkspaceSessionRenamer onRename,
      bool embedded = true,
      WorkspaceSessionsData? data,
      WorkspaceSessionsLoader? load,
      ValueChanged<Session>? onOpen,
      LocalChatPinStore? pinStore,
    }) async {
      final initial =
          data ??
          const WorkspaceSessionsData(
            sessions: [richSession],
            claimedSessionIds: {'s1'},
            projectLabels: {'s1': 'Project label'},
          );
      final browser = WorkspaceSessionsScreen(
        title: 'Chats',
        view: WorkspaceSessionView.all,
        embedded: embedded,
        now: now,
        initialData: initial,
        load: load ?? () async => initial,
        onOpenSession: onOpen ?? (_) {},
        onRename: onRename,
        pinStore: pinStore,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: embedded ? Scaffold(body: browser) : browser,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openRename(WidgetTester tester, {String? rowTitle}) async {
      final menu = rowTitle == null
          ? find.byTooltip(l10n.chat_actions).first
          : find.descendant(
              of: find.ancestor(
                of: find.text(rowTitle),
                matching: find.byType(HermesCard),
              ),
              matching: find.byTooltip(l10n.chat_actions),
            );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.rename));
      // The dialog must wait for the popup route to finish tearing down.
      await tester.pumpAndSettle();
      await tester.pump(kThemeAnimationDuration);
      await tester.pumpAndSettle();
      expect(find.text(l10n.rename_chat), findsOneWidget);
    }

    Finder dialogField() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );

    Future<void> submit(WidgetTester tester, String title) async {
      await tester.enterText(dialogField(), title);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    void expectMetadata(Session actual, Session expected) {
      expect(actual.id, expected.id);
      expect(actual.model, expected.model);
      expect(actual.source, expected.source);
      expect(actual.messageCount, expected.messageCount);
      expect(actual.isActive, expected.isActive);
      expect(actual.preview, expected.preview);
      expect(actual.startedAt, expected.startedAt);
      expect(actual.endedAt, expected.endedAt);
      expect(actual.lastActive, expected.lastActive);
      expect(actual.pinned, expected.pinned);
      expect(actual.lineageRootId, expected.lineageRootId);
      expect(actual.archived, expected.archived);
      expect(actual.isLocalDraft, expected.isLocalDraft);
    }

    for (final embedded in [true, false]) {
      final surface = embedded ? 'embedded' : 'standalone';
      testWidgets('$surface offers Rename without a pin store', (tester) async {
        var writes = 0;
        await pumpBrowser(
          tester,
          embedded: embedded,
          onRename: (_, _) async {
            writes++;
            return 'Saved';
          },
        );
        await openRename(tester);
        expect(
          tester.widget<TextFormField>(dialogField()).initialValue,
          richSession.title,
        );
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        expect(writes, 0);
      });

      testWidgets('$surface keeps local pin action alongside Rename', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final store = LocalChatPinStore(
          await SharedPreferences.getInstance(),
          connectionId: 'rename-$surface',
        );
        var writes = 0;
        await pumpBrowser(
          tester,
          embedded: embedded,
          pinStore: store,
          onRename: (_, _) async {
            writes++;
            return 'Saved';
          },
        );
        await tester.tap(find.byTooltip(l10n.chat_actions));
        await tester.pumpAndSettle();
        expect(find.text(l10n.rename), findsOneWidget);
        expect(find.text(l10n.pin_on_this_device), findsOneWidget);
        await tester.tap(find.text(l10n.pin_on_this_device));
        await tester.pumpAndSettle();
        expect(await store.load(), ['s1']);
        expect(writes, 0);
        await tester.tap(find.byTooltip(l10n.chat_actions));
        await tester.pumpAndSettle();
        expect(find.text(l10n.unpin_on_this_device), findsOneWidget);
        expect(find.text(l10n.rename), findsOneWidget);
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      });
    }

    testWidgets(
      'uses authoritative saved title, retains metadata and searches it',
      (tester) async {
        final opened = <Session>[];
        final requested = <String>[];
        await pumpBrowser(
          tester,
          onOpen: opened.add,
          data: WorkspaceSessionsData(
            sessions: [richSession, _session('s2', 'Unrelated')],
            claimedSessionIds: const {'s1'},
            projectLabels: const {'s1': 'Project label'},
            archivedQuickChatIds: const {'s2'},
            archivedSessions: [_session('s3', 'Archived row', archived: true)],
          ),
          onRename: (session, title) async {
            expect(identical(session, richSession), isTrue);
            requested.add(title);
            return 'Authoritative title';
          },
        );
        await openRename(tester, rowTitle: richSession.title);
        await submit(tester, '  Requested title  ');
        await tester.pumpAndSettle();
        expect(requested, ['Requested title']);
        expect(find.text('Authoritative title'), findsOneWidget);
        expect(find.text(richSession.title), findsNothing);
        expect(find.text(richSession.preview), findsOneWidget);
        expect(find.text('Project label'), findsOneWidget);
        expect(find.text('Running'), findsOneWidget);
        expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
        expect(find.text('Unrelated'), findsOneWidget);
        await tester.tap(find.text('Authoritative title'));
        expect(opened.single.title, 'Authoritative title');
        expectMetadata(opened.single, richSession);

        await tester.enterText(
          find.byKey(kWorkspaceSessionSearchKey),
          'original title',
        );
        await tester.pumpAndSettle();
        expect(find.text('Authoritative title'), findsNothing);
        await tester.enterText(
          find.byKey(kWorkspaceSessionSearchKey),
          'authoritative title',
        );
        await tester.pumpAndSettle();
        expect(find.text('Authoritative title'), findsOneWidget);
        await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), '');
        await tester.tap(find.widgetWithText(ChoiceChip, l10n.filter_recent));
        await tester.pumpAndSettle();
        expect(find.text('Authoritative title'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, l10n.unassigned));
        await tester.pumpAndSettle();
        expect(find.text('Authoritative title'), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, l10n.archived));
        await tester.pumpAndSettle();
        expect(find.text('Unrelated'), findsOneWidget);
        expect(find.text('Archived row'), findsOneWidget);
      },
    );

    testWidgets(
      'cancel, blank keyboard submit and unchanged title never write',
      (tester) async {
        var writes = 0;
        await pumpBrowser(
          tester,
          onRename: (_, _) async {
            writes++;
            return 'Saved';
          },
        );
        await openRename(tester);
        await tester.enterText(dialogField(), 'Changed but cancelled');
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        expect(writes, 0);
        await openRename(tester);
        await submit(tester, '   ');
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, l10n.rename),
              )
              .onPressed,
          isNull,
        );
        expect(writes, 0);
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        await openRename(tester);
        await submit(tester, '  ${richSession.title}  ');
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text(richSession.title), findsOneWidget);
        expect(writes, 0);
      },
    );

    testWidgets('failure retains old title and reports localized error', (
      tester,
    ) async {
      final error = StateError('Server rejected rename');
      var writes = 0;
      await pumpBrowser(
        tester,
        onRename: (_, _) async {
          writes++;
          throw error;
        },
      );
      await openRename(tester);
      await submit(tester, 'Rejected title');
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text(richSession.title), findsOneWidget);
      expect(find.text('Rejected title'), findsNothing);
      expect(
        find.text(l10n.could_not_rename_chat(error.toString())),
        findsOneWidget,
      );
      // A failed save releases the single-flight guard so it can be retried.
      await openRename(tester);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'late pre-save load cannot revert title or lose fresh row metadata',
      (tester) async {
        final staleLoad = Completer<WorkspaceSessionsData>();
        final opened = <Session>[];
        var loads = 0;
        await pumpBrowser(
          tester,
          onOpen: opened.add,
          load: () {
            loads++;
            return loads == 1
                ? staleLoad.future
                : Future.value(
                    WorkspaceSessionsData(
                      sessions: [_session('s1', 'Later server title')],
                    ),
                  );
          },
          onRename: (_, _) async => 'Saved title',
        );
        await openRename(tester);
        await submit(tester, 'Requested title');
        await tester.pumpAndSettle();
        expect(find.text('Saved title'), findsOneWidget);
        final refreshed = _session(
          's1',
          richSession.title,
          isActive: false,
          lastActive: 1749999999,
        );
        staleLoad.complete(
          WorkspaceSessionsData(
            sessions: [refreshed, _session('s2', 'New unrelated row')],
            projectLabels: const {'s1': 'Refreshed project'},
            claimedSessionIds: const {'s1'},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Saved title'), findsOneWidget);
        expect(find.text(richSession.title), findsNothing);
        expect(find.text('New unrelated row'), findsOneWidget);
        expect(find.text('Refreshed project'), findsOneWidget);
        await tester.tap(find.text('Saved title'));
        expect(opened.single.title, 'Saved title');
        expectMetadata(opened.single, refreshed);
        // Only pre-save reads are fenced; a genuinely fresh server title wins.
        final refresh = tester.widget<RefreshIndicator>(
          find.byType(RefreshIndicator),
        );
        await refresh.onRefresh();
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(find.text('Later server title'), findsOneWidget);
      },
    );

    testWidgets(
      'save merges into latest data and disables duplicate renames while pending',
      (tester) async {
        final save = Completer<String>();
        final freshLoad = Completer<WorkspaceSessionsData>();
        var loads = 0;
        var writes = 0;
        final opened = <Session>[];
        await pumpBrowser(
          tester,
          onOpen: opened.add,
          load: () async {
            loads++;
            return loads == 1
                ? const WorkspaceSessionsData(sessions: [richSession])
                : freshLoad.future;
          },
          onRename: (_, _) {
            writes++;
            return save.future;
          },
        );
        await openRename(tester);
        await submit(tester, 'Requested title');
        expect(writes, 1);
        expect(find.text(richSession.title), findsOneWidget);
        expect(find.text('Requested title'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.byTooltip(l10n.chat_actions));
        await tester.pump();
        await tester.pump(kThemeAnimationDuration);
        final renameItem = tester.widget<PopupMenuItem<String>>(
          find.widgetWithText(PopupMenuItem<String>, l10n.rename),
        );
        expect(renameItem.enabled, isFalse);
        await tester.tap(find.text(l10n.rename));
        await tester.pump();
        expect(writes, 1);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tapAt(Offset.zero);
        await tester.pump();
        await tester.pump(kThemeAnimationDuration);

        final refresh = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        final latest = _session(
          's1',
          richSession.title,
          lastActive: 1749999999,
        );
        freshLoad.complete(
          WorkspaceSessionsData(
            sessions: [latest, _session('s2', 'Added during save')],
            projectLabels: const {'s1': 'New project'},
          ),
        );
        await refresh;
        await tester.pump();
        save.complete('Saved title');
        await tester.pumpAndSettle();
        expect(find.text('Saved title'), findsOneWidget);
        expect(find.text('Added during save'), findsOneWidget);
        expect(find.text('New project'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Saved title'));
        expectMetadata(opened.single, latest);
      },
    );

    testWidgets(
      'renames both active and archived copies without losing archive state',
      (tester) async {
        final archived = _session('s1', 'Archived original', archived: true);
        final opened = <Session>[];
        final staleLoad = Completer<WorkspaceSessionsData>();
        await pumpBrowser(
          tester,
          onOpen: opened.add,
          data: WorkspaceSessionsData(
            sessions: [richSession],
            archivedSessions: [archived],
            archivedQuickChatIds: const {'s1'},
            projectLabels: const {'s1': 'Archived project'},
          ),
          load: () => staleLoad.future,
          onRename: (_, _) async => 'Archived saved',
        );
        await tester.tap(find.widgetWithText(ChoiceChip, l10n.archived));
        await tester.pumpAndSettle();
        await openRename(tester);
        await submit(tester, 'Requested archive title');
        await tester.pumpAndSettle();
        expect(find.text('Archived saved'), findsOneWidget);
        expect(find.text('Archived project'), findsOneWidget);
        await tester.tap(find.text('Archived saved'));
        expect(opened.single.title, 'Archived saved');
        expectMetadata(opened.single, archived);
        // Drop the archived copy via the in-flight response. Its active copy
        // must also retain the saved title when it becomes visible under All.
        staleLoad.complete(
          const WorkspaceSessionsData(sessions: [richSession]),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, l10n.filter_all));
        await tester.pumpAndSettle();
        expect(find.text('Archived saved'), findsOneWidget);
        expect(find.text(richSession.title), findsNothing);
      },
    );

    for (final fails in [false, true]) {
      testWidgets('disposed pending ${fails ? 'failure' : 'success'} is safe', (
        tester,
      ) async {
        final save = Completer<String>();
        var writes = 0;
        await pumpBrowser(
          tester,
          onRename: (_, _) {
            writes++;
            return save.future;
          },
        );
        await openRename(tester);
        await submit(tester, 'Requested title');
        expect(writes, 1);
        await tester.pumpWidget(const SizedBox());
        if (fails) {
          save.completeError(StateError('Late failure'));
        } else {
          save.complete('Late success');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('disposed popup teardown never opens a dialog or writes', (
      tester,
    ) async {
      var writes = 0;
      await pumpBrowser(
        tester,
        onRename: (_, _) async {
          writes++;
          return 'Saved';
        },
      );
      await tester.tap(find.byTooltip(l10n.chat_actions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.rename));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(kThemeAnimationDuration);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('the conversation rows', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1750000000 * 1000);

    Future<void> pumpRows(
      WidgetTester tester, {
      List<Session> sessions = const [],
      Map<String, String> projectLabels = const {},
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: now,
            load: () async => WorkspaceSessionsData(
              sessions: sessions,
              projectLabels: projectLabels,
            ),
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('marks a running session and a finished one', (tester) async {
      await pumpRows(
        tester,
        sessions: [
          _session('s1', 'Building', isActive: true, lastActive: 1750000000),
          _session('s2', 'Finished', lastActive: 1749990000),
        ],
      );

      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('labels the project when known, Unassigned otherwise', (
      tester,
    ) async {
      await pumpRows(
        tester,
        sessions: [
          _session('s1', 'In project', lastActive: 1750000000),
          _session('s2', 'Loose', lastActive: 1749990000),
        ],
        projectLabels: const {'s1': 'Hermes Android'},
      );

      expect(find.text('Hermes Android'), findsOneWidget);
      // The Unassigned chip plus the row meta-chip are both present; the
      // row-level marker is the inbox icon.
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    testWidgets('shows the pinned marker', (tester) async {
      await pumpRows(
        tester,
        sessions: [
          _session('s1', 'Pinned chat', lastActive: 1750000000, pinned: true),
        ],
      );

      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    });
  });

  testWidgets('search opens a result and Archived Quick offers Promote', (
    tester,
  ) async {
    final opened = <String>[];
    final promoted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Archived Quick chats',
          view: WorkspaceSessionView.archivedQuick,
          load: () async => WorkspaceSessionsData(
            sessions: [_session('s1', 'Old research')],
            archivedQuickChatIds: const {'s1'},
          ),
          onOpenSession: (session) => opened.add(session.id),
          onPromote: (session) async {
            promoted.add(session.id);
            return 'Project';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Old research'), findsOneWidget);
    await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), 'old');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old research'));
    expect(opened, ['s1']);

    await tester.tap(find.byTooltip('Promote to project'));
    await tester.pumpAndSettle();
    expect(promoted, ['s1']);
    expect(find.text('Old research'), findsNothing);
  });

  testWidgets('Unassigned rows offer Move to project and drop on move', (
    tester,
  ) async {
    final moved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Unassigned chats',
          view: WorkspaceSessionView.unassigned,
          load: () async => WorkspaceSessionsData(
            sessions: [
              _session('s1', 'Loose chat'),
              _session('s2', 'Also loose'),
            ],
          ),
          onOpenSession: (_) {},
          onPromote: (session) async {
            moved.add(session.id);
            return 'Project';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loose chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Move to project').first);
    await tester.pumpAndSettle();

    expect(moved, ['s1']);
    // The moved chat leaves the Unassigned list immediately (claimed);
    // the other stays.
    expect(find.text('Loose chat'), findsNothing);
    expect(find.text('Also loose'), findsOneWidget);
  });

  testWidgets('moving a chat updates its project label before showing All', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: Scaffold(
          body: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            load: () async => WorkspaceSessionsData(
              sessions: [_session('s1', 'Loose chat')],
              archivedSessions: [
                _session('s2', 'Archived chat', archived: true),
              ],
            ),
            onOpenSession: (_) {},
            onPromote: (_) async => 'Hermes Android',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move to project'));
    await tester.pumpAndSettle();
    expect(find.text('Loose chat'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('Loose chat'),
      matching: find.byType(HermesCard),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Hermes Android')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Unassigned')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Archived chat'), findsOneWidget);
  });

  testWidgets('public state refresh updates a retained embedded Chats pane', (
    tester,
  ) async {
    final key = GlobalKey<WorkspaceSessionsScreenState>();
    var loads = 0;
    final opened = <Session>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: Scaffold(
          body: WorkspaceSessionsScreen(
            key: key,
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            load: () async {
              loads++;
              return WorkspaceSessionsData(
                sessions: [
                  _session(
                    's1',
                    loads == 1 ? 'Before chat' : 'Renamed in chat',
                  ),
                ],
              );
            },
            onOpenSession: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Before chat'), findsOneWidget);
    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('Before chat'), findsNothing);
    expect(find.text('Renamed in chat'), findsOneWidget);
    await tester.tap(find.text('Renamed in chat'));
    expect(opened.single.title, 'Renamed in chat');
  });

  testWidgets(
    'queued explicit refreshes share one fresh read and await its completion',
    (tester) async {
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final staleLoad = Completer<WorkspaceSessionsData>();
      final freshLoad = Completer<WorkspaceSessionsData>();
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            key: key,
            title: 'Chats',
            view: WorkspaceSessionView.all,
            refreshInterval: const Duration(seconds: 10),
            load: () {
              loads++;
              return loads == 1 ? staleLoad.future : freshLoad.future;
            },
            onOpenSession: (_) {},
          ),
        ),
      );
      var refreshCompleted = false;
      final refresh = key.currentState!.refresh();
      final secondRefresh = key.currentState!.refresh();
      expect(identical(refresh, secondRefresh), isTrue);
      unawaited(refresh.then<void>((_) => refreshCompleted = true));
      await tester.pump(const Duration(seconds: 30));
      expect(loads, 1);
      expect(refreshCompleted, isFalse);

      staleLoad.complete(
        WorkspaceSessionsData(sessions: [_session('s1', 'Old snapshot')]),
      );
      await tester.pump();
      expect(loads, 2);
      expect(refreshCompleted, isFalse);
      await tester.pump(const Duration(seconds: 30));
      expect(loads, 2);

      freshLoad.complete(
        WorkspaceSessionsData(
          sessions: [_session('s1', 'Confirmed new title')],
        ),
      );
      await Future.wait([refresh, secondRefresh]);
      await tester.pumpAndSettle();
      expect(refreshCompleted, isTrue);
      expect(find.text('Confirmed new title'), findsOneWidget);
      expect(find.text('Old snapshot'), findsNothing);
      expect(loads, 2);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'disposed queued refresh skips new reads after old load ${fails ? 'fails' : 'succeeds'}',
      (tester) async {
        final key = GlobalKey<WorkspaceSessionsScreenState>();
        final staleLoad = Completer<WorkspaceSessionsData>();
        var loads = 0;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: hermesTheme(Brightness.dark),
            home: WorkspaceSessionsScreen(
              key: key,
              title: 'Chats',
              view: WorkspaceSessionView.all,
              load: () {
                loads++;
                return staleLoad.future;
              },
              onOpenSession: (_) {},
            ),
          ),
        );
        final state = key.currentState!;
        final refresh = state.refresh();
        await tester.pumpWidget(const SizedBox());
        if (fails) {
          staleLoad.completeError(StateError('Late load failure'));
        } else {
          staleLoad.complete(const WorkspaceSessionsData());
        }
        await refresh;
        await state.refresh();
        await tester.pumpAndSettle();
        expect(loads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'refreshes the list on the injected interval and stops on dispose',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            refreshInterval: const Duration(seconds: 10),
            load: () async {
              loads++;
              return WorkspaceSessionsData(
                sessions: [_session('s1', 'Daily driver')],
              );
            },
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(loads, 1);

      // The silent refresh keeps running/idle chips honest while visible…
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(loads, 2);

      // …and stops with the screen (no pending timer after dispose).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(loads, 2);
    },
  );

  testWidgets('does not refresh while hidden behind another shell pane', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: HermesPaneVisibility(
          active: false,
          child: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            refreshInterval: const Duration(seconds: 10),
            load: () async {
              loads++;
              return WorkspaceSessionsData(
                sessions: [_session('s1', 'Daily driver')],
              );
            },
            onOpenSession: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    // The initial fetch still happens…
    expect(loads, 1);

    // …but a hidden pane must not keep hitting the gateway.
    await tester.pump(const Duration(seconds: 30));
    expect(loads, 1);
  });

  testWidgets('coalesces a tick while a slow load is in flight', (
    tester,
  ) async {
    final gate = Completer<WorkspaceSessionsData>();
    var loads = 0;
    Future<WorkspaceSessionsData> load() {
      loads++;
      if (loads == 1) return gate.future;
      return Future.value(
        WorkspaceSessionsData(sessions: [_session('s1', 'Daily driver')]),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          title: 'Chats',
          view: WorkspaceSessionView.all,
          refreshInterval: const Duration(seconds: 10),
          load: load,
          onOpenSession: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(loads, 1);

    // The first load is still in flight: the tick must not overlap it.
    await tester.pump(const Duration(seconds: 10));
    expect(loads, 1);

    // Settle the slow load, then the next tick runs normally.
    gate.complete(
      WorkspaceSessionsData(sessions: [_session('s1', 'Daily driver')]),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(loads, 2);
  });
}
