import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A published Hermes Android release, read from the project's GitHub Releases.
class AppReleaseInfo {
  const AppReleaseInfo({
    required this.version,
    required this.tagName,
    required this.releaseUrl,
    this.name = '',
    this.notes = '',
    this.publishedAt,
  });

  /// The version the app compares against its own, normalised: no leading `v`,
  /// no `+build` suffix (`v2.1.19+2159` becomes `2.1.19`).
  final String version;

  /// The tag exactly as published (`v2.1.19`), the fallback label for a release
  /// whose owner left the title empty.
  final String tagName;

  /// The release page the prompt navigates to.
  final String releaseUrl;

  /// The release title, empty when the release has none.
  final String name;

  /// Release notes as markdown, empty when the release has none.
  final String notes;

  final DateTime? publishedAt;

  /// What to call this release in the prompt.
  String get label => name.isNotEmpty ? name : tagName;
}

/// What a check found.
enum AppUpdateOutcome {
  /// A release newer than the installed build is published.
  updateAvailable,

  /// The installed build is current.
  upToDate,

  /// Not checked: the previous attempt is inside [AppUpdateService.checkInterval].
  throttled,

  /// GitHub Releases could not be reached or did not answer with a release.
  failed,
}

/// The outcome of one check, with the release when there is one.
class AppUpdateResult {
  const AppUpdateResult(this.outcome, {this.release});

  final AppUpdateOutcome outcome;
  final AppReleaseInfo? release;

  bool get hasUpdate =>
      outcome == AppUpdateOutcome.updateAvailable && release != null;
}

/// Strips the leading `v`/`V` and any `+build` metadata from a version string.
///
/// Release tags and `pubspec.yaml` disagree on shape — the tag is `v2.1.19`,
/// package_info reports `2.1.19` for a `2.1.19+2159` build — so both sides are
/// normalised before they are compared.
String normalizeAppVersion(String version) {
  var value = version.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  final buildIndex = value.indexOf('+');
  if (buildIndex >= 0) value = value.substring(0, buildIndex);
  return value.trim();
}

/// Compares two dotted numeric versions, newest last: returns a positive number
/// when [a] is newer than [b], negative when older, zero when they match.
///
/// Deliberately small: the project tags plain `vMAJOR.MINOR.PATCH`, so only the
/// leading digits of each dotted segment are compared and a missing segment
/// counts as zero (`2.2` equals `2.2.0`). A pre-release suffix (`2.2.0-beta.1`)
/// sorts *below* the release it precedes, so a beta tag never prompts a stable
/// install to "update".
int compareAppVersions(String a, String b) {
  final left = _versionParts(normalizeAppVersion(a));
  final right = _versionParts(normalizeAppVersion(b));
  final length = left.numbers.length > right.numbers.length
      ? left.numbers.length
      : right.numbers.length;
  for (var index = 0; index < length; index += 1) {
    final leftPart = index < left.numbers.length ? left.numbers[index] : 0;
    final rightPart = index < right.numbers.length ? right.numbers[index] : 0;
    if (leftPart != rightPart) return leftPart > rightPart ? 1 : -1;
  }
  if (left.preRelease == right.preRelease) return 0;
  if (left.preRelease == null) return 1;
  if (right.preRelease == null) return -1;
  return left.preRelease!.compareTo(right.preRelease!);
}

/// Whether [candidate] is a release the installed [current] build has not seen.
bool isNewerAppVersion(String candidate, String current) =>
    compareAppVersions(candidate, current) > 0;

class _VersionParts {
  const _VersionParts(this.numbers, this.preRelease);

  final List<int> numbers;
  final String? preRelease;
}

_VersionParts _versionParts(String version) {
  var core = version;
  String? preRelease;
  final preReleaseIndex = core.indexOf('-');
  if (preReleaseIndex >= 0) {
    preRelease = core.substring(preReleaseIndex + 1);
    core = core.substring(0, preReleaseIndex);
  }
  final numbers = <int>[];
  for (final segment in core.split('.')) {
    final digits = RegExp(r'^\d+').stringMatch(segment);
    numbers.add(digits == null ? 0 : int.parse(digits));
  }
  return _VersionParts(numbers, preRelease);
}

