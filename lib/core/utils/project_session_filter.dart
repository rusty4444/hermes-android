/// View-layer narrowing of a project's already-loaded chats.
///
/// The per-Project search field filters what the server already returned via
/// `projects.project_sessions`. The gateway remains the source of truth for
/// membership; this helper only decides what the user sees. Matching is
/// case-insensitive across the fields a user can actually remember (title,
/// preview, id, model) and must never throw on a sparse row.
library;

import '../models/session.dart';

/// Returns the sessions whose title, preview, id, or model contains [query]
/// (case-insensitive), preserving server order.
///
/// Empty untitled cron scaffolds are hidden regardless of the query. No match
/// returns an empty list; a blank query preserves all other rows in server order.
List<Session> filterProjectSessions(List<Session> sessions, String query) {
  final needle = query.trim().toLowerCase();

  return sessions
      .where(
        (session) =>
            !session.isUntitledCronShell &&
            (needle.isEmpty ||
                session.title.toLowerCase().contains(needle) ||
                session.preview.toLowerCase().contains(needle) ||
                session.id.toLowerCase().contains(needle) ||
                session.model.toLowerCase().contains(needle)),
      )
      .toList(growable: false);
}
