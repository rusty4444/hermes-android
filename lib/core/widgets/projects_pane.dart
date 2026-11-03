/// The Projects destination pane.
///
/// First screen built entirely on the design system: it renders server-owned
/// Projects through [ProjectsRepository], shows the cache immediately while a
/// live refresh runs, and expresses every situation — loading, empty, offline,
/// unsupported gateway, failure — as a designed state rather than a spinner or
/// a crash. See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/hermes_project.dart';
import '../models/projects_tree_overview.dart';
import '../services/chat_space_store.dart';
import '../services/projects_repository.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';
import 'hermes_shell.dart';
import 'space_migration_preview.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class ProjectsPane extends StatefulWidget {
  final ProjectsRepository repository;
  final Future<void> Function(String projectId)? onProjectSelected;

  /// The legacy local Spaces store, when this connection still has one.
  ///
  /// Supplying it surfaces the read-only migration preview; it is never
  /// written to from here.
  final ChatSpaceStore? spaceStore;

  const ProjectsPane({
    required this.repository,
    this.onProjectSelected,
    this.spaceStore,
    super.key,
  });

  @override
  State<ProjectsPane> createState() => _ProjectsPaneState();
}

class _ProjectsPaneState extends State<ProjectsPane>
    with WidgetsBindingObserver {
  StreamSubscription<ProjectsView>? _subscription;
  ProjectsView? _view;
  ProjectsTreeOverview _overview = ProjectsTreeOverview.empty;
  ChatSpaceState? _spaces;
  int _refreshGeneration = 0;
  bool? _wasVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.repository.changes.listen((view) {
      if (mounted) setState(() => _view = view);
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _refreshGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = HermesPaneVisibility.of(context);
    if (_wasVisible == false && visible) unawaited(_refresh());
    _wasVisible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _wasVisible == true &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      unawaited(_refresh());
    }
  }

  /// Show the cache first so the pane opens with content, then reconcile.
  Future<void> _bootstrap() async {
    final cached = await widget.repository.loadCached();
    if (cached.projects.isEmpty && cached.archived.isEmpty) {
      // Nothing worth showing: keep the skeleton until the live read lands.
      if (mounted) setState(() => _view = null);
    }
    await _refresh();
    await _loadSpaces();
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    await widget.repository.refresh();
    if (!mounted || generation != _refreshGeneration) return;
    try {
      final overview = await widget.repository.overview(refresh: true);
      if (mounted && generation == _refreshGeneration) {
        setState(() => _overview = overview);
      }
    } catch (_) {
      // Counts and previews are progressive enhancement. Keep the list usable.
    }
  }

  Future<void> _openProject(String projectId) async {
    await widget.onProjectSelected?.call(projectId);
    if (mounted) await _refresh();
  }

  /// Reads the legacy local Spaces so the migration preview can be offered.
  /// Read-only: a failure here must never block the Projects list.
  Future<void> _loadSpaces() async {
    final store = widget.spaceStore;
    if (store == null) return;
    try {
      final spaces = await store.load();
      if (mounted) setState(() => _spaces = spaces);
    } catch (_) {
      // A corrupt local store is not a reason to hide server projects.
    }
  }

  Future<void> _showMigrationPreview() async {
    final spaces = _spaces;
    if (spaces == null) return;
    final plan = widget.repository.planMigration(spaces);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.7,
          child: SpaceMigrationPreview(
            plan: plan,
            onMigrate: () async {
              final result = await widget.repository.migrateSpaces(spaces);
              if (result.isComplete && mounted) {
                await _refresh();
              }
              return result;
            },
            onDismiss: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  /// Only offer the migration when there is something real to migrate.
  bool get _hasLocalSpaces => _spaces?.spaces.isNotEmpty ?? false;

  Future<void> _createProject() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _CreateProjectDialog(),
    );
    if (name == null || !mounted) return;

    try {
      await widget.repository.create(name);
    } catch (error) {
      if (!mounted) return;
      _showMutationError('create', error);
    }
  }

  Future<void> _renameProject(HermesProject project) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameProjectDialog(project: project),
    );
    if (name == null || !mounted || name == project.name) return;
    try {
      await widget.repository.rename(project.id, name);
    } catch (error) {
      if (mounted) _showMutationError('rename', error);
    }
  }

  Future<void> _archiveProject(HermesProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.archive_3(project.name)),
        content: Text(
          context.l10n.the_project_will_move_to_archived_its_chats_and_files,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.archive),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.archive(project.id);
    } catch (error) {
      if (mounted) _showMutationError('archive', error);
    }
  }

  Future<void> _restoreProject(HermesProject project) async {
    try {
      await widget.repository.archive(project.id, restore: true);
    } catch (error) {
      if (mounted) _showMutationError('restore', error);
    }
  }

  void _showMutationError(String action, Object error) {
    final actionLabel = switch (action) {
      'create' => context.l10n.action_create,
      'rename' => context.l10n.action_rename,
      'archive' => context.l10n.action_archive,
      'restore' => context.l10n.action_restore,
      _ => action,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.could_not_the_project(actionLabel, error)),
      ),
    );
  }

  ProjectOverviewNode? _overviewFor(String projectId) {
    for (final project in _overview.projects) {
      if (project.id == projectId) return project;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final view = _view;

    if (view == null) {
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    if (view.support == ProjectsSupport.unsupported) {
      return _CompatibilityMode(spaces: _spaces, onRetry: _refresh);
    }

    if (view.projects.isEmpty && view.error != null) {
      return ErrorState(
        title: context.l10n.could_not_reach_hermes,
        message: context
            .l10n
            .check_that_the_gateway_is_running_and_reachable_then_try,
        onRetry: _refresh,
      );
    }

    if (view.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            EmptyState(
              icon: Icons.folder_outlined,
              title: context.l10n.no_projects_yet,
              message: context
                  .l10n
                  .projects_group_related_chats_files_and_activity_and_stay_in,
              actionLabel: context.l10n.create_a_project,
              onAction: _createProject,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: tokens.surface,
      floatingActionButton: FloatingActionButton(
        onPressed: _createProject,
        tooltip: context.l10n.new_project,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (view.isStale) _OfflineBanner(error: view.error),
            SectionHeader(
              title: context.l10n.projects,
              count: view.projects.length,
              actionLabel: _hasLocalSpaces
                  ? context.l10n.review_local_spaces
                  : null,
              onAction: _hasLocalSpaces ? _showMigrationPreview : null,
            ),
            for (final project in view.projects)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.md,
                ),
                child: _ProjectCard(
                  project: project,
                  isActive: project.id == view.activeId,
                  onTap: () => unawaited(_openProject(project.id)),
                  overview: _overviewFor(project.id),
                  onRename: () => _renameProject(project),
                  onArchive: () => _archiveProject(project),
                ),
              ),
            if (view.archived.isNotEmpty) ...[
              SectionHeader(
                title: context.l10n.archived,
                count: view.archived.length,
              ),
              for (final project in view.archived)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HermesSpacing.lg,
                    0,
                    HermesSpacing.lg,
                    HermesSpacing.md,
                  ),
                  child: _ProjectCard(
                    project: project,
                    isActive: false,
                    onTap: () {},
                    onRestore: () => _restoreProject(project),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the Projects pane becomes on a gateway that predates `projects.*`.
///
/// The roadmap requires an older gateway to stay *usable* under a clearly
/// labelled compatibility mode rather than hitting a dead-end error screen.
/// So this keeps the local Spaces grouping visible and read-only: nothing here
/// can create a server project, because the server has none to create.
class _CompatibilityMode extends StatelessWidget {
  final ChatSpaceState? spaces;
  final Future<void> Function() onRetry;

  const _CompatibilityMode({required this.spaces, required this.onRetry});

  static const _explanation =
      'This Hermes gateway is older than server-side projects, so chats stay '
      'grouped on this device only. Update Hermes to share the same projects '
      'across your devices.';

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final state = spaces;
    final localSpaces = state?.spaces ?? const <ChatSpace>[];

    final counts = <String, int>{};
    for (final spaceId in state?.assignments.values ?? const <String>[]) {
      counts[spaceId] = (counts[spaceId] ?? 0) + 1;
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          SectionHeader(title: context.l10n.compatibility_mode),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              0,
              HermesSpacing.lg,
              HermesSpacing.md,
            ),
            child: HermesCard(
              status: HermesStatus.idle,
              padding: const EdgeInsets.all(HermesSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: tokens.muted),
                  const SizedBox(width: HermesSpacing.sm),
                  Expanded(
                    child: Text(
                      _explanation,
                      style: tokens.typography.body.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (localSpaces.isEmpty)
            EmptyState(
              icon: Icons.folder_outlined,
              title: context.l10n.no_spaces_on_this_device,
              message: context
                  .l10n
                  .chats_from_this_gateway_are_not_grouped_yet_grouping_stays,
            )
          else ...[
            SectionHeader(
              title: context.l10n.on_this_device,
              count: localSpaces.length,
            ),
            for (final space in localSpaces)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.md,
                ),
                child: _LocalSpaceCard(
                  space: space,
                  sessionCount: counts[space.id] ?? 0,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LocalSpaceCard extends StatelessWidget {
  final ChatSpace space;
  final int sessionCount;

  const _LocalSpaceCard({required this.space, required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final chats = context.l10n.chats_count(sessionCount);

    return HermesCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.muted.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(HermesRadius.sm),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              size: 20,
              color: tokens.muted,
            ),
          ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
                const SizedBox(height: HermesSpacing.xs),
                Text(
                  context.l10n.on_this_device_only(chats),
                  style: tokens.typography.body.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final Object? error;

  const _OfflineBanner({this.error});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.lg,
        HermesSpacing.lg,
        0,
      ),
      child: HermesCard(
        status: HermesStatus.idle,
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: tokens.muted),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.offline_showing_the_last_known_projects,
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final HermesProject project;
  final bool isActive;
  final VoidCallback onTap;
  final ProjectOverviewNode? overview;
  final VoidCallback? onRename;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  const _ProjectCard({
    required this.project,
    required this.isActive,
    required this.onTap,
    this.overview,
    this.onRename,
    this.onArchive,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final path = project.workingDirectory;

    return HermesCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(HermesRadius.sm),
            ),
            child: Icon(
              Icons.folder_rounded,
              size: 20,
              color: tokens.onAccentContainer,
            ),
          ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
                if (overview != null) ...[
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    context.l10n.chats_count(overview!.sessionCount),
                    style: tokens.typography.label.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                ],
                if (project.description != null) ...[
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    project.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                ],
                if (path != null) ...[
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.mono.copyWith(color: tokens.muted),
                  ),
                ],
              ],
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: HermesSpacing.sm),
            StatusChip(
              status: HermesStatus.running,
              label: context.l10n.active,
            ),
          ],
          PopupMenuButton<String>(
            key: Key('project-actions-${project.id}'),
            tooltip: context.l10n.project_actions,
            onSelected: (action) {
              switch (action) {
                case 'rename':
                  onRename?.call();
                case 'archive':
                  onArchive?.call();
                case 'restore':
                  onRestore?.call();
              }
            },
            itemBuilder: (_) => [
              if (onRename != null)
                PopupMenuItem(
                  value: 'rename',
                  child: Text(context.l10n.rename_project),
                ),
              if (onArchive != null)
                PopupMenuItem(
                  value: 'archive',
                  child: Text(context.l10n.archive_project),
                ),
              if (onRestore != null)
                PopupMenuItem(
                  value: 'restore',
                  child: Text(context.l10n.restore_project),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RenameProjectDialog extends StatefulWidget {
  final HermesProject project;

  const _RenameProjectDialog({required this.project});

  @override
  State<_RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<_RenameProjectDialog> {
  late String _draft = widget.project.name;
  String? _error;

  void _submit() {
    final name = _draft.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.enter_a_name);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.rename_3(widget.project.name)),
      content: TextFormField(
        key: const Key('rename-project-name'),
        initialValue: widget.project.name,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: context.l10n.name,
          errorText: _error,
        ),
        onChanged: (value) => _draft = value,
        onFieldSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.rename)),
      ],
    );
  }
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  String _draft = '';
  String? _error;

  void _submit() {
    final name = _draft.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.enter_a_name);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.new_project),
      content: TextField(
        key: const Key('project-name'),
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: context.l10n.name,
          errorText: _error,
        ),
        onChanged: (value) => _draft = value,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.create)),
      ],
    );
  }
}