/// The installed app version (`2.1.19` for a `2.1.19+2159` build), or null when
/// the platform cannot report it — a test, or a host without the plugin.
Future<String?> installedAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return normalizeAppVersion(info.version);
  } catch (_) {
    return null;
  }
}

/// Checks GitHub Releases for a newer Hermes Android build.
///
/// The check is advisory and must never be able to break a launch: every
/// failure — offline, rate-limited, malformed JSON — is reported as
/// [AppUpdateOutcome.failed] instead of thrown, and repeat attempts are
/// throttled so offline launches do not hammer GitHub.
class AppUpdateService {
  /// [client] and [preferences] are injectable so tests can drive the check
  /// against a fake GitHub and a mock store; the app passes neither.
  AppUpdateService({http.Client? client, SharedPreferences? preferences}) {
    _client = client;
    _preferences = preferences;
  }

  /// The upstream project whose releases the app follows.
  static const releasesApiUrl =
      'https://api.github.com/repos/rusty4444/hermes-android/releases/latest';

  /// How long a check counts for. GitHub answers unauthenticated callers on a
  /// per-IP budget, and a launch several times an hour must not spend it.
  static const checkInterval = Duration(hours: 12);

  static const requestTimeout = Duration(seconds: 10);

  static const lastCheckKey = 'app_update_last_check_v1';
  static const etagKey = 'app_update_etag_v1';
  static const cachedReleaseKey = 'app_update_cached_release_v1';
  static const skippedVersionKey = 'app_update_skipped_version_v1';
  static const checkOnLaunchKey = 'app_update_check_on_launch_v1';

  http.Client? _client;
  SharedPreferences? _preferences;

  http.Client get _http => _client ??= http.Client();

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? await SharedPreferences.getInstance();

