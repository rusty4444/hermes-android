// Assets — the server-authoritative artifact/attachment gallery.
//
// Talks to the gateway's `assets.*` RPC family (tui_gateway/methods_assets.py):
//   assets.status — is the index reachable
//   assets.list   — delivered MEDIA files, user uploads, and generated
//                   artifacts, newest first, filterable by kind
//
// The index is derived from durable server state (session transcripts and
// the attachments dir), so what this screen shows is the same on every
// device. Files live on the server: tapping a row copies its path so it can
// be opened through Files or shared from there.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/assets_gateway_client.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../theme/hermes_theme.dart';
import '../widgets/hermes_components.dart';

/// Kind filter for the gallery. `all` sends no kind param.
enum AssetFilter {
  all('All', null),
  artifact('Artifacts', 'artifact'),
  attachment('Attachments', 'attachment'),
  media('Media', 'media');

  const AssetFilter(this.label, this.kind);
  final String label;
  final String? kind;
}

class AssetsScreen extends StatefulWidget {
  final SavedConnection connection;

  /// When set, the gallery is scoped to this Project.
  final String? projectId;
  final String? projectName;

  const AssetsScreen({
    required this.connection,
    this.projectId,
    this.projectName,
    super.key,
  });

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  DesktopGatewayClient? _gateway;
  List<HermesAsset> _assets = const [];
  AssetFilter _filter = AssetFilter.all;
  bool _loading = true;
  String? _error;
  bool _unsupported = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _open() {
    try {
      _gateway = DesktopGatewayClient.fromConnection(widget.connection);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _gateway?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _gateway?.assets;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await client.status();
      if (!mounted) return;
      if (!status.available) {
        setState(() {
          _loading = false;
          _unsupported = true;
        });
        return;
      }
      final assets = await client.list(
        kind: _filter.kind,
        projectId: widget.projectId,
      );
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
        _unsupported = false;
      });
    } on AssetsUnsupportedException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unsupported = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _setFilter(AssetFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _load();
  }

  void _copyPath(HermesAsset asset) {
    Clipboard.setData(ClipboardData(text: asset.path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Path copied: ${asset.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        title: Text(widget.projectName == null
            ? 'Assets'
            : 'Assets · ${widget.projectName}'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(tokens),
    );
  }

  Widget _buildBody(HermesTokens tokens) {
    if (_loading) {
      return const Center(child: LoadingSkeleton(rows: 5));
    }
    if (_error != null) {
      return ErrorState(
        title: 'Assets check failed',
        message: _error!,
        onRetry: _load,
      );
    }
    if (_unsupported) {
      return const ErrorState.unsupported(
        title: 'Assets not available on this server',
        message:
            'This Hermes gateway has no server-authoritative assets index. '
            'Update the gateway (assets.* RPC) to browse artifacts and '
            'attachments here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                HermesSpacing.lg, HermesSpacing.md, HermesSpacing.lg, 0),
            child: Wrap(
              spacing: HermesSpacing.sm,
              children: [
                for (final f in AssetFilter.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => _setFilter(f),
                  ),
              ],
            ),
          ),
          const SizedBox(height: HermesSpacing.md),
          if (_assets.isEmpty)
            const EmptyState(
              icon: Icons.image_outlined,
              title: 'No assets yet',
              message:
                  'Files delivered in chats (MEDIA), uploads, and generated '
                  'artifacts show up here, newest first.',
            )
          else
            for (final a in _assets) _assetCard(tokens, a),
        ],
      ),
    );
  }

  Widget _assetCard(HermesTokens tokens, HermesAsset asset) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HermesSpacing.lg, HermesSpacing.sm, HermesSpacing.lg, 0),
      child: HermesCard(
        onTap: () => _copyPath(asset),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(HermesRadius.sm),
              ),
              child: Icon(_iconFor(asset), size: 20, color: tokens.accent),
            ),
            const SizedBox(width: HermesSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.typography.section
                        .copyWith(color: tokens.onSurface),
                  ),
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    _subtitleFor(asset),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HermesSpacing.sm),
            Text(
              _humanSize(asset.sizeBytes),
              style: tokens.typography.label.copyWith(color: tokens.muted),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(HermesAsset asset) {
    if (asset.isImage) return Icons.image_outlined;
    if (asset.isMedia) return Icons.play_circle_outline;
    switch (asset.kind) {
      case 'attachment':
        return Icons.attach_file;
      case 'media':
        return Icons.play_circle_outline;
      default:
        return Icons.description_outlined;
    }
  }

  String _subtitleFor(HermesAsset asset) {
    final source = asset.projectName != null && asset.projectName!.isNotEmpty
        ? asset.projectName!
        : (asset.sessionTitle.isNotEmpty ? asset.sessionTitle : 'Unassigned');
    final when = DateTime.fromMillisecondsSinceEpoch(
            (asset.modifiedAt * 1000).round())
        .toString()
        .substring(0, 16);
    return '$source · $when';
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
