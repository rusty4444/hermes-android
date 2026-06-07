// Memory browser screen — read memory entries from Hermes config.
//
// Memory entries live in config.yaml under the 'memory' key as a list:
//   memory:
//     - target: user
//       content: "User name..."
//
// API: GET /api/config returns the full config including memory.
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';

class MemoryScreen extends StatefulWidget {
  final SavedConnection connection;
  const MemoryScreen({required this.connection, super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late DashboardClient _client;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;
  String? _source; // 'config' or 'api'

  @override
  void initState() {
    super.initState();
    _client = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.port,
      useHttps: widget.connection.useHttps,
    );
    _loadMemory();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadMemory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Try dedicated /api/memory endpoint first
      try {
        final memData = await _client.apiGet('memory');
        final items =
            memData['entries'] as List? ?? memData['memory'] as List? ?? [];
        if (items.isNotEmpty) {
          setState(() {
            _entries = items.cast<Map<String, dynamic>>();
            _source = 'api';
            _loading = false;
          });
          return;
        }
      } catch (_) {
        // Endpoint not available — fall through to config
      }

      // Fallback: read memory from /api/config
      final config = await _client.apiGet('config');
      final mem = config['memory'];

      if (mem is List) {
        // Memory is a list of {target, content}
        setState(() {
          _entries = mem.cast<Map<String, dynamic>>();
          _source = 'config';
          _loading = false;
        });
      } else if (mem is Map) {
        // Memory is a map {key: value}
        final items = <Map<String, dynamic>>[];
        mem.forEach((key, value) {
          items.add({'target': key, 'content': value.toString()});
        });
        setState(() {
          _entries = items;
          _source = 'config';
          _loading = false;
        });
      } else {
        setState(() {
          _entries = [];
          _source = 'config';
          _loading = false;
        });
      }
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Memory'),
            if (_source != null)
              Text(
                'Source: $_source',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadMemory,
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
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load memory',
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
                onPressed: _loadMemory,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No memory entries',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Memory entries are cross-session facts the agent remembers.\n'
              'They are configured in ~/.hermes/config.yaml',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMemory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final target = entry['target'] as String? ?? 'memory';
          final content = entry['content'] as String? ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(
                        label: Text(
                          target,
                          style: const TextStyle(fontSize: 11),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: target == 'user'
                            ? Colors.blue.shade800
                            : Colors.grey.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(content, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
