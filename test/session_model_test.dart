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
    });

    test(
      'active session has no end and recent activity falls back to start',
      () {
        final session = Session.fromJson({
          'id': 's2',
          'title': 'Running',
          'started_at': 1750000000.5,
          'last_active': 1750000030.0,
        });

        expect(session.isActive, isTrue);
        expect(session.endedAt, isNull);
        expect(session.lastActive, 1750000030.0);
        expect(session.pinned, isFalse);
        expect(session.archived, isFalse);
      },
    );

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

    test('untitled cron shell is flagged', () {
      final shell = Session.fromJson({
        'id': 'cron-shell',
        'source': 'cron',
        'message_count': 0,
        'started_at': 1750000000.0,
      });

      expect(shell.isUntitledCronShell, isTrue);
    });

    test('titled cron session is not a shell', () {
      final real = Session.fromJson({
        'id': 'cron-real',
        'title': 'Evening brief',
        'source': 'cron',
        'message_count': 12,
        'started_at': 1750000000.0,
      });

      expect(real.isUntitledCronShell, isFalse);
    });
  });
}
