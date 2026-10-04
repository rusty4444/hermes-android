import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';

void main() {
  group('Session.fromJson', () {
    test('parses the gateway session payload', () {
      final session = Session.fromJson({
        'id': 's1',
        'title': 'Daily driver',
        'model': 'gpt-oss-20b',
        'source': 'gateway',
        'message_count': 2,
        'started_at': 1750000000.5,
        'ended_at': 1750000100.0,
        'preview': 'hello',
        'last_active': 1750000090.25,
        'pinned': true,
        'archived': false,
      });

      expect(session.id, 's1');
      expect(session.title, 'Daily driver');
      expect(session.isActive, isFalse);
      expect(session.lastActive, 1750000090.25);
      expect(session.pinned, isTrue);
      expect(session.archived, isFalse);
      expect(session.isLocalDraft, isFalse);
    });

    test('gateway JSON cannot opt a server session into draft routing', () {
      final session = Session.fromJson({
        'id': 'server-existing',
        'title': 'Existing chat',
        'started_at': 1750000000.5,
        'is_local_draft': true,
      });

      expect(session.isLocalDraft, isFalse);
    });

    test(
      'un-ended session with recent activity is active (recency fallback)',
      () {
        final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final session = Session.fromJson({
          'id': 's2',
          'title': 'Running',
          'started_at': nowSeconds - 3600,
          'last_active': nowSeconds - 30,
        });

        expect(session.isActive, isTrue);
        expect(session.endedAt, isNull);
        expect(session.lastActive, nowSeconds - 30);
        expect(session.pinned, isFalse);
        expect(session.archived, isFalse);
      },
    );

    test(
      'un-ended session with stale activity is idle (recency fallback)',
      () {
        // Regression: the Gateway never sets `ended_at` for sessions that
        // finished their work, so without the recency window every old chat
        // kept showing as running.
        final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000.0;
        final session = Session.fromJson({
          'id': 's7',
          'title': 'Long finished',
          'started_at': nowSeconds - 172800,
          'last_active': nowSeconds - 172800,
        });

        expect(session.isActive, isFalse);
        expect(session.endedAt, isNull);
      },
    );

    test('an ended session is never active, even with fresh activity', () {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final session = Session.fromJson({
        'id': 's8',
        'title': 'Ended recently',
        'started_at': nowSeconds - 3600,
        'ended_at': nowSeconds - 100,
        'last_active': nowSeconds - 10,
      });

      expect(session.isActive, isFalse);
    });

    test('lastActive falls back to startedAt when absent', () {
      final session = Session.fromJson({
        'id': 's3',
        'title': 'Legacy',
        'started_at': 1750000000.5,
      });

      expect(session.lastActive, 1750000000.5);
    });

    test('archived sessions are parsed', () {
      final session = Session.fromJson({
        'id': 's4',
        'title': 'Old',
        'started_at': 1740000000.0,
        'archived': true,
      });

      expect(session.archived, isTrue);
      expect(session.lastActive, 1740000000.0);
    });

    test(
      'is_active:false marks a finished session idle even without ended_at',
      () {
        // Regression: the Gateway keeps `ended_at` null for sessions that
        // are done but not explicitly ended; liveness comes from `is_active`.
        // Using ended_at alone showed every finished session as running.
        final session = Session.fromJson({
          'id': 's5',
          'title': 'Finished test session',
          'started_at': 1750000000.5,
          'ended_at': null,
          'is_active': false,
        });

        expect(session.isActive, isFalse);
      },
    );

    test('is_active:true wins over an absent ended_at', () {
      final session = Session.fromJson({
        'id': 's6',
        'title': 'Live now',
        'started_at': 1750000000.5,
        'is_active': true,
      });

      expect(session.isActive, isTrue);
    });
  });
}
