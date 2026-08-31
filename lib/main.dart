import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/connection_manager.dart';
import 'core/services/gateway_turn_application_controller.dart';
import 'core/services/text_size_preference.dart';
import 'core/screens/session_list_screen.dart';
import 'core/utils/responsive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final connManager = await ConnectionManager.create(prefs);
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

  static TextSizePreference getTextSizePreference(SharedPreferences prefs) {
    return TextSizePreferenceStore(prefs).read();
  }
}

class HermesAppState extends State<HermesApp> {
  late final GatewayTurnApplicationController _turnApplicationController;

  @override
  void initState() {
    super.initState();
    _turnApplicationController = GatewayTurnApplicationController();
  }

  Future<void> setTextSizePreference(TextSizePreference preference) async {
    await TextSizePreferenceStore(widget.connManager.prefs).save(preference);
    if (mounted) setState(() {});
  }

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
      builder: (context, child) {
        final systemMediaQuery = MediaQuery.of(context);
        final preference = HermesApp.getTextSizePreference(
          widget.connManager.prefs,
        );
        return MediaQuery(
          data: systemMediaQuery.copyWith(
            textScaler: preference.applyTo(systemMediaQuery.textScaler),
          ),
          child: child!,
        );
      },
      home: HomeScreen(
        connManager: widget.connManager,
        turnApplicationController: _turnApplicationController,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_turnApplicationController.close());
    super.dispose();
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
            style: TextStyle(
              fontFamily: 'Cinzel',
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
  final GatewayTurnApplicationController turnApplicationController;

  const HomeScreen({
    required this.connManager,
    required this.turnApplicationController,
    super.key,
  });

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

  Future<void> _closeDialogAndRefresh(BuildContext dialogContext) async {
    // Let editable controls detach from the IME before removing their route.
    // Rebuilding HomeScreen while the dialog still owns focus can deactivate
    // inherited dependencies out of order on Android.
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
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
      MaterialPageRoute(
        builder: (_) => SessionListScreen(
          connection: conn,
          turnApplicationController: widget.turnApplicationController,
        ),
      ),
    );
  }

  void _showAddDialog() => _showConnectionDialog();

  void _showEditConnectionDialog(SavedConnection conn) {
    _showConnectionDialog(existing: conn);
  }

