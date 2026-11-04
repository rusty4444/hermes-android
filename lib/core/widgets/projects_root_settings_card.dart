/// Per-connection editor for the server-side Projects root (issue #232).
///
/// Hermes Projects live on the server, so the folder new Projects are created
/// under is a server path, not a device path. Users who run Hermes with its
/// Projects under `~/.hermes/projects` previously had no way to tell the phone
/// about that, and the app's own Projects landed in `<home>/Projects` where
/// Hermes never looked.
///
/// The only server interface consulted is `GET /api/files`
/// ([ProjectsRootResolver]), which reports the dashboard's `locked_root` and
/// browse home. When the dashboard is locked, the lock wins: the path is shown
/// read-only with an explanation and the local preference is ignored.
///
/// Hosted by [ProjectsRootScreen], an explicitly opened More destination —
/// never by the device Settings screen, which must stay free of
/// dashboard-backed editors and server discovery.
library;

import 'package:flutter/material.dart';

import '../services/connection_manager.dart';
import '../services/projects_root_preference.dart';
import '../services/projects_root_resolver.dart';
import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class ProjectsRootSettingsCard extends StatefulWidget {
  final SavedConnection connection;

  /// Injected dashboard client. When null the card builds (and closes) its
  /// own from [connection]; supplying one keeps tests off the network.
  ///
  /// Construction is deferred to [_load], so a card that is built but whose
  /// connection names no dashboard never opens a client at all.
  final DashboardClient? dashboardClient;

  /// Injected preference store, so tests can seed a value.
  final ProjectsRootPreference? preference;

  const ProjectsRootSettingsCard({
    required this.connection,
    this.dashboardClient,
    this.preference,
    super.key,
  });

  @override
  State<ProjectsRootSettingsCard> createState() =>
      _ProjectsRootSettingsCardState();
}

class _ProjectsRootSettingsCardState extends State<ProjectsRootSettingsCard> {
  /// Fences every held read against connection replacement. A resolve started
  /// for the previous connection must not apply to the new one, and a resolve
  /// in flight at dispose must not touch state at all.
  int _generation = 0;

  DashboardClient? _ownedClient;
  ProjectsRootPreference? _preference;
  final _controller = TextEditingController();

