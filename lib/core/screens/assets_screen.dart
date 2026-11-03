import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/session.dart';
import '../services/chat_assets_client.dart';
import '../services/remote_files_client.dart';
import '../theme/hermes_theme.dart';
import '../widgets/hermes_components.dart';
import '../widgets/media_artifact_card.dart';

/// A deliberately incremental view of explicit files in saved Hermes replies.
/// It never crawls folders, starts agents, or persists a second transcript index.
class AssetsScreen extends StatefulWidget {
  final ChatAssetsDataSource source;
  final RemoteFilesDataSource Function(Session session) filesClient;
  final ValueChanged<Session> onOpenSession;

  const AssetsScreen({
    required this.source,
    required this.filesClient,
    required this.onOpenSession,
    super.key,
  });

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

enum _Scan { chats, older, retry }

class _MessageCursor {
  final Session session;
  final int offset;

  const _MessageCursor(this.session, [this.offset = 0]);

  String get key => '${session.id.length}:${session.id}:$offset';
}

class _AssetsScreenState extends State<AssetsScreen> {
  static const _batchSize = 10;
  final _search = TextEditingController();
  final _assets = <String, ChatAsset>{};
  final _seenSessions = <String>{};
  final _scannedSessions = <String>{};
  final _recent = Queue<_MessageCursor>();
  final _older = Queue<_MessageCursor>();
  final _failed = <String, _MessageCursor>{};
  ChatAssetKind? _kind;
  int _sessionOffset = 0;
  int _generation = 0;
  int _assetEpoch = 0;
  bool _moreSessions = true;
  bool _loading = false;
  bool _listFailed = false;
  bool _partial = false;

  @override
  void initState() {
    super.initState();
    unawaited(_scan(_Scan.chats, reset: true));
  }

  @override
  void didUpdateWidget(AssetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      unawaited(_scan(_Scan.chats, reset: true));
    }
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  bool _owns(int generation) => mounted && generation == _generation;

