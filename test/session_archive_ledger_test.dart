import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/session_archive_ledger.dart';

Session _session(
  String id, {
  String? root,
  bool archived = false,
  String title = 'Rich title',
  String preview = 'Fresh preview with search context',
  int messageCount = 47,
  double lastActive = 1800000123.5,
}) => Session(
  id: id,
  title: title,
  model: 'fixture-model',
  source: 'telegram',
  messageCount: messageCount,
  isActive: true,
  preview: preview,
  startedAt: 1799990000.25,
  endedAt: 1800000000.75,
  lastActive: lastActive,
  pinned: true,
  lineageRootId: root,
  archived: archived,
  isLocalDraft: true,
);

/// Compare every non-archive field explicitly, so reconciliation cannot replace
/// a fresh list/search row with a sparse mutation acknowledgement unnoticed.
Map<String, Object?> _metadata(Session session) => {
  'id': session.id,
  'title': session.title,
  'model': session.model,
  'source': session.source,
  'messageCount': session.messageCount,
  'isActive': session.isActive,
  'preview': session.preview,
  'startedAt': session.startedAt,
  'endedAt': session.endedAt,
  'lastActive': session.lastActive,
  'pinned': session.pinned,
  'lineageRootId': session.lineageRootId,
  'isLocalDraft': session.isLocalDraft,
};

/// Models the physical request boundary, not the time the response arrives.
Future<List<Session>> _read(
  SessionArchiveLedger ledger,
  Future<List<Session>> response, {
  bool includeMissing = false,
}) async {
  final observedRevision = ledger.revision;
  final rows = await response;
  return ledger.apply(rows, observedRevision, includeMissing: includeMissing);
}

