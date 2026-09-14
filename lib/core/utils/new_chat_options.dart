/// The decision layer behind Home's global **New** button.
///
/// The roadmap's Home offers exactly two creation modes — **Project chat** and
/// **Quick chat** — and they are not symmetric:
///
/// - a Project chat is durable, belongs to a server-owned Project, and
///   inherits that Project's context;
/// - a Quick chat is deliberately *unfiled*: it starts with no Project even
///   when one is active, is marked `Quick`, and auto-archives after
///   [kQuickChatRetention]. It never suppresses normal Hermes/Hindsight
///   memory — ephemeral is an organization state, not a memory policy.
///
/// Two rules are encoded here rather than in the widget, so they can be
/// asserted without pumping a frame:
///
/// 1. **Nothing is hidden.** A mode that cannot run right now is returned
///    disabled *with a reason*, per the roadmap's capability-discovery rule.
///    A gateway that has not been probed yet says so instead of claiming
///    Projects are unsupported.
/// 2. **Quick chat never inherits a Project.** Passing an active project is
///    silently ignored for [NewChatMode.quickChat] rather than quietly
///    polluting a durable Project list.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import '../models/hermes_project.dart';
import '../models/session.dart';
import '../services/projects_repository.dart';

/// How long a Quick chat stays out of the archive. Validated default: 72 h.
const Duration kQuickChatRetention = Duration(hours: 72);

/// The model a drafted chat uses when the caller pins none.
const String kDefaultChatModel = 'hermes-agent';

/// The two validated creation modes of the global New button.
enum NewChatMode {
  /// A durable chat inside a server-owned Project.
  projectChat,

  /// An unfiled, clearly marked chat that auto-archives after 72 hours.
  quickChat;

  String get label {
    switch (this) {
      case NewChatMode.projectChat:
        return 'Project chat';
      case NewChatMode.quickChat:
        return 'Quick chat';
    }
  }

  String get description {
    switch (this) {
      case NewChatMode.projectChat:
        return 'Durable work inside one of your projects, shared with Desktop.';
      case NewChatMode.quickChat:
        return 'A one-off question. Archives itself after 72 hours; anything '
            'worth keeping is still remembered.';
    }
  }
}

/// One entry of the New sheet, enabled or disabled with a stated reason.
class NewChatOption {
  final NewChatMode mode;
  final bool enabled;

  /// Why this mode cannot run right now. Always null when [enabled].
  final String? disabledReason;

  const NewChatOption({
    required this.mode,
    required this.enabled,
    this.disabledReason,
  });

  String get label => mode.label;

  String get description => mode.description;
}

/// Builds the New sheet entries for the current Projects state.
///
/// [projects] is the *active* (non-archived) listing; [isStale] means it came
/// from the offline cache, which deliberately does not disable anything — the
/// user may still start work in a project they already know about.
List<NewChatOption> buildNewChatOptions({
  required ProjectsSupport support,
  required List<HermesProject> projects,
  bool isStale = false,
}) {
  final usable = projects.where((project) => !project.archived).toList();

  String? projectChatBlocker;
  switch (support) {
    case ProjectsSupport.unknown:
      projectChatBlocker = 'Still loading your projects.';
    case ProjectsSupport.unsupported:
      projectChatBlocker =
          'This gateway does not host projects yet. Update the gateway to '
          'organize chats across your devices.';
    case ProjectsSupport.native:
      projectChatBlocker = usable.isEmpty
          ? 'Create a project first, then chats can live inside it.'
          : null;
  }

  return [
    NewChatOption(
      mode: NewChatMode.projectChat,
      enabled: projectChatBlocker == null,
      disabledReason: projectChatBlocker,
    ),
    // Quick chat needs no project and no `projects.*` family, so a legacy
    // gateway must still be able to start work from Home.
    const NewChatOption(mode: NewChatMode.quickChat, enabled: true),
  ];
}

/// Convenience over [buildNewChatOptions] reading a [ProjectsView] directly,
/// so a caller cannot drift from the repository's own view of support.
List<NewChatOption> buildNewChatOptionsFor(ProjectsView view) {
  return buildNewChatOptions(
    support: view.support,
    projects: view.projects,
    isStale: view.isStale,
  );
}

/// A chat about to be opened: the local [Session] plus its organization state.
class NewChatDraft {
  final Session session;
  final NewChatMode mode;

  /// The owning Project, or null for a Quick chat.
  final String? projectId;

  /// Project label carried into the sticky Chat context header.
  final String? projectName;

  /// The owning Project's working directory on the gateway host. Used as the
  /// session `cwd` fallback binding when the gateway lacks
  /// `projects.assign_session` (stock Hermes groups sessions under a project
  /// by cwd via `project_for_path`).
  final String? projectWorkingDirectory;

  /// When a Quick chat becomes eligible for auto-archive. Null when durable.
  final DateTime? expiresAt;

  const NewChatDraft({
    required this.session,
    required this.mode,
    this.projectId,
    this.projectName,
    this.projectWorkingDirectory,
    this.expiresAt,
  });

  bool get isQuick => mode == NewChatMode.quickChat;
}

/// Drafts the session a New button tap opens.
///
/// [sessionId] is generated by the caller (`GatewayChatClient.generateSessionId`
/// in the app) so this stays a pure function and the id can be pinned in tests.
NewChatDraft buildNewChatDraft({
  required NewChatMode mode,
  required String sessionId,
  required DateTime now,
  HermesProject? project,
  String? model,
}) {
  final id = sessionId.trim();
  if (id.isEmpty) {
    throw ArgumentError.value(sessionId, 'sessionId', 'must not be blank');
  }

  final isQuick = mode == NewChatMode.quickChat;
  if (!isQuick && project == null) {
    throw ArgumentError.notNull('project');
  }

  final projectName = project?.name.trim() ?? '';
  final title = isQuick
      ? 'Quick chat'
      : (projectName.isEmpty ? 'New chat' : 'New chat · $projectName');

  return NewChatDraft(
    session: Session(
      id: id,
      title: title,
      model: model ?? kDefaultChatModel,
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: now.millisecondsSinceEpoch / 1000.0,
    ),
    mode: mode,
    // A Quick chat never inherits the active project, even when one is passed.
    projectId: isQuick ? null : project!.id,
    projectName: isQuick || projectName.isEmpty ? null : projectName,
    projectWorkingDirectory: isQuick ? null : project!.workingDirectory,
    expiresAt: isQuick ? now.add(kQuickChatRetention) : null,
  );
}
