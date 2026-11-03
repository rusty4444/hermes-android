import '../models/session.dart';

const Set<String> kMachineSessionSources = {'cron', 'kanban', 'oneshot'};

// Mirrors the scheduler's persisted IDs, including non-hex legacy job IDs.
final _cronSessionId = RegExp(r'^cron_[A-Za-z0-9][A-Za-z0-9._-]*_\d{8}_\d{6}$');

/// Persisted run identity from before the gateway switched cron to local-* IDs.
bool isLegacyCronSessionId(String id) => _cronSessionId.hasMatch(id);

bool isCronSession(Session session) =>
    session.source == 'cron' ||
    isLegacyCronSessionId(session.id) ||
    (session.lineageRootId != null &&
        isLegacyCronSessionId(session.lineageRootId!));

bool isMachineSession(Session session) =>
    kMachineSessionSources.contains(session.source) || isCronSession(session);
