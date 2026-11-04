/// Adopt a server folder that exists but is not a Project yet (issue #232).
///
/// Hermes Projects are *records* in the gateway's projects database, so a
/// directory created by the TUI (or by hand) never shows up in `projects.list`
/// and therefore never shows up in the app. This sheet lists the directories
/// under the configured Projects root through the dashboard's existing
/// `GET /api/fs/list` route, marks the ones already claimed by a Project, and
/// registers the chosen one through the existing `projects.create` /
/// `projects.add_folder` contract.
///
/// Nothing here invents a server interface. When the connection cannot list
/// server folders at all, the sheet says so and falls back to typing the
/// absolute path of an existing folder — which goes through exactly the same
/// registration contract.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/hermes_project.dart';
import '../services/project_folder_discovery.dart';
import '../services/projects_repository.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Registers [path] as a Project named [name].
typedef ProjectFolderAdopter =
    Future<HermesProject> Function({
      required String name,
      required String path,
    });

/// Opens the adoption sheet. Returns the adopted Project, or null.
Future<HermesProject?> showAdoptProjectFolderSheet(
  BuildContext context, {
  required ProjectFolderDiscovery discovery,
  required Iterable<HermesProject> registered,
  required ProjectFolderAdopter adopt,
}) {
  final snapshot = List<HermesProject>.of(registered);
  return showModalBottomSheet<HermesProject>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: AdoptProjectFolderSheet(
            discovery: discovery,
            registered: snapshot,
            adopt: adopt,
          ),
        ),
      ),
    ),
  );
}

class AdoptProjectFolderSheet extends StatefulWidget {
  final ProjectFolderDiscovery discovery;
  final List<HermesProject> registered;
  final ProjectFolderAdopter adopt;

  const AdoptProjectFolderSheet({
    required this.discovery,
    required this.registered,
    required this.adopt,
    super.key,
  });

  @override
  State<AdoptProjectFolderSheet> createState() =>
      _AdoptProjectFolderSheetState();
}

class _AdoptProjectFolderSheetState extends State<AdoptProjectFolderSheet> {
  /// Fences held reads: a scan started before the sheet was rebuilt for a
  /// different connection (or disposed) must not apply its result.
  int _generation = 0;

  final _pathController = TextEditingController();
  final _nameController = TextEditingController();

  ProjectFolderDiscoveryResult? _result;
  bool _loading = true;
  bool _adopting = false;
  String? _failure;
  String? _pathIssue;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  @override
  void dispose() {
    _generation++;
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
    });
    final result = await widget.discovery.scan(registered: widget.registered);
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  Future<void> _adopt({required String name, required String path}) async {
    final generation = _generation;
    setState(() {
      _adopting = true;
      _failure = null;
    });
    try {
      final project = await widget.adopt(name: name, path: path);
      if (!mounted || generation != _generation) return;
      Navigator.of(context).pop(project);
    } on ProjectFolderAdoptionException catch (error) {
      // The Project exists but holds no folder. Never reported as success:
      // Hermes derives membership from the working folder.
      if (!mounted || generation != _generation) return;
      setState(() {
        _adopting = false;
        _failure = context.l10n.adopt_folder_folderless(error.project.name);
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _adopting = false;
        _failure = context.l10n.adopt_folder_error('$error');
      });
    }
  }

  void _adoptManual() {
    final validation = _validatePath(_pathController.text);
    if (validation != null) {
      setState(() => _pathIssue = validation);
      return;
    }
    final path = _pathController.text.trim();
    final typedName = _nameController.text.trim();
    final name = typedName.isEmpty
        ? (path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? path)
        : typedName;
    setState(() => _pathIssue = null);
    unawaited(_adopt(name: name, path: path));
  }

  /// Syntactic only: the app has no interface that proves a server directory
  /// exists without trying to use it, so a wrong path surfaces as the server's
  /// own error on registration rather than a fake local check.
  String? _validatePath(String raw) {
    final trimmed = raw.trim();
    final l10n = context.l10n;
    if (trimmed.isEmpty) return l10n.projects_root_invalid_empty;
    if (!trimmed.startsWith('/')) return l10n.projects_root_invalid_absolute;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = HermesTokens.of(context);
    final result = _result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            HermesSpacing.lg,
            HermesSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.adopt_folder_action,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              HermesSpacing.sm,
              HermesSpacing.lg,
              HermesSpacing.lg,
            ),
            children: [
              if (_loading)
                const LoadingSkeleton(rows: 3)
              else if (result != null) ...[
                if (result.status == ProjectFolderDiscoveryStatus.unsupported)
                  _Notice(
                    key: const Key('adopt-folder-unsupported'),
                    icon: Icons.info_outline,
                    message: l10n.adopt_folder_unsupported,
                  )
                else if (result.status == ProjectFolderDiscoveryStatus.failed)
                  _Notice(
                    key: const Key('adopt-folder-failed'),
                    icon: Icons.cloud_off_outlined,
                    message: l10n.adopt_folder_failed('${result.error ?? ''}'),
                  )
                else ...[
                  Text(
                    l10n.adopt_folder_description(result.root ?? ''),
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                  const SizedBox(height: HermesSpacing.md),
                  if (result.unregistered.isEmpty)
                    _Notice(
                      key: const Key('adopt-folder-none'),
                      icon: Icons.check_circle_outline,
                      message: l10n.adopt_folder_none,
                    ),
                  for (final folder in result.folders)
                    _FolderTile(
                      folder: folder,
                      enabled: !_adopting && !folder.registered,
                      onTap: () => unawaited(
                        _adopt(name: folder.name, path: folder.path),
                      ),
                    ),
                ],
                const SizedBox(height: HermesSpacing.lg),
                const Divider(),
                const SizedBox(height: HermesSpacing.sm),
                TextField(
                  key: const Key('adopt-folder-path'),
                  controller: _pathController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.adopt_folder_manual_label,
                    errorText: _pathIssue,
                    prefixIcon: const Icon(Icons.folder_outlined),
                  ),
                ),
                const SizedBox(height: HermesSpacing.sm),
                TextField(
                  key: const Key('adopt-folder-name'),
                  controller: _nameController,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.adopt_folder_name_label,
                  ),
                ),
                const SizedBox(height: HermesSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const Key('adopt-folder-submit'),
                    onPressed: _adopting ? null : _adoptManual,
                    child: Text(l10n.adopt_folder_add),
                  ),
                ),
              ],
              if (_failure != null) ...[
                const SizedBox(height: HermesSpacing.md),
                _Notice(
                  key: const Key('adopt-folder-error'),
                  icon: Icons.error_outline,
                  message: _failure!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final DiscoveredProjectFolder folder;
  final bool enabled;
  final VoidCallback onTap;

  const _FolderTile({
    required this.folder,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
      child: HermesCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Row(
          children: [
            Icon(
              folder.registered
                  ? Icons.folder_special_outlined
                  : Icons.drive_folder_upload_outlined,
              size: 20,
              color: folder.registered ? tokens.muted : tokens.onSurface,
            ),
            const SizedBox(width: HermesSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.body.copyWith(
                      color: folder.registered
                          ? tokens.muted
                          : tokens.onSurface,
                    ),
                  ),
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    folder.registered
                        ? context.l10n.adopt_folder_registered(
                            folder.registeredProjectName ?? folder.name,
                          )
                        : folder.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.mono.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _Notice({required this.icon, required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
      child: HermesCard(
        status: HermesStatus.idle,
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: tokens.muted),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: tokens.typography.body.copyWith(color: tokens.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
