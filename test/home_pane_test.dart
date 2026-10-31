import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_digest.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/home_pane.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

/// A fixed clock so the window boundaries the digest owns stay asserted
/// rather than approximated.
final _now = DateTime.utc(2026, 8, 27, 12, 0, 0);

double _epoch(Duration ago) =>
    _now.subtract(ago).millisecondsSinceEpoch / 1000.0;

Session _session({
  required String id,
  String title = 'Session',
  Duration startedAgo = const Duration(minutes: 5),
  Duration? lastActiveAgo,
  Duration? endedAgo,
  bool? isActive,
  String preview = 'preview',
}) {
  return Session(
    id: id,
    title: title,
    model: 'claude-opus-5',
    source: 'gateway',
    messageCount: 4,
    isActive: isActive ?? endedAgo == null,
    preview: preview,
    startedAt: _epoch(startedAgo),
    lastActive: lastActiveAgo == null ? 0 : _epoch(lastActiveAgo),
    endedAt: endedAgo == null ? null : _epoch(endedAgo),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required HomeSessionsLoader loadSessions,
  HomeProgressiveSessionsLoader? loadProgressiveSessions,
  Map<String, String> attention = const {},
  Set<String> running = const {},
  Map<String, String> projectNames = const {},
  ValueChanged<Session>? onOpenSession,
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: Scaffold(
        body: HomePane(
          loadSessions: loadSessions,
          loadProgressiveSessions: loadProgressiveSessions,
          attention: attention,
          running: running,
          projectNames: projectNames,
          onOpenSession: onOpenSession,
          clock: () => _now,
        ),
      ),
    ),
  );
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  testWidgets('refresh keeps old blocked work and ignores stale completions', (
    tester,
  ) async {
    final oldRefresh = Completer<List<Session>>();
    final callbacks = <void Function(List<Session>?)>[];
    var reads = 0;
    await _pump(
      tester,
      loadSessions: () async => const [],
      loadProgressiveSessions: (update) {
        callbacks.add(update);
        reads++;
        if (reads == 2) return oldRefresh.future;
        return Future.value([
          _session(id: 'recent-$reads', title: 'Recent $reads'),
        ]);
      },
      attention: const {'old': 'Approval required'},
    );
    await tester.pump();
    callbacks.single([
      _session(id: 'old', title: 'Old blocked'),
      _session(id: 'recent-1', title: 'Recent 1'),
    ]);
    await tester.pump();
    expect(find.text('Old blocked'), findsOneWidget);

    final state = tester.state<HomePaneState>(find.byType(HomePane));
    unawaited(state.refresh()); // Delayed first refresh.
    unawaited(state.refresh()); // Newer refresh wins.
    await tester.pump();
    expect(find.text('Recent 3'), findsOneWidget);
    expect(find.text('Old blocked'), findsOneWidget);
    oldRefresh.complete([_session(id: 'stale', title: 'Stale first page')]);
    callbacks[1]([_session(id: 'stale-bg', title: 'Stale background')]);
    await tester.pump();
    expect(find.text('Stale first page'), findsNothing);
    expect(find.text('Stale background'), findsNothing);

    callbacks[2](null); // Background failure keeps the usable digest.
    await tester.pump();
    expect(find.text('Old blocked'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(l10n.could_not_reach_hermes), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    callbacks[2]([_session(id: 'late', title: 'Disposed result')]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('an empty first slice is not mistaken for an empty Home', (
    tester,
  ) async {
    late void Function(List<Session>?) finishScan;
    await _pump(
      tester,
      loadSessions: () async => const [],
      loadProgressiveSessions: (update) async {
        finishScan = update;
        return const [];
      },
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    finishScan(null);
    await tester.pump();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
  });
  testWidgets('holds a loading skeleton until the first read lands', (
    tester,
  ) async {
    final gate = Completer<List<Session>>();
    await _pump(tester, loadSessions: () => gate.future);
    await tester.pump();

    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    gate.complete([_session(id: 's1', title: 'Roadmap')]);
    await tester.pumpAndSettle();

    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Roadmap'), findsOneWidget);
  });

  testWidgets('renders the digest sections in attention order', (tester) async {
    await _pump(
      tester,
      loadSessions: () async => [
        _session(
          id: 'done',
          title: 'Finished work',
          endedAgo: const Duration(hours: 2),
        ),
        _session(
          id: 'idle',
          title: 'Resume this',
          startedAgo: const Duration(hours: 3),
        ),
        _session(id: 'live', title: 'Working now'),
        _session(id: 'blocked', title: 'Waiting on you'),
      ],
      attention: const {'blocked': 'Approval needed'},
      running: const {'live'},
    );
    await tester.pumpAndSettle();

    double topOf(String text) => tester.getTopLeft(find.text(text).first).dy;

    expect(
      topOf(HomeSectionKind.needsYou.title(l10n)),
      lessThan(topOf(HomeSectionKind.running.title(l10n))),
    );
    expect(
      topOf(HomeSectionKind.running.title(l10n)),
      lessThan(topOf(HomeSectionKind.continueWorking.title(l10n))),
    );
    expect(
      topOf(HomeSectionKind.continueWorking.title(l10n)),
      lessThan(topOf(HomeSectionKind.completedRecently.title(l10n))),
    );
  });

  testWidgets('Home shows remote recency without claiming a live turn', (
    tester,
  ) async {
    await _pump(
      tester,
      loadSessions: () async => [
        _session(
          id: 'remote',
          title: 'Remote work',
          startedAgo: const Duration(days: 30),
          lastActiveAgo: const Duration(minutes: 1),
          isActive: true,
        ),
        _session(
          id: 'stale',
          title: 'Older work',
          startedAgo: const Duration(days: 1),
          lastActiveAgo: const Duration(hours: 1),
          isActive: false,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Remote work'), findsOneWidget);
    expect(find.text(l10n.recently_active), findsOneWidget);
    expect(find.text(l10n.status_idle), findsOneWidget);
    expect(find.text(l10n.status_running), findsNothing);
    expect(find.text(l10n.running_now), findsNothing);
    expect(
      tester.getTopLeft(find.text('Remote work')).dy,
      lessThan(tester.getTopLeft(find.text('Older work')).dy),
    );
  });

  testWidgets(
    'a blocked session states its reason and never doubles as running',
    (tester) async {
      await _pump(
        tester,
        loadSessions: () async => [
          _session(id: 'blocked', title: 'Waiting on you'),
        ],
        attention: const {'blocked': 'Approval needed'},
        // The same session is reported as running by a stale event.
        running: const {'blocked'},
      );
      await tester.pumpAndSettle();

      expect(find.text('Approval needed'), findsOneWidget);
      expect(find.text('Waiting on you'), findsOneWidget);
      expect(find.text(HomeSectionKind.running.title(l10n)), findsNothing);
    },
  );

  testWidgets('shows the owning project so a row says where it happened', (
    tester,
  ) async {
    await _pump(
      tester,
      loadSessions: () async => [_session(id: 's1', title: 'Roadmap')],
      projectNames: const {'s1': 'Hermes Android'},
    );
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
  });

  testWidgets('a calm state replaces an empty list when nothing needs you', (
    tester,
  ) async {
    await _pump(tester, loadSessions: () async => const <Session>[]);
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.textContaining('Nothing needs you'), findsOneWidget);
  });

  testWidgets('a first read that fails offers a retry that recovers', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      loadSessions: () async {
        calls++;
        if (calls == 1) throw Exception('offline');
        return [_session(id: 's1', title: 'Roadmap')];
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Roadmap'), findsOneWidget);
  });

  testWidgets(
    'a later failure keeps the last known Home behind an offline notice',
    (tester) async {
      var calls = 0;
      await _pump(
        tester,
        loadSessions: () async {
          calls++;
          if (calls == 1) return [_session(id: 's1', title: 'Roadmap')];
          throw Exception('offline');
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Roadmap'), findsOneWidget);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();

      expect(calls, greaterThan(1));
      // Losing the network must never blank the screen the user relies on.
      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.textContaining('Offline'), findsOneWidget);
    },
  );

  testWidgets('a capped section reports what it hid', (tester) async {
    await _pump(
      tester,
      loadSessions: () async => [
        for (var index = 0; index < kHomeSectionLimit + 2; index++)
          _session(
            id: 'blocked-$index',
            title: 'Blocked $index',
            startedAgo: Duration(minutes: index),
          ),
      ],
      attention: {
        for (var index = 0; index < kHomeSectionLimit + 2; index++)
          'blocked-$index': 'Approval needed',
      },
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 more'), findsOneWidget);
  });

  testWidgets('tapping a row reports the session to the host', (tester) async {
    final opened = <Session>[];
    await _pump(
      tester,
      loadSessions: () async => [_session(id: 's1', title: 'Roadmap')],
      onOpenSession: opened.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadmap'));
    await tester.pumpAndSettle();

    expect(opened.map((session) => session.id), ['s1']);
  });

  testWidgets('a stale attention id cannot conjure a row', (tester) async {
    await _pump(
      tester,
      loadSessions: () async => [_session(id: 's1', title: 'Roadmap')],
      attention: const {'ghost': 'Approval needed'},
    );
    await tester.pumpAndSettle();

    expect(find.text(HomeSectionKind.needsYou.title(l10n)), findsNothing);
    expect(find.text('Roadmap'), findsOneWidget);
  });
}
