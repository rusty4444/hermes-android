import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/hermes_theme.dart';
import '../utils/relative_time.dart';
import '../widgets/hermes_components.dart';

const kWorkspaceSessionSearchKey = Key('workspace-session-search');

enum WorkspaceSessionView { all, unassigned, archivedQuick, search }

/// The chip filters the Chats browser offers (decision #4 of the final UI
/// spec): every conversation, recent activity, unassigned, and archived.
enum WorkspaceChatsFilter {
  all('All'),
  recent('Recent'),
  unassigned('Unassigned'),
  archived('Archived');

  final String label;
  const WorkspaceChatsFilter(this.label);
}

/// How recently a conversation was last active, for date group headers.
enum ChatDateBucket {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  earlier('Earlier');

  final String label;
  const ChatDateBucket(this.label);
}

/// How long "Recent" means in the Chats browser.
const Duration kRecentChatsWindow = Duration(days: 7);

/// Assigns a conversation to its date bucket, by calendar day.
ChatDateBucket chatDateBucket(DateTime now, double lastActiveSeconds) {
  final activity = DateTime.fromMillisecondsSinceEpoch(
    (lastActiveSeconds * 1000).round(),
  );
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(activity.year, activity.month, activity.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return ChatDateBucket.today;
  if (diff == 1) return ChatDateBucket.yesterday;
  if (diff < 7) return ChatDateBucket.thisWeek;
  return ChatDateBucket.earlier;
}

/// Filters and sorts the Chats browser list for one chip filter.
///
/// Sorting is always by most recent activity, so a conversation moving up in
/// the list is the honest signal that it changed. [now] is injectable so the
/// "Recent" window and date buckets are deterministic in tests.
List<Session> filterChats({
  required List<Session> sessions,
  required WorkspaceChatsFilter filter,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final normalized = query.trim().toLowerCase();
  final recentCutoff =
      current.subtract(kRecentChatsWindow).millisecondsSinceEpoch / 1000.0;

  final filtered = [
    for (final session in sessions)
      if (switch (filter) {
            WorkspaceChatsFilter.all => true,
            WorkspaceChatsFilter.recent => session.lastActive >= recentCutoff,
            WorkspaceChatsFilter.unassigned => !claimedSessionIds.contains(
              session.id,
            ),
            WorkspaceChatsFilter.archived =>
              session.archived || archivedQuickChatIds.contains(session.id),
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return filtered;
}

/// Groups conversations into date buckets, newest bucket first.
List<MapEntry<ChatDateBucket, List<Session>>> groupChatsByDate(
  DateTime now,
  List<Session> sessions,
) {
  final buckets = <ChatDateBucket, List<Session>>{
    for (final bucket in ChatDateBucket.values) bucket: <Session>[],
  };
  for (final session in sessions) {
    buckets[chatDateBucket(now, session.lastActive)]!.add(session);
  }
  return [
    for (final bucket in ChatDateBucket.values)
      if (buckets[bucket]!.isNotEmpty)
        MapEntry(bucket, List.unmodifiable(buckets[bucket]!)),
  ];
}

class WorkspaceSessionsData {
  final List<Session> sessions;
  final Set<String> claimedSessionIds;
  final Set<String> archivedQuickChatIds;

  /// Best-effort session id → project label mapping.
  ///
  /// Built from the server `projects.tree` preview rows; a conversation whose
  /// project is unknown stays honest as "Unassigned" in the UI.
  final Map<String, String> projectLabels;

  const WorkspaceSessionsData({
    this.sessions = const [],
    this.claimedSessionIds = const {},
    this.archivedQuickChatIds = const {},
    this.projectLabels = const {},
  });
}

typedef WorkspaceSessionsLoader = Future<WorkspaceSessionsData> Function();
typedef WorkspaceSessionPromoter = Future<void> Function(Session session);

/// A reversible batch action the gateway's `organization.*` surface supports.
enum WorkspaceBatchAction { pin, unpin, archive }

/// Runs a batch action over the given session ids; returns the server's
/// batch id so the caller can offer an undo.
typedef WorkspaceBatchRunner =
    Future<String> Function(List<String> sessionIds, WorkspaceBatchAction action);

/// Reverses one batch by id.
typedef WorkspaceBatchUndoRunner = Future<void> Function(String batchId);

class QuickChatPromotionCancelled implements Exception {
  const QuickChatPromotionCancelled();
}

List<Session> filterWorkspaceSessions({
  required List<Session> sessions,
  required WorkspaceSessionView view,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
}) {
  final normalized = query.trim().toLowerCase();
  return [
    for (final session in sessions)
      if (switch (view) {
            WorkspaceSessionView.unassigned => !claimedSessionIds.contains(
              session.id,
            ),
            WorkspaceSessionView.archivedQuick => archivedQuickChatIds.contains(
              session.id,
            ),
            WorkspaceSessionView.all || WorkspaceSessionView.search => true,
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ];
}

class WorkspaceSessionsScreen extends StatefulWidget {
  final String title;
  final WorkspaceSessionView view;
  final WorkspaceSessionsLoader load;
  final ValueChanged<Session> onOpenSession;
  final WorkspaceSessionPromoter? onPromote;

  /// Batch organization callbacks. When [runBatch] is null the batch
  /// selection affordances stay hidden — the gateway has not proven the
  /// `organization.*` contract.
  final WorkspaceBatchRunner? runBatch;
  final WorkspaceBatchUndoRunner? undoBatch;
  final bool embedded;

  /// Clock injection for deterministic filter/date tests. When null the
  /// screen uses `DateTime.now()`.
  final DateTime? now;

  const WorkspaceSessionsScreen({
    required this.title,
    required this.view,
    required this.load,
    required this.onOpenSession,
    this.onPromote,
    this.runBatch,
    this.undoBatch,
    this.embedded = false,
    this.now,
    super.key,
  });

  @override
  State<WorkspaceSessionsScreen> createState() =>
      _WorkspaceSessionsScreenState();
}

class _WorkspaceSessionsScreenState extends State<WorkspaceSessionsScreen> {
  WorkspaceSessionsData? _data;
  Object? _error;
  String _query = '';
  final Set<String> _promoting = {};

  /// Batch selection mode. Enters on long-press (when the gateway proved
  /// `organization.*`), exits on cancel or after a batch completes.
  final Set<String> _selected = {};
  bool _batchBusy = false;

  bool get _selectMode => widget.runBatch != null && _selected.isNotEmpty;

  /// The active chip filter in the embedded Chats browser.
  WorkspaceChatsFilter _filter = WorkspaceChatsFilter.all;

  /// Injectable clock for deterministic tests.
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.load();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('[workspace-sessions] load failed: $error');
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _promote(Session session) async {
    final promote = widget.onPromote;
    if (promote == null || _promoting.contains(session.id)) return;
    setState(() => _promoting.add(session.id));
    try {
      await promote(session);
      if (!mounted) return;
      final data = _data;
      if (data != null) {
        setState(() {
          _data = WorkspaceSessionsData(
            sessions: data.sessions,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: {
              for (final id in data.archivedQuickChatIds)
                if (id != session.id) id,
            },
            projectLabels: data.projectLabels,
          );
          _promoting.remove(session.id);
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Promoted to a Project')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _promoting.remove(session.id));
      if (error is QuickChatPromotionCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Couldn’t promote conversation'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => unawaited(_promote(session)),
          ),
        ),
      );
    }
  }

  void _toggleSelected(String sessionId) {
    setState(() {
      if (!_selected.remove(sessionId)) _selected.add(sessionId);
    });
  }

  void _exitSelection() => setState(_selected.clear);

  Future<void> _runBatchAction(WorkspaceBatchAction action) async {
    final runner = widget.runBatch;
    if (runner == null || _selected.isEmpty || _batchBusy) return;
    final ids = _selected.toList();
    setState(() => _batchBusy = true);
    try {
      final batchId = await runner(ids, action);
      if (!mounted) return;
      setState(() {
        _batchBusy = false;
        _selected.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (action) {
            WorkspaceBatchAction.pin => 'Pinned ${ids.length} chat(s)',
            WorkspaceBatchAction.unpin => 'Unpinned ${ids.length} chat(s)',
            WorkspaceBatchAction.archive => 'Archived ${ids.length} chat(s)',
          }),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(_undoBatch(batchId)),
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _batchBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Batch failed: $error')),
      );
    }
  }

  Future<void> _undoBatch(String batchId) async {
    final undo = widget.undoBatch;
    if (undo == null || _batchBusy) return;
    setState(() => _batchBusy = true);
    try {
      await undo(batchId);
      if (!mounted) return;
      setState(() => _batchBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch undone')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _batchBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Undo failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final body = data == null
        ? _error == null
              ? const Padding(
                  padding: EdgeInsets.only(top: HermesSpacing.lg),
                  child: LoadingSkeleton(rows: 5),
                )
              : ErrorState(
                  title: 'Could not load conversations',
                  message: 'Check the connection and try again.',
                  onRetry: _load,
                )
        : _buildLoaded(data);
    if (widget.embedded) {
      return Material(color: Colors.transparent, child: body);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }

  Widget _buildLoaded(WorkspaceSessionsData data) {
    final sessions = widget.embedded
        ? filterChats(
            sessions: data.sessions,
            filter: _filter,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
            now: _now,
          )
        : filterWorkspaceSessions(
            sessions: data.sessions,
            view: widget.view,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
          );

    final groups = widget.embedded
        ? groupChatsByDate(_now, sessions)
        : [
            MapEntry(
              ChatDateBucket.today,
              List<Session>.unmodifiable(sessions),
            ),
          ];

    return Column(
      children: [
        if (_selectMode) _buildBatchBar(sessions),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
        padding: const EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.md,
          HermesSpacing.lg,
          HermesSpacing.xl,
        ),
        children: [
          TextField(
            key: kWorkspaceSessionSearchKey,
            autofocus: widget.view == WorkspaceSessionView.search,
            decoration: InputDecoration(
              hintText: 'Search conversations',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          if (widget.embedded) ...[
            const SizedBox(height: HermesSpacing.md),
            _buildChips(),
          ],
          const SizedBox(height: HermesSpacing.lg),
          if (sessions.isEmpty)
            EmptyState(
              icon: _emptyIcon,
              title: _query.isEmpty ? 'Nothing here' : 'No matches',
              message: _emptyMessage,
            )
          else
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: HermesSpacing.xs,
                  bottom: HermesSpacing.sm,
                ),
                child: Text(
                  widget.embedded ? group.key.label : widget.title,
                  style: HermesTokens.of(context).typography.section,
                ),
              ),
              for (final session in group.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
                  child: _buildSessionRow(session, data),
                ),
            ],
          ],
            ),
          ),
        ),
      ],
    );
  }

  /// The select-mode action bar: what is selected, what can be done, and
  /// how to get out. Disabled buttons while a batch is in flight so a
  /// double-tap can't fire two overlapping batches.
  Widget _buildBatchBar(List<Session> sessions) {
    final tokens = HermesTokens.of(context);
    final count = _selected.length;
    final allSelected = count >= sessions.length && sessions.isNotEmpty;
    return Material(
      color: tokens.raised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.sm,
          HermesSpacing.lg,
          HermesSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: allSelected ? 'Deselect all' : 'Select all',
              onPressed: _batchBusy
                  ? null
                  : () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(sessions.map((s) => s.id));
                        }
                      }),
              icon: Icon(
                allSelected
                    ? Icons.deselect
                    : Icons.select_all,
              ),
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: tokens.typography.label.copyWith(
                  color: tokens.onSurface,
                ),
              ),
            ),
            if (_batchBusy)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              IconButton(
                tooltip: 'Pin',
                onPressed: () =>
                    unawaited(_runBatchAction(WorkspaceBatchAction.pin)),
                icon: const Icon(Icons.push_pin_outlined),
              ),
              IconButton(
                tooltip: 'Unpin',
                onPressed: () =>
                    unawaited(_runBatchAction(WorkspaceBatchAction.unpin)),
                icon: const Icon(Icons.push_pin),
              ),
              IconButton(
                tooltip: 'Archive',
                onPressed: () =>
                    unawaited(_runBatchAction(WorkspaceBatchAction.archive)),
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: _batchBusy ? null : _exitSelection,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in WorkspaceChatsFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: HermesSpacing.sm),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Session session, WorkspaceSessionsData data) {
    final tokens = HermesTokens.of(context);
    final projectLabel = data.projectLabels[session.id];
    final showPromote =
        widget.view == WorkspaceSessionView.archivedQuick &&
        widget.onPromote != null;
    final selectable = widget.runBatch != null;
    final selected = _selected.contains(session.id);
    return HermesCard(
      onTap: _selectMode
          ? () => _toggleSelected(session.id)
          : () => widget.onOpenSession(session),
      onLongPress: selectable
          ? () => _toggleSelected(session.id)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectMode)
            Padding(
              padding: const EdgeInsets.only(right: HermesSpacing.sm, top: 1),
              child: Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? tokens.accent : tokens.muted,
              ),
            )
          else
            Icon(
              session.pinned
                  ? Icons.push_pin_outlined
                  : Icons.chat_bubble_outline,
              size: 20,
              color: session.pinned ? tokens.accent : tokens.muted,
            ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title.isEmpty ? 'Untitled chat' : session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.preview.isNotEmpty)
                  Text(
                    session.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.muted),
                  ),
                const SizedBox(height: HermesSpacing.xs),
                Wrap(
                  spacing: HermesSpacing.sm,
                  runSpacing: HermesSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(
                      status: session.isActive
                          ? HermesStatus.running
                          : HermesStatus.completed,
                      label: session.isActive ? 'Running' : 'Done',
                    ),
                    if (projectLabel != null)
                      _MetaChip(
                        label: projectLabel,
                        icon: Icons.folder_outlined,
                      )
                    else
                      _MetaChip(
                        label: 'Unassigned',
                        icon: Icons.inbox_outlined,
                      ),
                    Text(
                      _relativeTime(_now, session.lastActive),
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showPromote)
            _promoting.contains(session.id)
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Promote to project',
                    onPressed: () => unawaited(_promote(session)),
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
        ],
      ),
    );
  }

  IconData get _emptyIcon {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned => Icons.inbox_outlined,
        WorkspaceChatsFilter.archived => Icons.archive_outlined,
        WorkspaceChatsFilter.recent => Icons.history_outlined,
        WorkspaceChatsFilter.all => Icons.search_off,
      };
    }
    return widget.view == WorkspaceSessionView.unassigned
        ? Icons.inbox_outlined
        : Icons.search_off;
  }

  String get _emptyMessage {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned =>
          'Every conversation is already assigned to a Project.',
        WorkspaceChatsFilter.archived => 'Archived conversations appear here.',
        WorkspaceChatsFilter.recent =>
          'Nothing changed in the last seven days.',
        WorkspaceChatsFilter.all => 'No conversation matches this view.',
      };
    }
    return switch (widget.view) {
      WorkspaceSessionView.unassigned =>
        'Every conversation is already assigned to a Project.',
      WorkspaceSessionView.archivedQuick =>
        'Quick chats appear here after their retention period.',
      WorkspaceSessionView.all ||
      WorkspaceSessionView.search => 'No conversation matches this view.',
    };
  }

  /// Compact relative time: "now", "5m", "2h", "3d", else a date.
  String _relativeTime(DateTime now, double lastActiveSeconds) =>
      formatRelativeTime(now, lastActiveSeconds);
}

/// A small neutral label under a conversation row (project, unassigned).
class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.sm,
            vertical: HermesSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.raised,
            borderRadius: BorderRadius.circular(HermesRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: tokens.muted),
              const SizedBox(width: 4),
              Text(label, style: tokens.typography.label),
            ],
          ),
        ),
      ),
    );
  }
}