  bool _loading = true;
  bool _supported = true;
  ProjectsRootResolution? _resolution;
  ProjectsRootIssue? _issue;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProjectsRootSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection.id != widget.connection.id ||
        oldWidget.dashboardClient != widget.dashboardClient) {
      _ownedClient?.close();
      _ownedClient = null;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    _ownedClient?.close();
    super.dispose();
  }

  String get _identity => ProjectsRootPreference.identityOf(widget.connection);

  /// Whether this connection names a dashboard at all. Projects (and the
  /// managed-files routes behind this setting) ride the Desktop Gateway; a
  /// legacy REST-only connection has nowhere to ask, which must be said out
  /// loud rather than rendered as an empty field.
  bool get _hasDashboardRoute =>
      widget.dashboardClient != null ||
      (widget.connection.desktopGatewayUrl?.trim().isNotEmpty ?? false);

  /// Re-reads the server root. [keepSavedNotice] survives the reload that
  /// follows a save, so the confirmation is not wiped by its own refresh.
  Future<void> _load({bool keepSavedNotice = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _issue = null;
      if (!keepSavedNotice) _saved = false;
    });
    if (!_hasDashboardRoute) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _supported = false;
        _resolution = null;
      });
      return;
    }
    final preference = _preference ??=
        widget.preference ?? await ProjectsRootPreference.open();
    if (!mounted || generation != _generation) return;
    final configured = preference.read(connectionIdentity: _identity);
    final client =
        widget.dashboardClient ??
        (_ownedClient ??= DashboardClient.fromConnection(widget.connection));
    final resolution = await ProjectsRootResolver(
      dashboard: client,
      configuredRoot: configured,
    ).resolve();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _supported = true;
      _resolution = resolution;
      // Show the configured value; the server default stays the placeholder so
      // an untouched connection reads as "unchanged", not as a stored path.
      _controller.text = resolution.isLocked ? '' : (configured ?? '');
    });
  }

  Future<void> _save() async {
    final preference = _preference;
    if (preference == null) return;
    final validation = ProjectsRootPreference.validate(_controller.text);
    if (!validation.isValid) {
      setState(() {
        _issue = validation.issue;
        _saved = false;
      });
      return;
    }
    final generation = _generation;
    await preference.save(
      connectionIdentity: _identity,
      path: validation.path!,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _issue = null;
      _saved = true;
      _controller.text = validation.path!;
    });
    await _load(keepSavedNotice: true);
  }

  Future<void> _reset() async {
    final preference = _preference;
    if (preference == null) return;
    final generation = _generation;
    await preference.clear(connectionIdentity: _identity);
    if (!mounted || generation != _generation) return;
    setState(() {
      _issue = null;
      _saved = true;
      _controller.clear();
    });
    await _load(keepSavedNotice: true);
  }

  String? _issueText(AppLocalizations l10n) => switch (_issue) {
    ProjectsRootIssue.empty => l10n.projects_root_invalid_empty,
    ProjectsRootIssue.notAbsolute => l10n.projects_root_invalid_absolute,
    ProjectsRootIssue.unsafeSegments => l10n.projects_root_invalid_segments,
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = HermesTokens.of(context);
    final resolution = _resolution;

    final List<Widget> children = [
      Text(
        l10n.projects_root_title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.projects_root_description,
        style: TextStyle(color: tokens.muted),
      ),
      const SizedBox(height: 12),
    ];

    if (_loading) {
      children.add(
        const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (!_supported) {
      children.add(
        Text(
          l10n.projects_root_unsupported,
          key: const Key('projects-root-unsupported'),
          style: TextStyle(color: tokens.muted),
        ),
      );
    } else if (resolution == null ||
        resolution.source == ProjectsRootSource.unavailable) {
      children.addAll([
        Text(
          l10n.projects_root_unavailable,
          key: const Key('projects-root-unavailable'),
          style: TextStyle(color: tokens.muted),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: const Key('projects-root-retry'),
            onPressed: _load,
            child: Text(l10n.retry),
          ),
        ),
      ]);
    } else if (resolution.isLocked) {
      // A server lock outranks the local preference: show the path, never a
      // field, so the UI cannot imply an override that would be ignored.
      children.addAll([
        Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: tokens.muted),
            const SizedBox(width: 6),
            Text(
              l10n.projects_root_locked_title,
              key: const Key('projects-root-locked'),
              style: TextStyle(color: tokens.muted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SelectableText(
          resolution.path!,
          style: tokens.typography.mono.copyWith(color: tokens.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.projects_root_locked_explanation,
          style: TextStyle(color: tokens.muted),
        ),
      ]);
    } else {
      children.addAll([
        TextField(
          key: const Key('projects-root-field'),
          controller: _controller,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: l10n.projects_root_label,
            hintText: resolution.serverDefault == null
                ? null
                : l10n.projects_root_default_hint(resolution.serverDefault!),
            errorText: _issueText(l10n),
            prefixIcon: const Icon(Icons.folder_outlined),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('projects-root-save'),
              onPressed: _save,
              child: Text(l10n.save),
            ),
            if (resolution.source == ProjectsRootSource.configured)
              OutlinedButton(
                key: const Key('projects-root-reset'),
                onPressed: _reset,
                child: Text(l10n.projects_root_reset),
              ),
          ],
        ),
        if (_saved && _issue == null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.projects_root_saved,
            key: const Key('projects-root-saved'),
            style: TextStyle(color: tokens.muted),
          ),
        ],
      ]);
    }

    return Card(
      key: const Key('projects-root-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
