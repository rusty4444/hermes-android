import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/connection_manager.dart';
import 'core/screens/session_list_screen.dart';
import 'core/utils/responsive.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final connManager = ConnectionManager(prefs);
  await NotificationService.init();
  runApp(HermesApp(connManager: connManager));
}

class HermesApp extends StatelessWidget {
  final ConnectionManager connManager;
  const HermesApp({required this.connManager, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Agent',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(connManager: connManager),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ConnectionManager connManager;
  const HomeScreen({required this.connManager, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedConnection> _connections = [];
  bool _autoNavigated = false;

  static const String _lastConnectionKey = 'last_connection_id';

  void _refresh() {
    setState(() {
      _connections = widget.connManager.getConnections();
    });
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-navigate to last used server once on first frame
    if (!_autoNavigated && _connections.isNotEmpty) {
      _autoNavigated = true;
      _maybeAutoNavigate();
    }
  }

  /// Auto-navigate to the last used connection if it still exists.
  void _maybeAutoNavigate() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    if (lastId == null) return;

    final conn = _connections.where((c) => c.id == lastId).firstOrNull;
    if (conn == null) return;

    // Navigate after the first frame to avoid build-during-build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _navigateToSessions(conn);
      }
    });
  }

  void _navigateToSessions(SavedConnection conn) {
    // Save as last used
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionListScreen(connection: conn),
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(onSave: (label, host, port) {
        widget.connManager.saveConnection(label, host, port);
        _refresh();
      }),
    );
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.cloud, color: Colors.blue),
        title: Text(conn.label),
        subtitle: Text('${conn.host}:${conn.port}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') {
              widget.connManager.deleteConnection(conn.id);
              _refresh();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _navigateToSessions(conn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hermes Agent')),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No connections', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Tap + to add a remote Hermes dashboard',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = Responsive.isTablet(context);
                if (isTablet) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(context),
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _connections.length,
                    itemBuilder: (_, i) => _buildConnectionCard(_connections[i]),
                  );
                }
                return ListView.builder(
                  itemCount: _connections.length,
                  itemBuilder: (_, i) => _buildConnectionCard(_connections[i]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Connection',
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final void Function(String label, String host, int port) onSave;
  const _AddDialog({required this.onSave});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _label = TextEditingController(text: 'Home');
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '9119');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Connection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _host,
            decoration: const InputDecoration(labelText: 'Host'),
            keyboardType: TextInputType.text,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            final host = _host.text.trim();
            final port = int.tryParse(_port.text.trim()) ?? 9119;
            if (label.isNotEmpty && host.isNotEmpty && port > 0) {
              widget.onSave(label, host, port);
              Navigator.pop(context);
            }
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }
}
