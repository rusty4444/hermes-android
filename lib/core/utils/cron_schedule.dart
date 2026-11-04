/// Shared parsing for Hermes cron job *definitions*.
///
/// `GET /api/cron/jobs` returns the scheduler's own records (see the host's
/// `cron/jobs.py` and `hermes_cli/web_routers/cron.py`):
///
/// ```json
/// {"id": "...", "name": "...", "prompt": "...", "schedule": {"kind": "cron",
///  "expr": "0 9 * * 1", "display": "every monday 9am"},
///  "schedule_display": "every monday 9am", "enabled": true,
///  "state": "scheduled", "paused_at": null, "last_run_at": null,
///  "next_run_at": "2026-11-09T09:00:00+11:00", "deliver": "local",
///  "origin": {"platform": "telegram", "chat_id": 42}}
/// ```
///
/// Two screens read those records — the Cron manager (`CronScreen`) and the
/// Workspace **Crons → Upcoming** pane — so the field semantics live here
/// once rather than being re-derived, and differently, in each place.
///
/// ## Timezone honesty
///
/// The record carries **no IANA timezone field**. `next_run_at` /
/// `last_run_at` are ISO-8601 strings produced from timezone-aware datetimes
/// in the host's configured Hermes timezone, so the zone information they
/// carry is a numeric UTC offset (`+11:00`, `Z`). This parser therefore keeps
/// the server's wall clock *and* its offset, and labels the value with that
/// offset. It never converts into the device's local zone, and when a
/// timestamp arrives with no zone at all it reports
/// [CronZoneSource.unknown] so the UI can say so instead of implying the
/// phone's zone is the schedule's zone. [CronTimestamp.zoneName] is read from
/// optional `timezone` / `tz` fields so a future host that does supply a named
/// zone is believed; today's host does not send one.
library;

/// Where the zone shown beside a cron timestamp came from.
enum CronZoneSource {
  /// The record named the schedule's zone explicitly.
  zoneName,

  /// The timestamp carried an explicit UTC offset (including `Z`).
  utcOffset,

  /// The timestamp carried no zone. The value is presented verbatim and the
  /// UI must say the zone is unknown rather than assume device-local time.
  unknown,
}

/// One parsed cron timestamp, with the zone it is actually expressed in.
class CronTimestamp {
  /// Exactly what the server sent, so nothing is ever silently dropped.
  final String raw;

  /// The schedule's own wall clock, when the string was parseable.
  ///
  /// The fields (year, month, day, hour, minute) are the server's wall clock;
  /// this is deliberately **not** an instant in the device's zone.
  final DateTime? wallClock;

  /// The UTC offset the server sent, when it sent one.
  final Duration? utcOffset;

  /// A named zone, when the record supplied one.
  final String? zoneName;

  final CronZoneSource zoneSource;

  const CronTimestamp({
    required this.raw,
    required this.wallClock,
    required this.utcOffset,
    required this.zoneName,
    required this.zoneSource,
  });

  /// A label for the zone, or null when the zone is unknown.
  String? get zoneLabel {
    // The clock is expressed in the timestamp's numeric offset, not
    // necessarily in the job's named schedule zone (hosts may serialize UTC).
    final offset = utcOffset;
    if (offset != null) return formatUtcOffset(offset);
    return zoneName;
  }

  /// The wall clock rendered for display, or the raw string when unparseable.
  String get wallClockLabel {
    final clock = wallClock;
    if (clock == null) return raw;
    return formatCronWallClock(clock);
  }

  /// A comparable key for ordering only.
  ///
  /// With a known offset this is the real instant. Without one the wall clock
  /// is used as-is, which orders zone-less legacy rows sensibly among
  /// themselves without claiming to know their instant.
  DateTime get orderingKey {
    final clock = wallClock;
    if (clock == null) return DateTime.utc(9999);
    final wall = DateTime.utc(
      clock.year,
      clock.month,
      clock.day,
      clock.hour,
      clock.minute,
      clock.second,
    );
    final offset = utcOffset;
    if (offset == null) return wall;
    return wall.subtract(offset);
  }
}

final RegExp _isoPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt ]'
  r'(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?'
  r'\s*(?:(Z|z)|([+-])(\d{2}):?(\d{2}))?$',
);

