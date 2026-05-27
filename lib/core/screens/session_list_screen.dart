/// Session list screen that displays sessions from a connected Hermes dashboard.
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';

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

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _fetchSessions();
  }

  @override
  void dispose() {
    _client?.close();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchSessions,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            ),
          );
        },
      ),
    );
  }
}