  /// Runs a check. Throttled unless [force] is set (the manual, user-initiated
  /// path); [currentVersion] is the installed version, e.g. `2.1.19`.
  Future<AppUpdateResult> checkForUpdate({
    required String currentVersion,
    bool force = false,
  }) async {
    final preferences = await _prefs;
    if (!force && await _isThrottled(preferences)) {
      return const AppUpdateResult(AppUpdateOutcome.throttled);
    }
    try {
      final headers = <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'hermes-android',
      };
      final cachedRelease = _cachedRelease(preferences);
      final etag = cachedRelease == null
          ? null
          : preferences.getString(etagKey);
      // A 304 is useful only when we retained the release it refers to.
      if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
      final response = await _http
          .get(Uri.parse(releasesApiUrl), headers: headers)
          .timeout(requestTimeout);
      await _recordCheck(preferences);
      if (response.statusCode == 304) {
        return cachedRelease == null
            ? const AppUpdateResult(AppUpdateOutcome.failed)
            : _compareRelease(cachedRelease, currentVersion);
      }
      if (response.statusCode != 200) {
        await _clearCachedRelease(preferences);
        return const AppUpdateResult(AppUpdateOutcome.failed);
      }
      final release = parseRelease(response.body);
      if (release == null) {
        await _clearCachedRelease(preferences);
        return const AppUpdateResult(AppUpdateOutcome.failed);
      }
      // Persist validated metadata before its ETag: the pair must survive
      // restarts for a 304 to have the same meaning as the original 200.
      await preferences.setString(cachedReleaseKey, response.body);
      final responseEtag = response.headers['etag'];
      if (responseEtag != null && responseEtag.isNotEmpty) {
        await preferences.setString(etagKey, responseEtag);
      } else {
        await preferences.remove(etagKey);
      }
      return _compareRelease(release, currentVersion);
    } catch (_) {
      // Offline, DNS failure, timeout: the attempt never reached GitHub, so it
      // is not charged to the throttle — the next launch may try again. A
      // rate-limited or malformed *answer* is a different story and throttles
      // above, because that request did spend the caller's budget.
      return const AppUpdateResult(AppUpdateOutcome.failed);
    }
  }

  /// The release worth prompting about at launch, or null when there is nothing
  /// to say — the check is switched off, found nothing, or
  /// names a version the user already skipped.
  ///
  /// Kept here rather than in the widget so the whole launch policy — enabled,
  /// throttled, newer, skipped — is one testable decision.
  Future<AppReleaseInfo?> launchPromptRelease({
    required String currentVersion,
  }) async {
    if (!await checkOnLaunchEnabled()) return null;
    final result = await checkForUpdate(currentVersion: currentVersion);
    // Throttling applies to the network, not to presentation: "Later" should
    // prompt on the next launch even when no second request is due yet.
    final release = result.outcome == AppUpdateOutcome.throttled
        ? _cachedRelease(await _prefs)
        : result.release;
    if (release == null ||
        !isNewerAppVersion(release.version, currentVersion)) {
      return null;
    }
    final skipped = await skippedVersion();
    if (skipped != null && normalizeAppVersion(skipped) == release.version) {
      return null;
    }
    return release;
  }

  Future<bool> checkOnLaunchEnabled() async =>
      (await _prefs).getBool(checkOnLaunchKey) ?? true;

  Future<void> setCheckOnLaunchEnabled(bool enabled) async {
    final preferences = await _prefs;
    await preferences.setBool(checkOnLaunchKey, enabled);
  }

  /// The version the user asked not to be told about again, if any.
  Future<String?> skippedVersion() async =>
      (await _prefs).getString(skippedVersionKey);

  Future<void> skipVersion(String version) async {
    final preferences = await _prefs;
    await preferences.setString(
      skippedVersionKey,
      normalizeAppVersion(version),
    );
  }

  Future<void> clearSkippedVersion() async {
    final preferences = await _prefs;
    await preferences.remove(skippedVersionKey);
  }

  AppUpdateResult _compareRelease(
    AppReleaseInfo release,
    String currentVersion,
  ) => isNewerAppVersion(release.version, currentVersion)
      ? AppUpdateResult(AppUpdateOutcome.updateAvailable, release: release)
      : const AppUpdateResult(AppUpdateOutcome.upToDate);

  AppReleaseInfo? _cachedRelease(SharedPreferences preferences) {
    final raw = preferences.getString(cachedReleaseKey);
    return raw == null ? null : parseRelease(raw);
  }

  Future<void> _clearCachedRelease(SharedPreferences preferences) async {
    await preferences.remove(cachedReleaseKey);
    await preferences.remove(etagKey);
  }

  Future<bool> _isThrottled(SharedPreferences preferences) async {
    final raw = preferences.getString(lastCheckKey);
    final lastCheck = raw == null ? null : DateTime.tryParse(raw);
    if (lastCheck == null) return false;
    final elapsed = DateTime.now().toUtc().difference(lastCheck.toUtc());
    return elapsed >= Duration.zero && elapsed < checkInterval;
  }

  Future<void> _recordCheck(SharedPreferences preferences) => preferences
      .setString(lastCheckKey, DateTime.now().toUtc().toIso8601String());

  /// Parses the GitHub release payload, or null when it is not a usable release
  /// (a draft, a tag without a page, malformed JSON).
  ///
  /// A draft is what an unauthenticated caller sees for a release being
  /// prepared, and it must never prompt.
  static AppReleaseInfo? parseRelease(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['draft'] == true) return null;
    final tag = decoded['tag_name'];
    final url = decoded['html_url'];
    if (tag is! String || tag.trim().isEmpty) return null;
    if (url is! String || url.trim().isEmpty) return null;
    final publishedAt = decoded['published_at'];
    return AppReleaseInfo(
      version: normalizeAppVersion(tag),
      tagName: tag.trim(),
      releaseUrl: url.trim(),
      name: (decoded['name'] as String?)?.trim() ?? '',
      notes: (decoded['body'] as String?) ?? '',
      publishedAt: publishedAt is String
          ? DateTime.tryParse(publishedAt)?.toUtc()
          : null,
    );
  }
}
