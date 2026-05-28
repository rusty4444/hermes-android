/// Chat screen with real-time streaming via WebSocket JSON-RPC.
/// Maintains a persistent WS connection for the session, streams
/// assistant responses token-by-token, and falls back to REST polling
/// when WS is unavailable.
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/connection_manager.dart';
import '../services/ws_client.dart';
import '../utils/responsive.dart';

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

  // Chat sending state
  final _textController = TextEditingController();
  bool _sending = false;
  bool _streaming = false; // true while assistant is responding

  // Streaming state
  WsClient? _ws;
  String _streamedContent = '';
  int _streamMessageId = -1; // index of streaming message in _messages

  // Media attachments
  final ImagePicker _picker = ImagePicker();
  List<XFile> _attachments = [];

  // Scroll management
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _fetchMessages();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _client?.close();
    _ws?.close();
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Track whether user has scrolled away from bottom.
  void _onScroll() {
    // Show scroll-to-bottom button when user scrolls more than 200px from bottom
    final atBottom = _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200;
    if (atBottom != !_showScrollToBottom && _streaming) {
      setState(() => _showScrollToBottom = !atBottom);
    }
  }

  /// Scroll to the bottom of the message list.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0, // reverse: true so 0 = bottom
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 404 means new session — just show empty chat
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('not found')) {
        setState(() {
          _messages = [];
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = errStr;
        _loading = false;
      });
    }
  }

  /// Try to send via WebSocket with streaming. Falls back to send + poll.
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final hasAttachments = _attachments.isNotEmpty;
    if (text.isEmpty && !hasAttachments) return;
    if (_sending || _streaming) return;

    // Build message content
    final msgContent = _buildMessageContent(text);

    // Save attachments before clearing them
    _textController.text = '';

    setState(() {
      _sending = true;
      _streaming = true;
      _showScrollToBottom = false;
      _attachments = [];
      _messages.insert(0, {'role': 'user', 'content': msgContent});
    });

    // Scroll to bottom after inserting user message
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // If we have images, encode and include them
    try {
      await _sendViaWebSocket(msgContent);
    } catch (_) {
      // WS failed, try REST fallback
      try {
        await _sendViaRest(msgContent);
      } catch (e) {
        _handleSendError(msgContent, e);
      }
    }
  }

  /// Build message content from text + attachments.
  String _buildMessageContent(String text) {
    if (_attachments.isEmpty) return text;
    final buf = StringBuffer(text);
    for (final file in _attachments) {
      buf.writeln();
      buf.writeln('[Attached: ${file.name}]');
    }
    return buf.toString();
  }

  /// Pick an image from gallery or camera.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() => _attachments.add(file));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image pick failed: $e')),
        );
      }
    }
  }

  /// Show attachment options.
  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Remove an attachment at index.
  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  /// Send message via WebSocket with real-time streaming.
  Future<void> _sendViaWebSocket(String text) async {
    _ws ??= WsClient(widget.connection.baseUrl, token: _client != null ? await _client!.getToken(widget.connection.baseUrl) : null);
    await _ws!.connect();
    await _ws!.resumeSession(widget.session.id);

    // Track streaming state
    _streamedContent = '';
    _streamMessageId = -1;

    await _ws!.sendMessageStreaming(
      text,
      onEvent: (event) {
        if (!mounted) return;
        _handleStreamEvent(event);
      },
    );

    // Streaming done — fetch final messages to get complete state
    if (mounted) {
      try {
        final messages = await _client!.getMessages(
          widget.connection.baseUrl,
          widget.session.id,
        );
        setState(() {
          _messages = messages;
          _streaming = false;
          _sending = false;
          _streamedContent = '';
          _streamMessageId = -1;
          _showScrollToBottom = false;
        });
      } catch (_) {
        setState(() {
          _streaming = false;
          _sending = false;
          _streamedContent = '';
          _streamMessageId = -1;
          _showScrollToBottom = false;
        });
      }
    }
  }

  /// Handle a stream event from the WebSocket.
  void _handleStreamEvent(StreamEvent event) {
    switch (event.type) {
      case 'assistant':
        // Accumulate streaming assistant content
        final chunk = event.data['delta'] as String? ?? event.data['content'] as String? ?? '';
        setState(() {
          _streamedContent += chunk;
          if (_streamMessageId < 0) {
            // First chunk — insert a placeholder message
            _messages.insert(0, {
              'role': 'assistant',
              'content': _streamedContent,
            });
            _streamMessageId = 0;
          } else {
            // Update the streaming message in place
            _messages[0] = {
              'role': 'assistant',
              'content': _streamedContent,
            };
          }
        });
        // Auto-scroll if user is near the bottom
        if (!_showScrollToBottom) {
          _scrollToBottom();
        }
        break;
      case 'tool_call':
        // Show tool usage in the stream
        final toolName = event.data['tool'] as String? ?? 'tool';
        setState(() {
          _streamedContent += '\n\n🔧 *${toolName}*';
          if (_streamMessageId >= 0) {
            _messages[0] = {
              'role': 'assistant',
              'content': _streamedContent,
            };
          }
        });
        break;
      case 'tool_result':
        // Tool result — could show a summary
        break;
      case 'done':
        // Stream complete — final fetch will replace
        break;
      case 'error':
        final errorMsg = event.data['message'] as String? ?? 'Unknown error';
        setState(() {
          _streamedContent += '\n\n⚠️ Error: $errorMsg';
          if (_streamMessageId >= 0) {
            _messages[0] = {
              'role': 'assistant',
              'content': _streamedContent,
            };
          }
        });
        break;
    }
  }

  /// Fallback: send via REST and poll for response.
  Future<void> _sendViaRest(String text) async {
    final ws = WsClient(widget.connection.baseUrl, token: _client != null ? await _client!.getToken(widget.connection.baseUrl) : null);
    await ws.connect();
    await ws.resumeSession(widget.session.id);
    await ws.sendMessage(text);
    ws.close();

    setState(() {
      _sending = false;
      _loading = false;
      _error = null;
    });

    _pollForResponse();
  }

  /// Poll for new messages until we see a new one (or timeout).
  Future<void> _pollForResponse() async {
    const maxPolls = 60; // up to 60 seconds of polling
    const pollInterval = Duration(milliseconds: 1000);
    final lastCount = _messages.length;

    for (int i = 0; i < maxPolls; i++) {
      if (!mounted) return;
      await Future.delayed(pollInterval);

      try {
        final messages = await _client!.getMessages(
          widget.connection.baseUrl,
          widget.session.id,
        );

        if (messages.length > lastCount) {
          setState(() {
            _messages = messages;
            _streaming = false;
            _sending = false;
          });
          return;
        }
      } catch (_) {
        // Continue polling on transient errors
      }
    }

    // Timeout
    if (mounted) {
      try {
        final messages = await _client!.getMessages(
          widget.connection.baseUrl,
          widget.session.id,
        );
        setState(() {
          _messages = messages;
          _streaming = false;
          _sending = false;
        });
      } catch (_) {
        setState(() {
          _streaming = false;
          _sending = false;
        });
      }
    }
  }

  /// Handle send errors — remove optimistic message, show snackbar.
  void _handleSendError(String text, Object e) {
    setState(() {
      _sending = false;
      _streaming = false;
      _streamedContent = '';
      _streamMessageId = -1;
      if (_messages.isNotEmpty &&
          _messages[0]['role'] == 'user' &&
          _messages[0]['content'] == text) {
        _messages.removeAt(0);
      }
    });

    if (mounted) {
      final msg = e.toString().contains('Connection closed')
          ? 'WebSocket blocked — dashboard only allows WS from localhost.\n'
              'Run hermes dashboard --insecure --bind 0.0.0.0'
          : 'Send failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_streaming)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Streaming…', style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _fetchMessages,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.isTablet(context) ? 800 : double.infinity,
          ),
          child: Column(
            children: [
              Expanded(child: _buildBody()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.1)),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attachment previews
            if (_attachments.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: _attachments.length,
                  itemBuilder: (context, i) {
                    final file = _attachments[i];
                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(file.path),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 72,
                                height: 72,
                                color: Colors.grey[800],
                                child: const Icon(Icons.attach_file, size: 32),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _removeAttachment(i),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            // Text input row
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: (_loading || _streaming) ? null : _showAttachmentMenu,
                  tooltip: 'Attach',
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    enabled: !_loading && !_streaming,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  child: _streaming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send, size: 20),
                          onPressed: _sendMessage,
                          tooltip: 'Send',
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
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

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 4),
          reverse: true,
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final msg = _messages[index];
            final role = (msg['role'] as String?) ?? 'assistant';
            final content = (msg['content'] as String?) ?? '';
            final isUser = role == 'user';

            return _MessageBubble(content: content, isUser: isUser);
          },
        ),
        // Scroll-to-bottom button
        if (_showScrollToBottom)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: () {
                _scrollToBottom();
                setState(() => _showScrollToBottom = false);
              },
              tooltip: 'Scroll to bottom',
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
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
            color: const Color(0xFFD4AF37),
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
