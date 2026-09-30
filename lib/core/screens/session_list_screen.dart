import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session_search_hit.dart';
import '../services/ai_search_query_rewriter.dart';
import '../services/chat_space_store.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_application_controller.dart';
import '../services/session_search_client.dart';
import '../services/session_search_preferences.dart';
import '../services/ws_client.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'memory_screen.dart';
import 'spaces_screen.dart';
import 'cron_screen.dart';
import 'skills_screen.dart';
import 'workspace_screen.dart';

Future<String?> showSessionNameDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required String actionLabel,
}) async {
  var draft = initialValue;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onChanged: (value) => draft = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, draft.trim()),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return result?.trim().isEmpty == true ? null : result;
}

class SessionListScreen extends StatefulWidget {
  final SavedConnection connection;
  final GatewayTurnApplicationController turnApplicationController;

  /// Test-only HTTP client injected into the session-list [ApiClient] so
  /// paging behaviour (pinned back-fills, offset advance) can be driven
  /// against a fake server without a real gateway.
  final http.Client? testHttpClient;

  /// Test-only page-size override so a fake can make a base window
  /// consist entirely of pinned rows (the pin-only-window case) without
  /// shipping 50+ fixtures. Production keeps the 50-row window.
  final int? testSessionPageSize;

  /// Test-only seam for pausing a preferences read across a refresh. This
  /// makes stale-generation races deterministic without changing production
  /// persistence behaviour.
  final Future<SharedPreferences> Function()? testPreferencesLoader;

  const SessionListScreen({
    required this.connection,
    required this.turnApplicationController,
    this.testHttpClient,
    this.testSessionPageSize,
    this.testPreferencesLoader,
    super.key,
  });

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  /// Debounce window before a typed query is sent to the dashboard. Local
  /// search filters in-memory on every keystroke; server search must not.
  static const _searchDebounce = Duration(milliseconds: 350);

  late final ApiClient _client;
  DesktopGatewayClient? _desktopGateway;
  final _searchController = TextEditingController();
  List<SavedConnection> _profiles = const [];
  List<Session> _sessions = [];
  ChatSpaceStore? _spaceStore;
  ChatSpaceState _spaceState = const ChatSpaceState(
    spaces: [],
    assignments: {},
  );
  ChatSpaceScope _spaceScope = const ChatSpaceScope.all();
  bool _loading = true;
  String? _error;

  /// Session-list paging state. The gateway serves the list newest-first in
  /// pages; [_sessions] accumulates loaded pages so the Unassigned bucket
  /// can reach sessions beyond the first page.
  int get _sessionPageSize => widget.testSessionPageSize ?? 50;
  int _sessionsOffset = 0;
  bool _hasMoreSessions = false;
  bool _loadingMoreSessions = false;

  /// Raw session ids from every loaded page, before any source filtering.
  /// This drives page deduplication and scan-exhaustion detection only. The
  /// live OFFSET scan is not a deletion-safe snapshot: activity can reorder a
  /// session into an already-scanned prefix between requests.
  final Set<String> _rawLoadedIds = {};

  /// Bumped by every full refresh ([_fetchSessions]). Every async continuation
  /// captures it and discards stale results before mutating the accumulator or
  /// UI state a newer refresh owns.
  int _sessionsGeneration = 0;

  /// Consecutive pages (across refresh + load-more) that contributed zero
  /// unseen ids. See [_requiredZeroNewPages] for why one such page does NOT
  /// prove end-of-list when pins exist.
  int _zeroNewIdPages = 0;

  /// Upper bound on the number of pinned sessions, taken as the max count
  /// of pinned rows seen on any single page. The stock gateway repeats
  /// EVERY pin on EVERY page (window rows + back-fill, deduped), so one
  /// page's pinned count already bounds the whole pin set.
  int _seenPinCount = 0;

