/// The read-only Spaces → Projects migration preview.
///
/// The roadmap requires the local Spaces prototype to be migrated onto
/// server-owned Projects *only* after the user has seen exactly what would
/// happen. This widget renders [SpaceMigrationPlan] — which never writes
/// anything — so the preview is honest by construction: it shows matches,
/// the projects that would have to be created, and how many chats are
/// involved, while stating plainly that nothing has moved.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` ("Migration of the current
/// Spaces prototype").
library;

import 'package:flutter/material.dart';

import '../services/projects_repository.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

import 'package:hermes_android/core/l10n/l10n.dart';
class SpaceMigrationPreview extends StatefulWidget {
  final SpaceMigrationPlan plan;
  final VoidCallback? onDismiss;
  final Future<SpaceMigrationResult> Function()? onMigrate;

  const SpaceMigrationPreview({
    required this.plan,
    this.onDismiss,
    this.onMigrate,
    super.key,
  });

  @override
  State<SpaceMigrationPreview> createState() => _SpaceMigrationPreviewState();
}

class _SpaceMigrationPreviewState extends State<SpaceMigrationPreview> {
  bool _migrating = false;
  SpaceMigrationResult? _result;
  Object? _error;

  String _chats(int count) => context.l10n.chats_count(count);

  String get _summary {
    final plan = widget.plan;
    final spaces = context.l10n.spaces_count(plan.entries.length);
    final toCreate = plan.projectsToCreate;
    final projects = switch (toCreate) {
      0 => context.l10n.no_new_projects_needed,
      _ => context.l10n.projects_to_create(toCreate),
    };
    return '$spaces · ${_chats(plan.sessionsToLink)} · $projects';
  }

  Future<void> _runMigration() async {
    final migrate = widget.onMigrate;
    if (migrate == null || _migrating) return;
    setState(() {
      _migrating = true;
      _error = null;
    });
    try {
      final result = await migrate();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final plan = widget.plan;

    if (plan.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: context.l10n.nothing_to_migrate,
            message:
                context.l10n.no_local_spaces_were_found_for_this_connection_so_projects,
          ),
          if (widget.onDismiss != null)
            TextButton(onPressed: widget.onDismiss, child: Text(context.l10n.close)),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
      children: [
        SectionHeader(title: context.l10n.migration_preview),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
          child: Text(
            _summary,
            style: tokens.typography.body.copyWith(color: tokens.onSurface),
          ),
        ),
        const SizedBox(height: HermesSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
          child: Text(
            context.l10n.nothing_has_moved_yet_this_is_only_what_a_migration,
            style: tokens.typography.label.copyWith(color: tokens.muted),
          ),
        ),
        if (_result case final result?) ...[
          const SizedBox(height: HermesSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: HermesCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.isComplete
                        ? context.l10n.migration_complete
                        : context.l10n.migration_incomplete,
                    style: tokens.typography.section.copyWith(
                      color: tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    context.l10n.chats_migrated_projects_created(
                      result.createdProjects,
                      result.linkedSessions,
                    ),
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                  if (result.unlinkedSessions > 0)
                    Text(
                      context.l10n.chats_stayed_in_local_spaces(
                        result.unlinkedSessions,
                      ),
                      style: tokens.typography.body.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: HermesSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: Text(
              context.l10n.migration_failed_local_spaces_were_kept_unchanged,
              style: tokens.typography.body.copyWith(color: tokens.danger),
            ),
          ),
        ],
        const SizedBox(height: HermesSpacing.md),
        for (final entry in plan.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              0,
              HermesSpacing.lg,
              HermesSpacing.md,
            ),
            child: _EntryCard(entry: entry),
          ),
        if (widget.onMigrate != null && _result?.isComplete != true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: FilledButton.icon(
              onPressed: _migrating ? null : _runMigration,
              icon: _migrating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz_rounded),
              label: Text(
                _migrating ? context.l10n.migrating : context.l10n.migrate,
              ),
            ),
          ),
        if (widget.onDismiss != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HermesSpacing.lg),
            child: TextButton(
              onPressed: _migrating ? null : widget.onDismiss,
              child: Text(context.l10n.close),
            ),
          ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final SpaceMigrationEntry entry;

  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final matched = entry.matchedProject;
    final assigned = context.l10n.assigned_chats(entry.sessionCount);

    return HermesCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.space.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              StatusChip(
                status: matched == null
                    ? HermesStatus.blocked
                    : HermesStatus.completed,
                label: matched == null ? context.l10n.new_project : context.l10n.matched,
              ),
            ],
          ),
          const SizedBox(height: HermesSpacing.xs),
          Text(
            matched == null
                ? context.l10n.no_server_project_matches_this_name(assigned)
                : context.l10n.matches(assigned, matched.name),
            style: tokens.typography.body.copyWith(color: tokens.muted),
          ),
        ],
      ),
    );
  }
}
