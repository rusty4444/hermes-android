/// Session list screen — messaging-app style with conversation items,
/// new chat creation, and FTS5 search.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/connection_manager.dart';
import '../services/ws_client.dart';
import '../utils/responsive.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'memory_screen.dart';
import 'cron_screen.dart';

class SessionListScreen extends StatefulWidget {
  final SavedConnection connection;
  const SessionListScreen({required this.connection, super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<Session> _sessions = [];
  bool _loading = true;
  String? _error;
  ApiClient? _client;
  bool _creating = false;

  // Search state
  bool _searching = false;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _fetchSessions();
  }

  @override
  void dispose() {
    _client?.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sessions = await _client!.getSessions(widget.connection.baseUrl);
      if (!mounted) return;
      setState(() { _sessions = sessions; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Create a new chat session via WebSocket, then navigate to it.
  Future<void> _createNewSession() async {
    // Ask for a name first
    final nameController = TextEditingController(text: 'New Chat');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Chat'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Session name',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? 'New Chat' : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = nameController.text.trim();
              Navigator.pop(ctx, n.isEmpty ? 'New Chat' : n);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || !mounted) return;

    setState(() => _creating = true);
    try {
      // Get the auth token for WebSocket connection
      final token = await _client!.getToken(widget.connection.baseUrl);
      final ws = WsClient(widget.connection.baseUrl, token: token);
      await ws.connect();
      final sessionId = await ws.createSession();
      ws.close();

      if (!mounted) return;
      setState(() => _creating = false);

      // Refresh to get the new session's details
      await _fetchSessions();

      // Find the newly created session and open it
      final newSession = _sessions.where((s) => s.id == sessionId).firstOrNull;
      if (newSession != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              connection: widget.connection,
              session: newSession,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create session: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; _searchError = null; });
      return;
    }
    setState(() { _searchLoading = true; _searchError = null; });
    try {
      final data = await _client!.searchSessions(widget.connection.baseUrl, query.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _searchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _searchError = e.toString(); _searchLoading = false; });
    }
  }

  void _onSearchResultTap(Map<String, dynamic> result) {
    final sessionId = result['session_id'] as String? ?? '';
    if (sessionId.isEmpty) return;
    final session = Session(
      id: sessionId,
      title: _bestSnippet(result['snippet'] as String?, 40),
      model: result['model'] as String? ?? '',
      messageCount: 0,
      isActive: false,
      preview: result['snippet'] as String? ?? '',
      createdAt: result['session_started'] as String? ?? '',
    );
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(connection: widget.connection, session: session),
    ));
  }

  Future<void> _deleteSession(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text('Delete "${session.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client!.deleteSession(widget.connection.baseUrl, session.id);
      setState(() => _sessions.removeWhere((s) => s.id == session.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  /// Relative time formatting.
  String _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }

  String _bestSnippet(String? text, int maxLen) {
    if (text == null || text.isEmpty) return '';
    // Strip HTML highlight tags and role prefixes
    var cleaned = text
        .replaceAll(RegExp(r'<b>|</b>'), '')
        .replaceFirst(RegExp(r'^(user|assistant|system|tool):\s*'), '');
    if (cleaned.length > maxLen) cleaned = '${cleaned.substring(0, maxLen)}…';
    return cleaned;
  }

  /// Get initials for avatar circle.
  String _initials(String title) {
    if (title.isEmpty) return '?';
    final words = title.split(RegExp(r'[\s_-]+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) {
      return '${words[0][0]}${words[words.length - 1][0]}'.toUpperCase();
    }
    return title[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _searching ? _searchAppBar() : _normalAppBar(),
      drawer: _buildNavDrawer(),
      body: _searching ? _searchBody() : _browseBody(),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton(
              onPressed: _creating ? null : _createNewSession,
              tooltip: 'New Chat',
              child: _creating
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.edit, color: Colors.black),
            ),
    );
  }

  Widget _buildNavDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D0D),
      child: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFD4AF37), width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFFD4AF37)),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'HERMES',
                    style: GoogleFonts.cinzel(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      fontSize: 20,
                      color: const Color(0xFFD4AF37),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.psychology, color: Color(0xFFD4AF37)),
              title: const Text('Memory'),
              onTap: () {
                Navigator.pop(context); // close drawer
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => MemoryScreen(connection: widget.connection),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: Color(0xFFD4AF37)),
              title: const Text('Cron Jobs'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CronScreen(connection: widget.connection),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFFD4AF37)),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SettingsScreen(connection: widget.connection),
                ));
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${widget.connection.host}:${widget.connection.port}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _normalAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Text(
        'HERMES',
        style: GoogleFonts.cinzel(
          fontWeight: FontWeight.w700,
          letterSpacing: 6,
          fontSize: 22,
          color: const Color(0xFFD4AF37),
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
          tooltip: 'Search',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : _fetchSessions,
        ),
      ],
    );
  }

  AppBar _searchAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        cursorColor: const Color(0xFFD4AF37),
        decoration: const InputDecoration(
          hintText: 'Search messages…',
          hintStyle: TextStyle(color: Colors.white38),
          border: InputBorder.none,
        ),
        onChanged: _doSearch,
      ),
      actions: [
        IconButton(icon: const Icon(Icons.close), onPressed: () {
          setState(() {
            _searching = false;
            _searchController.clear();
            _searchResults = [];
            _searchError = null;
          });
        }),
      ],
    );
  }

  Widget _searchBody() {
    if (_searchLoading) return const Center(child: CircularProgressIndicator());
    if (_searchError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text('Search error', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(_searchError!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ]),
      ));
    }
    if (_searchController.text.trim().isNotEmpty && _searchResults.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off, size: 48, color: Colors.grey[700]),
        const SizedBox(height: 16),
        Text('No results', style: Theme.of(context).textTheme.titleMedium),
      ]));
    }
    if (_searchController.text.trim().isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search, size: 48, color: Colors.grey[700]),
        const SizedBox(height: 16),
        Text('Search all messages', style: Theme.of(context).textTheme.titleMedium),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final r = _searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.search, color: Color(0xFFD4AF37)),
            title: Text(_bestSnippet(r['snippet'] as String?, 80), maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _onSearchResultTap(r),
          ),
        );
      },
    );
  }

  Widget _browseBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: Colors.orange),
          const SizedBox(height: 16),
          Text('Connection issue', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _fetchSessions, child: const Text('Retry')),
        ]),
      ));
    }
    if (_sessions.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[800]),
        const SizedBox(height: 16),
        Text('No chats yet', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Tap the pencil to start a new chat', style: TextStyle(color: Colors.grey[600])),
      ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSessions,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72, color: Color(0xFF2A2A2A)),
        itemBuilder: (context, index) {
          final session = _sessions[index];
          final time = _relativeTime(session.createdAt);

          return Dismissible(
            key: Key(session.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Chat'),
                  content: Text('Delete "${session.title}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              return confirmed ?? false;
            },
            onDismissed: (_) async {
              try {
                await _client!.deleteSession(widget.connection.baseUrl, session.id);
                setState(() => _sessions.removeWhere((s) => s.id == session.id));
              } catch (_) {}
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                child: Text(
                  _initials(session.title),
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (session.model.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          session.model,
                          style: TextStyle(fontSize: 10, color: const Color(0xFFD4AF37).withValues(alpha: 0.8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        session.preview.isNotEmpty && session.preview != 'Tap to view session...'
                            ? session.preview
                            : '${session.messageCount} messages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ),
                    if (session.isActive)
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD4AF37),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(connection: widget.connection, session: session),
                ));
              },
            ),
          );
        },
      ),
    );
  }
}