  Future<void> _scan(_Scan mode, {bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = ++_generation;
    final source = widget.source;
    setState(() {
      if (reset) {
        _assetEpoch++;
        _assets.clear();
        _seenSessions.clear();
        _scannedSessions.clear();
        _recent.clear();
        _older.clear();
        _failed.clear();
        _sessionOffset = 0;
        _moreSessions = true;
        _partial = false;
      }
      _loading = true;
      if (mode == _Scan.chats) _listFailed = false;
    });
    try {
      if (mode == _Scan.chats && _recent.isEmpty && _moreSessions) {
        final page = await source.listSessions(
          offset: _sessionOffset,
          limit: _batchSize,
        );
        if (!_owns(generation)) return;
        if (page.nextOffset <= _sessionOffset && page.hasMore) {
          throw const FormatException('Session pagination made no progress');
        }
        _sessionOffset = page.nextOffset;
        _moreSessions = page.hasMore;
        _partial = _partial || page.partial;
        for (final session in page.sessions) {
          if (_seenSessions.add(session.id)) {
            _recent.add(_MessageCursor(session));
          }
        }
      }
      // Snapshot the retry set so a failed retry is not retried in this batch.
      final queue = switch (mode) {
        _Scan.chats => _recent,
        _Scan.older => _older,
        _Scan.retry => Queue<_MessageCursor>.of(_failed.values),
      };
      // Both recent and older scans are bounded. Newly discovered older pages
      // stay queued for an explicit later action, not an unbounded startup scan.
      final count = queue.length.clamp(0, _batchSize);
      for (var i = 0; i < count; i++) {
        if (!_owns(generation)) return;
        final cursor = queue.removeFirst();
        // Remove before retrying so another failure rotates to the tail.
        // A permanently failing first batch must not starve later cursors.
        if (mode == _Scan.retry) _failed.remove(cursor.key);
        try {
          final page = await source.getMessages(
            cursor.session,
            offset: cursor.offset,
            limit: 100,
          );
          if (!_owns(generation)) return;
          if (page.nextOffset <= cursor.offset && page.hasMore) {
            throw const FormatException('Message pagination made no progress');
          }
          for (final asset in chatAssetsFromMessages(
            cursor.session,
            page.messages,
          )) {
            final previous = _assets[asset.id];
            _assets[asset.id] = previous?.merge(asset) ?? asset;
          }
          _scannedSessions.add(cursor.session.id);
          _failed.remove(cursor.key);
          if (page.hasMore) {
            _older.add(_MessageCursor(cursor.session, page.nextOffset));
          }
        } catch (_) {
          if (!_owns(generation)) return;
          _failed[cursor.key] = cursor;
        }
        setState(() {});
      }
    } catch (_) {
      if (_owns(generation)) setState(() => _listFailed = true);
    } finally {
      if (_owns(generation)) setState(() => _loading = false);
    }
  }

  List<ChatAsset> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _assets.values.where((asset) {
      if (_kind != null && asset.kind != _kind) return false;
      return query.isEmpty ||
          asset.ref.path.toLowerCase().contains(query) ||
          asset.session.title.toLowerCase().contains(query);
    }).toList()..sort((a, b) {
      final time = b.timestamp.compareTo(a.timestamp);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
  }

  String _kindLabel(ChatAssetKind? kind) => switch (kind) {
    null => context.l10n.assets_all,
    ChatAssetKind.image => context.l10n.assets_images,
    ChatAssetKind.audio => context.l10n.assets_audio,
    ChatAssetKind.video => context.l10n.assets_video,
    ChatAssetKind.document => context.l10n.assets_documents,
  };

  Widget _header() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.assets_scope_notice),
        const SizedBox(height: HermesSpacing.sm),
        Text(
          l10n.assets_download_limit,
          style: TextStyle(color: HermesTokens.of(context).muted),
        ),
        const SizedBox(height: HermesSpacing.md),
        TextField(
          key: const Key('assets-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n.assets_search_hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.clear_search,
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: HermesSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final kind in <ChatAssetKind?>[
                null,
                ...ChatAssetKind.values,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: HermesSpacing.sm),
                  child: FilterChip(
                    label: Text(_kindLabel(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HermesSpacing.sm),
        Text(l10n.assets_scan_summary(_assets.length, _scannedSessions.length)),
        if (_partial) ...[
          const SizedBox(height: HermesSpacing.sm),
          Text(l10n.assets_partial),
        ],
        if (_listFailed || _failed.isNotEmpty) ...[
          const SizedBox(height: HermesSpacing.sm),
          Text(l10n.assets_load_failed),
          if (_listFailed)
            TextButton(
              onPressed: _loading ? null : () => unawaited(_scan(_Scan.chats)),
              child: Text(l10n.retry),
            ),
          if (_failed.isNotEmpty)
            TextButton(
              onPressed: _loading ? null : () => unawaited(_scan(_Scan.retry)),
              child: Text(l10n.assets_retry_failed),
            ),
        ],
        const SizedBox(height: HermesSpacing.md),
        if (_loading)
          const LinearProgressIndicator(key: Key('assets-progress')),
      ],
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.symmetric(vertical: HermesSpacing.lg),
    child: Wrap(
      spacing: HermesSpacing.sm,
      runSpacing: HermesSpacing.sm,
      children: [
        if (_moreSessions || _recent.isNotEmpty)
          OutlinedButton.icon(
            key: const Key('assets-more-chats'),
            onPressed: _loading ? null : () => unawaited(_scan(_Scan.chats)),
            icon: const Icon(Icons.forum_outlined),
            label: Text(context.l10n.assets_load_more_chats),
          ),
        if (_older.isNotEmpty)
          OutlinedButton.icon(
            key: const Key('assets-older-messages'),
            onPressed: _loading ? null : () => unawaited(_scan(_Scan.older)),
            icon: const Icon(Icons.history),
            label: Text(context.l10n.assets_load_older_messages),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final indices = <Key, int>{
      for (var i = 0; i < visible.length; i++)
        ValueKey('asset-$_assetEpoch-${visible[i].id}'): i + 1,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.assets),
        actions: [
          IconButton(
            tooltip: context.l10n.refresh,
            onPressed: () => unawaited(_scan(_Scan.chats, reset: true)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _scan(_Scan.chats, reset: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(HermesSpacing.lg),
          itemCount: visible.length + 3,
          findChildIndexCallback: (key) {
            if (key == const Key('assets-header')) return 0;
            if (key == const Key('assets-footer')) return visible.length + 2;
            if (key == const Key('assets-empty')) return visible.length + 1;
            return indices[key];
          },
          itemBuilder: (context, index) {
            if (index == 0) {
              return KeyedSubtree(
                key: const Key('assets-header'),
                child: _header(),
              );
            }
            if (index == visible.length + 2) {
              return KeyedSubtree(
                key: const Key('assets-footer'),
                child: _footer(),
              );
            }
            if (index == visible.length + 1) {
              if (visible.isNotEmpty || _loading) {
                return const SizedBox.shrink(key: Key('assets-empty'));
              }
              return Padding(
                key: const Key('assets-empty'),
                padding: const EdgeInsets.symmetric(vertical: HermesSpacing.lg),
                child: EmptyState(
                  icon: Icons.image_outlined,
                  title: _assets.isEmpty
                      ? context.l10n.assets_empty
                      : context.l10n.assets_no_matches,
                  message: context.l10n.assets_empty_detail,
                ),
              );
            }
            final asset = visible[index - 1];
            return Column(
              key: ValueKey('asset-$_assetEpoch-${asset.id}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MediaArtifactCard(
                  key: ValueKey('$_assetEpoch:${asset.id}'),
                  ref: asset.ref,
                  filesClient: () => widget.filesClient(asset.session),
                  sourceIdentity: (widget.source, asset.session.id),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => widget.onOpenSession(asset.session),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: Text(
                      context.l10n.assets_open_chat(asset.session.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: HermesSpacing.md),
              ],
            );
          },
        ),
      ),
    );
  }
}
