// The NextGen sidebar (Kyllene's session drawer): search, shortcut tiles,
// pinned chats, All / Running / Needs you filters and the gateway switcher.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../data/seen_chats.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

enum NgSidebarFilter { all, running, needsYou }

/// How a chat row is highlighted, most urgent first: orange while the agent
/// waits on a question or approval, green when it finished with a reply
/// unread, blue while it runs with updates unread.
enum NgChatAttention { waiting, finished, updates, none }

enum NgDestination {
  scheduled,
  insights,
  capabilities,
  archived,
  more,
  settings,
}

/// Holds the sidebar's session list so it survives the drawer closing.
class NgSessionsModel extends ChangeNotifier {
  NgSessionsModel(NgScope scope) : _scope = scope {
    _listen();
  }

  NgScope _scope;
  NgScope get scope => _scope;
  set scope(NgScope value) {
    if (identical(value.gateway, _scope.gateway) &&
        value.connection.id == _scope.connection.id) {
      _scope = value;
      return;
    }
    _scope = value;
    _seen = null;
    _listen();
  }

  List<Session> sessions = [];

  /// The chat on screen: never unread while it's shown.
  String? currentId;

  NgSeenStore? _seen;
  NgSeenStore get seen =>
      _seen ??= NgSeenStore(scope.prefs, scope.connection.id);

  StreamSubscription<dynamic>? _changes;
  Timer? _changedDebounce;

  /// Another client (or a background turn) moved the gateway's chats on:
  /// read the list again so new progress shows as unread.
  void _listen() {
    _changes?.cancel();
    _changes = scope.gateway.events.listen((event) {
      if (event.type != 'sessions.changed' && event.type != 'session.title') {
        return;
      }
      _changedDebounce?.cancel();
      _changedDebounce = Timer(const Duration(seconds: 1), refresh);
    });
  }

  /// Whether [s] has progress the user hasn't seen (Kyllene's unread mark).
  bool isUnread(Session s) => s.id != currentId && seen.chats.isUnread(s);

  /// The highlight [s] gets in the list.
  NgChatAttention attentionOf(Session s, {Set<String>? needsYou}) {
    if ((needsYou ?? scope.gateway.needsYou).contains(s.id)) {
      return NgChatAttention.waiting;
    }
    if (!isUnread(s)) return NgChatAttention.none;
    return s.isActive ? NgChatAttention.updates : NgChatAttention.finished;
  }

  /// Chats besides the one on screen with something to see, for the badge.
  int get unreadCount => sessions
      .where((s) => s.id != currentId && attentionOf(s) != NgChatAttention.none)
      .length;

  /// The most urgent highlight among chats besides the one on screen.
  NgChatAttention get topAttention {
    final needsYou = scope.gateway.needsYou;
    var top = NgChatAttention.none;
    for (final s in sessions) {
      if (s.id == currentId) continue;
      final a = attentionOf(s, needsYou: needsYou);
      if (a.index < top.index) top = a;
    }
    return top;
  }

  /// Records the user saw [id] up to now (or its newest activity), clearing
  /// the gateway's shared unread mark too when it keeps one.
  void markRead(String? id, {bool running = false}) {
    if (id == null || id.isEmpty) return;
    final i = sessions.indexWhere((s) => s.id == id);
    final row = i >= 0 ? sessions[i] : null;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final activity = row == null
        ? 0.0
        : (row.lastActive > 0 ? row.lastActive : row.startedAt);
    seen.markLooked(id, activity > now ? activity : now, running: running);
    if (row != null && (row.unread || row.lastReadAt != null)) {
      sessions[i] = row.withReadState(unread: false, lastReadAt: now);
      if (row.unread || (row.lastReadAt ?? 0) < activity) {
        unawaited(
          scope.gateway.api
              .setSessionUnread(id, unread: false)
              .catchError((_) {}),
        );
      }
    }
    notifyListeners();
  }

  /// Marks [s] unread here and, when the gateway keeps read state, for every
  /// client.
  void markUnread(Session s) {
    seen.markUnread(s.id);
    final i = sessions.indexWhere((e) => e.id == s.id);
    if (i >= 0 && s.lastReadAt != null) {
      sessions[i] = s.withReadState(unread: true, lastReadAt: 0);
      unawaited(
        scope.gateway.api
            .setSessionUnread(s.id, unread: true)
            .catchError((_) {}),
      );
    }
    notifyListeners();
  }

