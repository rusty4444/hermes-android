import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/l10n_test_utils.dart';

final _now = DateTime.fromMillisecondsSinceEpoch(1750010000000);

Session _chat(
  String id, {
  String source = 'cli',
  double lastActive = 1750000000,
  bool archived = false,
}) => Session(
  id: id,
  title: id,
  source: source,
  model: 'model',
  messageCount: 12,
  isActive: false,
  preview: 'Preview of $id',
  startedAt: 1750000000,
  lastActive: lastActive,
  archived: archived,
);

List<Session> _rows(String prefix, {bool archived = false}) => [
  for (var i = 0; i < 8; i++)
    _chat(
      '$prefix-$i',
      lastActive: 1750000000 - i.toDouble(),
      archived: archived,
    ),
];

class _Flight {
  final done = Completer<WorkspaceSessionsData>();
  late void Function(WorkspaceSessionsData) emit;

  Future<WorkspaceSessionsData> load(
    void Function(WorkspaceSessionsData) onProgress,
  ) {
    emit = onProgress;
    return done.future;
  }
}

Widget _browser({
  required WorkspaceProgressiveSessionsLoader progressive,
  WorkspaceSessionsLoader? load,
  WorkspaceSessionsData? initialData,
  GlobalKey<WorkspaceSessionsScreenState>? stateKey,
  WorkspaceSessionView view = WorkspaceSessionView.all,
  bool embedded = true,
  WorkspaceSessionRenamer? rename,
  WorkspaceSessionPromoter? move,
  ValueChanged<Session>? open,
  Duration? refreshInterval,
  bool visible = true,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: Scaffold(
    body: HermesPaneVisibility(
      active: visible,
      child: WorkspaceSessionsScreen(
        key: stateKey,
        title: 'Chats',
        view: view,
        embedded: embedded,
        now: _now,
        initialData: initialData,
        load: load ?? () => throw StateError('Legacy loader must not run'),
        loadProgressively: progressive,
        onOpenSession: open ?? (_) {},
        onRename: rename,
        onPromote: move,
        refreshInterval: refreshInterval,
      ),
    ),
  ),
);

void _largeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectRows(List<String> titles) {
  expect(find.byType(HermesCard), findsNWidgets(titles.length));
  for (final title in titles) {
    expect(find.text(title), findsOneWidget);
  }
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async => l10n = await loadTestL10n());

  test(
    'standalone Unassigned excludes server archives as well as machine runs',
    () {
      final human = _chat('human');
      final archived = _chat('server-archive', archived: true);
      final machine = _chat('machine', source: 'cron');
      final claimed = _chat('claimed');
      expect(
        filterWorkspaceSessions(
          sessions: [human, archived, machine, claimed],
          view: WorkspaceSessionView.unassigned,
          claimedSessionIds: {claimed.id},
        ),
        [human],
      );
    },
  );

  test(
    'standalone Archived Quick excludes machine sources despite expiry metadata',
    () {
      final human = _chat('human');
      final machines = [
        for (final source in kMachineSessionSources)
          _chat(source, source: source),
      ];
      expect(
        filterWorkspaceSessions(
          sessions: [human, ...machines],
          view: WorkspaceSessionView.archivedQuick,
          archivedQuickChatIds: {human.id, ...machines.map((s) => s.id)},
        ),
        [human],
      );
    },
  );

  test(
    'Archived chip ignores active server pin backfill and ended-only rows',
    () {
      final activePin = Session.fromJson({
        'id': 'active-pin',
        'pinned': true,
        'archived': false,
        'source': 'cli',
        'ended_at': 1750001000,
      });
      final archived = _chat('archive', archived: true);
      expect(
        filterChats(
          sessions: [activePin, archived],
          filter: WorkspaceChatsFilter.archived,
        ),
        [archived],
      );
      expect(
        filterChats(sessions: [activePin], filter: WorkspaceChatsFilter.all),
        [activePin],
      );
    },
  );

  for (final filter in WorkspaceChatsFilter.values) {
    testWidgets('synchronous ${filter.name} progress caps five matching rows', (
      tester,
    ) async {
      _largeViewport(tester);
      final flight = _Flight();
      final matching = _rows(
        'match',
        archived: filter == WorkspaceChatsFilter.archived,
      );
      final noise = switch (filter) {
        WorkspaceChatsFilter.all => _chat(
          'cron-noise',
          source: 'cron',
          lastActive: 1750009000,
        ),
        WorkspaceChatsFilter.recent => _chat('old-noise', lastActive: 1),
        WorkspaceChatsFilter.unassigned => _chat(
          'filed-noise',
          lastActive: 1750009000,
        ),
        WorkspaceChatsFilter.archived => _chat(
          'active-noise',
          lastActive: 1750009000,
        ),
      };
      final snapshot = WorkspaceSessionsData(
        sessions: [
          noise,
          if (filter != WorkspaceChatsFilter.archived) ...matching,
        ],
        archivedSessions: filter == WorkspaceChatsFilter.archived
            ? matching
            : const [],
        claimedSessionIds: const {'filed-noise'},
        isPartial: true,
        archivedIsPartial: filter == WorkspaceChatsFilter.archived,
      );
      var legacyLoads = 0;
      await tester.pumpWidget(
        _browser(
          load: () async {
            legacyLoads++;
            return const WorkspaceSessionsData();
          },
          progressive: (onProgress) {
            final result = flight.load(onProgress);
            onProgress(snapshot);
            return result;
          },
        ),
      );
      if (filter != WorkspaceChatsFilter.all) {
        await tester.tap(find.widgetWithText(ChoiceChip, filter.label(l10n)));
        await tester.pump();
      }
      expect(legacyLoads, 0);
      _expectRows([for (var i = 0; i < 5; i++) 'match-$i']);
      expect(find.text(noise.title), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text(l10n.loading), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      flight.done.complete(
        WorkspaceSessionsData(
          sessions: snapshot.sessions,
          archivedSessions: snapshot.archivedSessions,
          claimedSessionIds: snapshot.claimedSessionIds,
        ),
      );
      await tester.pumpAndSettle();
      _expectRows(matching.map((s) => s.title).toList());
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  }

  for (final view in WorkspaceSessionView.values) {
    testWidgets(
      'standalone ${view.name} caps after view and search filtering',
      (tester) async {
        _largeViewport(tester);
        final flight = _Flight();
        final matching = _rows('match');
        final noise = _chat(
          'filed-noise',
          source: view == WorkspaceSessionView.all ? 'cron' : 'cli',
        );
        final snapshot = WorkspaceSessionsData(
          sessions: [noise, ...matching],
          claimedSessionIds: const {'filed-noise'},
          archivedQuickChatIds: matching.map((s) => s.id).toSet(),
          isPartial: true,
        );
        await tester.pumpWidget(
          _browser(
            embedded: false,
            view: view,
            progressive: (onProgress) {
              final future = flight.load(onProgress);
              onProgress(snapshot);
              return future;
            },
          ),
        );
        if (view == WorkspaceSessionView.search) {
          await tester.enterText(
            find.byKey(kWorkspaceSessionSearchKey),
            'match',
          );
          await tester.pump();
        }
        _expectRows([for (var i = 0; i < 5; i++) 'match-$i']);
        expect(find.text('match-5'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        flight.done.complete(snapshot);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'later pages fill a machine-only preview and search has its own five',
    (tester) async {
      _largeViewport(tester);
      final flight = _Flight();
      final machine = _chat('machine', source: 'kanban');
      await tester.pumpWidget(
        _browser(
          progressive: (onProgress) {
            final future = flight.load(onProgress);
            onProgress(
              WorkspaceSessionsData(sessions: [machine], isPartial: true),
            );
            return future;
          },
        ),
      );
      expect(find.byType(HermesCard), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text(l10n.loading), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final rows = [..._rows('new'), ..._rows('needle')];
      flight.emit(
        WorkspaceSessionsData(sessions: [machine, ...rows], isPartial: true),
      );
      await tester.pump();
      expect(find.byType(HermesCard), findsNWidgets(5));
      await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), 'needle');
      await tester.pump();
      _expectRows([for (var i = 0; i < 5; i++) 'needle-$i']);
      flight.done.complete(WorkspaceSessionsData(sessions: rows));
      await tester.pumpAndSettle();
      _expectRows(_rows('needle').map((s) => s.title).toList());
    },
  );

  for (final archived in [false, true]) {
    for (final embedded in [false, true]) {
      testWidgets(
        '${embedded ? 'chip' : 'standalone'} ${archived ? 'archive' : 'unassigned'} unknown stays loading then shows retry',
        (tester) async {
          final first = _Flight();
          final retry = _Flight();
          final key = GlobalKey<WorkspaceSessionsScreenState>();
          var reads = 0;
          WorkspaceSessionsData unknown({required bool partial}) =>
              WorkspaceSessionsData(
                isPartial: partial,
                archivedIsPartial: archived && partial,
                projectsLoading: !archived && partial,
                projectsKnown: archived,
                archivesKnown: !archived,
              );
          await tester.pumpWidget(
            _browser(
              stateKey: key,
              embedded: embedded,
              view: embedded
                  ? WorkspaceSessionView.all
                  : (archived
                        ? WorkspaceSessionView.archivedQuick
                        : WorkspaceSessionView.unassigned),
              progressive: (onProgress) {
                final flight = ++reads == 1 ? first : retry;
                final result = flight.load(onProgress);
                onProgress(unknown(partial: true));
                return result;
              },
            ),
          );
          if (embedded) {
            await tester.tap(
              find.widgetWithText(
                ChoiceChip,
                archived ? l10n.archived : l10n.unassigned,
              ),
            );
            await tester.pump();
          }
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text(l10n.could_not_load_conversations), findsNothing);
          expect(find.byType(EmptyState), findsNothing);
          first.done.complete(unknown(partial: false));
          await tester.pumpAndSettle();
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.text(l10n.could_not_load_conversations), findsOneWidget);
          expect(find.text(l10n.retry), findsOneWidget);
          expect(find.byType(EmptyState), findsNothing);
          await tester.tap(find.text(l10n.retry));
          await tester.pump();
          expect(reads, 2);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text(l10n.could_not_load_conversations), findsNothing);
          retry.done.complete(const WorkspaceSessionsData());
          await tester.pumpAndSettle();
          expect(find.byType(EmptyState), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.text(l10n.retry), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'refresh preserves eight rows through short progress, error and retry',
    (tester) async {
      _largeViewport(tester);
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final refreshFlight = _Flight();
      final retry = _Flight();
      final rows = _rows('kept');
      var reads = 0;
      await tester.pumpWidget(
        _browser(
          stateKey: key,
          progressive: (onProgress) {
            reads++;
            if (reads == 1) {
              return Future.value(WorkspaceSessionsData(sessions: rows));
            }
            return (reads == 2 ? refreshFlight : retry).load(onProgress);
          },
        ),
      );
      await tester.pumpAndSettle();
      _expectRows(rows.map((s) => s.title).toList());
      final refreshed = key.currentState!.refresh();
      refreshFlight.emit(
        WorkspaceSessionsData(sessions: [rows.first], isPartial: true),
      );
      await tester.pump();
      _expectRows(rows.map((s) => s.title).toList());
      refreshFlight.done.completeError(
        StateError('Held progressive read failed'),
      );
      await refreshed;
      await tester.pumpAndSettle();
      _expectRows(rows.map((s) => s.title).toList());
      expect(find.text(l10n.retry), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      refreshFlight.emit(const WorkspaceSessionsData());
      await tester.pump();
      _expectRows(rows.map((s) => s.title).toList());
      await tester.tap(find.text(l10n.retry));
      await tester.pump();
      retry.emit(const WorkspaceSessionsData(isPartial: true));
      await tester.pump();
      _expectRows(rows.map((s) => s.title).toList());
      retry.done.complete(WorkspaceSessionsData(sessions: [rows.first]));
      await tester.pumpAndSettle();
      _expectRows([rows.first.title]);
    },
  );

  testWidgets('cold progress error keeps its preview and exposes retry', (
    tester,
  ) async {
    _largeViewport(tester);
    final flight = _Flight();
    await tester.pumpWidget(
      _browser(
        progressive: (onProgress) {
          final result = flight.load(onProgress);
          onProgress(
            WorkspaceSessionsData(sessions: _rows('partial'), isPartial: true),
          );
          return result;
        },
      ),
    );
    flight.done.completeError(StateError('Cold scan failed'));
    await tester.pumpAndSettle();
    _expectRows([for (var i = 0; i < 5; i++) 'partial-$i']);
    expect(find.text(l10n.retry), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets(
    'unknown refresh metadata retains classified rows, not newly unproven chats',
    (tester) async {
      _largeViewport(tester);
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final flight = _Flight();
      final rows = _rows('known');
      var reads = 0;
      await tester.pumpWidget(
        _browser(
          stateKey: key,
          progressive: (onProgress) => ++reads == 1
              ? Future.value(WorkspaceSessionsData(sessions: rows))
              : flight.load(onProgress),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.unassigned));
      await tester.pumpAndSettle();
      final refresh = key.currentState!.refresh();
      flight.emit(
        WorkspaceSessionsData(
          sessions: [_chat('unproven')],
          isPartial: true,
          projectsKnown: false,
          archivesKnown: false,
        ),
      );
      await tester.pump();
      _expectRows(rows.map((s) => s.title).toList());
      expect(find.text('unproven'), findsNothing);
      flight.done.completeError(StateError('metadata failed'));
      await refresh;
      await tester.pumpAndSettle();
      _expectRows(rows.map((s) => s.title).toList());
      expect(find.text(l10n.retry), findsOneWidget);
    },
  );

  testWidgets(
    'archive failure preserves old and newly paged rows beside notice',
    (tester) async {
      _largeViewport(tester);
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final flight = _Flight();
      final old = _chat('old archive', archived: true);
      final fresh = _chat('fresh archive', archived: true);
      var reads = 0;
      await tester.pumpWidget(
        _browser(
          stateKey: key,
          progressive: (onProgress) => ++reads == 1
              ? Future.value(WorkspaceSessionsData(archivedSessions: [old]))
              : flight.load(onProgress),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.archived));
      await tester.pumpAndSettle();
      final refresh = key.currentState!.refresh();
      flight.emit(
        WorkspaceSessionsData(
          archivedSessions: [fresh],
          archivesKnown: false,
          archivedIsPartial: true,
          isPartial: true,
        ),
      );
      await tester.pump();
      _expectRows([old.title, fresh.title]);
      expect(find.text(l10n.retry), findsNothing);
      flight.done.complete(
        WorkspaceSessionsData(archivedSessions: [fresh], archivesKnown: false),
      );
      await refresh;
      await tester.pumpAndSettle();
      _expectRows([old.title, fresh.title]);
      expect(find.text(l10n.retry), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    },
  );

  testWidgets(
    'Home bootstrap cannot replace newer progressive project metadata',
    (tester) async {
      final flight = _Flight();
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final chat = _chat('chat');
      Widget browser(WorkspaceSessionsData? initial) => _browser(
        stateKey: key,
        initialData: initial,
        progressive: flight.load,
      );
      await tester.pumpWidget(browser(null));
      await tester.pumpWidget(
        browser(
          WorkspaceSessionsData(
            sessions: [chat],
            isPartial: true,
            projectsKnown: false,
          ),
        ),
      );
      expect(find.text(chat.title), findsOneWidget);
      flight.emit(
        WorkspaceSessionsData(
          sessions: [chat],
          isPartial: true,
          claimedSessionIds: {chat.id},
          projectLabels: {chat.id: 'Progressive Project'},
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        browser(
          WorkspaceSessionsData(
            sessions: [chat],
            isPartial: true,
            projectsKnown: false,
          ),
        ),
      );
      expect(find.text('Progressive Project'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.unassigned));
      await tester.pump();
      expect(find.text(chat.title), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
      flight.done.complete(
        WorkspaceSessionsData(sessions: [chat], claimedSessionIds: {chat.id}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
    },
  );

  testWidgets(
    'rename and move revisions guard every progress and final archive snapshot',
    (tester) async {
      _largeViewport(tester);
      final flight = _Flight();
      final chat = _chat('original', archived: true);
      final initial = WorkspaceSessionsData(
        archivedSessions: [chat],
        archivesKnown: false,
        projectLabels: {chat.id: 'Old Project'},
        claimedSessionIds: {chat.id},
        isPartial: true,
      );
      final opened = <Session>[];
      await tester.pumpWidget(
        _browser(
          initialData: initial,
          progressive: flight.load,
          rename: (_, title) async => title,
          move: (_) async => 'Saved Project',
          open: opened.add,
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.archived));
      await tester.pump();
      PopupMenuButton<String> menu() => tester.widget<PopupMenuButton<String>>(
        find.byType(PopupMenuButton<String>),
      );
      menu().onSelected!('rename');
      await tester.pump(kThemeAnimationDuration);
      await tester.pump(kThemeAnimationDuration);
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Saved title');
      await tester.tap(find.widgetWithText(FilledButton, l10n.rename));
      await tester.pump(kThemeAnimationDuration);
      await tester.pump();
      menu().onSelected!('move');
      await tester.pump(kThemeAnimationDuration);
      await tester.pump();
      flight.emit(initial);
      await tester.pump();
      expect(find.text('Saved title'), findsOneWidget);
      expect(find.text('Saved Project'), findsOneWidget);
      expect(find.text('Old Project'), findsNothing);
      flight.done.complete(
        WorkspaceSessionsData(
          archivedSessions: [chat],
          archivesKnown: false,
          projectLabels: {chat.id: 'Old Project'},
          claimedSessionIds: {chat.id},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved title'), findsOneWidget);
      expect(find.text('Saved Project'), findsOneWidget);
      // Both mutation copy helpers must preserve archivesKnown=false.
      expect(find.text(l10n.retry), findsOneWidget);
      await tester.tap(find.text('Saved title'));
      expect(opened.single.title, 'Saved title');
      expect(opened.single.archived, isTrue);
      expect(opened.single.messageCount, chat.messageCount);
      // A read begun after both saves remains authoritative, not patched forever.
      final subsequent = _Flight();
      final key = tester.state<WorkspaceSessionsScreenState>(
        find.byType(WorkspaceSessionsScreen),
      );
      await tester.pumpWidget(
        _browser(
          progressive: subsequent.load,
          rename: (_, title) async => title,
          move: (_) async => 'Saved Project',
        ),
      );
      final refresh = key.refresh();
      subsequent.done.complete(WorkspaceSessionsData(archivedSessions: [chat]));
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('original'), findsOneWidget);
      expect(find.text('Saved title'), findsNothing);
      expect(find.text(l10n.retry), findsNothing);
    },
  );

  testWidgets(
    'queued refresh coalesces ticks and fences settled and obsolete progress',
    (tester) async {
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      final first = _Flight();
      final second = _Flight();
      var reads = 0;
      await tester.pumpWidget(
        _browser(
          stateKey: key,
          refreshInterval: const Duration(seconds: 10),
          progressive: (onProgress) =>
              (++reads == 1 ? first : second).load(onProgress),
        ),
      );
      final refresh = key.currentState!.refresh();
      final duplicate = key.currentState!.refresh();
      expect(identical(refresh, duplicate), isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(reads, 1);
      first.done.complete(WorkspaceSessionsData(sessions: [_chat('first')]));
      await tester.pump();
      expect(reads, 2);
      first.emit(
        WorkspaceSessionsData(sessions: [_chat('obsolete')], isPartial: true),
      );
      second.emit(
        WorkspaceSessionsData(sessions: [_chat('second')], isPartial: true),
      );
      await tester.pump();
      expect(find.text('obsolete'), findsNothing);
      expect(find.text('second'), findsOneWidget);
      second.done.complete(WorkspaceSessionsData(sessions: [_chat('final')]));
      await Future.wait([refresh, duplicate]);
      second.emit(
        WorkspaceSessionsData(sessions: [_chat('late')], isPartial: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('final'), findsOneWidget);
      expect(find.text('late'), findsNothing);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'dispose fences progress, final ${fails ? 'error' : 'success'}, queued refresh and timer',
      (tester) async {
        final key = GlobalKey<WorkspaceSessionsScreenState>();
        final flight = _Flight();
        var reads = 0;
        await tester.pumpWidget(
          _browser(
            stateKey: key,
            refreshInterval: const Duration(seconds: 10),
            progressive: (onProgress) {
              reads++;
              return flight.load(onProgress);
            },
          ),
        );
        final state = key.currentState!;
        final refresh = state.refresh();
        await tester.pumpWidget(const SizedBox());
        flight.emit(const WorkspaceSessionsData(isPartial: true));
        if (fails) {
          flight.done.completeError(StateError('Disposed read'));
        } else {
          flight.done.complete(const WorkspaceSessionsData());
        }
        await refresh;
        await state.refresh();
        await tester.pump(const Duration(seconds: 30));
        expect(reads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'progressive polling stays paused behind hidden pane and background lifecycle',
    (tester) async {
      var reads = 0;
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      Widget browser({required bool visible}) => _browser(
        stateKey: key,
        visible: visible,
        refreshInterval: const Duration(seconds: 10),
        progressive: (_) async {
          reads++;
          return WorkspaceSessionsData(sessions: [_chat('chat')]);
        },
      );
      await tester.pumpWidget(browser(visible: false));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(reads, 1);
      await tester.pumpWidget(browser(visible: true));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(reads, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(reads, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(reads, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
