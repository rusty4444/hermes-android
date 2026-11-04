// Shared cron job-definition parsing (issue #259).
//
// These are the contract tests for the helper both the Cron manager and the
// Workspace Crons → Upcoming pane read records through, so the two surfaces
// cannot disagree about a schedule — above all about which timezone a
// next-run time is expressed in.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/utils/cron_schedule.dart';
import 'package:hermes_android/core/widgets/cron_schedule_labels.dart';
import 'package:http/http.dart' as http;

void main() {
  group('next-run timezone', () {
    test('an offset timestamp keeps the server wall clock and its zone', () {
      final next = cronNextRun({'next_run_at': '2026-11-09T09:00:00+11:00'})!;
      expect(next.zoneSource, CronZoneSource.utcOffset);
      expect(next.utcOffset, const Duration(hours: 11));
      expect(next.wallClockLabel, '2026-11-09 09:00');
      expect(next.zoneLabel, 'UTC+11:00');
    });

    test('a Z timestamp is labelled UTC, not converted to device local', () {
      final next = cronNextRun({'next_run_at': '2026-11-09T22:00:00Z'})!;
      expect(next.zoneSource, CronZoneSource.utcOffset);
      expect(next.wallClockLabel, '2026-11-09 22:00');
      expect(next.zoneLabel, 'UTC');
    });

    test('a negative half-hour offset renders exactly', () {
      final next = cronNextRun({'next_run_at': '2026-11-09T09:00:00-05:30'})!;
      expect(next.zoneLabel, 'UTC-05:30');
      expect(next.utcOffset, const Duration(hours: -5, minutes: -30));
    });

    test('a zone-less timestamp reports an unknown zone, never local', () {
      final next = cronNextRun({'next_run_at': '2026-11-09T09:00:00'})!;
      expect(next.zoneSource, CronZoneSource.unknown);
      expect(next.utcOffset, isNull);
      expect(next.zoneLabel, isNull);
      expect(next.wallClockLabel, '2026-11-09 09:00');
    });

    test('a named zone in the payload wins over the bare offset', () {
      final next = cronNextRun({
        'next_run_at': '2026-11-09T09:00:00+11:00',
        'timezone': 'Australia/Sydney',
      })!;
      expect(next.zoneSource, CronZoneSource.zoneName);
      expect(next.zoneLabel, 'Australia/Sydney');
    });

    test('a nested schedule zone is read too', () {
      final next = cronNextRun({
        'next_run_at': '2026-11-09T09:00:00+11:00',
        'schedule': {'tz': 'Europe/Berlin'},
      })!;
      expect(next.zoneLabel, 'Europe/Berlin');
    });

    test('an unparseable timestamp is preserved verbatim', () {
      final next = cronNextRun({'next_run_at': 'soonish'})!;
      expect(next.zoneSource, CronZoneSource.unknown);
      expect(next.wallClockLabel, 'soonish');
    });

    test('absent and empty next-run fields are no next run', () {
      expect(cronNextRun(<String, dynamic>{}), isNull);
      expect(cronNextRun({'next_run_at': null}), isNull);
      expect(cronNextRun({'next_run_at': '  '}), isNull);
      expect(cronLastRun({'last_run_at': null}), isNull);
    });

    test('ordering uses the real instant when the offset is known', () {
      final sydney = cronNextRun({'next_run_at': '2026-11-09T09:00:00+11:00'})!;
      final utc = cronNextRun({'next_run_at': '2026-11-08T23:00:00Z'})!;
      // 09:00+11:00 is 22:00Z the previous day, so it is the earlier instant.
      expect(sydney.orderingKey.isBefore(utc.orderingKey), isTrue);
    });
  });

  group('job fields', () {
    test(
      'schedule display prefers the host rendering, then the expression',
      () {
        expect(
          cronScheduleDisplay({'schedule_display': 'every monday 9am'}),
          'every monday 9am',
        );
        expect(
          cronScheduleDisplay({
            'schedule': {'kind': 'cron', 'expr': '0 9 * * 1'},
          }),
          '0 9 * * 1',
        );
        expect(cronScheduleDisplay({'schedule': '30m'}), '30m');
        expect(cronScheduleDisplay(<String, dynamic>{}), '');
      },
    );

    test('paused covers every shape the host persists', () {
      expect(cronJobPaused({'state': 'paused'}), isTrue);
      expect(cronJobPaused({'paused_at': '2026-11-01T00:00:00Z'}), isTrue);
      expect(cronJobPaused({'enabled': false}), isTrue);
      expect(cronJobPaused({'enabled': true, 'state': 'scheduled'}), isFalse);
    });

    test('name falls back to the id, then to the supplied label', () {
      expect(
        cronJobName({'name': 'Weekly report'}, fallback: 'x'),
        'Weekly report',
      );
      expect(cronJobName({'id': 'abc123'}, fallback: 'x'), 'abc123');
      expect(cronJobName(<String, dynamic>{}, fallback: 'x'), 'x');
    });

    test('prompt previews are bounded', () {
      expect(cronJobPromptPreview({'prompt': 'short'}), 'short');
      expect(cronJobPromptPreview({'prompt': 'a' * 200}).length, 121);
    });

    group('delivery target', () {
      test('an explicit platform:chat target is shown as sent', () {
        expect(
          cronDeliveryTarget({'deliver': 'telegram:4242'}),
          'telegram:4242',
        );
      });

      test('origin delivery names the originating conversation', () {
        expect(
          cronDeliveryTarget({
            'deliver': 'origin',
            'origin': {
              'platform': 'telegram',
              'chat_id': 7,
              'chat_name': 'Ops',
            },
          }),
          'Ops',
        );
        expect(
          cronDeliveryTarget({
            'deliver': 'origin',
            'origin': {'platform': 'slack', 'chat_id': 'C01'},
          }),
          'slack:C01',
        );
      });

      test('a local run has no conversation target', () {
        expect(cronDeliveryTarget({'deliver': 'local'}), isNull);
        expect(cronDeliveryTarget(<String, dynamic>{}), isNull);
      });
    });
  });

  group('partitioning', () {
    test('jobs with a next run sort ascending ahead of jobs without one', () {
      final jobs = <Map<String, dynamic>>[
        {'name': 'later', 'next_run_at': '2026-11-20T09:00:00+11:00'},
        {'name': 'paused', 'next_run_at': null, 'state': 'paused'},
        {'name': 'sooner', 'next_run_at': '2026-11-09T09:00:00+11:00'},
        {'name': 'finished', 'state': 'completed'},
      ];
      final split = partitionCronJobs(jobs);
      expect(split.upcoming.map((job) => job['name']), ['sooner', 'later']);
      // Nothing is hidden: a paused job and a finished one-off are still
      // real schedule entries.
      expect(split.inactive.map((job) => job['name']), ['paused', 'finished']);
    });
  });

  group('failure classification', () {
    test('a 404 from the cron route means no dashboard cron capability', () {
      expect(
        classifyCronScheduleFailure(const DashboardHttpException(404)),
        CronScheduleFailure.needsDashboard,
      );
      expect(
        classifyCronScheduleFailure(const DashboardHttpException(501)),
        CronScheduleFailure.needsDashboard,
      );
    });

    test('an API-only origin with no dashboard homepage needs a Dashboard', () {
      expect(
        classifyCronScheduleFailure(
          const DashboardAuthUnavailableException(
            'Dashboard not reachable',
            statusCode: 404,
          ),
        ),
        CronScheduleFailure.needsDashboard,
      );
    });

    test('a gated dashboard with no usable credentials needs auth', () {
      expect(
        classifyCronScheduleFailure(const DashboardHttpException(401)),
        CronScheduleFailure.needsDashboardAuth,
      );
      expect(
        classifyCronScheduleFailure(
          const DashboardAuthUnavailableException('Session token not found'),
        ),
        CronScheduleFailure.needsDashboardAuth,
      );
    });

    test('transport faults are unreachable, not unsupported', () {
      expect(
        classifyCronScheduleFailure(const SocketException('refused')),
        CronScheduleFailure.unreachable,
      );
      expect(
        classifyCronScheduleFailure(TimeoutException('slow')),
        CronScheduleFailure.unreachable,
      );
      expect(
        classifyCronScheduleFailure(http.ClientException('broken')),
        CronScheduleFailure.unreachable,
      );
      expect(
        classifyCronScheduleFailure(
          const DashboardAuthUnavailableException(
            'Dashboard not reachable',
            statusCode: 502,
          ),
        ),
        CronScheduleFailure.unreachable,
      );
    });

    test('an unknown failure is not dressed up as a capability gap', () {
      expect(
        classifyCronScheduleFailure(const DashboardHttpException(500)),
        CronScheduleFailure.unknown,
      );
      expect(
        classifyCronScheduleFailure(StateError('bad shape')),
        CronScheduleFailure.unknown,
      );
      expect(isCronCapabilityFailure(CronScheduleFailure.unknown), isFalse);
      expect(
        isCronCapabilityFailure(CronScheduleFailure.needsDashboard),
        isTrue,
      );
    });
  });
}
