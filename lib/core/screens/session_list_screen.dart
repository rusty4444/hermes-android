/// Session list screen that displays sessions from a connected Hermes dashboard.
/// Supports browse mode (all sessions) and search mode (FTS5-powered).
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sessions = await _client!.getSessions(widget.connection.baseUrl);
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _searchLoading = true;
      _searchError = null;
    });

    try {
      final data = await _client!.searchSessions(
        widget.connection.baseUrl,
        query.trim(),
      );
      setState(() {
        _searchResults =
            (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _searchLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchError = e.toString();
        _searchLoading = false;
      });
    }
  }

  void _onSearchResultTap(Map<String, dynamic> result) {
    final sessionId = result['session_id'] as String? ?? '';
    if (sessionId.isEmpty) return;

    // Construct a minimal session to pass to ChatScreen.
    // The source/model/session_started fields come from the search result.
    // We don't have message count or preview from search, so use the available fields.
    final session = Session(
      id: sessionId,
      title: _bestSnippet(result['snippet'] as String?, 40),
      model: (result['model'] as String?) ?? '',
      messageCount: 0,
      isActive: false,
      preview: result['snippet'] as String? ?? '',
      createdAt: (result['session_started'] as String?) ?? '',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          connection: widget.connection,
          session: session,
        ),
      ),
    );
  }

  /// Shorten a snippet to at most `maxLen` characters, on a word boundary.
  /// Strips Markdown formatting and leading role prefixes.
  static String _bestSnippet(String? raw, int maxLen) {
    if (raw == null || raw.isEmpty) return 'Untitled';
    // Remove FTS5 highlight markers
    var clean = raw.replaceAll(RegExp(r'<b>|</b>'), '');
    // Strip common role prefixes
    clean = clean.replaceFirst(
      RegExp(r'^(user|assistant|system|tool)\s*[:：]\s*', caseSensitive: false),
      '',
    ).trim();
    if (clean.length <= maxLen) return clean;
    final truncated = clean.substring(0, maxLen);
    final lastSpace = truncated.lastIndexOf(' ');
    return (lastSpace > 0 ? truncated.substring(0, lastSpace) : truncated) +
        '…';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _searching ? _searchAppBar() : _normalAppBar(),
      body: _searching ? _searchBody() : _browseBody(),
    );
  }

  AppBar _normalAppBar() {
    return AppBar(
      title: Text(widget.connection.label),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
          tooltip: 'Search sessions',
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(connection: widget.connection),
              ),
            );
          },
          tooltip: 'Settings',
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
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.white,
        decoration: const InputDecoration(
          hintText: 'Search sessions…',
          hintStyle: TextStyle(color: Colors.white54),
          border: InputBorder.none,
        ),
        onChanged: _doSearch,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _searching = false;
              _searchController.clear();
              _searchResults = [];
              _searchError = null;
            });
          },
          tooltip: 'Close search',
        ),
      ],
    );
  }

  Widget _searchBody() {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Search error', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_searchError!, style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_searchController.text.trim().isNotEmpty && _searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No results', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Type to search sessions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Search by message content across all sessions',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        final sessionId = result['session_id'] as String? ?? '';
        final snippet = result['snippet'] as String? ?? '';
        final model = result['model'] as String? ?? '';
        final source = result['source'] as String?;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.search, color: Colors.blue.shade300),
            title: Text(
              _bestSnippet(snippet, 80),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                if (model.isNotEmpty) ...[
                  Chip(
                    label: Text(model, style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                ],
                if (source != null && source.isNotEmpty)
                  Chip(
                    label: Text(source, style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            onTap: () => _onSearchResultTap(result),
          ),
        );
      },
    );
  }

  Widget _browseBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

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
              'Sessions will appear here when you start chatting',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                Icons.chat,
                color: session.isActive
                    ? Colors.blueAccent
                    : Colors.grey,
              ),
              title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${session.messageCount} messages • ${session.model}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (session.preview.isNotEmpty && session.preview != 'Tap to view session...')
                    Text(
                      session.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                    ),
                ],
              ),
              isThreeLine: session.preview.isNotEmpty && session.preview != 'Tap to view session...',
              trailing: session.isActive
                  ? Chip(
                      label: const Text('Active'),
                      backgroundColor: Colors.blueAccent,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    )
                  : null,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      connection: widget.connection,
                      session: session,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