  bool loading = false;
  bool hasMore = false;
  String? error;
  String query = '';
  Timer? _debounce;
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await scope.gateway.api.getSessionsPage(
        limit: 60,
        title: query.isEmpty ? null : query,
      );
      if (generation != _generation) return;
      sessions = page.sessions.where((s) => !s.isUntitledCronShell).toList();
      hasMore = page.hasMore;
      // The chat on screen is read through whatever the list now says.
      final current = currentId;
      if (current != null) {
        final row = sessions.where((s) => s.id == current).firstOrNull;
        if (row != null && seen.chats.isUnread(row)) {
          markRead(current);
        }
      }
    } catch (e) {
      if (generation != _generation) return;
      error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || !hasMore || query.isNotEmpty) return;
    loading = true;
    notifyListeners();
    try {
      final page = await scope.gateway.api.getSessionsPage(
        limit: 60,
        offset: sessions.length,
      );
      final known = sessions.map((s) => s.id).toSet();
      sessions = [
        ...sessions,
        ...page.sessions.where((s) => !known.contains(s.id)),
      ];
      hasMore = page.hasMore;
    } catch (_) {
      hasMore = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void search(String value) {
    query = value.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  void replace(Session updated) {
    final i = sessions.indexWhere((s) => s.id == updated.id);
    if (i >= 0) {
      sessions[i] = updated;
      notifyListeners();
    }
  }

  void remove(String id) {
    sessions.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changedDebounce?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}

String ngSessionTitle(Session s) {
  if (s.title.trim().isNotEmpty) return s.title.trim();
  if (s.preview.trim().isNotEmpty) return s.preview.trim();
  return ngL.ng_new_chat;
}

DateTime? ngSessionTime(Session s) {
  final t = s.lastActive > 0 ? s.lastActive : s.startedAt;
  if (t <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((t * 1000).round());
}

class NgSessionsSidebar extends StatefulWidget {
  const NgSessionsSidebar({
    super.key,
    required this.model,
    required this.currentSessionId,
    required this.onOpen,
    required this.onNewChat,
    required this.onDestination,
  });

  final NgSessionsModel model;
  final String? currentSessionId;
  final ValueChanged<Session> onOpen;
  final VoidCallback onNewChat;
  final ValueChanged<NgDestination> onDestination;

  @override
  State<NgSessionsSidebar> createState() => _NgSessionsSidebarState();
}

class _NgSessionsSidebarState extends State<NgSessionsSidebar> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  NgSidebarFilter _filter = NgSidebarFilter.all;

  @override
  void initState() {
    super.initState();
    _search.text = widget.model.query;
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) widget.model.loadMore();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _actions(Session s) async {
    final scope = NgScope.of(context);
    final api = scope.gateway.api;
    final c = NgColors.of(context);
    final choice = await showNgSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                ngSessionTitle(s),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NgType.heading.copyWith(color: c.text),
              ),
            ),
            if (s.pinKnown)
              ListTile(
                leading: Icon(
                  s.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                ),
                title: Text(s.pinned ? ngL.ng_unpin : ngL.ng_pin),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
            if (s.id != widget.currentSessionId)
              ListTile(
                leading: Icon(
                  widget.model.isUnread(s)
                      ? Icons.mark_chat_read_outlined
                      : Icons.mark_chat_unread_outlined,
                ),
                title: Text(
                  widget.model.isUnread(s)
                      ? ngL.ng_mark_as_read
                      : ngL.ng_mark_as_unread,
                ),
                onTap: () => Navigator.pop(context, 'read'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(ngL.ng_rename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(ngL.ng_archive),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text(ngL.ng_delete, style: TextStyle(color: c.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    try {
      switch (choice) {
        case 'read':
          if (widget.model.isUnread(s)) {
            widget.model.markRead(s.id);
          } else {
            widget.model.markUnread(s);
          }
        case 'pin':
          await api.setSessionPinned(sessionId: s.id, pinned: !s.pinned);
          await widget.model.refresh();
        case 'rename':
          final title = await ngPromptText(
            context,
            title: ngL.ng_rename_chat,
            initial: ngSessionTitle(s),
          );
          if (title == null || title.trim().isEmpty) return;
          await api.renameSession(sessionId: s.id, title: title);
          await widget.model.refresh();
        case 'archive':
          await api.setSessionArchived(
            sessionId: s.id,
            archived: true,
            clearPin: true,
          );
          widget.model.remove(s.id);
          if (mounted) ngToast(context, ngL.ng_archived);
        case 'delete':
          final ok = await ngConfirm(
            context,
            title: ngL.ng_delete_this_chat,
            body: ngL.ng_it_is_removed_from_the_gateway,
          );
          if (!ok) return;
          await api.deleteSession(s.id);
          widget.model.remove(s.id);
      }
    } catch (e) {
      if (mounted) ngToast(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final scope = NgScope.of(context);
    return Drawer(
      backgroundColor: c.sidebar,
      width: 330,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.model, scope.gateway]),
          builder: (context, _) {
            final needsYou = scope.gateway.needsYou;
            final all = widget.model.sessions;
            final filtered = switch (_filter) {
              NgSidebarFilter.all => all,
              NgSidebarFilter.running => all.where((s) => s.isActive).toList(),
              NgSidebarFilter.needsYou =>
                all
                    .where(
                      (s) =>
                          needsYou.contains(s.id) || widget.model.isUnread(s),
                    )
                    .toList(),
            };
            final pinned =
                _filter == NgSidebarFilter.all && widget.model.query.isEmpty
                ? filtered.where((s) => s.pinned).toList()
                : <Session>[];
            final rest = filtered.where((s) => !pinned.contains(s)).toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: TextField(
                    controller: _search,
                    onChanged: widget.model.search,
                    style: NgType.body.copyWith(color: c.text),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.input,
                      prefixIcon: Icon(Icons.search, color: c.text3, size: 20),
                      hintText: ngL.ng_search_chats,
                      hintStyle: NgType.body.copyWith(color: c.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(NgRadii.full),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: widget.model.refresh,
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                      children: [
                        _tiles(c),
                        const SizedBox(height: 8),
                        _filters(
                          c,
                          all
                              .where(
                                (s) =>
                                    needsYou.contains(s.id) ||
                                    widget.model.isUnread(s),
                              )
                              .length,
                        ),
                        if (pinned.isNotEmpty) ...[
                          NgSectionLabel(ngL.ng_pinned),
                          for (final s in pinned) _tile(c, s, needsYou),
                        ],
                        if (pinned.isNotEmpty && rest.isNotEmpty)
                          NgSectionLabel(ngL.ng_recent),
                        if (widget.model.error != null && all.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              widget.model.error!,
                              style: NgType.bodySmall.copyWith(color: c.danger),
                            ),
                          )
                        else if (!widget.model.loading && filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              switch (_filter) {
                                _ when widget.model.query.isNotEmpty =>
                                  ngL.ng_no_chats_match,
                                NgSidebarFilter.all => ngL.ng_no_chats_yet,
                                NgSidebarFilter.running =>
                                  ngL.ng_nothing_is_running,
                                NgSidebarFilter.needsYou =>
                                  ngL.ng_nothing_is_waiting_on_you,
                              },
                              textAlign: TextAlign.center,
                              style: NgType.bodySmall.copyWith(color: c.text3),
                            ),
                          ),
                        for (final s in rest) _tile(c, s, needsYou),
                        if (widget.model.loading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _footer(c, scope),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tiles(NgColors c) {
    Widget tile(IconData icon, String label, NgDestination d) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(NgRadii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(NgRadii.md),
            onTap: () => widget.onDestination(d),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(icon, size: 20, color: c.text2),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgType.caption.copyWith(color: c.text2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            tile(Icons.schedule, ngL.ng_scheduled, NgDestination.scheduled),
            tile(
              Icons.insights_outlined,
              ngL.ng_insights,
              NgDestination.insights,
            ),
            tile(
              Icons.extension_outlined,
              ngL.ng_capabilities,
              NgDestination.capabilities,
            ),
          ],
        ),
        Row(
          children: [
            tile(
              Icons.archive_outlined,
              ngL.ng_archived,
              NgDestination.archived,
            ),
            tile(Icons.apps, ngL.ng_more, NgDestination.more),
            tile(
              Icons.settings_outlined,
              ngL.ng_settings,
              NgDestination.settings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _filters(NgColors c, int waiting) {
    Widget chip(NgSidebarFilter f, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == f,
        showCheckmark: false,
        labelStyle: NgType.label.copyWith(
          color: _filter == f ? c.text : c.text3,
        ),
        selectedColor: c.thumb,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: _filter == f ? c.strokeStrong : c.stroke),
        shape: const StadiumBorder(),
        onSelected: (_) => setState(() => _filter = f),
      ),
    );
    // Scrolls sideways when translated labels don't fit the drawer.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          chip(NgSidebarFilter.all, ngL.ng_all),
          chip(NgSidebarFilter.running, ngL.ng_running),
          chip(
            NgSidebarFilter.needsYou,
            waiting > 0 ? ngL.ng_needs_you(waiting) : ngL.ng_needs_you_2,
          ),
        ],
      ),
    );
  }

  Widget _tile(NgColors c, Session s, Set<String> needsYou) {
    final selected = s.id == widget.currentSessionId;
    final waiting = needsYou.contains(s.id);
    final attention = selected
        ? NgChatAttention.none
        : widget.model.attentionOf(s, needsYou: needsYou);
    final marked = attention != NgChatAttention.none;
    final (Color tone, Color tint, String label) = switch (attention) {
      NgChatAttention.waiting => (
        c.warning,
        c.warningSoft,
        ngL.ng_hermes_is_waiting_for_you,
      ),
      NgChatAttention.finished => (
        c.success,
        c.successSoft,
        ngL.ng_unread_finished,
      ),
      NgChatAttention.updates => (
        c.accent,
        c.accentSoft,
        ngL.ng_unread_updates,
      ),
      NgChatAttention.none => (c.accent, Colors.transparent, ''),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        key: ValueKey(
          'ng-session-${s.id}${marked ? '-${attention.name}' : ''}',
        ),
        color: selected ? c.surface2 : tint,
        borderRadius: BorderRadius.circular(NgRadii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(NgRadii.sm),
          onTap: () => widget.onOpen(s),
          onLongPress: () => _actions(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                if (waiting)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.pan_tool_alt, size: 15, color: c.warning),
                  )
                else if (s.isActive)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: c.accent,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    ngSessionTitle(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NgType.label.copyWith(
                      color: selected || marked ? c.text : c.text2,
                      fontWeight: marked
                          ? FontWeight.w700
                          : selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ngAgo(ngSessionTime(s)),
                  style: NgType.caption.copyWith(
                    color: marked ? c.text2 : c.textMuted,
                    fontWeight: marked ? FontWeight.w600 : null,
                  ),
                ),
                if (marked)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Semantics(
                      label: label,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(NgColors c, NgScope scope) {
    final state = scope.gateway.state;
    final tone = switch (state.phase) {
      _ when state.isConnected => c.success,
      _ => c.warning,
    };
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(NgRadii.md),
              onTap: () => _switcher(scope),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scope.connection.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NgType.label.copyWith(color: c.text),
                          ),
                          Text(
                            state.label,
                            style: NgType.caption.copyWith(color: c.text3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more, size: 18, color: c.text3),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              shape: const StadiumBorder(),
            ),
            onPressed: widget.onNewChat,
            icon: const Icon(Icons.edit_square, size: 18),
            label: Text(ngL.ng_new_chat),
          ),
        ],
      ),
    );
  }

  Future<void> _switcher(NgScope scope) async {
    final c = NgColors.of(context);
    final picked = await showNgSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  ngL.ng_gateways,
                  style: NgType.title.copyWith(color: c.text),
                ),
              ),
            ),
            for (final conn in scope.connections)
              ListTile(
                leading: Icon(
                  conn.id == scope.connection.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: conn.id == scope.connection.id ? c.accent : c.text3,
                ),
                title: Text(conn.label),
                subtitle: Text(
                  conn.singleLogin
                      ? (conn.singleLoginUrl ?? conn.baseUrl)
                      : ngL.ng_classic_connection(conn.baseUrl),
                ),
                onTap: () => Navigator.pop(context, conn.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(ngL.ng_add_a_gateway),
              onTap: () => Navigator.pop(context, '+'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == '+') {
      await scope.addGateway();
    } else if (picked != scope.connection.id) {
      await scope.switchTo(picked);
    }
  }
}
