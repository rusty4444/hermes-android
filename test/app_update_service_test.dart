import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One GitHub `releases/latest` payload, shaped like the real one.
String releaseJson({
  String tag = 'v2.1.20',
  String name = 'Hermes Android 2.1.20',
  String body = 'Fixes the chat stream teardown.',
  String url =
      'https://github.com/rusty4444/hermes-android/releases/tag/v2.1.20',
  bool draft = false,
  String? publishedAt = '2026-10-15T09:30:00Z',
}) {
  final buffer = StringBuffer('{');
  buffer.write('"tag_name": ${jsonString(tag)},');
  buffer.write('"name": ${jsonString(name)},');
  buffer.write('"body": ${jsonString(body)},');
  buffer.write('"html_url": ${jsonString(url)},');
  buffer.write('"draft": $draft,');
  buffer.write(
    '"published_at": ${publishedAt == null ? 'null' : jsonString(publishedAt)}',
  );
  buffer.write('}');
  return buffer.toString();
}

String jsonString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('version comparison', () {
    test('orders the dotted tags the project publishes', () {
      expect(compareAppVersions('2.1.19', '2.1.19'), 0);
      expect(compareAppVersions('2.1.20', '2.1.19'), greaterThan(0));
      expect(compareAppVersions('2.1.9', '2.1.19'), lessThan(0));
      expect(compareAppVersions('2.2.0', '2.1.19'), greaterThan(0));
      expect(compareAppVersions('3.0.0', '2.9.9'), greaterThan(0));
    });

    test('ignores the leading tag v and the pubspec +build suffix', () {
      expect(normalizeAppVersion('v2.1.19'), '2.1.19');
      expect(normalizeAppVersion('2.1.19+2159'), '2.1.19');
      expect(normalizeAppVersion('V2.1.19+2159'), '2.1.19');
      expect(isNewerAppVersion('v2.1.20', '2.1.19+2159'), isTrue);
      expect(isNewerAppVersion('v2.1.19', '2.1.19+2159'), isFalse);
    });

    test('treats a missing segment as zero', () {
      expect(compareAppVersions('2.2', '2.2.0'), 0);
      expect(compareAppVersions('2.2', '2.1.9'), greaterThan(0));
    });

    test('sorts a pre-release below the release it precedes', () {
      expect(compareAppVersions('2.1.20-beta.1', '2.1.20'), lessThan(0));
      expect(compareAppVersions('2.1.20', '2.1.20-beta.1'), greaterThan(0));
      // A beta never prompts a stable install to "update" to it.
      expect(isNewerAppVersion('v2.1.20-beta.1', '2.1.19'), isTrue);
      expect(isNewerAppVersion('v2.1.19-beta.1', '2.1.19'), isFalse);
    });

    test('an unparseable version never reads as newer', () {
      expect(isNewerAppVersion('not a version', '2.1.19'), isFalse);
      expect(isNewerAppVersion('v2.1.20', 'not a version'), isTrue);
    });
  });

  group('AppUpdateService.checkForUpdate', () {
    test('reports the published release when it is newer', () async {
      final client = MockClient((request) async {
        expect(
          request.url.path,
          '/repos/rusty4444/hermes-android/releases/latest',
        );
        expect(request.headers['Accept'], 'application/vnd.github+json');
        return http.Response(releaseJson(), 200, headers: {'etag': 'W/"abc"'});
      });
      final service = AppUpdateService(client: client);

      final result = await service.checkForUpdate(currentVersion: '2.1.19');

      expect(result.outcome, AppUpdateOutcome.updateAvailable);
      final release = result.release!;
      expect(release.version, '2.1.20');
      expect(release.tagName, 'v2.1.20');
      expect(release.label, 'Hermes Android 2.1.20');
      expect(release.notes, contains('chat stream'));
      expect(
        release.releaseUrl,
        'https://github.com/rusty4444/hermes-android/releases/tag/v2.1.20',
      );
      expect(release.publishedAt, DateTime.utc(2026, 10, 15, 9, 30));
    });

    test('falls back to the tag when the release has no title', () async {
      final client = MockClient(
        (request) async => http.Response(releaseJson(name: ''), 200),
      );
      final result = await AppUpdateService(
        client: client,
      ).checkForUpdate(currentVersion: '2.1.19');
      expect(result.release!.label, 'v2.1.20');
    });

    test(
      'reports up to date when the published release is not newer',
      () async {
        final client = MockClient(
          (request) async => http.Response(releaseJson(tag: 'v2.1.19'), 200),
        );
        final result = await AppUpdateService(
          client: client,
        ).checkForUpdate(currentVersion: '2.1.19');
        expect(result.outcome, AppUpdateOutcome.upToDate);
        expect(result.hasUpdate, isFalse);
      },
    );

    test('304 reuses the release for an outdated installation', () async {
      var calls = 0;
      final prefs = await SharedPreferences.getInstance();
      final service = AppUpdateService(
        preferences: prefs,
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            expect(request.headers.containsKey('If-None-Match'), isFalse);
            return http.Response(
              releaseJson(),
              200,
              headers: {'etag': 'W/"cached"'},
            );
          }
          expect(request.headers['If-None-Match'], 'W/"cached"');
          return http.Response('', 304);
        }),
      );

      expect(
        (await service.checkForUpdate(currentVersion: '2.1.19')).hasUpdate,
        isTrue,
      );
      final result = await AppUpdateService(
        preferences: prefs,
        client: MockClient((request) async {
          expect(request.headers['If-None-Match'], 'W/"cached"');
          return http.Response('', 304);
        }),
      ).checkForUpdate(currentVersion: '2.1.19', force: true);
      expect(result.hasUpdate, isTrue);
      expect(result.release?.version, '2.1.20');
      expect(result.release?.notes, contains('chat stream'));
    });

    test('orphaned ETag cannot cause a false up-to-date result', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppUpdateService.etagKey, 'W/"orphaned"');
      final service = AppUpdateService(
        preferences: prefs,
        client: MockClient((request) async {
          expect(request.headers.containsKey('If-None-Match'), isFalse);
          return http.Response(releaseJson(), 200);
        }),
      );
      expect(
        (await service.checkForUpdate(currentVersion: '2.1.19')).hasUpdate,
        isTrue,
      );
    });

    test('an answered failure reports failed without throwing', () async {
      final thrown = AppUpdateService(
        client: MockClient((request) async => throw const SocketFailure()),
      );
      expect(
        (await thrown.checkForUpdate(currentVersion: '2.1.19')).outcome,
        AppUpdateOutcome.failed,
      );

      // Answered, so it spent the caller's rate budget and throttles the next
      // check — hence force here.
      final rateLimited = AppUpdateService(
        client: MockClient(
          (request) async =>
              http.Response('{"message":"API rate limit exceeded"}', 403),
        ),
      );
      expect(
        (await rateLimited.checkForUpdate(
          currentVersion: '2.1.19',
          force: true,
        )).outcome,
        AppUpdateOutcome.failed,
      );

      final malformed = AppUpdateService(
        client: MockClient((request) async => http.Response('not json', 200)),
      );
      expect(
        (await malformed.checkForUpdate(
          currentVersion: '2.1.19',
          force: true,
        )).outcome,
        AppUpdateOutcome.failed,
      );
    });

    test('a request that never reached GitHub is retried next launch', () async {
      var calls = 0;
      final service = AppUpdateService(
        client: MockClient((request) async {
          calls += 1;
          if (calls == 1) throw const SocketFailure();
          return http.Response(releaseJson(), 200);
        }),
      );

      // Offline at launch: nothing to say, and nothing charged to the throttle.
      expect(
        (await service.checkForUpdate(currentVersion: '2.1.19')).outcome,
        AppUpdateOutcome.failed,
      );
      // Back online at the next launch: the check actually runs again.
      expect(
        (await service.checkForUpdate(currentVersion: '2.1.19')).outcome,
        AppUpdateOutcome.updateAvailable,
      );
      expect(calls, 2);
    });

    test('a draft release never prompts', () async {
      final client = MockClient(
        (request) async => http.Response(releaseJson(draft: true), 200),
      );
      final result = await AppUpdateService(
        client: client,
      ).checkForUpdate(currentVersion: '2.1.19');
      expect(result.outcome, AppUpdateOutcome.failed);
      expect(result.release, isNull);
    });

    test('throttles repeat checks but honours a forced one', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls += 1;
        return http.Response(releaseJson(), 200);
      });
      final service = AppUpdateService(client: client);

      expect(
        (await service.checkForUpdate(currentVersion: '2.1.19')).outcome,
        AppUpdateOutcome.updateAvailable,
      );
      expect(calls, 1);

      // A second launch inside the interval asks GitHub nothing.
      expect(
        (await service.checkForUpdate(currentVersion: '2.1.19')).outcome,
        AppUpdateOutcome.throttled,
      );
      expect(calls, 1);

      // The manual path is always a real check.
      expect(
        (await service.checkForUpdate(
          currentVersion: '2.1.19',
          force: true,
        )).outcome,
        AppUpdateOutcome.updateAvailable,
      );
      expect(calls, 2);
    });

    test('a check older than the interval is not throttled', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppUpdateService.lastCheckKey,
        DateTime.now()
            .toUtc()
            .subtract(AppUpdateService.checkInterval * 2)
            .toIso8601String(),
      );
      var calls = 0;
      final service = AppUpdateService(
        client: MockClient((request) async {
          calls += 1;
          return http.Response(releaseJson(), 200);
        }),
        preferences: prefs,
      );

      await service.checkForUpdate(currentVersion: '2.1.19');

      expect(calls, 1);
    });

    test('stores the etag for the next conditional request', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = AppUpdateService(
        client: MockClient(
          (request) async =>
              http.Response(releaseJson(), 200, headers: {'etag': 'W/"fresh"'}),
        ),
        preferences: prefs,
      );

      await service.checkForUpdate(currentVersion: '2.1.19');

      expect(prefs.getString(AppUpdateService.etagKey), 'W/"fresh"');
    });
  });

  group('launch prompt policy', () {
    test('prompts when a newer release is published', () async {
      final service = AppUpdateService(
        client: MockClient(
          (request) async => http.Response(releaseJson(), 200),
        ),
      );

      final release = await service.launchPromptRelease(
        currentVersion: '2.1.19',
      );

      expect(release?.version, '2.1.20');
    });

    test('stays silent when the launch check is switched off', () async {
      var calls = 0;
      final service = AppUpdateService(
        client: MockClient((request) async {
          calls += 1;
          return http.Response(releaseJson(), 200);
        }),
      );
      await service.setCheckOnLaunchEnabled(false);

      expect(
        await service.launchPromptRelease(currentVersion: '2.1.19'),
        isNull,
      );
      expect(calls, 0);
    });

    test('stays silent for a version the user skipped', () async {
      final service = AppUpdateService(
        client: MockClient(
          (request) async => http.Response(releaseJson(), 200),
        ),
      );
      await service.skipVersion('2.1.20');

      expect(
        await service.launchPromptRelease(currentVersion: '2.1.19'),
        isNull,
      );
    });

    test('a new release after a skip prompts again', () async {
      final service = AppUpdateService(
        client: MockClient(
          (request) async => http.Response(releaseJson(tag: 'v2.1.21'), 200),
        ),
      );
      await service.skipVersion('2.1.20');

      final release = await service.launchPromptRelease(
        currentVersion: '2.1.19',
      );

      expect(release?.version, '2.1.21');
    });

    test(
      'stays silent when the install is current or the check failed',
      () async {
        final current = AppUpdateService(
          client: MockClient(
            (request) async => http.Response(releaseJson(tag: 'v2.1.19'), 200),
          ),
        );
        expect(
          await current.launchPromptRelease(currentVersion: '2.1.19'),
          isNull,
        );

        final offline = AppUpdateService(
          client: MockClient((request) async => throw const SocketFailure()),
        );
        expect(
          await offline.launchPromptRelease(currentVersion: '2.1.19'),
          isNull,
        );
      },
    );
  });

  group('preferences', () {
    test('backups retain update choices but not transient HTTP cache', () {
      expect(
        ConfigBackupService.isBackedUpKey(AppUpdateService.checkOnLaunchKey),
        isTrue,
      );
      expect(
        ConfigBackupService.isBackedUpKey(AppUpdateService.skippedVersionKey),
        isTrue,
      );
      expect(
        ConfigBackupService.isBackedUpKey(AppUpdateService.cachedReleaseKey),
        isFalse,
      );
      expect(
        ConfigBackupService.isBackedUpKey(AppUpdateService.etagKey),
        isFalse,
      );
    });
    test('launch checks are on until the user turns them off', () async {
      final service = AppUpdateService();
      expect(await service.checkOnLaunchEnabled(), isTrue);
      await service.setCheckOnLaunchEnabled(false);
      expect(await service.checkOnLaunchEnabled(), isFalse);
    });

    test('skip bookkeeping normalises and clears', () async {
      final service = AppUpdateService();
      expect(await service.skippedVersion(), isNull);

      await service.skipVersion('v2.1.20+2159');

      expect(await service.skippedVersion(), '2.1.20');
      await service.clearSkippedVersion();
      expect(await service.skippedVersion(), isNull);
    });
  });
}

/// Stands in for the client-side network failures that surface as exceptions.
class SocketFailure implements Exception {
  const SocketFailure();
}