void main() {
  group('Session.withArchived', () {
    for (final originalFlag in [true, false]) {
      for (final requestedFlag in [true, false]) {
        test(
          'changes $originalFlag to $requestedFlag without losing rich fields',
          () {
            final original = _session(
              'visible-tip',
              root: 'compression-root',
              archived: originalFlag,
            );
            final copied = original.withArchived(requestedFlag);

            expect(copied.archived, requestedFlag);
            expect(_metadata(copied), _metadata(original));
            expect(
              original.archived,
              originalFlag,
              reason: 'the input is immutable',
            );
            expect(copied.id, 'visible-tip');
            expect(copied.lineageRootId, 'compression-root');
          },
        );
      }
    }

    test(
      'preserves null metadata and false/default fields on a sparse session',
      () {
        const original = Session(
          id: 'stored-session',
          title: '',
          model: '',
          source: '',
          messageCount: 0,
          isActive: false,
          preview: '',
          startedAt: 0,
        );

        final archived = original.withArchived(true);
        final restored = archived.withArchived(false);

        expect(archived.archived, isTrue);
        expect(restored.archived, isFalse);
        expect(_metadata(archived), _metadata(original));
        expect(_metadata(restored), _metadata(original));
        expect(original.archived, isFalse);
      },
    );
  });

  group('sameSessionLineage', () {
    final cases = <(String, Session, Session, bool)>[
      ('same exact ID', _session('a'), _session('a'), true),
      (
        'same exact ID with one sparse lineage',
        _session('tip', root: 'root'),
        _session('tip'),
        true,
      ),
      ('root and tip', _session('root'), _session('tip', root: 'root'), true),
      (
        'two continuation tips',
        _session('tip-1', root: 'root'),
        _session('tip-2', root: 'root'),
        true,
      ),
      ('unrelated rootless sessions', _session('a'), _session('b'), false),
      (
        'different lineage roots',
        _session('tip-1', root: 'root-1'),
        _session('tip-2', root: 'root-2'),
        false,
      ),
      (
        'similar ID is not an alias',
        _session('root'),
        _session('root-extra', root: 'different-root'),
        false,
      ),
    ];
    for (final (name, a, b, expected) in cases) {
      test('$name is symmetric', () {
        expect(sameSessionLineage(a, b), expected);
        expect(sameSessionLineage(b, a), expected);
      });
    }
  });

  group('SessionArchiveLedger', () {
    test(
      'starts empty and does not invent rows or alter an untouched snapshot',
      () {
        final ledger = SessionArchiveLedger();
        final original = _session('a', archived: true);

        expect(ledger.revision, 0);
        expect(ledger.changesSince(0), isEmpty);
        expect(ledger.apply([], 0, includeMissing: true), isEmpty);
        final rows = ledger.apply([original], 0);
        expect(rows, hasLength(1));
        expect(_metadata(rows.single), _metadata(original));
        expect(rows.single.archived, isTrue);
        expect(ledger.revision, 0);
      },
    );

    test(
      'records monotonic revisions with an exclusive observation boundary',
      () {
        final ledger = SessionArchiveLedger();
        final a = _session('a');
        final b = _session('b');
        ledger.record(a, true);
        final afterArchive = ledger.revision;
        ledger.record(b, false);
        final afterOther = ledger.revision;
        ledger.record(a, false);

        expect(afterArchive, 1);
        expect(afterOther, 2);
        expect(ledger.revision, 3);
        final changes = ledger.changesSince(0).toList();
        expect(changes, hasLength(2));
        expect(
          {for (final change in changes) change.session.id: change.revision},
          {'a': 3, 'b': 2},
        );
        expect(
          {for (final change in changes) change.session.id: change.archived},
          {'a': false, 'b': false},
        );
        expect(ledger.changesSince(afterOther).single.session.id, 'a');
        expect(ledger.changesSince(afterOther).single.revision, 3);
        expect(ledger.changesSince(ledger.revision), isEmpty);
        expect(ledger.changesSince(ledger.revision + 1), isEmpty);
      },
    );

    test('reconfirming the same value still fences reads begun in between', () {
      final ledger = SessionArchiveLedger();
      final session = _session('a');
      ledger.record(session, true);
      final observedRevision = ledger.revision;
      ledger.record(session, true);

      expect(ledger.revision, 2);
      expect(ledger.changesSince(0), hasLength(1));
      expect(ledger.apply([session], observedRevision).single.archived, isTrue);
    });

    for (final archived in [true, false]) {
      final action = archived ? 'archive' : 'unarchive';
      final aliases = <(String, Session, Session)>[
        (
          'exact ID',
          _session('same', archived: !archived, title: 'Mutation baseline'),
          _session('same', archived: !archived, title: 'Fresh list title'),
        ),
        (
          'mutation root to returned tip',
          _session('root', archived: !archived, title: 'Mutation baseline'),
          _session(
            'new-tip',
            root: 'root',
            archived: !archived,
            title: 'Fresh list title',
          ),
        ),
        (
          'mutation tip to returned root',
          _session(
            'tip',
            root: 'root',
            archived: !archived,
            title: 'Mutation baseline',
          ),
          _session('root', archived: !archived, title: 'Fresh list title'),
        ),
        (
          'mutation tip to later compression tip',
          _session(
            'tip-1',
            root: 'root',
            archived: !archived,
            title: 'Mutation baseline',
          ),
          _session(
            'tip-2',
            root: 'root',
            archived: !archived,
            title: 'Fresh list title',
          ),
        ),
      ];
      for (final (name, mutationRow, incomingRow) in aliases) {
        test(
          'held pre-$action read cannot undo $name or erase fresh metadata',
          () async {
            final ledger = SessionArchiveLedger();
            final response = Completer<List<Session>>();
            final pending = _read(ledger, response.future);
            final unrelated = _session('unrelated', archived: !archived);

            ledger.record(mutationRow, archived);
            response.complete([incomingRow, unrelated]);
            final rows = await pending;

            expect(rows.map((row) => row.id), [incomingRow.id, unrelated.id]);
            expect(rows.first.archived, archived);
            expect(_metadata(rows.first), _metadata(incomingRow));
            expect(rows.last.archived, !archived);
            expect(_metadata(rows.last), _metadata(unrelated));
            expect(incomingRow.archived, !archived);
            expect(mutationRow.archived, !archived);
            expect(ledger.revision, 1);
          },
        );
      }

      test(
        '$action patches every old progressive emission without consuming it',
        () {
          final ledger = SessionArchiveLedger();
          final revisionBeforeRead = ledger.revision;
          final original = _session('a', archived: !archived);
          ledger.record(original, archived);

          for (final rows in [
            [original],
            [original, _session('b')],
            [original.withTitle('Final page title'), _session('c')],
          ]) {
            final patched = ledger.apply(rows, revisionBeforeRead);
            expect(patched.first.archived, archived);
            expect(_metadata(patched.first), _metadata(rows.first));
          }
          expect(ledger.revision, 1);
          expect(ledger.changesSince(0), hasLength(1));
        },
      );

      test(
        'latest conflicting action wins across root/tip aliases after $action',
        () async {
          final ledger = SessionArchiveLedger();
          final oldest = Completer<List<Session>>();
          final oldestRead = _read(ledger, oldest.future);
          final root = _session('root', archived: !archived);
          ledger.record(root, archived);
          final between = Completer<List<Session>>();
          final betweenRead = _read(ledger, between.future);
          final tip = _session('tip-1', root: 'root', archived: archived);
          ledger.record(tip, !archived);
          final rows = [
            _session('root', archived: archived),
            _session('tip-2', root: 'root', archived: archived),
          ];

          // Deliver newer-started and older-started reads in the harmful order.
          between.complete(rows);
          final betweenRows = await betweenRead;
          oldest.complete(rows);
          final oldestRows = await oldestRead;

          for (final reconciled in [betweenRows, oldestRows]) {
            expect(reconciled, hasLength(1));
            expect(reconciled.single.id, 'tip-2');
            expect(reconciled.single.archived, !archived);
            expect(_metadata(reconciled.single), _metadata(rows.last));
          }
          expect(ledger.revision, 2);
          final latest = ledger.changesSince(0).single;
          expect(latest.revision, 2);
          expect(latest.archived, !archived);
          expect(latest.session.id, 'tip-1');
          expect(rows.map((row) => row.archived), [archived, archived]);
        },
      );

      test(
        'post-$action read remains authoritative for external edits',
        () async {
          final ledger = SessionArchiveLedger();
          final oldResponse = Completer<List<Session>>();
          final oldRead = _read(ledger, oldResponse.future);
          final baseline = _session('tip', root: 'root', archived: !archived);
          ledger.record(baseline, archived);
          final newResponse = Completer<List<Session>>();
          final newRead = _read(ledger, newResponse.future);
          final externalEdit = _session(
            'new-tip',
            root: 'root',
            archived: !archived,
            title: 'Renamed on another device',
            preview: 'Latest remote content',
            messageCount: 102,
            lastActive: 1800009999.75,
          );

          newResponse.complete([externalEdit]);
          final newRows = await newRead;
          expect(newRows.single.archived, !archived);
          expect(_metadata(newRows.single), _metadata(externalEdit));

          oldResponse.complete([baseline]);
          expect((await oldRead).single.archived, archived);
          final nextRead = ledger.apply([externalEdit], ledger.revision);
          expect(nextRead.single.archived, !archived);
          expect(_metadata(nextRead.single), _metadata(externalEdit));
          expect(ledger.revision, 1);
        },
      );
    }

    test('independent lineages retain their own latest actions', () {
      final ledger = SessionArchiveLedger();
      final observedRevision = ledger.revision;
      ledger.record(_session('root-a'), true);
      ledger.record(_session('root-b', archived: true), false);
      ledger.record(_session('tip-a', root: 'root-a', archived: true), false);
      final rows = ledger.apply([
        _session('tip-a2', root: 'root-a', archived: true),
        _session('tip-b', root: 'root-b', archived: true),
        _session('unrelated', archived: true),
      ], observedRevision);

      expect(rows.map((row) => row.archived), [false, false, true]);
      expect(ledger.changesSince(0), hasLength(2));
      expect(ledger.revision, 3);
    });

    test(
      'deduplicates exact IDs with last metadata winning and stable order',
      () {
        final ledger = SessionArchiveLedger();
        ledger.record(_session('a'), true);
        final older = _session('a', title: 'Old title', messageCount: 1);
        final unrelated = _session('b');
        final fresh = _session(
          'a',
          title: 'Fresh server title',
          preview: 'Fresh excerpt',
          messageCount: 99,
          lastActive: 1800009999,
        );
        final input = [older, unrelated, fresh];
        final rows = ledger.apply(input, 0, includeMissing: true);

        expect(rows.map((row) => row.id), ['a', 'b']);
        expect(rows.first.archived, isTrue);
        expect(_metadata(rows.first), _metadata(fresh));
        expect(_metadata(rows.last), _metadata(unrelated));
        expect(input, hasLength(3));
        expect(input.map((row) => row.archived), [false, false, false]);
      },
    );

    test('deduplicates even when there are no intervening archive changes', () {
      final ledger = SessionArchiveLedger();
      final a = _session('a');
      final freshA = _session('a', title: 'Newer metadata', archived: true);
      final rows = ledger.apply([a, _session('b'), freshA], ledger.revision);

      expect(rows.map((row) => row.id), ['a', 'b']);
      expect(rows.first.archived, isTrue);
      expect(_metadata(rows.first), _metadata(freshA));
    });

    test(
      'default apply does not resurrect missing rows from a filtered read',
      () {
        final ledger = SessionArchiveLedger();
        ledger.record(_session('missing'), true);
        final present = _session('present');

        expect(ledger.apply([], 0), isEmpty);
        final rows = ledger.apply([present], 0);
        expect(rows.map((row) => row.id), ['present']);
        expect(_metadata(rows.single), _metadata(present));
      },
    );

    for (final archived in [true, false]) {
      test(
        'includeMissing falls back to confirmed row with archived=$archived',
        () async {
          final ledger = SessionArchiveLedger();
          final response = Completer<List<Session>>();
          final pending = _read(ledger, response.future, includeMissing: true);
          final saved = _session(
            'tip',
            root: 'root',
            archived: !archived,
            title: 'Rich confirmed baseline',
          );
          ledger.record(saved, archived);
          final unrelated = _session('unrelated');

          response.complete([unrelated]);
          final rows = await pending;

          expect(rows.map((row) => row.id), ['unrelated', 'tip']);
          expect(rows.last.archived, archived);
          expect(_metadata(rows.last), _metadata(saved));
          expect(saved.archived, !archived);
          expect(
            ledger
                .apply([unrelated], ledger.revision, includeMissing: true)
                .map((row) => row.id),
            ['unrelated'],
            reason: 'a later read omitting the session is authoritative',
          );
          expect(
            ledger.apply([], ledger.revision, includeMissing: true),
            isEmpty,
          );
        },
      );
    }

    test(
      'includeMissing uses only latest conflicting alias and latest metadata',
      () {
        final ledger = SessionArchiveLedger();
        ledger.record(_session('root', title: 'Obsolete root title'), true);
        final latest = _session(
          'tip',
          root: 'root',
          archived: true,
          title: 'Latest confirmed title',
          preview: 'Latest confirmed preview',
          messageCount: 100,
        );
        ledger.record(latest, false);

        final rows = ledger.apply([], 0, includeMissing: true);

        expect(rows, hasLength(1));
        expect(rows.single.id, 'tip');
        expect(rows.single.archived, isFalse);
        expect(_metadata(rows.single), _metadata(latest));
        expect(ledger.changesSince(0), hasLength(1));
      },
    );

    for (final alias in ['root', 'same-tip', 'new-tip']) {
      test(
        'includeMissing keeps fresh $alias metadata without adding old alias',
        () {
          final ledger = SessionArchiveLedger();
          ledger.record(
            _session('same-tip', root: 'root', title: 'Old action metadata'),
            true,
          );
          final fresh = _session(
            alias,
            root: alias == 'root' ? null : 'root',
            title: 'Fresh list/search metadata',
            preview: 'Fresh excerpt not in the action row',
            messageCount: 250,
            lastActive: 1800012345.5,
          );

          final rows = ledger.apply([fresh, fresh], 0, includeMissing: true);

          expect(rows, hasLength(1));
          expect(rows.single.id, alias);
          expect(rows.single.archived, isTrue);
          expect(_metadata(rows.single), _metadata(fresh));
          expect(fresh.archived, isFalse);
        },
      );
    }

    test('includeMissing adds only changes newer than that physical read', () {
      final ledger = SessionArchiveLedger();
      ledger.record(_session('before-read'), true);
      final observedRevision = ledger.revision;
      ledger.record(_session('after-read'), true);

      final rows = ledger.apply([], observedRevision, includeMissing: true);

      expect(rows.map((row) => row.id), ['after-read']);
      expect(rows.single.archived, isTrue);
    });

    test('apply accepts a lazy iterable and never mutates its source', () {
      final ledger = SessionArchiveLedger();
      ledger.record(_session('a'), true);
      final source = [_session('a'), _session('b', archived: true)];
      final rows = ledger.apply(source.where((_) => true), 0);

      expect(rows.map((row) => row.archived), [true, true]);
      expect(source.map((row) => row.archived), [false, true]);
      expect(rows.map(_metadata), source.map(_metadata));
    });
  });
}
