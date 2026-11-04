/// Localized presentation and failure classification for cron schedules.
///
/// Shared by the Cron manager (`CronScreen`) and the Workspace Crons →
/// Upcoming pane so both describe the same record, and the same failure, in
/// the same words. The record parsing itself is pure and lives in
/// `utils/cron_schedule.dart`.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/connection_manager.dart';
import '../utils/cron_schedule.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Why the schedule could not be read, in terms the user can act on.
enum CronScheduleFailure {
  /// The origin does not serve the dashboard cron route at all — what an
  /// API-server-only connection answers.
  needsDashboard,

  /// A dashboard is there, but it rejected or could not supply credentials.
  needsDashboardAuth,

  /// The dashboard could not be reached (DNS, refused, TLS, timeout).
  unreachable,

  /// Something else went wrong; do not pretend to know what.
  unknown,
}

/// Classifies a failed cron-jobs read from typed errors, never from message
/// text. An unsupported route and an empty schedule must never look alike, so
/// this distinction has to be reliable rather than best-effort string matching.
CronScheduleFailure classifyCronScheduleFailure(Object error) {
  if (error is DashboardHttpException) {
    return switch (error.statusCode) {
      404 || 410 || 501 => CronScheduleFailure.needsDashboard,
      401 || 403 => CronScheduleFailure.needsDashboardAuth,
      _ => CronScheduleFailure.unknown,
    };
  }
  if (error is DashboardAuthUnavailableException) {
    final status = error.statusCode;
    // No status: the homepage answered but carried no SPA session token, so
    // this dashboard is gated and needs configured credentials.
    if (status == null) return CronScheduleFailure.needsDashboardAuth;
    return switch (status) {
      404 || 410 || 501 => CronScheduleFailure.needsDashboard,
      401 || 403 => CronScheduleFailure.needsDashboardAuth,
      _ => CronScheduleFailure.unreachable,
    };
  }
  if (error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return CronScheduleFailure.unreachable;
  }
  return CronScheduleFailure.unknown;
}

/// Whether this failure is a missing capability rather than a fault: those are
/// presented calmly, and never with a retry that cannot help.
bool isCronCapabilityFailure(CronScheduleFailure failure) =>
    failure == CronScheduleFailure.needsDashboard ||
    failure == CronScheduleFailure.needsDashboardAuth;

/// The explanation for one [CronScheduleFailure].
String cronScheduleFailureMessage(
  AppLocalizations l10n,
  CronScheduleFailure failure,
) {
  return switch (failure) {
    CronScheduleFailure.needsDashboard => l10n.cron_upcoming_needs_dashboard,
    CronScheduleFailure.needsDashboardAuth =>
      l10n.cron_upcoming_needs_dashboard_auth,
    CronScheduleFailure.unreachable => l10n.cron_upcoming_dashboard_unreachable,
    CronScheduleFailure.unknown => l10n.cron_upcoming_load_failed,
  };
}

/// Renders one cron timestamp in the zone the server expressed it in.
///
/// The zone is always stated. When the payload carried no zone the value says
/// so, instead of letting a bare wall clock imply the device's zone.
String cronTimestampLabel(AppLocalizations l10n, CronTimestamp timestamp) {
  final zone = timestamp.zoneLabel;
  if (zone == null) {
    return l10n.cron_time_zone_unknown(timestamp.wallClockLabel);
  }
  final rendered = l10n.cron_time_with_zone(timestamp.wallClockLabel, zone);
  final scheduleZone = timestamp.zoneName;
  // Never relabel e.g. 09:00Z as 09:00 Australia/Sydney. Without an IANA
  // conversion, the named schedule zone is separate metadata.
  if (timestamp.utcOffset != null && scheduleZone != null) {
    return '$rendered · ${l10n.cron_schedule_timezone(scheduleZone)}';
  }
  return rendered;
}
