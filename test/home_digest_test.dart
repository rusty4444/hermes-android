import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_digest.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

/// A fixed clock so window boundaries are asserted, not approximated.
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
  int messageCount = 4,
  String preview = 'preview',
}) {
  return Session(
    id: id,
    title: title,
    model: 'claude-opus-5',
    source: 'gateway',
    messageCount: messageCount,
    isActive: isActive ?? endedAgo == null,
    preview: preview,
    startedAt: _epoch(startedAgo),
    lastActive: lastActiveAgo == null ? 0 : _epoch(lastActiveAgo),
    endedAt: endedAgo == null ? null : _epoch(endedAgo),
  );
}

HomeSection? _section(HomeDigest digest, HomeSectionKind kind) {
  for (final section in digest.sections) {
    if (section.kind == kind) return section;
  }
  return null;
}

List<String> _ids(HomeDigest digest, HomeSectionKind kind) {
  final section = _section(digest, kind);
  if (section == null) return const [];
  return section.items.map((item) => item.session.id).toList();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  group('HomeSectionKind', () {
    test('ranks attention above everything else', () {
      expect(HomeSectionKind.values, [
        HomeSectionKind.needsYou,
        HomeSectionKind.running,
        HomeSectionKind.continueWorking,
        HomeSectionKind.completedRecently,
      ]);
    });

    test('each kind carries a distinct human title', () {
      final titles = <String>{};
      for (final kind in HomeSectionKind.values) {
        expect(kind.title(l10n), isNotEmpty);
        titles.add(kind.title(l10n));
      }
      expect(titles, hasLength(HomeSectionKind.values.length));
    });
  });

  group('buildHomeDigest', () {
    test('returns no section for an empty corpus', () {
      final digest = buildHomeDigest(sessions: const [], now: _now);

      expect(digest.sections, isEmpty);
      expect(digest.isEmpty, isTrue);
      expect(digest.needsAttention, isFalse);
    });

    test('drops empty sections instead of rendering empty lists', () {
      final digest = buildHomeDigest(
        sessions: [_session(id: 'a')],
        now: _now,
      );

      expect(_section(digest, HomeSectionKind.needsYou), isNull);
      expect(_section(digest, HomeSectionKind.running), isNull);
      expect(_ids(digest, HomeSectionKind.continueWorking), ['a']);
    });

    test('orders sections by attention rank', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'blocked'),
          _session(id: 'run'),
          _session(id: 'idle'),
          _session(id: 'done', endedAgo: const Duration(hours: 1)),
        ],
        now: _now,
        attention: const {'blocked': 'Approval required'},
        running: const {'run'},
      );

      expect(digest.sections.map((section) => section.kind), [
        HomeSectionKind.needsYou,
        HomeSectionKind.running,
        HomeSectionKind.continueWorking,
        HomeSectionKind.completedRecently,
      ]);
      expect(digest.needsAttention, isTrue);
      expect(digest.isEmpty, isFalse);
    });

    test('carries the blocked status and the reason it is blocked', () {
      final digest = buildHomeDigest(
        sessions: [_session(id: 'blocked')],
        now: _now,
        attention: const {'blocked': 'Clarification needed'},
      );

      final item = _section(digest, HomeSectionKind.needsYou)!.items.single;
      expect(item.status, HermesStatus.blocked);
      expect(item.attentionLabel, 'Clarification needed');
    });

    test('marks running work as running without an attention label', () {
      final digest = buildHomeDigest(
        sessions: [_session(id: 'run')],
        now: _now,
        running: const {'run'},
      );

      final item = _section(digest, HomeSectionKind.running)!.items.single;
      expect(item.status, HermesStatus.running);
      expect(item.attentionLabel, isNull);
    });

    test('remote recent activity is labelled, not promoted to Running', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(
            id: 'remote',
            startedAgo: const Duration(days: 30),
            lastActiveAgo: const Duration(minutes: 2),
            isActive: true, // API recency is not a live turn.
          ),
        ],
        now: _now,
      );

      expect(_section(digest, HomeSectionKind.running), isNull);
      final item = _section(
        digest,
        HomeSectionKind.continueWorking,
      )!.items.single;
      expect(item.status, HermesStatus.idle);
      expect(item.recentlyActive, isTrue);
      expect(item.activityAt, _epoch(const Duration(minutes: 2)));
    });

    test('stale activity remains resumable without a recent label', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(
            id: 'stale',
            startedAgo: const Duration(days: 30),
            lastActiveAgo: const Duration(hours: 2),
            isActive: true,
          ),
        ],
        now: _now,
      );

      expect(_section(digest, HomeSectionKind.running), isNull);
      final item = _section(
        digest,
        HomeSectionKind.continueWorking,
      )!.items.single;
      expect(item.status, HermesStatus.idle);
      expect(item.recentlyActive, isFalse);
    });

    test('journal Running outranks server recency', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(
            id: 'local',
            startedAgo: const Duration(days: 30),
            lastActiveAgo: const Duration(minutes: 1),
          ),
        ],
        now: _now,
        running: const {'local'},
      );

      final item = _section(digest, HomeSectionKind.running)!.items.single;
      expect(item.status, HermesStatus.running);
      expect(item.recentlyActive, isFalse);
      expect(_section(digest, HomeSectionKind.continueWorking), isNull);
    });

    test('lastActive defines recency regardless of isActive', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(
            id: 'recent',
            startedAgo: const Duration(days: 30),
            lastActiveAgo: const Duration(minutes: 4),
            isActive: false,
          ),
          _session(
            id: 'expired',
            startedAgo: const Duration(days: 30),
            lastActiveAgo: const Duration(minutes: 6),
            isActive: true,
          ),
        ],
        now: _now,
      );

      final items = _section(digest, HomeSectionKind.continueWorking)!.items;
      expect(items.map((item) => item.session.id), ['recent', 'expired']);
      expect(items.map((item) => item.recentlyActive), [true, false]);
      expect(_section(digest, HomeSectionKind.running), isNull);
    });

    test('blocked outranks journal Running and recent activity', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'blocked', lastActiveAgo: const Duration(minutes: 1)),
        ],
        now: _now,
        attention: const {'blocked': 'Approval required'},
        running: const {'blocked'},
      );

      expect(_section(digest, HomeSectionKind.running), isNull);
      final item = _section(digest, HomeSectionKind.needsYou)!.items.single;
      expect(item.status, HermesStatus.blocked);
      expect(item.attentionLabel, 'Approval required');
      expect(item.recentlyActive, isFalse);
    });

    test('no phantom Running from a recent row or unmatched journal id', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'remote', lastActiveAgo: const Duration(minutes: 1)),
        ],
        now: _now,
        running: const {'missing'},
      );

      expect(_section(digest, HomeSectionKind.running), isNull);
      expect(_ids(digest, HomeSectionKind.continueWorking), ['remote']);
      expect(digest.sections.expand((section) => section.items), hasLength(1));
    });

    test('a blocked session never also appears as running', () {
      final digest = buildHomeDigest(
        sessions: [_session(id: 'both')],
        now: _now,
        attention: const {'both': 'Approval required'},
        running: const {'both'},
      );

      expect(_ids(digest, HomeSectionKind.needsYou), ['both']);
      expect(_section(digest, HomeSectionKind.running), isNull);
    });

    test('every session appears in exactly one section', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'blocked'),
          _session(id: 'run'),
          _session(id: 'idle'),
          _session(id: 'done', endedAgo: const Duration(hours: 2)),
        ],
        now: _now,
        attention: const {'blocked': 'Approval required'},
        running: const {'run'},
      );

      final seen = <String>[];
      for (final section in digest.sections) {
        seen.addAll(section.items.map((item) => item.session.id));
      }
      expect(seen..sort(), ['blocked', 'done', 'idle', 'run']);
    });

    test('ignores attention and running ids with no matching session', () {
      final digest = buildHomeDigest(
        sessions: [_session(id: 'a')],
        now: _now,
        attention: const {'ghost': 'Approval required'},
        running: const {'phantom'},
      );

      expect(_section(digest, HomeSectionKind.needsYou), isNull);
      expect(_section(digest, HomeSectionKind.running), isNull);
      expect(_ids(digest, HomeSectionKind.continueWorking), ['a']);
    });

    test('sorts each section by most recent activity first', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'old', startedAgo: const Duration(hours: 6)),
          _session(id: 'new', startedAgo: const Duration(minutes: 2)),
          _session(id: 'mid', startedAgo: const Duration(hours: 1)),
        ],
        now: _now,
      );

      expect(_ids(digest, HomeSectionKind.continueWorking), [
        'new',
        'mid',
        'old',
      ]);
    });

    test('ranks old-start unfinished work by lastActive, not startedAt', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(
            id: 'new-start',
            startedAgo: const Duration(hours: 1),
            lastActiveAgo: const Duration(minutes: 40),
          ),
          _session(
            id: 'old-start',
            startedAgo: const Duration(days: 30),
            lastActiveAgo: const Duration(minutes: 10),
          ),
        ],
        now: _now,
      );

      expect(_ids(digest, HomeSectionKind.continueWorking), [
        'old-start',
        'new-start',
      ]);
    });

    test('uses the end time as the activity time of a finished session', () {
      final digest = buildHomeDigest(
        sessions: [
          // Started long ago but finished a minute ago: it is the freshest.
          _session(
            id: 'late',
            startedAgo: const Duration(hours: 20),
            endedAgo: const Duration(minutes: 1),
          ),
          _session(
            id: 'early',
            startedAgo: const Duration(hours: 3),
            endedAgo: const Duration(hours: 2),
          ),
        ],
        now: _now,
      );

      expect(_ids(digest, HomeSectionKind.completedRecently), [
        'late',
        'early',
      ]);
    });

    test('keeps a still-active session out of the completed section', () {
      final digest = buildHomeDigest(
        sessions: [_session(id: 'a', startedAgo: const Duration(days: 3))],
        now: _now,
      );

      expect(_ids(digest, HomeSectionKind.continueWorking), ['a']);
      expect(_section(digest, HomeSectionKind.completedRecently), isNull);
    });

    test('drops an active session older than the continue window', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'stale', startedAgo: const Duration(days: 30)),
          _session(id: 'fresh'),
        ],
        now: _now,
      );

      expect(_ids(digest, HomeSectionKind.continueWorking), ['fresh']);
    });

    test('drops work completed before the completed window', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(
            id: 'yesteryear',
            startedAgo: const Duration(days: 9),
            endedAgo: const Duration(days: 8),
          ),
        ],
        now: _now,
      );

      expect(digest.sections, isEmpty);
    });

    test('honours custom windows', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'a', startedAgo: const Duration(hours: 30)),
          _session(
            id: 'b',
            startedAgo: const Duration(hours: 5),
            endedAgo: const Duration(hours: 4),
          ),
        ],
        now: _now,
        continueWindow: const Duration(hours: 24),
        completedWindow: const Duration(hours: 1),
      );

      expect(digest.sections, isEmpty);
    });

    test('a session whose clock is ahead is still shown, never dropped', () {
      final digest = buildHomeDigest(
        sessions: [
          Session(
            id: 'skewed',
            title: 'Skewed',
            model: 'm',
            source: 'gateway',
            messageCount: 1,
            isActive: true,
            preview: '',
            startedAt: _epoch(const Duration(hours: -2)),
          ),
        ],
        now: _now,
      );

      expect(_ids(digest, HomeSectionKind.continueWorking), ['skewed']);
    });

    test('caps a long section and reports what it hid', () {
      final digest = buildHomeDigest(
        sessions: [
          for (var index = 0; index < 9; index++)
            _session(
              id: 's$index',
              startedAgo: Duration(minutes: index),
            ),
        ],
        now: _now,
        sectionLimit: 4,
      );

      final section = _section(digest, HomeSectionKind.continueWorking)!;
      expect(section.items.map((item) => item.session.id), [
        's0',
        's1',
        's2',
        's3',
      ]);
      expect(section.overflow, 5);
      expect(section.totalCount, 9);
    });

    test('reports no overflow when everything fits', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'a'),
          _session(id: 'b'),
        ],
        now: _now,
        sectionLimit: 5,
      );

      final section = _section(digest, HomeSectionKind.continueWorking)!;
      expect(section.overflow, 0);
      expect(section.totalCount, 2);
    });

    test('attaches the project name when the session belongs to one', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'a'),
          _session(id: 'b'),
        ],
        now: _now,
        projectNames: const {'a': 'Hermes Android'},
      );

      final items = _section(digest, HomeSectionKind.continueWorking)!.items;
      expect(
        items.firstWhere((i) => i.session.id == 'a').projectName,
        'Hermes Android',
      );
      expect(items.firstWhere((i) => i.session.id == 'b').projectName, isNull);
    });

    test(
      'rejects a non-positive section limit instead of hiding everything',
      () {
        expect(
          () => buildHomeDigest(
            sessions: [_session(id: 'a')],
            now: _now,
            sectionLimit: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('does not mutate the caller list', () {
      final sessions = [
        _session(id: 'old', startedAgo: const Duration(hours: 4)),
        _session(id: 'new'),
      ];

      buildHomeDigest(sessions: sessions, now: _now);

      expect(sessions.map((session) => session.id), ['old', 'new']);
    });

    test('needsAttention is true only while something is blocked', () {
      final running = buildHomeDigest(
        sessions: [_session(id: 'run')],
        now: _now,
        running: const {'run'},
      );
      expect(running.needsAttention, isFalse);

      final blocked = buildHomeDigest(
        sessions: [_session(id: 'run')],
        now: _now,
        attention: const {'run': 'Approval required'},
      );
      expect(blocked.needsAttention, isTrue);
    });

    test('blockedCount counts only what actually needs the user', () {
      final digest = buildHomeDigest(
        sessions: [
          _session(id: 'a'),
          _session(id: 'b'),
          _session(id: 'c'),
        ],
        now: _now,
        attention: const {'a': 'Approval required', 'b': 'Secret required'},
        running: const {'c'},
      );

      expect(digest.blockedCount, 2);
    });

    test('blockedCount ignores the section cap', () {
      final digest = buildHomeDigest(
        sessions: [
          for (var index = 0; index < 7; index++) _session(id: 's$index'),
        ],
        now: _now,
        attention: {
          for (var index = 0; index < 7; index++)
            's$index': 'Approval required',
        },
        sectionLimit: 3,
      );

      expect(_section(digest, HomeSectionKind.needsYou)!.items, hasLength(3));
      expect(digest.blockedCount, 7);
    });
  });
}
