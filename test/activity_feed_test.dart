import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'support/l10n_test_utils.dart';

const _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _mobileA = '11111111-1111-4111-8111-111111111111';

/// Canonical v4 UUIDs, generated per index so a test can hold several turns of
/// the same chat without hand-writing each one.
String _clientTurn(int index) {
  final hex = index.toRadixString(16).padLeft(2, '0');
  return '${hex * 4}-${hex * 2}-4${hex}0-8${hex}0-${hex * 6}';
}

/// A fixed clock so every window boundary is asserted rather than approximated.
final _now = DateTime.utc(2026, 8, 28, 12, 0, 0);

int _msAgo(Duration ago) => _now.subtract(ago).millisecondsSinceEpoch;

GatewayTurnJournalBinding _binding({
  String connectionId = 'connection-a',
  String endpointDigest = _digestA,
  String localSessionId = 'session-a',
}) {
  return GatewayTurnJournalBinding(
    connectionId: connectionId,
    endpointDigest: endpointDigest,
    localSessionId: localSessionId,
    mobileSessionId: _mobileA,
    storedSessionId: 'stored-$localSessionId',
    bindingVersion: 1,
    updatedAtEpochMs: _msAgo(const Duration(hours: 1)),
  );
}

GatewayTurnJournalEntry _entry({
  required GatewayTurnJournalBinding binding,
  int turn = 1,
  GatewayRecoveryTurnStatus? status,
  GatewayTurnRecoveryFailure? failure,
  Duration updatedAgo = const Duration(minutes: 1),
}) {
  final clientTurnId = _clientTurn(turn);
  final terminal = status?.isTerminal == true;
  final hasFailure = failure != null;
  return GatewayTurnJournalEntry(
    bindingIdentity: binding.bindingIdentity,
    clientTurnId: clientTurnId,
    turnId: status == null ? null : 'turn-$turn',
    status: status,
    lastSeq: status == null ? 0 : 3,
    eventPayloadBytes: 0,
    terminalEventRecorded: terminal && !hasFailure,
    terminalResult: status == GatewayRecoveryTurnStatus.completed && !hasFailure
        ? GatewayTurnTerminalResult(
            messageId: 'message-$turn',
            assistantText: 'Done.',
          )
        : null,
    ackUncertain: false,
    failure: failure,
    updatedAtEpochMs: _msAgo(updatedAgo),
  );
}

ActivityFeed _feed(
  List<GatewayTurnJournalBinding> bindings,
  List<GatewayTurnJournalEntry> entries, {
  String? connectionId = 'connection-a',
  String? endpointDigest = _digestA,
  Map<String, String> sessionTitles = const {},
  DateTime? now,
  int groupLimit = kActivityGroupLimit,
}) {
  return buildActivityFeed(
    snapshot: GatewayTurnJournalSnapshot(bindings: bindings, entries: entries),
    now: now ?? _now,
    connectionId: connectionId,
    endpointDigest: endpointDigest,
    sessionTitles: sessionTitles,
    groupLimit: groupLimit,
  );
}

