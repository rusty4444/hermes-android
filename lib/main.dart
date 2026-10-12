import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/android_launch_intent_service.dart';
import 'core/services/android_share_intent_service.dart';
import 'core/services/composer_draft_store.dart';
import 'core/services/config_backup.dart';
import 'core/services/config_backup_io.dart';
import 'core/services/config_backup_service.dart';
import 'core/services/connection_manager.dart';
import 'core/services/gateway_turn_application_controller.dart';
import 'core/services/local_chat_pin_store.dart';
import 'core/services/notification_prefs.dart';
import 'core/services/text_size_preference.dart';
import 'core/services/turn_notification_service.dart';
import 'core/screens/chat_screen.dart';
import 'core/screens/workspace_screen.dart';
import 'core/theme/hermes_theme.dart';
import 'core/utils/responsive.dart';
import 'core/widgets/config_backup_card.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  ConnectionManager? connManager;
  Object? startupError;
  try {
    connManager = await ConnectionManager.create(prefs);
  } catch (error) {
    // A corrupt saved-connections entry or a Keystore fault must not kill
    // the app before any UI exists — reinstall-only failure. Surface a
    // recovery screen instead so the user can reset the damaged store.
    startupError = error;
  }
  final shareIntents = AndroidShareIntentService();
  final launchIntents = AndroidLaunchIntentService();
  await Future.wait([shareIntents.initialize(), launchIntents.initialize()]);
  runApp(
    connManager == null
        ? _StartupRecoveryApp(
            prefs: prefs,
            error: startupError,
            shareIntents: shareIntents,
            launchIntents: launchIntents,
          )
        : HermesApp(
            connManager: connManager,
            shareIntents: shareIntents,
            launchIntents: launchIntents,
          ),
  );
}

/// Minimal recovery surface shown when the connection store could not be
/// loaded at launch. Offers to wipe the damaged saved-connections metadata
/// (and only that key) and retry, rather than dying silently.
class _StartupRecoveryApp extends StatelessWidget {
  static final GlobalKey _rootKey = GlobalKey();

  const _StartupRecoveryApp({
    required this.prefs,
    required this.error,
    required this.shareIntents,
    required this.launchIntents,
  });

