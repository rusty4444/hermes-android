import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/connection_manager.dart';
import 'core/screens/session_list_screen.dart';
import 'core/utils/responsive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final connManager = ConnectionManager(prefs);
  runApp(HermesApp(connManager: connManager));
}

class HermesApp extends StatefulWidget {
  final ConnectionManager connManager;
  const HermesApp({required this.connManager, super.key});

  @override
  State<HermesApp> createState() => HermesAppState();

  static ThemeMode getThemeMode(SharedPreferences prefs) {
    final stored = prefs.getString('theme_mode') ?? 'system';
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString('theme_mode', value);
  }
}

class HermesAppState extends State<HermesApp> {
  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return MaterialApp(
      title: 'Hermes Agent',
      themeMode: HermesApp.getThemeMode(widget.connManager.prefs),
      theme: ThemeData(
        colorSchemeSeed: gold,
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: gold,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A1A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.black,
        ),
      ),
      home: HomeScreen(connManager: widget.connManager),
    );
  }
}

/// Brand header used across screens.
class HermesHeader extends StatelessWidget {
  final String? subtitle;
  const HermesHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4AF37), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'HERMES',
            style: GoogleFonts.cinzel(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFD4AF37),
              letterSpacing: 6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
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
    setState(() => _connections = widget.connManager.getConnections());
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoNavigated && _connections.isNotEmpty) {
      _autoNavigated = true;
      _maybeAutoNavigate();
    }
  }

  void _maybeAutoNavigate() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    if (lastId == null) return;
    final conn = _connections.where((c) => c.id == lastId).firstOrNull;
    if (conn == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToSessions(conn);
    });
  }

  void _navigateToSessions(SavedConnection conn) {
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SessionListScreen(connection: conn)),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        onSave: (label, host, port, apiKey) {
          widget.connManager.saveConnection(label, host, port, apiKey);
          _refresh();
        },
      ),
    );
  }

  void _showApiKeyDialog(SavedConnection conn) {
    final ctrl = TextEditingController(text: conn.apiKey);
    bool validating = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Update API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'API_SERVER_KEY from ~/.hermes/.env',
                ),
                obscureText: true,
                enabled: !validating,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: validating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: validating
                  ? null
                  : () async {
                      final key = ctrl.text.trim();
                      if (key.isEmpty) return;

                      setDialogState(() {
                        validating = true;
                        error = null;
                      });

                      try {
                        final baseUrl = conn.baseUrl;
                        final client = ApiClient(baseUrl: baseUrl, apiKey: key);
                        final ok = await client.healthCheck();
                        client.close();

                        if (!ctx.mounted) return;

                        if (ok) {
                          widget.connManager.updateApiKey(conn.id, key);
                          _refresh();
                          Navigator.pop(ctx);
                        } else {
                          setDialogState(() {
                            error = 'Invalid API key. Server returned 401.';
                            validating = false;
                          });
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = 'Cannot reach ${conn.host}:${conn.port}.';
                          validating = false;
                        });
                      }
                    },
              child: validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.router, color: Color(0xFFD4AF37)),
        title: Text(conn.label),
        subtitle: Text(
          '${conn.host}:${conn.port}  \u2022  Key: ${conn.apiKey.isNotEmpty ? "\u2713" : "\u2717"}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') {
              widget.connManager.deleteConnection(conn.id);
              _refresh();
            } else if (v == 'apikey') {
              _showApiKeyDialog(conn);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'apikey', child: Text('Update API Key')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: () => _navigateToSessions(conn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: GoogleFonts.cinzel(
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 64, color: Colors.grey[800]),
                  const SizedBox(height: 16),
                  Text(
                    'No connections',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                if (Responsive.isTablet(context)) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(context),
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _connections.length,
                    itemBuilder: (_, i) =>
                        _buildConnectionCard(_connections[i]),
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
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final void Function(String label, String host, int port, String apiKey)
  onSave;
  const _AddDialog({required this.onSave});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _label = TextEditingController(text: 'Home');
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8642');
  final _apiKey = TextEditingController();
  bool _validating = false;
  String? _error;

  Future<void> _validateAndSave() async {
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8642;
    final apiKey = _apiKey.text.trim();

    if (label.isEmpty || host.isEmpty || port <= 0) return;

    setState(() {
      _validating = true;
      _error = null;
    });

    try {
      final normalized = SavedConnection.normalizeHostAndPort(host, port);
      final baseUrl = SavedConnection(
        id: '',
        label: '',
        host: normalized.host,
        port: normalized.port,
        apiKey: '',
        useHttps: normalized.useHttps,
      ).baseUrl;
      final client = ApiClient(baseUrl: baseUrl, apiKey: apiKey);
      final ok = await client.healthCheck();
      client.close();

      if (!mounted) return;

      if (ok) {
        widget.onSave(label, host, port, apiKey);
        Navigator.pop(context);
      } else {
        setState(() {
          _error = apiKey.isEmpty
              ? 'Server requires an API key. Enter your API_SERVER_KEY.'
              : 'Invalid API key. Server returned 401.';
          _validating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach $host:$port. Check the host and port.';
        _validating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Gateway Connection'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText:
                    '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net',
              ),
              keyboardType: TextInputType.text,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8642 (API Server)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKey,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'API_SERVER_KEY from ~/.hermes/.env',
              ),
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _validating ? null : _validateAndSave,
          child: _validating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _apiKey.dispose();
    super.dispose();
  }
}
