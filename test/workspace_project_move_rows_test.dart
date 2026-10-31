import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_test_utils.dart';

const _chat = Session(
  id: 's1',
  title: 'Original title',
  model: 'custom-model',
  source: 'cli',
  messageCount: 42,
  isActive: false,
  preview: 'Original preview',
  startedAt: 1750000000,
  lastActive: 1750001000,
  endedAt: 1750000500,
  pinned: true,
  lineageRootId: 'root',
);
const _other = Session(
  id: 's2',
  title: 'Other chat',
  model: 'other-model',
  source: 'cli',
  messageCount: 7,
  isActive: true,
  preview: 'Newer preview',
  startedAt: 1750000900,
  lastActive: 1750002000,
);
const _archived = Session(
  id: 'archive',
  title: 'Server archived',
  model: 'model',
  source: 'cli',
  messageCount: 5,
  isActive: false,
  preview: 'Archive preview',
  startedAt: 1750000000,
  archived: true,
);
const _data = WorkspaceSessionsData(
  sessions: [_chat],
  archivedSessions: [_archived],
  claimedSessionIds: {'s1'},
  projectLabels: {'s1': 'Project A'},
);

void main() {
  late AppLocalizations l10n;
  late LocalChatPinStore pins;
  setUpAll(() async => l10n = await loadTestL10n());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pins = LocalChatPinStore(
      await SharedPreferences.getInstance(),
      connectionId: 'row-moves',
    );
    await pins.setPinned(_chat.id, pinned: true);
  });

  Finder row(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(HermesCard));
  PopupMenuButton<String> menu(WidgetTester tester, String title) =>
      tester.widget<PopupMenuButton<String>>(
        find.descendant(
          of: row(title),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
  Future<void> pumpBrowser(
    WidgetTester tester, {
    WorkspaceSessionPromoter? move,
    WorkspaceSessionRenamer? rename,
    WorkspaceSessionsLoader? load,
    WorkspaceSessionsData data = _data,
    bool embedded = true,
    WorkspaceSessionView view = WorkspaceSessionView.all,
    GlobalKey<WorkspaceSessionsScreenState>? stateKey,
    ValueChanged<Session>? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: Scaffold(
          body: WorkspaceSessionsScreen(
            key: stateKey,
            title: 'Chats',
            embedded: embedded,
            view: view,
            now: DateTime.fromMillisecondsSinceEpoch(1750003000000),
            initialData: data,
            load: load ?? () async => data,
            onOpenSession: onOpen ?? (_) {},
            onPromote: move,
            onRename: rename ?? (_, title) async => title,
            pinStore: pins,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectMove(WidgetTester tester, String title) async {
    await tester.tap(
      find.descendant(
        of: row(title),
        matching: find.byTooltip(l10n.chat_actions),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.rename), findsOneWidget);
    await tester.tap(find.text(l10n.move_to_project));
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
    await tester.pump();
  }

  for (final filter in WorkspaceChatsFilter.values) {
    testWidgets(
      '${filter.name} chip exposes Move alongside Rename and local Pin',
      (tester) async {
        final moved = <Session>[];
        final data = WorkspaceSessionsData(
          sessions: [_chat],
          archivedSessions: [_archived],
          archivedQuickChatIds: const {'s1'},
        );
        await pumpBrowser(
          tester,
          data: data,
          move: (session) async {
            moved.add(session);
            return 'Project B';
          },
        );
        await tester.tap(find.widgetWithText(ChoiceChip, filter.label(l10n)));
        await tester.pumpAndSettle();
        await selectMove(tester, _chat.title);
        await tester.pumpAndSettle();
        expect(moved.single, same(_chat));
        if (filter == WorkspaceChatsFilter.unassigned ||
            filter == WorkspaceChatsFilter.archived) {
          expect(find.text(_chat.title), findsNothing);
        } else {
          expect(
            find.descendant(
              of: row(_chat.title),
              matching: find.text('Project B'),
            ),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final view in [WorkspaceSessionView.all, WorkspaceSessionView.search]) {
    testWidgets('standalone ${view.name} exposes Move', (tester) async {
      var moves = 0;
      await pumpBrowser(
        tester,
        embedded: false,
        view: view,
        move: (_) async {
          moves++;
          return 'Project B';
        },
      );
      await selectMove(tester, _chat.title);
      await tester.pumpAndSettle();
      expect(moves, 1);
      expect(
        find.descendant(of: row(_chat.title), matching: find.text('Project B')),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'server archived row moves without unarchiving or replacing its metadata',
    (tester) async {
      final opened = <Session>[];
      await pumpBrowser(
        tester,
        move: (_) async => 'Project B',
        onOpen: opened.add,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.archived));
      await tester.pumpAndSettle();
      await selectMove(tester, _archived.title);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: row(_archived.title),
          matching: find.text('Project B'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(_archived.title));
      expect(opened.single, same(_archived));
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.filter_all));
      await tester.pumpAndSettle();
      expect(find.text(_archived.title), findsNothing);
    },
  );

  testWidgets(
    'held pre-move metadata cannot regress a move or a concurrent title save',
    (tester) async {
      final held = Completer<WorkspaceSessionsData>();
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final opened = <Session>[];
      var loads = 0;
      await pumpBrowser(
        tester,
        stateKey: key,
        onOpen: opened.add,
        load: () => ++loads == 1 ? Future.value(_data) : held.future,
        move: (_) async => 'Project B',
      );
      final refresh = key.currentState!.refresh();
      await tester.pump();
      await selectMove(tester, _chat.title);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: row(_chat.title),
          matching: find.byTooltip(l10n.chat_actions),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.rename));
      await tester.pumpAndSettle();
      await tester.pump(kThemeAnimationDuration);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed during move');
      await tester.tap(find.widgetWithText(FilledButton, l10n.rename));
      await tester.pumpAndSettle();
      // The delayed response contains both unrelated new data and old ownership.
      held.complete(
        const WorkspaceSessionsData(
          sessions: [_chat, _other],
          archivedSessions: [_archived],
          projectLabels: {'s1': 'Project A', 's2': 'Other Project'},
          claimedSessionIds: {'s1', 's2'},
          archivedQuickChatIds: {'s1'},
        ),
      );
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('Renamed during move'), findsOneWidget);
      expect(find.text(_other.title), findsOneWidget);
      expect(find.text('Other Project'), findsOneWidget);
      expect(
        find.descendant(
          of: row('Renamed during move'),
          matching: find.text('Project B'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Renamed during move'));
      final saved = opened.single;
      expect(saved.id, _chat.id);
      expect(saved.title, 'Renamed during move');
      expect(saved.messageCount, _chat.messageCount);
      expect(saved.preview, _chat.preview);
      expect(saved.model, _chat.model);
      expect(saved.source, _chat.source);
      expect(saved.startedAt, _chat.startedAt);
      expect(saved.lastActive, _chat.lastActive);
      expect(saved.endedAt, _chat.endedAt);
      expect(saved.pinned, _chat.pinned);
      expect(saved.lineageRootId, _chat.lineageRootId);
      expect(saved.archived, _chat.archived);
      expect(saved.isLocalDraft, _chat.isLocalDraft);
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.unassigned));
      await tester.pumpAndSettle();
      expect(find.text('Renamed during move'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.archived));
      await tester.pumpAndSettle();
      expect(find.text('Renamed during move'), findsNothing);
      expect(find.text(_archived.title), findsOneWidget);
    },
  );

  testWidgets('move merges into data loaded while RPC was pending', (
    tester,
  ) async {
    final stateKey = GlobalKey<WorkspaceSessionsScreenState>();
    final pendingMove = Completer<String>();
    final pendingLoad = Completer<WorkspaceSessionsData>();
    final opened = <Session>[];
    var reads = 0;
    await pumpBrowser(
      tester,
      stateKey: stateKey,
      onOpen: opened.add,
      load: () => ++reads == 1 ? Future.value(_data) : pendingLoad.future,
      move: (_) => pendingMove.future,
    );
    await selectMove(tester, _chat.title);
    final refresh = stateKey.currentState!.refresh();
    final refreshed = _chat.withTitle('Fresh server title');
    pendingLoad.complete(
      WorkspaceSessionsData(
        sessions: [refreshed, _other],
        archivedSessions: const [_archived],
        claimedSessionIds: const {'s2'},
        projectLabels: const {'s2': 'Other Project'},
      ),
    );
    await refresh;
    await tester.pump();
    pendingMove.complete('Project B');
    await tester.pumpAndSettle();
    expect(find.text(_chat.title), findsNothing);
    expect(
      find.descendant(
        of: row(refreshed.title),
        matching: find.text('Project B'),
      ),
      findsOneWidget,
    );
    expect(find.text(_other.title), findsOneWidget);
    expect(find.text('Other Project'), findsOneWidget);
    await tester.tap(find.text(refreshed.title));
    expect(opened.single, same(refreshed));
  });

  testWidgets(
    'single flight starts before popup delay and leaves another row independent',
    (tester) async {
      final gates = <String, Completer<String>>{
        's1': Completer<String>(),
        's2': Completer<String>(),
      };
      final calls = <String>[];
      await pumpBrowser(
        tester,
        data: const WorkspaceSessionsData(sessions: [_chat, _other]),
        move: (chat) {
          calls.add(chat.id);
          return gates[chat.id]!.future;
        },
      );
      final firstMenu = menu(tester, _chat.title);
      firstMenu.onSelected!('move');
      firstMenu.onSelected!('move');
      expect(calls, isEmpty);
      await tester.pump(kThemeAnimationDuration);
      await tester.pump();
      expect(calls, ['s1']);
      firstMenu.onSelected!('move');
      final firstItems = menu(
        tester,
        _chat.title,
      ).itemBuilder(tester.element(row(_chat.title)));
      expect(
        (firstItems.whereType<PopupMenuItem<String>>().singleWhere(
          (item) => item.value == 'move',
        )).enabled,
        isFalse,
      );
      menu(tester, _other.title).onSelected!('move');
      await tester.pump(kThemeAnimationDuration);
      await tester.pump();
      expect(calls, ['s1', 's2']);
      gates['s2']!.complete('Project C');
      await tester.pump();
      gates['s1']!.complete('Project B');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row(_chat.title), matching: find.text('Project B')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row(_other.title),
          matching: find.text('Project C'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cancel is silent, no metadata mutation, and another move can retry',
    (tester) async {
      var cancelled = true;
      await pumpBrowser(
        tester,
        move: (_) async {
          if (cancelled) throw const QuickChatPromotionCancelled();
          return 'Project B';
        },
      );
      await selectMove(tester, _chat.title);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(of: row(_chat.title), matching: find.text('Project A')),
        findsOneWidget,
      );
      cancelled = false;
      await selectMove(tester, _chat.title);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row(_chat.title), matching: find.text('Project B')),
        findsOneWidget,
      );
    },
  );

  testWidgets('disposal during popup delay never invokes move', (tester) async {
    var calls = 0;
    await pumpBrowser(
      tester,
      move: (_) async {
        calls++;
        return 'Project B';
      },
    );
    menu(tester, _chat.title).onSelected!('move');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
  for (final fail in [false, true]) {
    testWidgets(
      'disposal during remote ${fail ? 'failure' : 'success'} is safe',
      (tester) async {
        final pending = Completer<String>();
        await pumpBrowser(tester, move: (_) => pending.future);
        await selectMove(tester, _chat.title);
        await tester.pumpWidget(const SizedBox());
        if (fail) {
          pending.completeError(StateError('offline'));
        } else {
          pending.complete('Project B');
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
