/// Chat screen for viewing session messages with Markdown rendering.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/connection_manager.dart';

class ChatScreen extends StatefulWidget {
  final SavedConnection connection;
  final Session session;

  const ChatScreen({
    required this.connection,
    required this.session,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;
  ApiClient? _client;

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _fetchMessages();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final messages = await _client!.getMessages(
        widget.connection.baseUrl,
        widget.session.id,
      );
      setState(() {
        _messages = messages;
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
        title: Text(
          widget.session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMessages,
            tooltip: 'Refresh',
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load messages',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchMessages,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final role = (msg['role'] as String?) ?? 'assistant';
        final content = (msg['content'] as String?) ?? '';
        final isUser = role == 'user';

        return _MessageBubble(content: content, isUser: isUser);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;

  const _MessageBubble({required this.content, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isUser) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 80,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: MarkdownBody(
            data: content,
            styleSheet: MarkdownStyleSheet(
              p: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
              code: TextStyle(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      );
    }

    // Assistant message
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: MarkdownBody(
        data: content,
        styleSheet: MarkdownStyleSheet(
          p: theme.textTheme.bodyMedium,
          h1: theme.textTheme.headlineSmall,
          h2: theme.textTheme.titleLarge,
          h3: theme.textTheme.titleMedium,
          code: TextStyle(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          blockquote: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
          ),
          a: TextStyle(color: theme.colorScheme.primary),
          em: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
          strong: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