/// Formats a UTC offset the way a person reads it: `UTC`, `UTC+11:00`.
String formatUtcOffset(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final sign = offset.isNegative ? '-' : '+';
  final total = offset.abs();
  final hours = total.inHours.toString().padLeft(2, '0');
  final minutes = (total.inMinutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

/// Renders a schedule wall clock in a locale-neutral, unambiguous form.
///
/// Deliberately numeric: this value is always shown beside an explicit zone
/// label, and a fixed `YYYY-MM-DD HH:MM` cannot be misread as the device's
/// idea of the date.
String formatCronWallClock(DateTime wallClock) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${wallClock.year}-${two(wallClock.month)}-${two(wallClock.day)} '
      '${two(wallClock.hour)}:${two(wallClock.minute)}';
}

/// Reads a named zone from the record, when the host supplies one.
String? cronJobZoneName(Map<String, dynamic> job) {
  for (final value in [job['timezone'], job['tz']]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  final schedule = job['schedule'];
  if (schedule is Map) {
    for (final value in [schedule['timezone'], schedule['tz']]) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
  }
  return null;
}

/// Parses one ISO-8601 cron timestamp, keeping the zone the server expressed
/// it in. Returns null when the field is absent or empty.
CronTimestamp? parseCronTimestamp(String? value, {String? zoneName}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final match = _isoPattern.firstMatch(raw);
  if (match == null) {
    return CronTimestamp(
      raw: raw,
      wallClock: null,
      utcOffset: null,
      zoneName: zoneName,
      zoneSource: zoneName == null
          ? CronZoneSource.unknown
          : CronZoneSource.zoneName,
    );
  }
  // UTC is only a container for wall-clock fields: constructing local time
  // would normalize a server clock through the device's DST rules.
  final wallClock = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
  Duration? offset;
  if (match.group(7) != null) {
    offset = Duration.zero;
  } else if (match.group(8) != null) {
    final magnitude = Duration(
      hours: int.parse(match.group(9)!),
      minutes: int.parse(match.group(10)!),
    );
    offset = match.group(8) == '-' ? -magnitude : magnitude;
  }
  final CronZoneSource source;
  if (zoneName != null && zoneName.isNotEmpty) {
    source = CronZoneSource.zoneName;
  } else if (offset != null) {
    source = CronZoneSource.utcOffset;
  } else {
    source = CronZoneSource.unknown;
  }
  return CronTimestamp(
    raw: raw,
    wallClock: wallClock,
    utcOffset: offset,
    zoneName: zoneName,
    zoneSource: source,
  );
}

/// The job's next scheduled run, or null when it has none (paused jobs and
/// finished one-offs carry `next_run_at: null`).
CronTimestamp? cronNextRun(Map<String, dynamic> job) => parseCronTimestamp(
  job['next_run_at'] as String?,
  zoneName: cronJobZoneName(job),
);

/// The job's most recent run, or null when it has never run.
CronTimestamp? cronLastRun(Map<String, dynamic> job) => parseCronTimestamp(
  job['last_run_at'] as String?,
  zoneName: cronJobZoneName(job),
);

/// The human schedule description, preferring the host's own rendering.
String cronScheduleDisplay(Map<String, dynamic> job) {
  final display = job['schedule_display'] as String?;
  if (display != null && display.isNotEmpty) return display;

  final schedule = job['schedule'];
  if (schedule is String) return schedule;
  if (schedule is Map) {
    return schedule['display'] as String? ??
        schedule['expr'] as String? ??
        schedule['run_at'] as String? ??
        schedule.toString();
  }
  return '';
}

/// Whether the scheduler will skip this job.
bool cronJobPaused(Map<String, dynamic> job) =>
    job['paused_at'] != null ||
    job['state'] == 'paused' ||
    job['enabled'] == false;

/// The job's display name, falling back to its id.
String cronJobName(Map<String, dynamic> job, {required String fallback}) {
  final name = job['name'] as String?;
  if (name != null && name.trim().isNotEmpty) return name.trim();
  final id = job['id'] as String?;
  if (id != null && id.trim().isNotEmpty) return id.trim();
  return fallback;
}

/// A bounded preview of the job's prompt.
String cronJobPromptPreview(Map<String, dynamic> job, {int limit = 120}) {
  final prompt = job['prompt'] as String? ?? '';
  if (prompt.length > limit) return '${prompt.substring(0, limit)}…';
  return prompt;
}

/// The conversation this job delivers into, when the record names one.
///
/// `deliver` is the host's delivery target: `local` (no conversation —
/// returns null), `origin` (the conversation the job was created in, named by
/// `origin`), a bare platform, or an explicit `platform:chat`. Nothing is
/// inferred beyond what the payload states.
String? cronDeliveryTarget(Map<String, dynamic> job) {
  String? originLabel;
  final origin = job['origin'];
  if (origin is Map) {
    final chatName = (origin['chat_name'] as String?)?.trim();
    final platform = (origin['platform'] as String?)?.trim();
    final chatId = origin['chat_id']?.toString().trim() ?? '';
    if (chatName != null && chatName.isNotEmpty) {
      originLabel = chatName;
    } else if (platform != null && platform.isNotEmpty && chatId.isNotEmpty) {
      originLabel = '$platform:$chatId';
    } else if (platform != null && platform.isNotEmpty) {
      originLabel = platform;
    }
  }

  final deliver = job['deliver'];
  if (deliver is String) {
    final trimmed = deliver.trim();
    if (trimmed.isEmpty) return originLabel;
    final lower = trimmed.toLowerCase();
    // A local run has no conversation target; saying "delivers to local" on
    // every job would be noise, not information.
    if (lower == 'local') return null;
    if (lower == 'origin') return originLabel;
    return trimmed;
  }
  return originLabel;
}

/// Splits job definitions into the ones that will run again and the ones that
/// have no next run. Upcoming jobs are ordered earliest-next-run first.
///
/// The second group is never hidden: a paused job and a finished one-off are
/// still real schedule entries, and dropping them would repeat the defect
/// this split exists to fix.
({List<Map<String, dynamic>> upcoming, List<Map<String, dynamic>> inactive})
partitionCronJobs(List<Map<String, dynamic>> jobs) {
  final upcoming = <Map<String, dynamic>>[];
  final inactive = <Map<String, dynamic>>[];
  for (final job in jobs) {
    if (cronNextRun(job) == null) {
      inactive.add(job);
    } else {
      upcoming.add(job);
    }
  }
  upcoming.sort((a, b) {
    final left = cronNextRun(a)!.orderingKey;
    final right = cronNextRun(b)!.orderingKey;
    return left.compareTo(right);
  });
  return (upcoming: upcoming, inactive: inactive);
}
