import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/core/widgets/activity_pane.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

final _now = DateTime.utc(2026, 8, 28, 12, 0, 0);

ActivityItem _item({
  String sessionId = 'session-a',
  String? title,
  String clientTurnId = 'turn-1',
  String label = 'Running',
  HermesStatus status = HermesStatus.running,
  Duration updatedAgo = const Duration(minutes: 3),
}) {
  return ActivityItem(
    sessionId: sessionId,
    title: title,
    clientTurnId: clientTurnId,
    label: label,
    status: status,
    updatedAt: _now.subtract(updatedAgo),
  );
}

ActivityGroup _group(
  ActivityGroupKind kind,
  List<ActivityItem> items, {
  int? totalCount,
}) {
  return ActivityGroup(
    kind: kind,
    items: items,
    totalCount: totalCount ?? items.length,
  );
}

ActivityFeed _feed(List<ActivityGroup> groups) {
  return ActivityFeed(
    groups: groups,
    blockedCount: groups
        .where((g) => g.kind == ActivityGroupKind.needsYou)
        .fold(0, (sum, g) => sum + g.totalCount),
    runningCount: groups
        .where((g) => g.kind == ActivityGroupKind.running)
        .fold(0, (sum, g) => sum + g.totalCount),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required ActivityFeedLoader loadFeed,
  ValueChanged<ActivityItem>? onOpenItem,
  bool actionableOnly = false,
  Duration? refreshInterval,
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
        body: ActivityPane(
          loadFeed: loadFeed,
          onOpenItem: onOpenItem,
          actionableOnly: actionableOnly,
          clock: () => _now,
          refreshInterval: refreshInterval,
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

  testWidgets('hidden shell Activity stops polling and refreshes on return', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: HermesShell(
          initialDestination: HermesDestination.activity,
          builder: (_, destination) => destination == HermesDestination.activity
              ? ActivityPane(
                  refreshInterval: const Duration(seconds: 10),
                  loadFeed: () async {
                    reads++;
                    return _feed([]);
                  },
                )
              : const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 1);
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a covering Navigator route stops polling until Activity is visible again',
    (tester) async {
      var reads = 0;
      await _pump(
        tester,
        refreshInterval: const Duration(seconds: 10),
        loadFeed: () async {
          reads++;
          return _feed([]);
        },
      );
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.byType(ActivityPane)));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Covering chat')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = reads;
      await tester.pump(const Duration(seconds: 30));
      expect(reads, before);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(reads, before + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed empty refresh never claims Inbox is clear', (
    tester,
  ) async {
    var reads = 0;
    await _pump(
      tester,
      actionableOnly: true,
      loadFeed: () async {
        if (++reads > 1) throw StateError('offline');
        return _feed([]);
      },
    );
    await tester.pumpAndSettle();
    await tester.state<ActivityPaneState>(find.byType(ActivityPane)).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Inbox is clear'), findsNothing);
    expect(find.text('Could not read activity'), findsOneWidget);
  });

  for (final inbox in [false, true]) {
    testWidgets(
      'partial ${inbox ? "Inbox" : "Activity"} is not an exhaustive empty verdict',
      (tester) async {
        await _pump(
          tester,
          actionableOnly: inbox,
          loadFeed: () async => const ActivityFeed(
            groups: [],
            blockedCount: 0,
            runningCount: 0,
            isPartial: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Activity partially loaded'), findsOneWidget);
        expect(find.text('No recent activity'), findsNothing);
        expect(find.text('Inbox is clear'), findsNothing);
      },
    );
  }

  testWidgets(
    'refresh requested during a held read performs a trailing fresh read',
    (tester) async {
      final first = Completer<ActivityFeed>();
      var calls = 0;
      await _pump(
        tester,
        loadFeed: () async {
          calls++;
          if (calls == 1) return first.future;
          return _feed([
            _group(ActivityGroupKind.completed, [_item(title: 'Finished')]),
          ]);
        },
      );
      await tester.pump();
      final state = tester.state<ActivityPaneState>(find.byType(ActivityPane));
      unawaited(state.refresh());
      first.complete(
        _feed([
          _group(ActivityGroupKind.running, [_item(title: 'Old state')]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Old state'), findsNothing);
    },
  );

  testWidgets(
    'a local observation cannot replace a queued manual gateway refresh',
    (tester) async {
      final held = Completer<ActivityFeed>();
      var serverReads = 0;
      var localReads = 0;
      await _pump(
        tester,
        loadFeed: () async {
          if (++serverReads == 1) return held.future;
          return _feed([]);
        },
      );
      await tester.pump();
      final state = tester.state<ActivityPaneState>(find.byType(ActivityPane));
      unawaited(state.refresh());
      unawaited(
        state.refresh(
          loader: () async {
            localReads++;
            return _feed([]);
          },
        ),
      );
      held.complete(_feed([]));
      await tester.pumpAndSettle();
      expect(serverReads, 2);
      expect(localReads, 0);
    },
  );

  testWidgets('polling pauses in background and refreshes on resume', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      refreshInterval: const Duration(seconds: 10),
      loadFeed: () async {
        calls++;
        return _feed([]);
      },
    );
    await tester.pumpAndSettle();
    final initial = calls;
    await tester.pump(const Duration(seconds: 10));
    expect(calls, initial + 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, initial + 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, initial + 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(calls, initial + 2);
  });

  testWidgets('holds a skeleton until the first read lands', (tester) async {
    final gate = Completer<ActivityFeed>();
    await _pump(tester, loadFeed: () => gate.future);
    await tester.pump();

    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    gate.complete(
      _feed([
        _group(ActivityGroupKind.running, [_item(title: 'Deploy ScriptHive')]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Deploy ScriptHive'), findsOneWidget);
  });

  testWidgets('draws groups in the order the feed produced them', (
    tester,
  ) async {
    await _pump(
      tester,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.needsYou, [
          _item(
            sessionId: 'blocked',
            title: 'Waiting chat',
            clientTurnId: 'turn-blocked',
            label: 'Waiting for your input',
            status: HermesStatus.blocked,
          ),
        ]),
        _group(ActivityGroupKind.running, [
          _item(sessionId: 'live', title: 'Live chat', clientTurnId: 't-live'),
        ]),
        _group(ActivityGroupKind.failed, [
          _item(
            sessionId: 'bad',
            title: 'Broken chat',
            clientTurnId: 't-bad',
            label: 'The turn failed',
            status: HermesStatus.failed,
          ),
        ]),
      ]),
    );
    await tester.pumpAndSettle();

    double topOf(String text) => tester.getTopLeft(find.text(text).first).dy;

    expect(
      topOf(ActivityGroupKind.needsYou.title(l10n)),
      lessThan(topOf(ActivityGroupKind.running.title(l10n))),
    );
    expect(
      topOf(ActivityGroupKind.running.title(l10n)),
      lessThan(topOf(ActivityGroupKind.failed.title(l10n))),
    );
  });

  testWidgets('a row states its label and how long ago it moved', (
    tester,
  ) async {
    await _pump(
      tester,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.needsYou, [
          _item(
            title: 'Waiting chat',
            label: 'Waiting for your input',
            status: HermesStatus.blocked,
            updatedAgo: const Duration(minutes: 7),
          ),
        ]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Waiting for your input'), findsOneWidget);
    // Elapsed time is the whole point of a blocked row: "stuck" without
    // "for how long" is not actionable.
    expect(find.text('7m ago'), findsOneWidget);
  });

  testWidgets('an untitled turn still draws a row rather than vanishing', (
    tester,
  ) async {
    // The journal is the truth about work. A turn whose chat is not in the
    // session list is still real, so it must not be silently dropped.
    await _pump(
      tester,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.running, [_item(sessionId: 'ghost')]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Untitled chat'), findsOneWidget);
  });

  testWidgets('a capped group says how many rows it hid', (tester) async {
    await _pump(
      tester,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.completed, [
          _item(title: 'One', status: HermesStatus.completed),
        ], totalCount: 4),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('and 3 more'), findsOneWidget);
  });

  testWidgets('an empty feed becomes a calm designed state, not a blank list', (
    tester,
  ) async {
    await _pump(tester, loadFeed: () async => _feed(const []));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No recent activity'), findsOneWidget);
  });

  testWidgets('Inbox mode only shows work that needs action', (tester) async {
    await _pump(
      tester,
      actionableOnly: true,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.needsYou, [
          _item(
            sessionId: 'blocked',
            title: 'Approve deployment',
            status: HermesStatus.blocked,
          ),
        ]),
        _group(ActivityGroupKind.running, [
          _item(sessionId: 'live', title: 'Still running'),
        ]),
        _group(ActivityGroupKind.failed, [
          _item(
            sessionId: 'failed',
            title: 'Repair failed turn',
            status: HermesStatus.failed,
          ),
        ]),
        _group(ActivityGroupKind.completed, [
          _item(
            sessionId: 'done',
            title: 'Already completed',
            status: HermesStatus.completed,
          ),
        ]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approve deployment'), findsOneWidget);
    expect(find.text('Repair failed turn'), findsOneWidget);
    expect(find.text('Still running'), findsNothing);
    expect(find.text('Already completed'), findsNothing);
  });

  testWidgets('an empty Inbox states that no action is required', (
    tester,
  ) async {
    await _pump(
      tester,
      actionableOnly: true,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.running, [_item(title: 'Still running')]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Inbox is clear'), findsOneWidget);
  });

  testWidgets('a first read that fails becomes a retryable error state', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      loadFeed: () async {
        attempts++;
        if (attempts == 1) throw StateError('journal unavailable');
        return _feed([
          _group(ActivityGroupKind.running, [_item(title: 'Recovered')]),
        ]);
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('a later failure keeps the timeline behind an offline notice', (
    tester,
  ) async {
    // Losing the network must never blank the screen the user relies on to
    // know what Hermes is doing.
    var attempts = 0;
    await _pump(
      tester,
      loadFeed: () async {
        attempts++;
        if (attempts > 1) throw StateError('offline');
        return _feed([
          _group(ActivityGroupKind.running, [_item(title: 'Still shown')]),
        ]);
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Still shown'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Still shown'), findsOneWidget);
    expect(find.textContaining('Offline', findRichText: true), findsOneWidget);
  });

  testWidgets('tapping a row reports the item it belongs to', (tester) async {
    final opened = <ActivityItem>[];
    await _pump(
      tester,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.running, [
          _item(sessionId: 'session-x', title: 'Open me'),
        ]),
      ]),
      onOpenItem: opened.add,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open me'));
    await tester.pumpAndSettle();

    expect(opened.map((item) => item.sessionId), ['session-x']);
  });

  testWidgets('rows are inert rather than fake-tappable with no handler', (
    tester,
  ) async {
    await _pump(
      tester,
      loadFeed: () async => _feed([
        _group(ActivityGroupKind.running, [_item(title: 'No handler')]),
      ]),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<HermesCard>(find.byType(HermesCard).first);
    expect(card.onTap, isNull);
  });

  testWidgets('refresh re-reads the feed', (tester) async {
    var reads = 0;
    await _pump(
      tester,
      loadFeed: () async {
        reads++;
        return _feed([
          _group(ActivityGroupKind.running, [_item(title: 'Read $reads')]),
        ]);
      },
    );
    await tester.pumpAndSettle();
    expect(reads, 1);

    final state = tester.state<ActivityPaneState>(find.byType(ActivityPane));
    await state.refresh();
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(find.text('Read 2'), findsOneWidget);
  });
}