  /// Consecutive zero-new-ids pages that prove this best-effort OFFSET scan is
  /// exhausted. This is not proof of a deletion-complete snapshot: activity
  /// can reorder rows between requests, so absence must never delete local
  /// metadata. For stopping pagination, the stock pin contract gives us:
  /// a non-pinned row appears only in its own LIMIT/OFFSET window
  /// (windows are disjoint, pins are the only repeats), so a mid-store
  /// window with zero unseen ids must consist ENTIRELY of pins — and each
  /// such window consumes pageSize DISTINCT pins. k consecutive zero-new
  /// windows therefore require k*pageSize pins to exist. Once k exceeds
  /// pinCount ~/ pageSize, the newest zero-new window cannot be mid-store:
  /// it is past the end under the stock pin-window contract, so this scan can
  /// stop without claiming that its mutable pages form a deletion snapshot.
  /// With no pins at all, one zero-new page already proves it (a full
  /// all-pin window cannot exist when pinCount < pageSize).
  /// The bound is exact because EVERY stock response carries EVERY pin
  /// (window pins plus the include_pinned back-fill of the rest,
  /// list_sessions_rich), so _seenPinCount equals the true pin count from
  /// page one. Reviewer reproduction covered: offset 2 returning only
  /// seen pins s2,s3 counts 1 < 2 required, so paging continues to the
  /// unseen s4,s5 at offset 4.
  static int _requiredZeroNewPages(int pinCount, int pageSize) =>
      pinCount == 0 ? 1 : pinCount ~/ pageSize + 1;

  bool _healthOk = false;
  final Set<String> _deletingSessionIds = {};
  final Set<String> _branchingSessionIds = {};

  SessionSearchPreferences? _searchPreferences;
  SessionSearchMode _searchMode = SessionSearchMode.local;
  AiSearchModel? _aiSearchModel;
  AiSearchQueryRewriter? _aiRewriter;
  String? _aiRewrittenQuery;
  bool _loadingAiModels = false;
  DashboardClient? _searchDashboard;
  SessionSearchClient? _searchClient;
  Timer? _searchDebounceTimer;
  int _searchRequestGeneration = 0;