ActivityGroup _group(ActivityFeed feed, ActivityGroupKind kind) =>
    feed.groups.firstWhere((group) => group.kind == kind);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  test('an empty journal produces an empty feed rather than empty groups', () {
    final feed = _feed(const [], const []);

    expect(feed.groups, isEmpty);
    expect(feed.isEmpty, isTrue);
    expect(feed.blockedCount, 0);
    expect(feed.runningCount, 0);
  });

  test('groups are emitted in the validated attention order', () {
    // One turn of each kind, deliberately journalled out of order so the
    // ranking is the helper's doing rather than the input's.
    final blocked = _binding(localSessionId: 'session-blocked');
    final running = _binding(localSessionId: 'session-running');
    final failed = _binding(localSessionId: 'session-failed');
    final done = _binding(localSessionId: 'session-done');

    final feed = _feed(
      [done, running, failed, blocked],
      [
        _entry(binding: done, status: GatewayRecoveryTurnStatus.completed),
        _entry(binding: running, status: GatewayRecoveryTurnStatus.running),
        _entry(binding: failed, status: GatewayRecoveryTurnStatus.failed),
        _entry(
          binding: blocked,
          status: GatewayRecoveryTurnStatus.waitingInput,
        ),
      ],
    );

    expect(feed.groups.map((group) => group.kind), [
      ActivityGroupKind.needsYou,
      ActivityGroupKind.running,
      ActivityGroupKind.failed,
      ActivityGroupKind.completed,
    ]);
    expect(feed.groups.map((group) => group.title(l10n)), [
      'Needs you',
      'Running now',
      'Failed',
      'Completed',
    ]);
  });

  test('an empty group is dropped instead of drawn as an empty list', () {
    final binding = _binding();
    final feed = _feed(
      [binding],
      [_entry(binding: binding, status: GatewayRecoveryTurnStatus.running)],
    );

    expect(feed.groups.map((group) => group.kind), [ActivityGroupKind.running]);
  });

  test('a waiting turn needs you and carries its reason', () {
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.waitingInput,
        ),
      ],
    );

    final item = _group(feed, ActivityGroupKind.needsYou).items.single;
    expect(item.sessionId, 'session-a');
    expect(item.label, 'Waiting for your input');
    expect(item.status, HermesStatus.blocked);
    expect(feed.blockedCount, 1);
  });

  test('an unacknowledged submit is running, not idle', () {
    // No status yet: the write-ahead record exists but the gateway has not
    // answered. The work is outstanding and must be visible as such.
    final binding = _binding();
    final feed = _feed([binding], [_entry(binding: binding)]);

    final item = _group(feed, ActivityGroupKind.running).items.single;
    expect(item.label, 'Submitted, waiting for Hermes');
    expect(item.status, HermesStatus.running);
    expect(item.turnId, isNull);
    expect(feed.runningCount, 1);
  });

  test('a recovery failure outranks the status the server reported', () {
    // The turn completed server-side but the client could not reconcile it,
    // so the composer stays blocked. Filing this under Completed would tell
    // the user the exact opposite of the truth.
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.completed,
          failure: GatewayTurnRecoveryFailure.replayPruned,
        ),
      ],
    );

    final item = _group(feed, ActivityGroupKind.failed).items.single;
    expect(item.label, 'Turn recovery failed');
    expect(item.status, HermesStatus.failed);
  });

  test('an interrupted turn reads as stopped, not as completed work', () {
    final binding = _binding();
    final feed = _feed(
      [binding],
      [_entry(binding: binding, status: GatewayRecoveryTurnStatus.interrupted)],
    );

    final item = _group(feed, ActivityGroupKind.completed).items.single;
    expect(item.label, 'Stopped');
    expect(item.status, HermesStatus.idle);
  });

  test('a running turn with no update for too long is reported as stalled', () {
    // Home drops a zombie turn because presenting it as live would be a lie.
    // Activity is the operational timeline, so it must say what happened
    // instead of quietly losing the work.
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.running,
          updatedAgo: kActivityRunningStaleAfter + const Duration(minutes: 1),
        ),
      ],
    );

    final item = _group(feed, ActivityGroupKind.failed).items.single;
    expect(item.label, 'Stalled — no update from Hermes');
    expect(feed.runningCount, 0);
  });

  test('a running turn exactly at the staleness boundary is still live', () {
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.running,
          updatedAgo: kActivityRunningStaleAfter,
        ),
      ],
    );

    expect(_group(feed, ActivityGroupKind.running).items, hasLength(1));
  });

  test('a clock behind the journal keeps the turn running', () {
    // Device clock skew must never turn live work into a fake failure.
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.running,
          updatedAgo: const Duration(minutes: -30),
        ),
      ],
    );

    expect(_group(feed, ActivityGroupKind.running).items, hasLength(1));
  });

  test('every turn of one chat appears: Activity is a timeline, not a list of '
      'chats', () {
    // Home deduplicates to one row per session. Activity must not, or a chat
    // that ran three jobs would report one.
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          turn: 1,
          status: GatewayRecoveryTurnStatus.completed,
          updatedAgo: const Duration(minutes: 30),
        ),
        _entry(
          binding: binding,
          turn: 2,
          status: GatewayRecoveryTurnStatus.completed,
          updatedAgo: const Duration(minutes: 10),
        ),
      ],
    );

    final items = _group(feed, ActivityGroupKind.completed).items;
    expect(items, hasLength(2));
    expect(items.map((item) => item.clientTurnId), [
      _clientTurn(2),
      _clientTurn(1),
    ]);
  });

  test('items inside a group are newest first', () {
    final older = _binding(localSessionId: 'session-older');
    final newer = _binding(localSessionId: 'session-newer');
    final feed = _feed(
      [older, newer],
      [
        _entry(
          binding: older,
          status: GatewayRecoveryTurnStatus.failed,
          updatedAgo: const Duration(hours: 2),
        ),
        _entry(
          binding: newer,
          status: GatewayRecoveryTurnStatus.failed,
          updatedAgo: const Duration(minutes: 5),
        ),
      ],
    );

    expect(
      _group(feed, ActivityGroupKind.failed).items.map((i) => i.sessionId),
      ['session-newer', 'session-older'],
    );
  });

  test('a session title is used when known and never invented when not', () {
    final titled = _binding(localSessionId: 'session-titled');
    final untitled = _binding(localSessionId: 'session-untitled');
    final feed = _feed(
      [titled, untitled],
      [
        _entry(binding: titled, status: GatewayRecoveryTurnStatus.running),
        _entry(binding: untitled, status: GatewayRecoveryTurnStatus.running),
      ],
      sessionTitles: {'session-titled': 'Deploy ScriptHive'},
    );

    final items = _group(feed, ActivityGroupKind.running).items;
    expect(
      items.firstWhere((i) => i.sessionId == 'session-titled').title,
      'Deploy ScriptHive',
    );
    // The journal is the truth about work: a turn whose chat is missing from
    // the session list is still real, so the row survives without a title.
    expect(
      items.firstWhere((i) => i.sessionId == 'session-untitled').title,
      isNull,
    );
  });

  test('work recorded for another connection or endpoint is excluded', () {
    final mine = _binding(localSessionId: 'session-mine');
    final otherConnection = _binding(
      connectionId: 'connection-b',
      localSessionId: 'session-other-connection',
    );
    final otherEndpoint = _binding(
      endpointDigest: _digestB,
      localSessionId: 'session-other-endpoint',
    );

    final feed = _feed(
      [mine, otherConnection, otherEndpoint],
      [
        _entry(binding: mine, status: GatewayRecoveryTurnStatus.running),
        _entry(
          binding: otherConnection,
          status: GatewayRecoveryTurnStatus.running,
        ),
        _entry(
          binding: otherEndpoint,
          status: GatewayRecoveryTurnStatus.running,
        ),
      ],
    );

    expect(
      _group(feed, ActivityGroupKind.running).items.map((i) => i.sessionId),
      ['session-mine'],
    );
  });

  test('an entry with no binding is ignored rather than turned into a row', () {
    final binding = _binding();
    final orphan = _binding(localSessionId: 'session-orphan');
    final feed = _feed(
      [binding],
      [
        _entry(binding: binding, status: GatewayRecoveryTurnStatus.running),
        _entry(binding: orphan, status: GatewayRecoveryTurnStatus.running),
      ],
    );

    expect(_group(feed, ActivityGroupKind.running).items, hasLength(1));
  });

  test('finished work older than the window falls off the timeline', () {
    final stale = _binding(localSessionId: 'session-stale');
    final fresh = _binding(localSessionId: 'session-fresh');
    final feed = _feed(
      [stale, fresh],
      [
        _entry(
          binding: stale,
          status: GatewayRecoveryTurnStatus.completed,
          updatedAgo: kActivityCompletedWindow + const Duration(hours: 1),
        ),
        _entry(
          binding: fresh,
          status: GatewayRecoveryTurnStatus.completed,
          updatedAgo: const Duration(hours: 1),
        ),
      ],
    );

    expect(
      _group(feed, ActivityGroupKind.completed).items.map((i) => i.sessionId),
      ['session-fresh'],
    );
  });

  test('blocked work is never aged out, however long it has waited', () {
    // Being stuck for a week is the strongest possible reason to show a row.
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        _entry(
          binding: binding,
          status: GatewayRecoveryTurnStatus.waitingInput,
          updatedAgo: kActivityCompletedWindow + const Duration(days: 30),
        ),
      ],
    );

    expect(_group(feed, ActivityGroupKind.needsYou).items, hasLength(1));
  });

  test('a capped group reports what it hid and the true total', () {
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        for (var turn = 1; turn <= 4; turn++)
          _entry(
            binding: binding,
            turn: turn,
            status: GatewayRecoveryTurnStatus.completed,
            updatedAgo: Duration(minutes: turn),
          ),
      ],
      groupLimit: 2,
    );

    final group = _group(feed, ActivityGroupKind.completed);
    expect(group.items, hasLength(2));
    expect(group.totalCount, 4);
    expect(group.overflow, 2);
  });

  test('the badge counts ignore the group cap', () {
    // The shell badge must state how much work is blocked, not how much of it
    // happens to fit on screen.
    final binding = _binding();
    final feed = _feed(
      [binding],
      [
        for (var turn = 1; turn <= 3; turn++)
          _entry(
            binding: binding,
            turn: turn,
            status: GatewayRecoveryTurnStatus.waitingInput,
            updatedAgo: Duration(minutes: turn),
          ),
      ],
      groupLimit: 1,
    );

    expect(_group(feed, ActivityGroupKind.needsYou).items, hasLength(1));
    expect(feed.blockedCount, 3);
  });

  test('a group limit below one is rejected instead of silently emptying the '
      'timeline', () {
    expect(() => _feed(const [], const [], groupLimit: 0), throwsArgumentError);
  });

  test(
    'a null scope reads every connection, which is what diagnostics want',
    () {
      final mine = _binding(localSessionId: 'session-mine');
      final other = _binding(
        connectionId: 'connection-b',
        endpointDigest: _digestB,
        localSessionId: 'session-other',
      );
      final feed = _feed(
        [mine, other],
        [
          _entry(binding: mine, status: GatewayRecoveryTurnStatus.running),
          _entry(binding: other, status: GatewayRecoveryTurnStatus.running),
        ],
        connectionId: null,
        endpointDigest: null,
      );

      expect(_group(feed, ActivityGroupKind.running).items, hasLength(2));
    },
  );

  test('every recovery-status value lands in exactly one group', () {
    // A status added to the contract later must be classified deliberately
    // rather than silently disappearing from the operational timeline.
    for (final status in GatewayRecoveryTurnStatus.values) {
      final binding = _binding(localSessionId: 'session-${status.wireValue}');
      final feed = _feed([binding], [_entry(binding: binding, status: status)]);
      final rows = feed.groups.expand((group) => group.items).toList();
      expect(
        rows,
        hasLength(1),
        reason: '${status.wireValue} produced ${rows.length} rows',
      );
      expect(rows.single.label, isNotEmpty);
    }
  });

  test('the feed does not mutate the snapshot it was given', () {
    final binding = _binding();
    final entries = [
      _entry(binding: binding, status: GatewayRecoveryTurnStatus.running),
    ];
    final snapshot = GatewayTurnJournalSnapshot(
      bindings: [binding],
      entries: entries,
    );

    buildActivityFeed(snapshot: snapshot, now: _now);

    expect(identical(snapshot.entries, entries), isTrue);
    expect(snapshot.entries, hasLength(1));
  });
}