  void _showConnectionDialog({SavedConnection? existing}) {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        initialConnection: existing,
        onSave:
            (
              label,
              host,
              port,
              apiKey, {
              gatewayPrefix,
              dashboardPrefix,
              dashboardProxied = false,
              desktopGatewayUrl,
              dashboardPort,
              dashboardUsername,
              dashboardPassword,
            }) async {
              if (existing == null) {
                await widget.connManager.saveConnection(
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  desktopGatewayUrl: desktopGatewayUrl,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                );
              } else {
                await widget.connManager.updateConnection(
                  existing.id,
                  label,
                  host,
                  port,
                  apiKey,
                  gatewayPrefix: gatewayPrefix,
                  dashboardPrefix: dashboardPrefix,
                  dashboardProxied: dashboardProxied,
                  desktopGatewayUrl: desktopGatewayUrl,
                  dashboardPort: dashboardPort,
                  dashboardUsername: dashboardUsername,
                  dashboardPassword: dashboardPassword,
                );
              }
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
                        final client = ApiClient(
                          baseUrl: baseUrl,
                          apiKey: key,
                          pathPrefix: conn.gatewayPrefix ?? '',
                        );
                        final result = await client.checkHealth();
                        client.close();

                        if (!ctx.mounted) return;

                        if (result.isHealthy) {
                          await widget.connManager.updateApiKey(conn.id, key);
                          if (!ctx.mounted) return;
                          await _closeDialogAndRefresh(ctx);
                        } else {
                          setDialogState(() {
                            error = result.userMessage(apiKeyProvided: true);
                            validating = false;
                          });
                        }
                      } on CredentialStorageException {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = 'The API key could not be stored securely.';
                          validating = false;
                        });
                      } catch (_) {
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

  void _showDashboardAuthDialog(SavedConnection conn) {
    final gatewayPrefixCtrl = TextEditingController(
      text: conn.gatewayPrefix ?? '',
    );
    final dashboardPrefixCtrl = TextEditingController(
      text: conn.dashboardPrefix ?? '',
    );
    final portCtrl = TextEditingController(
      text: conn.dashboardPortOverride?.toString() ?? '',
    );
    final userCtrl = TextEditingController(text: conn.dashboardUsername ?? '');
    final passCtrl = TextEditingController(text: conn.dashboardPassword ?? '');
    var proxied = conn.dashboardProxied;
    bool validating = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Dashboard / Proxy Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Used for hosted path prefixes and for the Settings, '
                    'Memory, Skills and Cron tabs. Leave username/password '
                    'blank for an open dashboard, or enable proxied mode when '
                    'your reverse proxy injects dashboard auth.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
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
                  controller: gatewayPrefixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gateway path prefix',
                    hintText: 'e.g. /profile/peter',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dashboardPrefixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard path prefix',
                    hintText: 'e.g. /dashboard',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: proxied,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dashboard behind proxy'),
                  subtitle: const Text(
                    'Proxy injects auth; app sends clean requests',
                  ),
                  onChanged: validating
                      ? null
                      : (v) => setDialogState(() => proxied = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard Port',
                    hintText: 'Leave blank for default (9119)',
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username (optional)',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password (optional)',
                  ),
                  obscureText: true,
                  enabled: !validating,
                ),
              ],
            ),
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
                      final portText = portCtrl.text.trim();
                      final port = portText.isEmpty
                          ? null
                          : int.tryParse(portText);
                      if (portText.isNotEmpty && (port == null || port <= 0)) {
                        setDialogState(() => error = 'Invalid port number.');
                        return;
                      }
                      final user = userCtrl.text.trim();
                      final pass = passCtrl.text.trim();
                      final gatewayPrefix = gatewayPrefixCtrl.text.trim();
                      final dashboardPrefix = dashboardPrefixCtrl.text.trim();

                      setDialogState(() {
                        validating = true;
                        error = null;
                      });

                      if (gatewayPrefix != (conn.gatewayPrefix ?? '')) {
                        final apiClient = ApiClient(
                          baseUrl: conn.baseUrl,
                          apiKey: conn.apiKey,
                          pathPrefix: gatewayPrefix,
                        );
                        final result = await apiClient.checkHealth();
                        apiClient.close();
                        if (!ctx.mounted) return;
                        if (!result.isHealthy) {
                          setDialogState(() {
                            error = result.userMessage(
                              apiKeyProvided: conn.apiKey.isNotEmpty,
                            );
                            validating = false;
                          });
                          return;
                        }
                      }

                      final client = DashboardClient(
                        host: conn.host,
                        port: port ?? conn.dashboardPort,
                        useHttps: conn.useHttps,
                        pathPrefix: dashboardPrefix,
                        proxied: proxied,
                        username: user.isEmpty ? null : user,
                        password: pass.isEmpty ? null : pass,
                      );
                      try {
                        await client.getModelInfo();
                        client.close();
                        if (!ctx.mounted) return;
                        await widget.connManager.updateDashboardAuth(
                          conn.id,
                          dashboardPort: port,
                          username: user,
                          password: pass,
                          gatewayPrefix: gatewayPrefix,
                          dashboardPrefix: dashboardPrefix,
                          dashboardProxied: proxied,
                        );
                        if (!ctx.mounted) return;
                        await _closeDialogAndRefresh(ctx);
                      } on CredentialStorageException {
                        client.close();
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error =
                              'The dashboard credentials could not be stored securely.';
                          validating = false;
                        });
                      } catch (_) {
                        client.close();
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error =
                              'Could not reach/authenticate the dashboard at '
                              '${conn.host}:${port ?? conn.dashboardPort}. '
                              'Check the port and credentials.';
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
    ).whenComplete(() {
      gatewayPrefixCtrl.dispose();
      dashboardPrefixCtrl.dispose();
      portCtrl.dispose();
      userCtrl.dispose();
      passCtrl.dispose();
    });
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.router, color: Color(0xFFD4AF37)),
        title: Text(conn.label),
        subtitle: Text(
          '${conn.host}:${conn.port}${conn.gatewayPrefix != null && conn.gatewayPrefix!.isNotEmpty ? conn.gatewayPrefix! : ''}'
          '  \u2022  Key: ${conn.apiKey.isNotEmpty ? "\u2713" : "\u2717"}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              try {
                await widget.connManager.deleteConnection(conn.id);
                if (mounted) _refresh();
              } on CredentialStorageException {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'The connection could not be deleted safely.',
                    ),
                  ),
                );
              }
            } else if (v == 'edit') {
              _showEditConnectionDialog(conn);
            } else if (v == 'apikey') {
              _showApiKeyDialog(conn);
            } else if (v == 'dashboard') {
              _showDashboardAuthDialog(conn);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit Connection')),
            const PopupMenuItem(value: 'apikey', child: Text('Update API Key')),
            const PopupMenuItem(
              value: 'dashboard',
              child: Text('Dashboard / Proxy Settings'),
            ),
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
          style: TextStyle(
            fontFamily: 'Cinzel',
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
  final SavedConnection? initialConnection;
  final Future<void> Function(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
  })
  onSave;
  const _AddDialog({required this.onSave, this.initialConnection});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _apiKey;
  late final TextEditingController _gatewayPrefix;
  late final TextEditingController _dashboardPrefix;
  late final TextEditingController _dashPort;
  late final TextEditingController _dashUser;
  late final TextEditingController _dashPass;
  late final TextEditingController _desktopGatewayUrl;
  late bool _showDashboard;
  late bool _dashboardProxied;
  bool _validating = false;
  String? _error;

  bool get _isEditing => widget.initialConnection != null;

  @override
  void initState() {
    super.initState();
    final conn = widget.initialConnection;
    _label = TextEditingController(text: conn?.label ?? 'Home');
    _host = TextEditingController(
      text: conn == null
          ? ''
          : conn.useHttps
          ? 'https://${conn.host}'
          : conn.host,
    );
    _port = TextEditingController(text: (conn?.port ?? 8642).toString());
    _apiKey = TextEditingController(text: conn?.apiKey ?? '');
    _gatewayPrefix = TextEditingController(text: conn?.gatewayPrefix ?? '');
    _dashboardPrefix = TextEditingController(text: conn?.dashboardPrefix ?? '');
    _dashPort = TextEditingController(
      text: conn?.dashboardPortOverride?.toString() ?? '',
    );
    _dashUser = TextEditingController(text: conn?.dashboardUsername ?? '');
    _dashPass = TextEditingController(text: conn?.dashboardPassword ?? '');
    _desktopGatewayUrl = TextEditingController(
      text: conn?.desktopGatewayUrl ?? 'http://192.168.1.193/desktop',
    );
    _dashboardProxied = conn?.dashboardProxied ?? false;
    _showDashboard =
        conn?.gatewayPrefix?.isNotEmpty == true ||
        conn?.dashboardPrefix?.isNotEmpty == true ||
        conn?.dashboardPortOverride != null ||
        conn?.dashboardUsername?.isNotEmpty == true ||
        conn?.dashboardPassword?.isNotEmpty == true ||
        _dashboardProxied ||
        conn?.desktopGatewayUrl?.isNotEmpty == true;
  }

  Future<void> _validateAndSave() async {
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8642;
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();

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
      final client = ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pathPrefix: gatewayPrefix,
      );
      final result = await client.checkHealth();
      client.close();

      if (!mounted) return;

      if (!result.isHealthy) {
        setState(() {
          _error = result.userMessage(apiKeyProvided: apiKey.isNotEmpty);
          _validating = false;
        });
        return;
      }

      final dashPortText = _dashPort.text.trim();
      final dashUser = _dashUser.text.trim();
      final dashPass = _dashPass.text.trim();
      final desktopGatewayUrl = _desktopGatewayUrl.text.trim();
      final dashPort = dashPortText.isEmpty ? null : int.tryParse(dashPortText);

      // If the user supplied any dashboard details, validate them before saving
      // (parity with the Dashboard Login dialog). The gateway is already known
      // good at this point.
      if (dashPortText.isNotEmpty ||
          dashUser.isNotEmpty ||
          dashPass.isNotEmpty ||
          dashboardPrefix.isNotEmpty ||
          _dashboardProxied) {
        final dashClient = DashboardClient(
          host: normalized.host,
          port: SavedConnection(
            id: '',
            label: '',
            host: normalized.host,
            port: normalized.port,
            apiKey: '',
            useHttps: normalized.useHttps,
            dashboardPortOverride: dashPort,
          ).dashboardPort,
          useHttps: normalized.useHttps,
          pathPrefix: dashboardPrefix,
          proxied: _dashboardProxied,
          username: dashUser.isEmpty ? null : dashUser,
          password: dashPass.isEmpty ? null : dashPass,
        );
        try {
          await dashClient.getModelInfo();
        } catch (_) {
          dashClient.close();
          if (!mounted) return;
          setState(() {
            _error =
                'Gateway connected, but the dashboard could not be reached or '
                'authenticated. Check the dashboard details, or clear them to skip.';
            _validating = false;
            _showDashboard = true;
          });
          return;
        }
        dashClient.close();
        if (!mounted) return;
      }

      await widget.onSave(
        label,
        host,
        port,
        apiKey,
        gatewayPrefix: gatewayPrefix.isEmpty ? null : gatewayPrefix,
        dashboardPrefix: dashboardPrefix.isEmpty ? null : dashboardPrefix,
        dashboardProxied: _dashboardProxied,
        desktopGatewayUrl: desktopGatewayUrl.isEmpty ? null : desktopGatewayUrl,
        dashboardPort: dashPort,
        dashboardUsername: dashUser.isEmpty ? null : dashUser,
        dashboardPassword: dashPass.isEmpty ? null : dashPass,
      );
      if (mounted) Navigator.pop(context);
    } on CredentialStorageException {
      if (!mounted) return;
      setState(() {
        _error = 'The connection could not be stored securely.';
        _validating = false;
      });
    } catch (_) {
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
      title: Text(
        _isEditing ? 'Edit Gateway Connection' : 'Add Gateway Connection',
      ),
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
            const SizedBox(height: 4),
            InkWell(
              onTap: _validating
                  ? null
                  : () => setState(() => _showDashboard = !_showDashboard),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showDashboard ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Custom proxy and dashboard details',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDashboard) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _gatewayPrefix,
                decoration: const InputDecoration(
                  labelText: 'Gateway path prefix',
                  hintText:
                      'e.g. /profile/peter (proxy path before /api/ and /v1/)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashboardPrefix,
                decoration: const InputDecoration(
                  labelText: 'Dashboard path prefix',
                  hintText: 'e.g. /dashboard (proxy path before /api/)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _dashboardProxied,
                contentPadding: EdgeInsets.zero,
                title: const Text('Dashboard behind proxy'),
                subtitle: const Text(
                  'Nginx injects auth — app sends clean requests',
                ),
                onChanged: (v) => setState(() => _dashboardProxied = v),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Optional. For the Memory/Cron/Skills/Settings tabs. Leave '
                  'blank to use the default dashboard port (9119) with no login.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
              TextField(
                controller: _dashPort,
                decoration: const InputDecoration(
                  labelText: 'Dashboard Port',
                  hintText: 'Leave blank for default (9119)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashUser,
                decoration: const InputDecoration(
                  labelText: 'Dashboard Username (optional)',
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashPass,
                decoration: const InputDecoration(
                  labelText: 'Dashboard Password (optional)',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desktopGatewayUrl,
                decoration: const InputDecoration(
                  labelText: 'Desktop Gateway URL (optional)',
                  hintText: 'https://hermes-desktop.example.lan',
                  helperText:
                      'Enables file attachments through the Desktop remote gateway.',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ],
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
              : Text(_isEditing ? 'Save Changes' : 'Connect'),
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
    _gatewayPrefix.dispose();
    _dashboardPrefix.dispose();
    _dashPort.dispose();
    _dashUser.dispose();
    _dashPass.dispose();
    _desktopGatewayUrl.dispose();
    super.dispose();
  }
}