  /// Query currently reflected by [_serverResults]; guards against an earlier
  /// slow response overwriting the results of a newer query.
  String _serverQuery = '';
  List<SessionSearchHit>? _serverResults;
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
      httpClient: widget.testHttpClient,
    );
    if (widget.connection.desktopGatewayUrl?.trim().isNotEmpty == true) {
      try {
        _desktopGateway = DesktopGatewayClient.fromConnection(
          widget.connection,
        );
      } on ArgumentError {
        _desktopGateway = null;
      }
    }
    _loadProfiles();
    _loadChatSpaces();
    _loadSearchPreferences();
    _checkHealth();
  }

  /// Restores the saved search mode for this connection.
  ///
  /// Failing to read preferences must not break the session list, so any
  /// error leaves the local default in place.
  Future<void> _loadSearchPreferences() async {
    try {
      final preferences = await SessionSearchPreferences.open();
      if (!mounted) return;
      setState(() {
        _searchPreferences = preferences;
        _searchMode = preferences.readMode(
          connectionIdentity: _searchConnectionIdentity,
        );
        _aiSearchModel = preferences.readAiModel(
          connectionIdentity: _searchConnectionIdentity,
        );
      });
    } catch (_) {
      // Keep SessionSearchMode.local.
    }
  }

  /// Namespaces stored search preferences, matching the chat model override
  /// convention so two connections to the same host stay independent.
  String get _searchConnectionIdentity =>
      '${widget.connection.baseUrl}|'
      '${widget.connection.gatewayPrefix ?? ''}|'
      '${widget.connection.desktopGatewayUrl ?? ''}';

  /// Server search reaches the dashboard, which the gateway connection alone
  /// does not guarantee is reachable.
  bool get _serverSearchAvailable => widget.connection.host.trim().isNotEmpty;

  SessionSearchClient _ensureSearchClient() {
    final existing = _searchClient;
    if (existing != null) return existing;

    final dashboard = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? '',
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
      apiKey: widget.connection.apiKey,
    );
    final created = SessionSearchClient(
      baseUrl: dashboard.baseUrl,
      headers: dashboard.authHeaders,
    );
    _searchDashboard = dashboard;
    _searchClient = created;
    return created;
  }

  Future<void> _setSearchMode(SessionSearchMode mode) async {
    if (mode == _searchMode) return;
    if (mode == SessionSearchMode.ai && _aiSearchModel == null) {
      final selected = await _showAiModelSelector();
      if (selected == null) return;
    }
    setState(() {
      _searchRequestGeneration++;
      _searchMode = mode;
      _serverResults = null;
      _searchError = null;
      _serverQuery = '';
      _aiRewrittenQuery = null;
    });
    await _searchPreferences?.saveMode(
      connectionIdentity: _searchConnectionIdentity,
      mode: mode,
    );
    if (mode != SessionSearchMode.local) {
      _onSearchChanged(_searchController.text);
    }
  }

  /// Handles a keystroke in the search bar.
  ///
  /// Local mode only needs a rebuild. Server mode debounces so typing a word
  /// issues one request instead of one per character.
  void _onSearchChanged(String raw) {
    setState(() {});
    if (_searchMode == SessionSearchMode.local) return;

    _searchDebounceTimer?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _searchRequestGeneration++;
        _serverResults = null;
        _searchError = null;
        _searching = false;
        _serverQuery = '';
        _aiRewrittenQuery = null;
      });
      return;
    }
    _searchDebounceTimer = Timer(
      _searchDebounce,
      () => _runServerSearch(query),
    );
  }

  AiSearchQueryRewriter _ensureAiRewriter() {
    final existing = _aiRewriter;
    if (existing != null) return existing;
    final created = AiSearchQueryRewriter(
      baseUrl: widget.connection.baseUrl,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
      apiKey: widget.connection.apiKey,
    );
    _aiRewriter = created;
    return created;
  }

  Future<AiSearchModel?> _showAiModelSelector() async {
    if (_loadingAiModels) return null;
    setState(() => _loadingAiModels = true);
    try {
      final options = await _client.getModelOptions();
      final choices = AiSearchModel.configuredFromOptions(options);
      if (choices.isEmpty) {
        throw StateError('Hermes returned no configured selectable models.');
      }

      if (!mounted) return null;
      final selection = await showModalBottomSheet<AiSearchModel>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI search model',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'The model only rewrites your question into a short '
                        'full-text query. Hermes uses the provider credentials '
                        'already configured on the host.',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: choices.length,
                    itemBuilder: (_, index) {
                      final choice = choices[index];
                      final isSelected =
                          _aiSearchModel?.provider == choice.provider &&
                          _aiSearchModel?.model == choice.model;
                      return ListTile(
                        leading: Icon(
                          choice.isRecommended
                              ? Icons.savings_outlined
                              : Icons.smart_toy_outlined,
                        ),
                        title: Text(choice.model),
                        subtitle: Text(
                          choice.isRecommended
                              ? '${choice.provider} • Recommended: small and inexpensive'
                              : choice.provider,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle)
                            : null,
                        onTap: () => Navigator.pop(sheetContext, choice),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selection == null || !mounted) return null;
      setState(() => _aiSearchModel = selection);
      await _searchPreferences?.saveAiModel(
        connectionIdentity: _searchConnectionIdentity,
        selection: selection,
      );
      if (_searchMode == SessionSearchMode.ai &&
          _searchController.text.trim().isNotEmpty) {
        unawaited(_runServerSearch(_searchController.text.trim()));
      }
      return selection;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load AI search models: $error')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _loadingAiModels = false);
    }
  }

  Future<void> _runServerSearch(String query) async {
    if (!mounted || query.isEmpty) return;
    final requestGeneration = ++_searchRequestGeneration;
    final requestMode = _searchMode;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    bool requestIsCurrent() =>
        mounted &&
        requestGeneration == _searchRequestGeneration &&
        _searchController.text.trim() == query;

    try {
      var effectiveQuery = query;
      if (requestMode == SessionSearchMode.ai) {
        final selected = _aiSearchModel;
        if (selected == null) {
          throw const AiSearchRewriteException(
            'Choose an AI search model before using AI search.',
          );
        }
        effectiveQuery = await _ensureAiRewriter().rewrite(
          query: query,
          provider: selected.provider,
          model: selected.model,
        );
      }
      final hits = await _ensureSearchClient().search(effectiveQuery);
      if (!requestIsCurrent()) return;
      setState(() {
        _serverResults = hits;
        _serverQuery = query;
        _aiRewrittenQuery = requestMode == SessionSearchMode.ai
            ? effectiveQuery
            : null;
        _searching = false;
      });
    } on AiSearchRewriteException catch (error) {
      if (!requestIsCurrent()) return;
      setState(() {
        _searchError = error.message;
        _serverResults = null;
        _searching = false;
      });
    } on SessionSearchException catch (error) {
      if (!requestIsCurrent()) return;
      setState(() {
        _searchError = error.message;
        _serverResults = null;
        _searching = false;
      });
    } catch (error) {
      if (!requestIsCurrent()) return;
      setState(() {
        _searchError = 'Session search failed: $error';
        _serverResults = null;
        _searching = false;
      });
    }
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _profiles = ConnectionManager(prefs).getConnections());
  }

  Future<void> _loadChatSpaces() async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: widget.connection.id);
    final state = await store.load();
    if (!mounted) return;
    setState(() {
      _spaceStore = store;
      _spaceState = state;
    });
  }

  Future<void> _switchProfile(String profileId) async {
    if (profileId == widget.connection.id) return;
    final profile = _profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_connection_id', profile.id);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionListScreen(
          connection: profile,
          turnApplicationController: widget.turnApplicationController,
        ),
      ),
    );
  }

  PopupMenuButton<String> _buildProfileSelector() {
    return PopupMenuButton<String>(
      tooltip: 'Switch profile',
      icon: const Icon(Icons.account_tree_outlined),
      onSelected: _switchProfile,
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('Profile', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        ..._profiles.map(
          (profile) => PopupMenuItem<String>(
            value: profile.id,
            child: Row(
              children: [
                Icon(
                  profile.id == widget.connection.id
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(profile.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _checkHealth() async {
    final ok = await _client.healthCheck();
    setState(() => _healthOk = ok);
    if (ok) _fetchSessions();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchClient?.close();
    _searchDashboard?.close();
    _aiRewriter?.close();
    _searchController.dispose();
    _desktopGateway?.close();
    _client.close();
    super.dispose();
  }

  Future<String?> _askForName({
    required String title,
    required String initialValue,
    required String actionLabel,
  }) => showSessionNameDialog(
    context: context,
    title: title,
    initialValue: initialValue,
    actionLabel: actionLabel,
  );

  Future<void> _renameSession(Session session) async {
    final gateway = _desktopGateway;
    if (gateway == null) return;
    final title = await _askForName(
      title: 'Rename chat',
      initialValue: session.title,
      actionLabel: 'Rename',
    );
    if (title == null || !mounted) return;
    try {
      await gateway.renameSession(sessionId: session.id, title: title);
      await _fetchSessions();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename chat: $error')));
    }
  }

  Future<void> _branchSession(Session session) async {
    final gateway = _desktopGateway;
    if (gateway == null || _branchingSessionIds.contains(session.id)) return;
    final knownSessionIds = _sessions.map((item) => item.id).toSet();
    String? requestedName;
    setState(() => _branchingSessionIds.add(session.id));
    try {
      final name = await _askForName(
        title: 'Branch chat',
        initialValue: '${session.title} branch',
        actionLabel: 'Create branch',
      );
      if (name == null || !mounted) return;
      requestedName = name;
      await gateway.branchSession(sessionId: session.id, name: name);
      await _fetchSessions();
      if (!mounted) return;
      _showBranchCreated();
    } catch (error) {
      if (!mounted) return;
      await _fetchSessions();
      if (!mounted) return;
      final branchAppeared = _sessions.any(
        (item) =>
            !knownSessionIds.contains(item.id) &&
            requestedName != null &&
            item.title.trim().toLowerCase() ==
                requestedName.trim().toLowerCase(),
      );
      if (branchAppeared) {
        _showBranchCreated();
        return;
      }
      final message = error is JsonRpcError && error.code == 4008
          ? 'This chat has no messages available in the Desktop session yet.'
          : 'Could not branch chat: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _branchingSessionIds.remove(session.id));
      }
    }
  }

  void _showBranchCreated() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Branch created in Hermes history.')),
    );
  }

  Future<void> _handleSessionAction(String action, Session session) async {
    // PopupMenuButton invokes this while its route is still being removed.
    // Defer route-producing actions so Flutter has completed that teardown.
    await Future<void>.delayed(kThemeAnimationDuration);
    if (!mounted) return;
    switch (action) {
      case 'move':
        await _moveSession(session);
      case 'rename':
        await _renameSession(session);
      case 'branch':
        await _branchSession(session);
      case 'delete':
        await _confirmDeleteSession(session);
    }
  }

  Future<void> _moveSession(Session session) async {
    final store = _spaceStore;
    if (store == null) return;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Move chat'),
              subtitle: Text('Choose its destination space'),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Unassigned'),
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            for (final space in _spaceState.spaces)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(space.name),
                trailing: _spaceState.spaceIdForSession(session.id) == space.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(sheetContext, space.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await store.assignSession(session.id, selected.isEmpty ? null : selected);
    final state = await store.load();
    if (!mounted) return;
    setState(() => _spaceState = state);
  }

  Future<void> _fetchSessions() async {
    final generation = ++_sessionsGeneration;
    setState(() {
      _loading = true;
      _loadingMoreSessions = false;
      _error = null;
    });
    // Full refresh: the paging accumulator belongs only to this generation.
    _rawLoadedIds.clear();
    _zeroNewIdPages = 0;
    _seenPinCount = 0;
    try {
      final page = await _client.getSessionsPage(limit: _sessionPageSize);
      if (!mounted || generation != _sessionsGeneration) return;
      final prefs =
          await (widget.testPreferencesLoader?.call() ??
              SharedPreferences.getInstance());
      if (!mounted || generation != _sessionsGeneration) return;
      final key = 'excluded_session_sources_${widget.connection.id}';
      final excluded = prefs.getStringList(key) ?? [];
      final filtered = page.sessions
          .where((s) => !excluded.contains(s.source))
          .toList();
      final store =
          _spaceStore ??
          ChatSpaceStore(prefs, connectionId: widget.connection.id);
      // Scan exhaustion is decided client-side, never by `has_more`: the stock
      // gateway computes it from the non-pinned rows in the combined
      // response (api_server.py: windowed >= limit), so any window holding
      // a pin can report has_more=false while rows still exist past the
      // offset. A single zero-new-ids page is NOT proof either: stock
      // include_pinned repeats EVERY pin on EVERY page, so a later base
      // window made entirely of already-seen pins contributes no new ids
      // even while unseen non-pinned rows remain further along. The
      // stopping rule lives in _requiredZeroNewPages: k consecutive
      // zero-new windows must consist entirely of pins, windows are
      // disjoint, so k * pageSize pins exist — once that exceeds the pin
      // bound observed on the pages, this scan is exhausted.
      _notePageForExhaustion(page.sessions);
      final scanExhausted = _isScanExhausted;
      final spaceState = await store.load();
      if (!mounted || generation != _sessionsGeneration) return;
      setState(() {
        _spaceStore = store;
        _spaceState = spaceState;
        _sessions = filtered;
        // Advance by the REQUESTED window, not the returned row count: the
        // stock gateway back-fills pinned sessions past `limit`, so a page
        // can carry more rows than the window and advancing by
        // sessions.length would skip the gap between the window and the
        // back-fill on the next request.
        _sessionsOffset = _sessionPageSize;
        _hasMoreSessions = !scanExhausted;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _sessionsGeneration) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Folds one page into the exhaustion bookkeeping: accumulates raw ids,
  /// tracks the pin bound, and counts consecutive zero-new-ids pages.
  void _notePageForExhaustion(List<Session> pageSessions) {
    final pageIds = pageSessions.map((session) => session.id).toSet();
    final newIds = pageIds.difference(_rawLoadedIds);
    _rawLoadedIds.addAll(pageIds);
    // The stock gateway repeats every pin on every page (window rows plus
    // back-fill, deduped), so any single page's pinned count already
    // bounds the total pin set; take the max to stay safe against pages
    // fetched across a pin/unpin race.
    final pinsOnPage = pageSessions.where((session) => session.pinned).length;
    if (pinsOnPage > _seenPinCount) _seenPinCount = pinsOnPage;
    if (newIds.isEmpty) {
      _zeroNewIdPages++;
    } else {
      _zeroNewIdPages = 0;
    }
  }

  bool get _isScanExhausted =>
      _zeroNewIdPages >= _requiredZeroNewPages(_seenPinCount, _sessionPageSize);

  /// Append the next page of sessions when the list is scrolled near bottom.
  Future<void> _loadMoreSessions() async {
    if (_loadingMoreSessions || !_hasMoreSessions) return;
    final generation = _sessionsGeneration;
    setState(() => _loadingMoreSessions = true);
    try {
      final page = await _client.getSessionsPage(
        limit: _sessionPageSize,
        offset: _sessionsOffset,
      );
      if (!mounted || generation != _sessionsGeneration) return;
      final prefs =
          await (widget.testPreferencesLoader?.call() ??
              SharedPreferences.getInstance());
      // SharedPreferences may suspend long enough for a full refresh to
      // replace this generation. Recheck before touching paging state.
      if (!mounted || generation != _sessionsGeneration) return;
      final excluded =
          prefs.getStringList(
            'excluded_session_sources_${widget.connection.id}',
          ) ??
          [];
      final existing = _sessions.map((s) => s.id).toSet();
      final incoming = page.sessions
          .where(
            (s) => !excluded.contains(s.source) && !existing.contains(s.id),
          )
          .toList();
      // Same end-of-list rule as the initial page: a zero-new page only
      // proves scan exhaustion once the consecutive-zero count passes the pin
      // bound (see _fetchSessions). Until then keep paging — a pin-only
      // window is not the end.
      _notePageForExhaustion(page.sessions);
      final scanExhausted = _isScanExhausted;
      setState(() {
        _sessions = [..._sessions, ...incoming];
        // Advance by the requested window, never the returned row count:
        // pinned back-fills arrive past `limit` and would otherwise shift
        // the offset past unfetched window rows (dedup below keeps the
        // repeated pins from showing twice).
        _sessionsOffset += _sessionPageSize;
        _hasMoreSessions = !scanExhausted;
        _loadingMoreSessions = false;
      });
    } catch (e) {
      if (!mounted || generation != _sessionsGeneration) return;
      // Keep the loaded pages; surface the failure and allow a retry on the
      // next scroll instead of losing the list.
      setState(() => _loadingMoreSessions = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load more chats: $e')));
    }
  }

  bool _onListScroll(ScrollNotification notification) {
    if (!_hasMoreSessions || _loadingMoreSessions) return false;
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 300) {
      _loadMoreSessions();
    }
    return false;
  }

  Future<void> _confirmDeleteSession(Session session) async {
    final title = session.title.trim().isEmpty
        ? 'Untitled session'
        : session.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'Delete "$title" from the remote Hermes history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSession(session);
    }
  }

  Future<void> _deleteSession(Session session) async {
    if (_deletingSessionIds.contains(session.id)) return;
    setState(() => _deletingSessionIds.add(session.id));

    try {
      await _client.deleteSession(session.id);
      await _spaceStore?.assignSession(session.id, null);
      if (_spaceStore != null) {
        _spaceState = await _spaceStore!.load();
      }
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((item) => item.id == session.id);
        _deletingSessionIds.remove(session.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session deleted from remote Hermes.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingSessionIds.remove(session.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete session: $e')));
    }
  }

  Future<void> _createNewSession() async {
    final sessionId = GatewayChatClient.generateSessionId();
    final session = Session(
      id: sessionId,
      title: 'New Chat',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: DateTime.now().millisecondsSinceEpoch.toDouble() / 1000,
    );
    if (_spaceScope.kind == ChatSpaceScopeKind.space && _spaceStore != null) {
      await _spaceStore!.assignSession(sessionId, _spaceScope.spaceId);
      _spaceState = await _spaceStore!.load();
      if (!mounted) return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          connection: widget.connection,
          session: session,
          turnApplicationController: widget.turnApplicationController,
        ),
      ),
    );
  }

  String _formatTime(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }

  void _openScreen(Widget screen) {
    Navigator.pop(context); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  String get _spaceScopeLabel {
    return switch (_spaceScope.kind) {
      ChatSpaceScopeKind.all => 'All chats',
      ChatSpaceScopeKind.unassigned => 'Unassigned',
      ChatSpaceScopeKind.space =>
        _spaceState.spaces
                .where((space) => space.id == _spaceScope.spaceId)
                .map((space) => space.name)
                .firstOrNull ??
            'Space',
    };
  }

  void _openSpaces({bool closeDrawer = false}) {
    final store = _spaceStore;
    if (store == null) return;
    if (closeDrawer) Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (spaceContext) => SpacesScreen(
          store: store,
          sessions: _sessions,
          onScopeSelected: (scope) {
            setState(() => _spaceScope = scope);
            Navigator.pop(spaceContext);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        actions: [
          _buildProfileSelector(),
          if (!_healthOk)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchSessions,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Chat',
        onPressed: _createNewSession,
        child: const Icon(Icons.chat, color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Brand header in drawer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HERMES',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AF37),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connection.label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            ListTile(
              key: const Key('open-spaces'),
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Spaces'),
              subtitle: Text(_spaceScopeLabel),
              enabled: _spaceStore != null,
              onTap: () => _openSpaces(closeDrawer: true),
            ),
            ListTile(
              key: const Key('open-workspace'),
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Workspace'),
              subtitle: const Text('Projects, Activity — new navigation'),
              onTap: () {
                Navigator.pop(context);
                _openScreen(
                  WorkspaceScreen(
                    connection: widget.connection,
                    // Home opens chats itself now; without the owner they
                    // would lose durable turn recovery.
                    turnApplicationController: widget.turnApplicationController,
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Memory'),
              onTap: () =>
                  _openScreen(MemoryScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Cron Jobs'),
              onTap: () =>
                  _openScreen(CronScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Skills'),
              onTap: () =>
                  _openScreen(SkillsScreen(connection: widget.connection)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () =>
                  _openScreen(SettingsScreen(connection: widget.connection)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_healthOk) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to ${widget.connection.baseUrl}...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure the Gateway API Server is running\n(hermes gateway status)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _checkHealth, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Connection issue',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchSessions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No sessions yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to start a new chat',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final rawQuery = _searchController.text.trim();
    final localQuery = rawQuery.toLowerCase();
    final scopedSessions = _spaceState.sessionsFor(_sessions, _spaceScope);
    final aiMode = _searchMode == SessionSearchMode.ai;
    final serverMode = _searchMode != SessionSearchMode.local;
    final serverHitsCurrent = serverMode && _serverQuery == rawQuery
        ? _serverResults
        : null;
    final visibleSessions = rawQuery.isEmpty
        ? scopedSessions
        : serverMode
        ? _spaceState.sessionsFor(
            serverHitsCurrent?.map((hit) => hit.session).toList() ?? const [],
            _spaceScope,
          )
        : scopedSessions
              .where(
                (session) =>
                    session.title.toLowerCase().contains(localQuery) ||
                    session.preview.toLowerCase().contains(localQuery) ||
                    session.model.toLowerCase().contains(localQuery),
              )
              .toList();
    final snippetsBySession = <String, SessionSearchHit>{
      for (final hit in serverHitsCurrent ?? const <SessionSearchHit>[])
        hit.session.id: hit,
    };

    return RefreshIndicator(
      onRefresh: rawQuery.isNotEmpty && serverMode
          ? () => _runServerSearch(rawQuery)
          : _fetchSessions,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onListScroll,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount:
              visibleSessions.length +
              1 +
              (_hasMoreSessions || _loadingMoreSessions ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == visibleSessions.length + 1) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: _loadingMoreSessions
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load more…'),
                ),
              );
            }
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        key: const Key('active-space'),
                        avatar: const Icon(Icons.folder_outlined, size: 18),
                        label: Text(_spaceScopeLabel),
                        onPressed: _spaceStore == null ? null : _openSpaces,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SearchBar(
                      controller: _searchController,
                      leading: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.search),
                      hintText: aiMode
                          ? 'Ask AI to find a conversation'
                          : serverMode
                          ? 'Search all message content'
                          : 'Search loaded chats',
                      trailing: [
                        if (rawQuery.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchDebounceTimer?.cancel();
                              _searchController.clear();
                              setState(() {
                                _searchRequestGeneration++;
                                _serverResults = null;
                                _searchError = null;
                                _serverQuery = '';
                                _aiRewrittenQuery = null;
                                _searching = false;
                              });
                            },
                          ),
                        if (aiMode)
                          IconButton(
                            tooltip: 'Change AI search model',
                            icon: _loadingAiModels
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.tune),
                            onPressed: _loadingAiModels
                                ? null
                                : _showAiModelSelector,
                          ),
                        PopupMenuButton<SessionSearchMode>(
                          tooltip: 'Search mode',
                          icon: Icon(
                            aiMode
                                ? Icons.auto_awesome
                                : serverMode
                                ? Icons.manage_search
                                : Icons.phone_android,
                          ),
                          onSelected: _setSearchMode,
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(
                              value: SessionSearchMode.local,
                              checked: !serverMode,
                              child: const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.phone_android),
                                title: Text('On-device'),
                                subtitle: Text('Titles, previews, and models'),
                              ),
                            ),
                            CheckedPopupMenuItem(
                              value: SessionSearchMode.server,
                              enabled: _serverSearchAvailable,
                              checked: _searchMode == SessionSearchMode.server,
                              child: const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.manage_search),
                                title: Text('Full-text'),
                                subtitle: Text('All stored message content'),
                              ),
                            ),
                            CheckedPopupMenuItem(
                              value: SessionSearchMode.ai,
                              enabled: _serverSearchAvailable,
                              checked: aiMode,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.auto_awesome),
                                title: const Text('AI + full-text'),
                                subtitle: Text(
                                  _aiSearchModel == null
                                      ? 'Choose a small model to rewrite queries'
                                      : '${_aiSearchModel!.provider} • ${_aiSearchModel!.model}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      onChanged: _onSearchChanged,
                      onSubmitted: (value) {
                        _searchDebounceTimer?.cancel();
                        if (serverMode && value.trim().isNotEmpty) {
                          _runServerSearch(value.trim());
                        }
                      },
                    ),
                    if (aiMode && _aiRewrittenQuery != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'AI searched for: $_aiRewrittenQuery',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_searchError != null) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _searchError!,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _setSearchMode(SessionSearchMode.local),
                                child: const Text('Use on-device'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (rawQuery.isEmpty && scopedSessions.isEmpty) ...[
                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          _spaceScope.kind == ChatSpaceScopeKind.space
                              ? 'No chats in this space yet. Tap + to start one.'
                              : 'No unassigned chats.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (serverMode &&
                        rawQuery.isNotEmpty &&
                        !_searching &&
                        _searchError == null &&
                        serverHitsCurrent != null &&
                        serverHitsCurrent.isEmpty) ...[
                      const SizedBox(height: 16),
                      const Center(child: Text('No message-content matches')),
                    ],
                  ],
                ),
              );
            }
            final session = visibleSessions[index - 1];
            final searchHit = snippetsBySession[session.id];
            final isDeleting = _deletingSessionIds.contains(session.id);
            final isBranching = _branchingSessionIds.contains(session.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                enabled: !isDeleting && !isBranching,
                leading: Icon(
                  session.isActive ? Icons.chat : Icons.chat_bubble_outline,
                  color: session.isActive
                      ? const Color(0xFFD4AF37)
                      : Colors.grey,
                ),
                trailing: isDeleting || isBranching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        tooltip: 'Chat actions',
                        onSelected: (action) =>
                            _handleSessionAction(action, session),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'move',
                            child: ListTile(
                              leading: Icon(Icons.drive_file_move_outline),
                              title: Text('Move to space'),
                            ),
                          ),
                          if (_desktopGateway != null)
                            const PopupMenuItem(
                              value: 'rename',
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Rename'),
                              ),
                            ),
                          if (_desktopGateway != null)
                            const PopupMenuItem(
                              value: 'branch',
                              child: ListTile(
                                leading: Icon(Icons.call_split_outlined),
                                title: Text('Branch'),
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                            ),
                          ),
                        ],
                      ),
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${session.messageCount} msgs \u2022 ${session.model} \u2022 ${_formatTime(session.startedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (searchHit?.snippet.isNotEmpty == true)
                      Text(
                        searchHit!.snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    else if (session.preview.isNotEmpty)
                      Text(
                        session.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
                isThreeLine:
                    searchHit?.snippet.isNotEmpty == true ||
                    session.preview.isNotEmpty,
                onLongPress: isDeleting ? null : () => _renameSession(session),
                onTap: isDeleting
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              connection: widget.connection,
                              session: session,
                              turnApplicationController:
                                  widget.turnApplicationController,
                            ),
                          ),
                        );
                      },
              ),
            );
          },
        ),
      ),
    );
  }
}