  final SharedPreferences prefs;
  final Object? error;
  final AndroidShareIntentService shareIntents;
  final AndroidLaunchIntentService launchIntents;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: _rootKey,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      localeListResolutionCallback: resolvePreferredLocale,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.hermes_could_not_load_your_saved_connections,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n
                        .the_local_connection_store_looks_damaged_you_can_reset_the(
                          error.runtimeType,
                        ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      await prefs.remove('saved_connections');
                      try {
                        final retry = await ConnectionManager.create(prefs);
                        runApp(
                          HermesApp(
                            connManager: retry,
                            shareIntents: shareIntents,
                            launchIntents: launchIntents,
                          ),
                        );
                      } catch (retryError) {
                        // Re-read the key after the await: the recovery
                        // screen may already have been replaced by the
                        // retried app.
                        final rootContext = _rootKey.currentContext;
                        if (rootContext != null) {
                          // The context is re-read from the root key after
                          // the await and null-checked immediately above.
                          // ignore: use_build_context_synchronously
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(
                              content: Builder(
                                builder: (snackContext) => Text(
                                  snackContext.l10n
                                      .reset_failed_the_secure_storage_may_need_reinstall(
                                        retryError,
                                      ),
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text(context.l10n.reset_saved_connections),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HermesApp extends StatefulWidget {
  final ConnectionManager connManager;
  final AndroidShareIntentService? shareIntents;
  final AndroidLaunchIntentService? launchIntents;
  const HermesApp({
    required this.connManager,
    this.shareIntents,
    this.launchIntents,
    super.key,
  });

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

  /// Pushes from the app root (notification taps) need a navigator below the
  /// MaterialApp this state builds.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _turnApplicationController = GatewayTurnApplicationController();
    unawaited(NotificationPrefsStore.load());
    notificationResponseHandler = _handleNotificationResponse;
    // A notification that launched a terminated app carries its tap/action in
    // the platform's launch details; route it once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await TurnNotificationService.shared
          .takeInitialNotificationResponse();
      if (initial != null && mounted) _handleNotificationResponse(initial);
    });
  }

  /// The connection a notification response should act on: the last one the
  /// user opened, or the only configured one.
  SavedConnection? _notificationConnection() {
    final connections = widget.connManager.getConnections();
    final lastId = widget.connManager.prefs.getString(
      HomeScreenState._lastConnectionKey,
    );
    final preferred = connections
        .where((connection) => connection.id == lastId)
        .firstOrNull;
    return preferred ?? (connections.length == 1 ? connections.single : null);
  }

  /// Routes a notification tap (or one of its action buttons) into the app.
  ///
  /// Approval actions answer through the turn controller when it owns the
  /// request; otherwise the action is left pending for the chat that does, and
  /// every response lands the user on the session the notification was about.
  void _handleNotificationResponse(NotificationResponse response) {
    final route = NotificationRoute.fromResponse(response);
    // An explicit connection id must resolve: falling back to another backend
    // could answer an approval against the wrong gateway. Only legacy
    // payloads without an id use the last-opened connection.
    final hasExplicitConnection =
        route.connectionId != null && route.connectionId!.isNotEmpty;
    final connection = hasExplicitConnection
        ? _connectionById(route.connectionId)
        : _notificationConnection();
    if (connection == null) return;

    final choice = route.approvalChoice;
    final sessionId = route.sessionId;
    final requestId = route.requestId;
    if (choice != null && sessionId != null && requestId != null) {
      final approval = PendingNotificationApproval(
        // Saved connection ids remain distinct even when two profiles point
        // at the same endpoint with different credentials or gateway profiles.
        connectionId: connection.id,
        sessionId: sessionId,
        requestId: requestId,
        choice: choice,
      );
      try {
        final session = _turnApplicationController.sessionFor(connection);
        unawaited(
          session
              .tryRespondToApproval(
                sessionId: sessionId,
                choice: choice,
                requestId: requestId,
              )
              .then((answered) {
                // The request belongs to an open chat's route-local gateway:
                // leave it pending so that screen answers it normally.
                if (!answered) addPendingNotificationApproval(approval);
              })
              .catchError((_) {
                // A throw is unresolved, not answered: keep the tap pending
                // so the owning chat can still answer it.
                addPendingNotificationApproval(approval);
              }),
        );
      } catch (_) {
        // A closed controller cannot answer; the owning chat still can.
        addPendingNotificationApproval(approval);
      }
    }

    unawaited(_openNotificationSession(connection, sessionId));
  }

  /// The connection a payload names, or null when it no longer exists.
  SavedConnection? _connectionById(String? id) {
    if (id == null || id.isEmpty) return null;
    return widget.connManager
        .getConnections()
        .where((connection) => connection.id == id)
        .firstOrNull;
  }

  /// Opens the chat a notification was about; falls back to the workspace when
  /// the session cannot be fetched (deleted, or outside the recent list).
  Future<void> _openNotificationSession(
    SavedConnection connection,
    String? sessionId,
  ) async {
    Session? session;
    if (sessionId != null && sessionId.isNotEmpty) {
      ApiClient? client;
      try {
        client = ApiClient(
          baseUrl: connection.baseUrl,
          apiKey: connection.apiKey,
          pathPrefix: connection.gatewayPrefix ?? '',
        );
        session = await client.getSessionById(sessionId);
      } catch (_) {
        session = null;
      } finally {
        client?.close();
      }
    }
    if (!mounted) return;
    widget.connManager.prefs.setString(
      HomeScreenState._lastConnectionKey,
      connection.id,
    );
    if (session == null) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => WorkspaceScreen(
            connection: connection,
            turnApplicationController: _turnApplicationController,
          ),
        ),
      );
      return;
    }
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          connection: connection,
          session: session!,
          turnApplicationController: _turnApplicationController,
        ),
      ),
    );
  }

  Future<void> setTextSizePreference(TextSizePreference preference) async {
    await TextSizePreferenceStore(widget.connManager.prefs).save(preference);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => context.l10n.hermes_agent,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      localeListResolutionCallback: resolvePreferredLocale,
      themeMode: HermesApp.getThemeMode(widget.connManager.prefs),
      theme: hermesTheme(Brightness.light),
      darkTheme: hermesTheme(Brightness.dark),
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
        shareIntents: widget.shareIntents,
        launchIntents: widget.launchIntents,
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
  final AndroidShareIntentService? shareIntents;
  final AndroidLaunchIntentService? launchIntents;
  final Future<String?> Function()? pickBackupFile;
  final Future<ConfigImportResult> Function(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  )?
  importBackup;

  const HomeScreen({
    required this.connManager,
    required this.turnApplicationController,
    this.shareIntents,
    this.launchIntents,
    this.pickBackupFile,
    this.importBackup,
    super.key,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<SavedConnection> _connections = [];
  bool _autoNavigated = false;
  static const String _lastConnectionKey = 'last_connection_id';

  void _refresh() {
    setState(() => _connections = widget.connManager.getConnections());
  }

  /// Public only so the import flow and its widget test can refresh Home after
  /// restoring connections without restarting the process.
  void refreshConnections() => _refresh();

  ConfigBackupIo get _backupIo =>
      ConfigBackupIo(connectionManager: widget.connManager);

  Future<void> _showRestoreConfig() async {
    String? contents;
    try {
      contents =
          await (widget.pickBackupFile?.call() ?? _backupIo.pickBackupFile());
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
      return;
    }
    if (contents == null || !mounted) return;

    final choice = await showModalBottomSheet<ImportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ImportOptionsSheet(),
    );
    if (choice == null || !mounted) return;

    try {
      final importer = widget.importBackup ?? _backupIo.importEncrypted;
      final result = await importer(contents, choice.passphrase, choice.mode);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.summary)));
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
    }
  }

  void _showRestoreError(Object error) {
    final message = error is ConfigBackupException
        ? error.message
        : context.l10n.the_backup_could_not_be_restored;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    widget.shareIntents?.pendingShare.addListener(_onSharedText);
    widget.launchIntents?.pendingQuickChat.addListener(_onQuickChat);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSharedText();
      _onQuickChat();
    });
  }

  SavedConnection? _connectionForExternalAction() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    final preferred = _connections
        .where((connection) => connection.id == lastId)
        .firstOrNull;
    return preferred ?? (_connections.length == 1 ? _connections.single : null);
  }

  void _onSharedText() {
    if (!mounted || widget.shareIntents?.pendingShare.value == null) return;
    final connection = _connectionForExternalAction();
    if (connection == null) return;
    _autoNavigated = true;
    _navigateToWorkspace(connection);
  }

  void _onQuickChat() {
    if (!mounted || widget.launchIntents?.pendingQuickChat.value != true) {
      return;
    }
    final connection = _connectionForExternalAction();
    if (connection == null) return;
    _autoNavigated = true;
    _navigateToWorkspace(connection);
  }

  @override
  void dispose() {
    widget.shareIntents?.pendingShare.removeListener(_onSharedText);
    widget.launchIntents?.pendingQuickChat.removeListener(_onQuickChat);
    super.dispose();
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
    // The share listener owns this route so the regular last-connection
    // auto-navigation cannot stack a second Workspace above the shared draft.
    if (widget.shareIntents?.pendingShare.value != null ||
        widget.launchIntents?.pendingQuickChat.value == true) {
      return;
    }
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    if (lastId == null) return;
    final conn = _connections.where((c) => c.id == lastId).firstOrNull;
    if (conn == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToWorkspace(conn);
    });
  }

  void _navigateToWorkspace(SavedConnection conn) {
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);
    final sharedPayload = widget.shareIntents?.takePendingShare();
    final initialQuickChat =
        widget.launchIntents?.takePendingQuickChat() == true &&
        sharedPayload == null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkspaceScreen(
          connection: conn,
          turnApplicationController: widget.turnApplicationController,
          initialSharedPayload: sharedPayload,
          initialQuickChat: initialQuickChat,
          sessionsRefreshInterval: const Duration(seconds: 10),
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
              gatewayProfile,
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
                  gatewayProfile: gatewayProfile,
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
                  gatewayProfile: gatewayProfile,
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
          title: Text(context.l10n.update_api_key),
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
                decoration: InputDecoration(
                  labelText: context.l10n.api_key,
                  hintText: context.l10n.api_server_key_from_hermes_env,
                ),
                obscureText: true,
                enabled: !validating,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: validating ? null : () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
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
                          error = context
                              .l10n
                              .the_api_key_could_not_be_stored_securely;
                          validating = false;
                        });
                      } catch (_) {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = context.l10n.cannot_reach(
                            conn.host,
                            conn.port,
                          );
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
                  : Text(context.l10n.save),
            ),
          ],
        ),
      ),
    ).whenComplete(ctrl.dispose);
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
          title: Text(context.l10n.dashboard_proxy_settings),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context
                        .l10n
                        .used_for_hosted_path_prefixes_and_for_the_settings_memory,
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
                  decoration: InputDecoration(
                    labelText: context.l10n.gateway_path_prefix,
                    hintText: context.l10n.e_g_profile_peter,
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dashboardPrefixCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.dashboard_path_prefix,
                    hintText: context.l10n.e_g_dashboard,
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: proxied,
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.dashboard_behind_proxy),
                  subtitle: Text(
                    context.l10n.proxy_injects_auth_app_sends_clean_requests,
                  ),
                  onChanged: validating
                      ? null
                      : (v) => setDialogState(() => proxied = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.dashboard_port,
                    hintText: context.l10n.leave_blank_for_default_9119,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.username_optional,
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.password_optional,
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
              child: Text(context.l10n.cancel),
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
                        setDialogState(
                          () => error = context.l10n.invalid_port_number,
                        );
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
                          error = context
                              .l10n
                              .the_dashboard_credentials_could_not_be_stored_securely;
                          validating = false;
                        });
                      } catch (_) {
                        client.close();
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = context.l10n
                              .could_not_reach_authenticate_the_dashboard_at_check_the_port(
                                port ?? conn.dashboardPort,
                                conn.host,
                              );
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
                  : Text(context.l10n.save),
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
          context.l10n.connection_address_key(
            '${conn.host}:${conn.port}${conn.gatewayPrefix != null && conn.gatewayPrefix!.isNotEmpty ? conn.gatewayPrefix! : ''}',
            conn.apiKey.isNotEmpty ? "\u2713" : "\u2717",
          ),
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'delete') {
              try {
                await widget.connManager.deleteConnection(conn.id);
                // Drop every draft stored for this connection: a deleted
                // connection must not leave orphaned drafts behind.
                await ComposerDraftStore.removeConnection(conn.id);
                await LocalChatPinStore.removeConnection(
                  await SharedPreferences.getInstance(),
                  conn.id,
                );
                if (mounted) _refresh();
              } on CredentialStorageException {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.the_connection_could_not_be_deleted_safely,
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
            PopupMenuItem(
              value: 'edit',
              child: Text(context.l10n.edit_connection),
            ),
            PopupMenuItem(
              value: 'apikey',
              child: Text(context.l10n.update_api_key),
            ),
            PopupMenuItem(
              value: 'dashboard',
              child: Text(context.l10n.dashboard_proxy_settings),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                context.l10n.delete,
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
        onTap: () => _navigateToWorkspace(conn),
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
          if (_connections.isNotEmpty)
            IconButton(
              key: const Key('home_restore_config_menu'),
              tooltip: context.l10n.restore_configuration,
              onPressed: _showRestoreConfig,
              icon: const Icon(Icons.settings_backup_restore),
            ),
        ],
      ),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 64, color: Colors.grey[800]),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.no_connections,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context
                        .l10n
                        .tap_to_add_a_remote_hermes_gateway_api_server_port,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('home_restore_config_button'),
                    onPressed: _showRestoreConfig,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(context.l10n.restore_configuration),
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
        tooltip: context.l10n.add_connection,
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
    int? port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
    String? gatewayProfile,
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
  late final TextEditingController _gatewayProfile;
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
    _port = TextEditingController(text: conn?.port.toString() ?? '');
    _apiKey = TextEditingController(text: conn?.apiKey ?? '');
    _gatewayPrefix = TextEditingController(text: conn?.gatewayPrefix ?? '');
    _dashboardPrefix = TextEditingController(text: conn?.dashboardPrefix ?? '');
    _dashPort = TextEditingController(
      text: conn?.dashboardPortOverride?.toString() ?? '',
    );
    _dashUser = TextEditingController(text: conn?.dashboardUsername ?? '');
    _dashPass = TextEditingController(text: conn?.dashboardPassword ?? '');
    // The Desktop Gateway URL is an advanced override, not a default: the
    // app derives the JSON-RPC/WebSocket origin from the dashboard details
    // when this field is blank. Pre-filling a hardcoded example here made
    // every new connection silently point at a dead host and wedge Project
    // loading. See docs/ANDROID_FINAL_UI_SPEC_DRAFT.md.
    _desktopGatewayUrl = TextEditingController(
      text: conn?.desktopGatewayUrl ?? '',
    );
    _gatewayProfile = TextEditingController(text: conn?.gatewayProfile ?? '');
    _dashboardProxied = conn?.dashboardProxied ?? false;
    _showDashboard =
        conn?.gatewayPrefix?.isNotEmpty == true ||
        conn?.gatewayProfile?.isNotEmpty == true ||
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
    final port = int.tryParse(_port.text.trim());
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();

    // A blank Port field means "not supplied": normalizeHostAndPort then infers
    // 8642 for HTTP and 443 for HTTPS.
    if (label.isEmpty || host.isEmpty || (port != null && port <= 0)) return;

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
      final gatewayProfile = _gatewayProfile.text.trim();
      if (gatewayProfile.contains('/') ||
          gatewayProfile.contains(RegExp(r'\s'))) {
        setState(() {
          _error =
              context.l10n.hermes_profile_must_be_a_plain_profile_name_such_as;
          _validating = false;
          _showDashboard = true;
        });
        return;
      }
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
            _error = context
                .l10n
                .gateway_connected_but_the_dashboard_could_not_be_reached_or;
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
        gatewayPrefix: gatewayPrefix,
        dashboardPrefix: dashboardPrefix,
        dashboardProxied: _dashboardProxied,
        desktopGatewayUrl: desktopGatewayUrl,
        dashboardPort: dashPort,
        dashboardUsername: dashUser.isEmpty ? null : dashUser,
        dashboardPassword: dashPass.isEmpty ? null : dashPass,
        gatewayProfile: gatewayProfile.isEmpty ? null : gatewayProfile,
      );
      if (mounted) Navigator.pop(context);
    } on CredentialStorageException {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.the_connection_could_not_be_stored_securely;
        _validating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.cannot_reach_check_the_host_and_port(
          host,
          port ?? '',
        );
        _validating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing
            ? context.l10n.edit_gateway_connection
            : context.l10n.add_gateway_connection,
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
              decoration: InputDecoration(labelText: context.l10n.label),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: InputDecoration(
                labelText: context.l10n.host,
                hintText:
                    '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net',
              ),
              keyboardType: TextInputType.text,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration: InputDecoration(
                labelText: context.l10n.port,
                hintText:
                    context.l10n.leave_blank_for_default_8642_443_with_https,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKey,
              decoration: InputDecoration(
                labelText: context.l10n.api_key,
                hintText: context.l10n.api_server_key_from_hermes_env,
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
                      context.l10n.custom_proxy_and_dashboard_details,
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
                decoration: InputDecoration(
                  labelText: context.l10n.gateway_path_prefix,
                  hintText: context.l10n.example_profile_prefix_hint_full,
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashboardPrefix,
                decoration: InputDecoration(
                  labelText: context.l10n.dashboard_path_prefix,
                  hintText: context.l10n.e_g_dashboard_proxy_path_before_api,
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _dashboardProxied,
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.dashboard_behind_proxy),
                subtitle: Text(
                  context.l10n.nginx_injects_auth_app_sends_clean_requests,
                ),
                onChanged: (v) => setState(() => _dashboardProxied = v),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  context
                      .l10n
                      .optional_for_the_memory_cron_skills_settings_tabs_leave_blank,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
              TextField(
                controller: _dashPort,
                decoration: InputDecoration(
                  labelText: context.l10n.dashboard_port,
                  hintText: context.l10n.leave_blank_for_default_9119,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashUser,
                decoration: InputDecoration(
                  labelText: context.l10n.dashboard_username_optional,
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dashPass,
                decoration: InputDecoration(
                  labelText: context.l10n.dashboard_password_optional,
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desktopGatewayUrl,
                decoration: InputDecoration(
                  labelText: context.l10n.desktop_gateway_url_optional,
                  hintText: 'https://hermes-desktop.example.lan',
                  helperText: context
                      .l10n
                      .enables_file_attachments_through_the_desktop_remote_gateway,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gatewayProfile,
                decoration: InputDecoration(
                  labelText: context.l10n.hermes_profile_optional,
                  hintText: context.l10n.e_g_sol,
                  helperText: context
                      .l10n
                      .profile_this_connection_chats_as_when_the_dashboard_serves_several,
                  helperMaxLines: 3,
                ),
                autocorrect: false,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
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
              : Text(
                  _isEditing ? context.l10n.save_changes : context.l10n.connect,
                ),
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
    _gatewayProfile.dispose();
    super.dispose();
  }
}
