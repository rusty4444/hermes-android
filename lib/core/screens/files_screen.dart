import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/remote_files_client.dart';
import '../theme/hermes_theme.dart';
import '../widgets/hermes_components.dart';

import 'package:hermes_android/core/l10n/l10n.dart';
class FilesScreen extends StatefulWidget {
  final RemoteFilesDataSource files;
  final ValueChanged<String>? onAddToChat;
  final Future<void> Function(RemoteFileDownload download)? onSaveDownload;

  const FilesScreen({
    required this.files,
    this.onAddToChat,
    this.onSaveDownload,
    super.key,
  });

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  RemoteDirectory? _root;
  String? _path;
  List<RemoteFileEntry> _entries = const [];
  RemoteFileEntry? _selected;
  RemoteTextPreview? _preview;
  Object? _error;
  bool _loading = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRoot());
  }

  Future<void> _loadRoot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await widget.files.defaultDirectory();
      if (!mounted) return;
      _root = root;
      await _openDirectory(root.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _openDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      _preview = null;
    });
    try {
      final entries = await widget.files.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _path = path;
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _openFile(RemoteFileEntry entry) async {
    setState(() {
      _selected = entry;
      _preview = null;
      _loading = true;
      _error = null;
    });
    try {
      final preview = await widget.files.readText(entry.path);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  String? get _parentPath {
    final path = _path;
    final root = _root?.path;
    if (path == null || root == null || path == root) return null;
    final separator = path.lastIndexOf('/');
    if (separator <= 0) return '/';
    return path.substring(0, separator);
  }

  void _back() {
    if (_selected != null) {
      setState(() {
        _selected = null;
        _preview = null;
        _error = null;
      });
      return;
    }
    final parent = _parentPath;
    if (parent != null) {
      unawaited(_openDirectory(parent));
      return;
    }
    Navigator.maybePop(context);
  }

  Future<void> _download() async {
    final selected = _selected;
    if (selected == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final download = await widget.files.download(selected.path);
      if (!mounted) return;
      final saver = widget.onSaveDownload;
      if (saver != null) {
        await saver(download);
      } else {
        await FilePicker.platform.saveFile(
          dialogTitle: context.l10n.save_2(download.filename),
          fileName: download.filename,
          bytes: download.bytes,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.downloaded(download.filename))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.download_failed(error))));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _directoryBody() {
    if (_entries.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.folder_open_outlined,
          title: context.l10n.folder_is_empty,
          message: context.l10n.there_are_no_visible_files_in_this_server_folder,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _openDirectory(_path!),
      child: ListView.separated(
        padding: const EdgeInsets.all(HermesSpacing.lg),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: HermesSpacing.sm),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return HermesCard(
            padding: const EdgeInsets.symmetric(
              horizontal: HermesSpacing.lg,
              vertical: HermesSpacing.md,
            ),
            onTap: () => entry.isDirectory
                ? unawaited(_openDirectory(entry.path))
                : unawaited(_openFile(entry)),
            child: Row(
              children: [
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  color: HermesTokens.of(context).accent,
                ),
                const SizedBox(width: HermesSpacing.md),
                Expanded(child: Text(entry.name)),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _previewBody() {
    final selected = _selected!;
    final preview = _preview;
    final tokens = HermesTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(HermesSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(selected.name, style: tokens.typography.section),
          const SizedBox(height: HermesSpacing.sm),
          Wrap(
            spacing: HermesSpacing.sm,
            runSpacing: HermesSpacing.sm,
            children: [
              if (preview != null)
                StatusChip(status: HermesStatus.idle, label: preview.language),
              if (preview?.truncated == true)
                StatusChip(
                  status: HermesStatus.blocked,
                  label: context.l10n.preview_truncated,
                ),
            ],
          ),
          const SizedBox(height: HermesSpacing.lg),
          Expanded(
            child: HermesCard(
              child: SingleChildScrollView(
                child: SelectableText(
                  preview?.binary == true
                      ? context.l10n.binary_preview_is_unavailable_download_the_file_to_open_it
                      : preview?.text ?? context.l10n.preview_unavailable,
                  style: tokens.typography.body.copyWith(
                    fontFamily: 'monospace',
                    color: tokens.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: HermesSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(context.l10n.download),
                ),
              ),
              if (widget.onAddToChat != null) ...[
                const SizedBox(width: HermesSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onAddToChat!(selected.path);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.file_reference_added_to_chat),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(context.l10n.add_to_chat),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingSkeleton(rows: 6);
    if (_error != null) {
      return Center(
        child: ErrorState(
          title: _selected == null
              ? context.l10n.could_not_load_files
              : context.l10n.could_not_preview_file,
          message: context.l10n.check_the_dashboard_connection_and_try_again,
          onRetry: _selected == null
              ? () => unawaited(
                  _path == null ? _loadRoot() : _openDirectory(_path!),
                )
              : () => unawaited(_openFile(_selected!)),
        ),
      );
    }
    return _selected == null ? _directoryBody() : _previewBody();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back)),
      title: Text(context.l10n.files),
      bottom: _selected == null && _path != null
          ? PreferredSize(
              preferredSize: const Size.fromHeight(42),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  HermesSpacing.lg,
                  0,
                  HermesSpacing.lg,
                  HermesSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _path!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_root?.branch != null)
                      StatusChip(
                        status: HermesStatus.idle,
                        label: _root!.branch,
                      ),
                  ],
                ),
              ),
            )
          : null,
    ),
    body: _body(),
  );
}
