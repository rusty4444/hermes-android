import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'core/services/hands_free_route_observer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/models/client_certificate.dart';
import 'core/services/android_launch_intent_service.dart';
import 'core/services/android_share_intent_service.dart';
import 'core/services/client_certificate_service.dart';
import 'core/services/composer_draft_store.dart';
import 'core/services/config_backup.dart';
import 'core/services/config_backup_io.dart';
import 'core/services/config_backup_service.dart';
import 'core/services/connection_keepalive_service.dart';
import 'core/services/connection_manager.dart';
import 'core/services/desktop_gateway_client.dart';
import 'core/services/background_work_prefs.dart';
import 'core/services/gateway_turn_application_controller.dart';
import 'core/services/local_chat_pin_store.dart';
import 'core/services/mobile_push_service.dart';
import 'core/services/notification_approval_authority.dart';
import 'core/services/connection_mutation_barrier.dart';
import 'core/services/notification_prefs.dart';
import 'core/services/hands_free_preference.dart';
import 'core/services/lan_discovery_service.dart';
import 'core/services/text_size_preference.dart';
import 'core/services/theme_preference.dart';
import 'core/services/turn_notification_service.dart';
import 'core/screens/chat_screen.dart';
import 'core/screens/workspace_screen.dart';
import 'core/theme/hermes_theme.dart';
import 'core/utils/responsive.dart';
import 'core/widgets/config_backup_card.dart';
import 'core/widgets/theme_palette_picker.dart';
import 'core/widgets/hermes_system_ui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Remove any private key left behind by a cancelled connection import.
  unawaited(ClientCertificateService().cleanupStaging());
  runApp(const StartupApp());
}

/// Draws a Flutter frame before reading preferences or Android Keystore.
/// The connection store must still finish migration and credential hydration
/// before Home can access any saved connection.
class StartupApp extends StatefulWidget {
  const StartupApp({super.key, this.createConnectionManager});

  /// The production path uses [ConnectionManager.create]; tests can hold a
  /// real credential read pending without depending on the platform Keystore.
  final Future<ConnectionManager> Function(SharedPreferences)?
  createConnectionManager;

  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  final _shareIntents = AndroidShareIntentService();
  final _launchIntents = AndroidLaunchIntentService();
  SharedPreferences? _prefs;
  ConnectionManager? _connManager;
  Object? _startupError;

  Future<ConnectionManager> _createConnectionManager(SharedPreferences prefs) =>
      widget.createConnectionManager?.call(prefs) ??
      ConnectionManager.create(prefs);

  @override
  void initState() {
    super.initState();
    // A pending secure-store read must not keep the native splash on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    late SharedPreferences prefs;
    ConnectionManager? connManager;
    Object? startupError;
    // Preferences/Keystore and the two Android intent channels are
    // independent. Start all three after the first frame, but do not mount
    // Home until both the credential load and initial intents have finished.
    await Future.wait<void>([
      () async {
        prefs = await SharedPreferences.getInstance();
        try {
          connManager = await _createConnectionManager(prefs);
        } catch (error) {
          // A corrupt connection entry or a Keystore fault must lead to the
          // existing reset/retry screen, never to Home with unhydrated secrets.
          startupError = error;
        }
      }(),
      _shareIntents.initialize(),
      _launchIntents.initialize(),
    ]);
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _connManager = connManager;
      _startupError = startupError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    if (prefs != null) {
      final connManager = _connManager;
      if (connManager != null) {
        return HermesApp(
          connManager: connManager,
          shareIntents: _shareIntents,
          launchIntents: _launchIntents,
        );
      }
      return _StartupRecoveryApp(
        prefs: prefs,
        error: _startupError,
        createConnectionManager: _createConnectionManager,
        onRecovered: (manager) {
          if (mounted) setState(() => _connManager = manager);
        },
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: hermesTheme(Brightness.light),
      darkTheme: hermesTheme(Brightness.dark),
      home: const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

/// Minimal recovery surface shown when the connection store could not be
/// loaded at launch. Offers to wipe the damaged saved-connections metadata
/// (and only that key) and retry, rather than dying silently.
class _StartupRecoveryApp extends StatelessWidget {
  static final GlobalKey _rootKey = GlobalKey();

  const _StartupRecoveryApp({
    required this.prefs,
    required this.error,
    required this.createConnectionManager,
    required this.onRecovered,
  });

  final SharedPreferences prefs;
  final Object? error;
  final Future<ConnectionManager> Function(SharedPreferences)
  createConnectionManager;
  final ValueChanged<ConnectionManager> onRecovered;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      localeListResolutionCallback: resolvePreferredLocale,
      themeMode: ThemePreferenceStore(prefs).readMode(),
      theme: hermesTheme(
        Brightness.light,
        palette: ThemePreferenceStore(prefs).readPalette(),
      ),
      darkTheme: hermesTheme(
        Brightness.dark,
        palette: ThemePreferenceStore(prefs).readPalette(),
      ),
      builder: (context, child) => HermesSystemUi(child: child!),
      home: Builder(
        key: _rootKey,
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
                      try {
                        await ConnectionManager(prefs).resetConnections();
                        final retry = await createConnectionManager(prefs);
                        onRecovered(retry);
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
  // Optional boundaries keep root tests on the real owner and dispatchers.
  final GatewayTurnApplicationController? turnApplicationController;
  final TurnNotificationService? notifications;
  final MobilePushService? mobilePush;
  final Future<void> Function()? loadBackgroundPolicy;
  final ApiClient Function(SavedConnection)? notificationClientFactory;

  @visibleForTesting
  final Future<Session?> Function(SavedConnection, String)?
  testNotificationSessionLookup;
  const HermesApp({
    required this.connManager,
    this.shareIntents,
    this.launchIntents,
    this.turnApplicationController,
    this.notifications,
    this.mobilePush,
    this.loadBackgroundPolicy,
    this.notificationClientFactory,
    this.testNotificationSessionLookup,
    super.key,
  });

  @override
  State<HermesApp> createState() => HermesAppState();

  static ThemeMode getThemeMode(SharedPreferences prefs) {
    return ThemePreferenceStore(prefs).readMode();
  }

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    await ThemePreferenceStore(prefs).saveMode(mode);
  }

  static HermesPalette getThemePalette(SharedPreferences prefs) {
    return ThemePreferenceStore(prefs).readPalette();
  }

  static TextSizePreference getTextSizePreference(SharedPreferences prefs) {
    return TextSizePreferenceStore(prefs).read();
  }
}

/// Root-owned user intent survives suspension, unlike a consumed native tap.
/// Its captured account and push authority are revalidated on every retry.
class _NotificationNavigationIntent {
  final SavedConnection connection;
  final String? sessionId;
  final MobilePushRoute? pushRoute;
  final int generation;
  final Object? mutationEpoch;

  _NotificationNavigationIntent(
    this.connection,
    this.sessionId,
    MobilePushRoute? pushRoute,
    this.generation,
  ) : mutationEpoch = ConnectionMutationBarrier.capture(connection.id),
      pushRoute = pushRoute == null
          ? null
          : MobilePushRoute(
              pushRoute.connection,
              pushRoute.sessionId,
              pushRoute.eventId,
              Map<String, dynamic>.unmodifiable(pushRoute.authority),
            );

  bool canCoalesceAuthority(MobilePushRoute? incomingPush) {
    // Ordinary taps share account authority. Push proofs can differ in event,
    // consent revision or expiry; target equality cannot establish equivalence.
    return pushRoute == null && incomingPush == null;
  }
}

class HermesAppState extends State<HermesApp> with WidgetsBindingObserver {
  late final GatewayTurnApplicationController _turnApplicationController;
  late final TurnNotificationService _notifications;
  late final MobilePushService _mobilePush;
  late final void Function(NotificationResponse) _notificationHandler;
  bool? _confirmedBackgroundPolicy;
  bool get _backgroundPolicyReady => _confirmedBackgroundPolicy != null;
  bool _rootFrameReady = false;
  bool _pushRouting = false;
  bool _pushDirty = false;
  String? _pushHintsSignature;
  int _notificationGeneration = 0;
  String? _routingIdentity;
  _NotificationNavigationIntent? _routingIntent;
  final _notificationChatRoutes =
      <
        ({
          SavedConnection connection,
          String sessionId,
          bool openedAsStoredSession,
          Route<void> route,
        })
      >[];
  _NotificationNavigationIntent? _pendingNavigation;
  void Function()? _pendingNormalResponse;
  final _pendingApprovalResponses =
      <
        ({
          NotificationRoute route,
          SavedConnection connection,
          NotificationApprovalAuthority authority,
        })
      >[];

  /// Android foreground keep-alive: while the app is backgrounded with an
  /// unresolved chat turn, a foreground service holds the process so
  /// heartbeat timers keep firing and the WebSocket survives minimization.
  /// Bounded to active turns — an idle connection never earns a persistent
  /// notification.
  final ConnectionKeepAliveService _keepAlive = ConnectionKeepAliveService();

  Object? _keepAliveTurnActivityToken;
  bool _background = false;
  bool _closingTurnOwner = false;
  String? _ongoingSignature;
  final Set<String> _ongoingChats = {};
  Future<void> _ongoingWrites = Future<void>.value();

  /// Pushes from the app root (notification taps) need a navigator below the
  /// MaterialApp this state builds.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _turnApplicationController =
        widget.turnApplicationController ?? GatewayTurnApplicationController();
    _notifications = widget.notifications ?? TurnNotificationService.shared;
    _mobilePush = widget.mobilePush ?? MobilePushService.shared;
    _notificationHandler = _handleNotificationResponse;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _background = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    // Unknown policy is disabled, including when mounted already paused. Set
    // this before Home creates/restores any normal owner or activity callback.
    _keepAlive.onPolicyChanged(false);
    _turnApplicationController.setLifecycle(
      background: _background,
      backgroundWorkEnabled: false,
    );
    _keepAlive.onAppLifecycleState(
      lifecycle ?? AppLifecycleState.resumed,
      hasActiveTurn: _turnApplicationController.hasActiveTurn,
    );
    // The keep-alive follows the work: a turn settling (or starting) while
    // backgrounded must end (or earn) the foreground service immediately,
    // not wait for the next resume.
    _keepAliveTurnActivityToken = _turnApplicationController
        .addTurnActivityListener(_onTurnActivityChanged);
    backgroundWorkEnabled.addListener(_onBackgroundWorkPolicyChanged);
    BackgroundWorkPrefsStore.pendingChoice.addListener(
      _onBackgroundWorkPolicyChanged,
    );
    BackgroundWorkPrefsStore.confirmedChanges.addListener(
      _onBackgroundWorkPolicyConfirmed,
    );
    notificationPrefs.addListener(_syncOngoingChats);
    _mobilePush.addListener(_onMobilePushChanged);
    notificationResponseHandler = _notificationHandler;
    ConnectionMutationBarrier.addListener(_pruneApprovalActions);
    // A notification that launched a terminated app carries its tap/action in
    // the platform's launch details; route it once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final initialGeneration = _notificationGeneration;
      _rootFrameReady = true;
      unawaited(_loadBackgroundPolicy());
      unawaited(NotificationPrefsStore.load());
      unawaited(HandsFreePreferenceStore.load());
      _restoreNormalSessions();
      // The singleton is process-owned, not disposed with a replaceable root.
      unawaited(
        _mobilePush.initialize(widget.connManager).catchError((Object _) {}),
      );
      _onMobilePushChanged();
      _resumeNormalNotificationResponses();
      unawaited(_initializeForegroundNotifications());
      final initial = await _notifications.takeInitialNotificationResponse();
      if (initial != null &&
          mounted &&
          initialGeneration == _notificationGeneration) {
        _notificationHandler(initial);
      }
    });
  }

  Future<void> _loadBackgroundPolicy() async {
    try {
      await (widget.loadBackgroundPolicy?.call() ??
          BackgroundWorkPrefsStore.load());
      if (!mounted || _closingTurnOwner) return;
      _confirmedBackgroundPolicy = BackgroundWorkPrefsStore.confirmedEnabled;
      _onBackgroundWorkPolicyChanged();
    } catch (_) {
      // Failure leaves protection disabled, not at a speculative default.
    }
  }

  bool get _protectBackgroundWork =>
      _confirmedBackgroundPolicy == true &&
      !BackgroundWorkPrefsStore.pendingChoice.value &&
      backgroundWorkEnabled.value;

  Future<void> _initializeForegroundNotifications() async {
    await _notifications.ensureInitialized(refreshPermission: false);
    if (!mounted || _closingTurnOwner || _background) return;
    await _notifications.ensureInitialized(
      requestPermission: true,
      refreshPermission: false,
    );
    if (!mounted || _closingTurnOwner || _background) return;
    await _notifications.refreshAuthorization();
    if (!mounted || _closingTurnOwner) return;
    _ongoingSignature = null;
    _syncOngoingChats();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _background = false;
      _restoreNormalSessions();
      if (_rootFrameReady) {
        if (!_backgroundPolicyReady) unawaited(_loadBackgroundPolicy());
        unawaited(_initializeForegroundNotifications());
        _resumeNotificationNavigation();
        _onMobilePushChanged();
        _resumeNormalNotificationResponses();
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _background = true;
    }
    _turnApplicationController.setLifecycle(
      background: _background,
      backgroundWorkEnabled: _protectBackgroundWork,
    );
    _syncOngoingChats();
    _keepAlive.onAppLifecycleState(
      state,
      hasActiveTurn: _turnApplicationController.hasActiveTurn,
    );
  }

  void _pruneApprovalActions() {
    _pendingApprovalResponses.removeWhere(
      (entry) => !entry.authority.isCurrent,
    );
    prunePendingNotificationApprovals();
  }

  void _resumeNormalNotificationResponses() {
    final pending = _pendingNormalResponse;
    _pendingNormalResponse = null;
    final approvals = List.of(_pendingApprovalResponses);
    _pendingApprovalResponses.clear();
    pending?.call();
    for (final entry in approvals) {
      _dispatchNotificationResponse(
        entry.route,
        entry.connection,
        entry.authority,
      );
    }
  }

  void _restoreNormalSessions() {
    _pruneApprovalActions();
    _pruneNotificationChatRoutes();
    final connections = widget.connManager.getConnections();
    for (final connection in connections) {
      if (DesktopGatewayClient.endpointDigestFor(connection) == null) continue;
      unawaited(
        _turnApplicationController
            .normalSessionFor(connection)
            .ready
            .catchError((Object _) {}),
      );
    }
    _turnApplicationController.retainConnections(
      connections.map((connection) => connection.id).toSet(),
    );
  }

  void _onTurnActivityChanged() {
    if (_closingTurnOwner) return;
    _keepAlive.onTurnActivityChanged(_turnApplicationController.hasActiveTurn);
    _syncOngoingChats();
  }

  void _onBackgroundWorkPolicyConfirmed() {
    if (!mounted || _closingTurnOwner) return;
    _confirmedBackgroundPolicy = BackgroundWorkPrefsStore.confirmedEnabled;
    _onBackgroundWorkPolicyChanged();
  }

  void _onBackgroundWorkPolicyChanged() {
    if (_closingTurnOwner) return;
    final enabled = _protectBackgroundWork;
    _keepAlive.onPolicyChanged(enabled);
    _turnApplicationController.setLifecycle(
      background: _background,
      backgroundWorkEnabled: enabled,
    );
    _syncOngoingChats();
  }

  void _syncOngoingChats() {
    if (_closingTurnOwner) return;
    final activities = _turnApplicationController.activeChatActivities.toList()
      ..sort(
        (a, b) => '${a.connectionId}:${a.localSessionId}'.compareTo(
          '${b.connectionId}:${b.localSessionId}',
        ),
      );
    final signature = jsonEncode([
      _background,
      _protectBackgroundWork,
      notificationPrefs.value.toJson(),
      for (final activity in activities)
        [
          activity.connectionId,
          activity.localSessionId,
          activity.storedSessionId,
          activity.title,
          activity.turnId,
          activity.status,
        ],
    ]);
    if (signature == _ongoingSignature) return;
    _ongoingSignature = signature;
    _ongoingWrites = _ongoingWrites
        .then((_) async {
          if (_closingTurnOwner) return;
          final service = _notifications;
          final current = _turnApplicationController.activeChatActivities
              .toList();
          final desired = <String>{};
          var failed = false;
          for (final activity in current.where(
            (_) =>
                _background &&
                _protectBackgroundWork &&
                notificationPrefs.value.enabled,
          )) {
            if (_closingTurnOwner) break;
            final key = jsonEncode([
              activity.connectionId,
              activity.localSessionId,
            ]);
            desired.add(key);
            // A platform call can post successfully and still fail its reply.
            // Own targeted cleanup before the await, not after the whole batch.
            _ongoingChats.add(key);
            try {
              await service.showOngoingChat(
                connectionId: activity.connectionId,
                localSessionId: activity.localSessionId,
                storedSessionId: activity.storedSessionId,
                title: activity.title,
                turnId: activity.turnId,
                status: activity.status,
              );
            } catch (_) {
              failed = true;
            }
          }
          for (final stale in _ongoingChats.difference(desired)) {
            if (!await _cancelTrackedOngoingChat(stale)) failed = true;
          }
          // Retry on a later reconciliation, even if its desired state is the
          // same. Never spin immediately on a failing platform implementation.
          if (failed && _ongoingSignature == signature) {
            _ongoingSignature = null;
          }
        })
        .catchError((Object _) {
          if (_ongoingSignature == signature) _ongoingSignature = null;
        });
  }

  Future<bool> _cancelTrackedOngoingChat(String key) async {
    try {
      final identity = jsonDecode(key) as List;
      await _notifications.cancelOngoingChat(
        connectionId: identity[0] as String,
        localSessionId: identity[1] as String,
      );
      _ongoingChats.remove(key);
      return true;
    } catch (_) {
      // Keep both root ownership and the service's durable numeric index for
      // retry. One failed cancellation must not abandon its siblings.
      return false;
    }
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

  void _onMobilePushChanged() {
    if (!_rootFrameReady || !mounted || _closingTurnOwner) return;
    // Hints only reconcile an already-owned turn. They never submit a prompt,
    // answer an input request or create/navigate to an arbitrary session.
    final signature = jsonEncode([
      _mobilePush.connectionId,
      _mobilePush.events,
    ]);
    if (_pushHintsSignature != signature) {
      _pushHintsSignature = signature;
      final connection = _connectionById(_mobilePush.connectionId);
      if (connection != null && _mobilePush.active) {
        final normal = _turnApplicationController.normalSessionFor(connection);
        unawaited(
          normal.ready
              .then<void>((_) {
                if (!mounted ||
                    _closingTurnOwner ||
                    _pushHintsSignature != signature ||
                    !_mobilePush.active ||
                    !_connectionIsCurrent(connection)) {
                  return;
                }
                for (final event in _mobilePush.events) {
                  final id = event['session_id'];
                  if (id is String) normal.findChat(id)?.requestRecovery();
                }
              })
              .catchError((Object _) {}),
        );
      }
    }
    if (_background) return; // Retain taps until foreground navigation is safe.
    if (_pushRouting && _mobilePush.hasPendingTap) ++_notificationGeneration;
    _pushDirty = true;
    if (_pushRouting) return;
    unawaited(_drainPushRoutes());
  }

  Future<void> _drainPushRoutes() async {
    _pushRouting = true;
    try {
      while (_pushDirty && mounted && !_closingTurnOwner && !_background) {
        _pushDirty = false;
        final generation = _notificationGeneration;
        final route = await _mobilePush.takePendingNotificationRoute();
        if (!mounted || _closingTurnOwner) return;
        if (generation != _notificationGeneration) continue;
        if (route == null) continue;
        // Transfer the consumed tap into root intent before checking lifecycle.
        // The navigation worker validates consent, including after resume.
        await _openNotificationSession(
          route.connection,
          route.sessionId,
          pushRoute: route,
        );
      }
    } catch (_) {
      // Optional native push failure must not break normal notification taps.
    } finally {
      _pushRouting = false;
      if (_pushDirty && mounted && !_closingTurnOwner && !_background) {
        _onMobilePushChanged();
      }
    }
  }

  bool _connectionIsCurrent(SavedConnection connection) {
    final current = _connectionById(connection.id);
    // getConnections hydrates fresh objects. Bind the complete saved account,
    // including credentials/profile, rather than testing object identity.
    return current != null &&
        MobilePushService.binding(current) ==
            MobilePushService.binding(connection);
  }

  /// Routes a notification tap (or one of its action buttons) into the app.
  ///
  /// Approval actions answer through the turn controller when it owns the
  /// request; otherwise the action is left pending for the chat that does, and
  /// every response lands the user on the session the notification was about.
  void _handleNotificationResponse(NotificationResponse response) {
    if (!mounted || _closingTurnOwner) return;
    _pruneApprovalActions();
    final route = NotificationRoute.fromResponse(response);
    final hasExplicitConnection =
        route.connectionId != null && route.connectionId!.isNotEmpty;
    final connection = hasExplicitConnection
        ? _connectionById(route.connectionId)
        : _notificationConnection();
    if (connection == null) return;
    final manager = widget.connManager;

    // Capture at physical ingress, before either lifecycle deferral or I/O.
    // Legacy actions retain navigation, never automatic answer authority.
    final normal = route.approvalChoice == null
        ? null
        : _turnApplicationController.normalSessionFor(connection);
    final authority = normal == null
        ? null
        : NotificationApprovalAuthority.capture(
            connection: connection,
            accountBinding: route.approvalAccount,
            originMutation: route.approvalMutation,
            owner: normal,
            ownerIsCurrent: () =>
                mounted &&
                !_closingTurnOwner &&
                identical(widget.connManager, manager) &&
                !normal.isClosed &&
                _connectionIsCurrent(connection),
            refresh: () async {
              await manager.prefs.reload();
              await manager.refreshConnectionCredentials(connection.id);
              return _connectionIsCurrent(connection);
            },
          );
    void consume() =>
        _dispatchNotificationResponse(route, connection, authority);
    if (_background || !_rootFrameReady) {
      if (authority != null) {
        final duplicate = _pendingApprovalResponses.any(
          (entry) =>
              entry.route.sessionId == route.sessionId &&
              entry.route.requestId == route.requestId &&
              entry.authority.sameCapture(authority),
        );
        if (!duplicate) {
          _pendingApprovalResponses.add((
            route: route,
            connection: connection,
            authority: authority,
          ));
        }
      } else {
        _pendingNormalResponse = consume;
      }
    } else {
      consume();
    }
  }

  void _dispatchNotificationResponse(
    NotificationRoute route,
    SavedConnection connection,
    NotificationApprovalAuthority? authority,
  ) {
    if (!mounted || _closingTurnOwner) return;
    final choice = route.approvalChoice;
    final sessionId = route.sessionId;
    final requestId = route.requestId;
    if (choice != null &&
        sessionId != null &&
        requestId != null &&
        authority?.isCurrent == true) {
      final approval = PendingNotificationApproval(
        connectionId: connection.id,
        sessionId: sessionId,
        requestId: requestId,
        choice: choice,
        authority: authority,
      );
      if (claimNotificationApproval(approval)) {
        // Capture both dispatch owners before the first await. Never borrow a
        // replacement owner if an old answer returns false or throws later.
        unawaited(
          (() async {
            var retry = false;
            try {
              final normal = _turnApplicationController.normalSessionFor(
                connection,
              );
              final recovery = _turnApplicationController.sessionFor(
                connection,
              );
              if (!await authority!.validate()) return;
              if (await normal.tryRespondToApproval(
                sessionId: sessionId,
                choice: choice,
                requestId: requestId,
              )) {
                return;
              }
              if (!authority.isCurrent) return;
              if (await recovery.tryRespondToApproval(
                sessionId: sessionId,
                choice: choice,
                requestId: requestId,
              )) {
                return;
              }
              retry = true;
            } catch (_) {
              // addPending also fences revoked completions and pending mutations.
              retry = true;
            } finally {
              releaseNotificationApproval(approval);
              if (retry) addPendingNotificationApproval(approval);
            }
          })(),
        );
      }
    }
    unawaited(
      _openNotificationSession(connection, sessionId).catchError((Object _) {}),
    );
  }

  /// The connection a payload names, or null when it no longer exists.
  SavedConnection? _connectionById(String? id) {
    if (id == null || id.isEmpty) return null;
    return widget.connManager
        .getConnections()
        .where((connection) => connection.id == id)
        .firstOrNull;
  }

  void _pruneNotificationChatRoutes() {
    final navigator = _navigatorKey.currentState;
    _notificationChatRoutes.removeWhere(
      (entry) =>
          !entry.route.isActive ||
          entry.route.navigator != navigator ||
          !_connectionIsCurrent(entry.connection),
    );
  }

  String _notificationChatIdentity(SavedConnection connection, String? id) {
    final normal = _turnApplicationController.normalSessionFor(connection);
    final owner = normal.findChat(id ?? '');
    return jsonEncode([
      MobilePushService.binding(connection),
      owner?.storedSessionId ?? owner?.localSessionId ?? id,
    ]);
  }

  bool _focusNotificationChat(SavedConnection connection, String? sessionId) {
    _pruneNotificationChatRoutes();
    final identity = _notificationChatIdentity(connection, sessionId);
    // Resolve both sides now: a verified handoff can change the winning owner's
    // local ID, and a later lineage binding can change its durable ID as well.
    final matches = _notificationChatRoutes.where(
      (entry) =>
          _notificationChatIdentity(entry.connection, entry.sessionId) ==
          identity,
    );
    // If independent pre-binding routes converge, prefer the original durable
    // route over a local draft route, even after its durable ID moves again.
    // Within each kind retain registration order, independent of the tapped alias.
    final route =
        (matches.where((entry) => entry.openedAsStoredSession).firstOrNull ??
                matches.firstOrNull)
            ?.route;
    final navigator = _navigatorKey.currentState;
    if (route == null || navigator == null || !navigator.mounted) return false;
    // isActive includes covered routes. Pop back to the canonical route rather
    // than constructing another ChatScreen or leaving an unrelated page above it.
    if (!route.isCurrent) navigator.popUntil((candidate) => candidate == route);
    return true;
  }

  void _resumeNotificationNavigation() {
    final intent = _pendingNavigation;
    if (intent != null && _routingIntent == null) {
      unawaited(_runNotificationNavigation(intent).catchError((Object _) {}));
    }
  }

  /// Opens the chat a notification was about; falls back to the workspace when
  /// the session cannot be fetched (deleted, or outside the recent list).
  Future<void> _openNotificationSession(
    SavedConnection connection,
    String? sessionId, {
    MobilePushRoute? pushRoute,
  }) async {
    if (!mounted ||
        _closingTurnOwner ||
        ConnectionMutationBarrier.isPending(connection.id) ||
        !_connectionIsCurrent(connection)) {
      return;
    }
    final identity = _notificationChatIdentity(connection, sessionId);
    final activeIntent = _routingIntent;
    if (_routingIdentity == identity &&
        activeIntent != null &&
        activeIntent.generation == _notificationGeneration &&
        activeIntent.canCoalesceAuthority(pushRoute)) {
      return;
    }
    if (pushRoute == null &&
        !_background &&
        _focusNotificationChat(connection, sessionId)) {
      // Tapping the already-open chat is still a newer routing intent: an
      // older, different pending lookup must not steal focus afterwards.
      ++_notificationGeneration;
      _pendingNavigation = null;
      return;
    }
    final generation = ++_notificationGeneration;
    final intent = _NotificationNavigationIntent(
      connection,
      sessionId,
      pushRoute,
      generation,
    );
    _pendingNavigation = intent;
    await _runNotificationNavigation(intent);
  }

  Future<void> _runNotificationNavigation(
    _NotificationNavigationIntent intent,
  ) async {
    final connection = intent.connection;
    if (!mounted ||
        _closingTurnOwner ||
        intent.generation != _notificationGeneration ||
        !ConnectionMutationBarrier.isCurrent(
          connection.id,
          intent.mutationEpoch,
        ) ||
        !_connectionIsCurrent(connection)) {
      if (identical(_pendingNavigation, intent)) _pendingNavigation = null;
      return;
    }
    var sessionId = intent.sessionId;
    final pushRoute = intent.pushRoute;
    final generation = intent.generation;
    final normal = _turnApplicationController.normalSessionFor(connection);
    _routingIdentity = _notificationChatIdentity(connection, sessionId);
    _routingIntent = intent;
    var deferred = false;
    bool currentSync() {
      if (!mounted ||
          _closingTurnOwner ||
          generation != _notificationGeneration ||
          !ConnectionMutationBarrier.isCurrent(
            connection.id,
            intent.mutationEpoch,
          ) ||
          !_connectionIsCurrent(connection)) {
        return false;
      }
      if (_background) {
        deferred = true;
        return false;
      }
      return true;
    }

    Future<bool> current() async {
      if (!currentSync()) return false;
      if (pushRoute != null) {
        final valid = await _mobilePush.isRouteCurrent(pushRoute);
        if (!currentSync() || !valid) return false;
      }
      // Validation itself awaits native authority; recheck the saved account
      // and latest tap generation after it, not just before it.
      return currentSync();
    }

    try {
      Session? session;
      Session? retainedSession;
      if (!await current() || !currentSync()) return;
      if (_focusNotificationChat(connection, sessionId)) return;
      if (sessionId != null && sessionId.isNotEmpty) {
        await normal.ready.catchError((Object _) {});
        if (!await current() || !currentSync()) return;
        final owner = normal.findChat(sessionId);
        _routingIdentity = _notificationChatIdentity(connection, sessionId);
        if (_focusNotificationChat(connection, sessionId)) return;
        sessionId = owner?.storedSessionId ?? sessionId;
        if (owner != null) {
          retainedSession = Session(
            id: owner.localSessionId,
            title: owner.title,
            model: '',
            source: 'mobile',
            messageCount: 0,
            isActive: owner.snapshot.hasActiveTurn,
            preview: '',
            startedAt: 0,
            isLocalDraft: owner.storedSessionId == null,
          );
        }
        ApiClient? client;
        try {
          client =
              widget.notificationClientFactory?.call(connection) ??
              ApiClient(
                baseUrl: connection.baseUrl,
                apiKey: connection.apiKey,
                pathPrefix: connection.gatewayPrefix ?? '',
                gatewayProfile: connection.gatewayProfile,
                clientCertificate: connection.clientCertificate,
              );
          session = widget.testNotificationSessionLookup != null
              ? await widget.testNotificationSessionLookup!(
                  connection,
                  sessionId,
                )
              : await client.getSessionById(
                  sessionId,
                  canContinue: current,
                  isCurrent: currentSync,
                );
          if (!await current() || !currentSync()) return;
          if (session != null &&
              session.id != sessionId &&
              session.lineageRootId != sessionId) {
            return;
          }
          session ??= pushRoute == null ? retainedSession : null;
        } catch (_) {
          if (!await current() || !currentSync()) return;
          session = pushRoute == null ? retainedSession : null;
        } finally {
          client?.close();
        }
      }
      if (!await current() || !currentSync()) return;
      // Push has no legacy workspace/draft fallback: only the authenticated
      // existing session named by the reconciled event is eligible.
      if (pushRoute != null && session == null) return;
      // Binding may have converged while the authenticated detail read awaited.
      if (session != null && _focusNotificationChat(connection, session.id)) {
        return;
      }
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
      final route = MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          connection: connection,
          session: session!,
          turnApplicationController: _turnApplicationController,
        ),
      );
      final navigator = _navigatorKey.currentState;
      if (navigator == null || !navigator.mounted) return;
      _notificationChatRoutes.add((
        connection: connection,
        sessionId: session.id,
        openedAsStoredSession: !session.isLocalDraft,
        route: route,
      ));
      unawaited(
        navigator.push(route).whenComplete(() {
          _notificationChatRoutes.removeWhere((entry) => entry.route == route);
        }),
      );
    } finally {
      if (!deferred && identical(_pendingNavigation, intent)) {
        _pendingNavigation = null;
      }
      if (identical(_routingIntent, intent)) {
        _routingIdentity = null;
        _routingIntent = null;
      }
      if (deferred && mounted && !_closingTurnOwner && !_background) {
        _resumeNotificationNavigation();
      }
    }
  }

  Future<void> setTextSizePreference(TextSizePreference preference) async {
    await TextSizePreferenceStore(widget.connManager.prefs).save(preference);
    if (mounted) setState(() {});
  }

  Future<void> setThemePalette(HermesPalette palette) async {
    try {
      await ThemePreferenceStore(widget.connManager.prefs).savePalette(palette);
    } finally {
      refreshAppearancePreferences();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      await ThemePreferenceStore(widget.connManager.prefs).saveMode(mode);
    } finally {
      refreshAppearancePreferences();
    }
  }

  /// Re-read preferences after a backup import without replacing the Navigator.
  void refreshAppearancePreferences() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [handsFreeRouteObserver],
      onGenerateTitle: (context) => context.l10n.hermes_agent,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      localeListResolutionCallback: resolvePreferredLocale,
      themeMode: HermesApp.getThemeMode(widget.connManager.prefs),
      theme: hermesTheme(
        Brightness.light,
        palette: HermesApp.getThemePalette(widget.connManager.prefs),
      ),
      darkTheme: hermesTheme(
        Brightness.dark,
        palette: HermesApp.getThemePalette(widget.connManager.prefs),
      ),
      builder: (context, child) {
        final systemMediaQuery = MediaQuery.of(context);
        final preference = HermesApp.getTextSizePreference(
          widget.connManager.prefs,
        );
        return HermesSystemUi(
          child: MediaQuery(
            data: systemMediaQuery.copyWith(
              textScaler: preference.applyTo(systemMediaQuery.textScaler),
            ),
            child: child!,
          ),
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
    WidgetsBinding.instance.removeObserver(this);
    final token = _keepAliveTurnActivityToken;
    _closingTurnOwner = true;
    _pendingNormalResponse = null;
    _pendingApprovalResponses.clear();
    ConnectionMutationBarrier.removeListener(_pruneApprovalActions);
    prunePendingNotificationApprovals();
    _pendingNavigation = null;
    _notificationChatRoutes.clear();
    ++_notificationGeneration;
    _mobilePush.removeListener(_onMobilePushChanged);
    // Do not dispose MobilePushService.shared: a root remount must still work.
    notificationPrefs.removeListener(_syncOngoingChats);
    if (identical(notificationResponseHandler, _notificationHandler)) {
      notificationResponseHandler = null;
    }
    backgroundWorkEnabled.removeListener(_onBackgroundWorkPolicyChanged);
    BackgroundWorkPrefsStore.pendingChoice.removeListener(
      _onBackgroundWorkPolicyChanged,
    );
    BackgroundWorkPrefsStore.confirmedChanges.removeListener(
      _onBackgroundWorkPolicyConfirmed,
    );
    if (token != null) {
      _turnApplicationController.removeTurnActivityListener(token);
      _keepAliveTurnActivityToken = null;
    }
    // Belt for the detached case: if the widget tree tears down while the
    // service is up, the native side must not outlive its only controller.
    unawaited(_keepAlive.stop());
    unawaited(_turnApplicationController.close());
    unawaited(
      _ongoingWrites
          .then<void>((_) async {
            for (final key in _ongoingChats.toList()) {
              await _cancelTrackedOngoingChat(key);
            }
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}

/// Brand header used across screens.
class HermesHeader extends StatelessWidget {
  final String? subtitle;
  const HermesHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.accent, width: 0.5)),
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
              color: tokens.accent,
              letterSpacing: 6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: tokens.muted,
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
    final controller = widget.turnApplicationController;
    for (final connection in _connections) {
      if (DesktopGatewayClient.endpointDigestFor(connection) == null) {
        controller.revokeConnection(connection.id);
      } else {
        unawaited(
          controller
              .normalSessionFor(connection)
              .ready
              .catchError((Object _) {}),
        );
      }
    }
    controller.retainConnections(
      _connections.map((connection) => connection.id).toSet(),
    );
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
      context
          .findAncestorStateOfType<HermesAppState>()
          ?.refreshAppearancePreferences();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.summary)));
    } catch (error) {
      if (!mounted) return;
      _showRestoreError(error);
    }
  }

  void _showAppearance() {
    final app = context.findAncestorStateOfType<HermesAppState>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sheetContext.l10n.appearance,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ThemeAppearanceSettings(
              preferences: widget.connManager.prefs,
              onChanged: app?.refreshAppearancePreferences,
            ),
          ],
        ),
      ),
    );
  }

  void _showRestoreError(Object error) {
    final message = error is ConfigBackupException
        ? error.message
        : context.l10n.the_backup_could_not_be_restored;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showLanDiscovery() async {
    final service = LanDiscoveryService();
    final discovered = await showModalBottomSheet<List<DiscoveredHermesServer>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => LanDiscoverySheet(service: service),
    );
    if (discovered == null || !mounted) return;
    for (final server in discovered) {
      if (!mounted) break;
      _showConnectionDialog(
        initialHost: server.connectionUrl,
        initialPort: server.port,
        initialLabel: server.label,
      );
    }
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

  void _showConnectionDialog({
    SavedConnection? existing,
    String? initialHost,
    int? initialPort,
    String? initialLabel,
  }) {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        initialConnection: existing,
        initialHost: initialHost,
        initialPort: initialPort,
        initialLabel: initialLabel,
        onCertificateFilesReleased:
            widget.connManager.cleanupUnreferencedCertificates,
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
              clientCertificate,
              clearClientCertificate = false,
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
                  clientCertificate: clientCertificate,
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
                  clientCertificate: clientCertificate,
                  clearClientCertificate: clearClientCertificate,
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
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
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
                          gatewayProfile: conn.gatewayProfile,
                          clientCertificate: conn.clientCertificate,
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
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: HermesTokens.of(context).onSurface,
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
                    style: TextStyle(
                      color: HermesTokens.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
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
                          clientCertificate: conn.clientCertificate,
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

                      final client = DashboardClient.fromConnection(
                        conn.copyWith(
                          dashboardPortOverride: port,
                          dashboardPrefix: dashboardPrefix,
                          dashboardProxied: proxied,
                          dashboardUsername: user,
                          dashboardPassword: pass,
                        ),
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
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: HermesTokens.of(context).onSurface,
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
        leading: Icon(Icons.router, color: HermesTokens.of(context).accent),
        title: Text(conn.label),
        subtitle: Text(
          context.l10n.connection_address_key(
            '${conn.host}:${conn.port}${conn.gatewayPrefix != null && conn.gatewayPrefix!.isNotEmpty ? conn.gatewayPrefix! : ''}',
            conn.apiKey.isNotEmpty ? "\u2713" : "\u2717",
          ),
          style: TextStyle(color: HermesTokens.of(context).muted),
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
                style: TextStyle(color: HermesTokens.of(context).danger),
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
          IconButton(
            key: const Key('home_appearance_button'),
            tooltip: context.l10n.appearance,
            onPressed: _showAppearance,
            icon: const Icon(Icons.palette_outlined),
          ),
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
                  Icon(
                    Icons.cloud_outlined,
                    size: 64,
                    color: HermesTokens.of(context).muted,
                  ),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HermesTokens.of(context).muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('home_restore_config_button'),
                    onPressed: _showRestoreConfig,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(context.l10n.restore_configuration),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('home_lan_discovery_button'),
                    onPressed: _showLanDiscovery,
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Find Hermes on LAN'),
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
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  final SavedConnection? initialConnection;
  final Future<void> Function() onCertificateFilesReleased;
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
    ClientCertificateConfig? clientCertificate,
    bool clearClientCertificate,
  })
  onSave;
  final String? initialHost;
  final int? initialPort;
  final String? initialLabel;

  const _AddDialog({
    required this.onSave,
    required this.onCertificateFilesReleased,
    this.initialConnection,
    this.initialHost,
    this.initialPort,
    this.initialLabel,
  });

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
  late final TextEditingController _certificatePassword;
  late final ClientCertificateService _certificateService;
  final _certificateFileLease = ClientCertificateFileLease();
  Future<void>? _certificateCleanup;
  late bool _showDashboard;
  late bool _dashboardProxied;
  late bool _useClientCertificate;
  ClientCertificateConfig? _clientCertificate;
  List<int>? _pemCertificateBytes;
  String? _pemCertificateName;
  List<int>? _pemPrivateKeyBytes;
  String? _pemPrivateKeyName;

  /// Bytes of the last pick that failed only because it needs a password.
  /// Retained so the password field can retry the import without a re-pick.
  List<int>? _pendingCertificateBytes;
  String? _pendingCertificateName;
  bool _pendingPasswordBytes = false;
  Timer? _certificateRetryTimer;
  bool _pickingCertificate = false;
  int _certificateSelection = 0;
  bool _importingCertificate = false;
  bool _validating = false;
  String? _error;

  /// Whether the current imported identity was committed by a successful save.
  /// Anything still staged when the dialog closes is discarded.
  bool _certificateSaved = false;

  bool get _isEditing => widget.initialConnection != null;

  bool get _certificateBusy => _pickingCertificate || _importingCertificate;

  @override
  void initState() {
    super.initState();
    final conn = widget.initialConnection;
    _label = TextEditingController(
      text: widget.initialLabel ?? conn?.label ?? 'Home',
    );
    _host = TextEditingController(
      text: conn == null
          ? (widget.initialHost ?? '')
          : conn.useHttps
          ? 'https://${conn.host}'
          : conn.host,
    );
    _port = TextEditingController(
      text: (widget.initialPort ?? conn?.port ?? 8642).toString(),
    );
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
    _certificateService = ClientCertificateService();
    _certificatePassword = TextEditingController();
    _certificatePassword.addListener(_onCertificatePasswordChanged);
    _clientCertificate = conn?.clientCertificate;
    if (_clientCertificate case final certificate?) {
      // Validation can finish on an already-loaded TLS context after another
      // manager rotates this account. Keep the selected files until Save and
      // its rollback/native cleanup settle, not just the validation request.
      _certificateFileLease.retainIdentity(certificate);
    }
    _useClientCertificate = conn?.clientCertificate != null;
    _host.addListener(_onHostChanged);
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

  void _onHostChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _isHttpsInput {
    final normalized = SavedConnection.normalizeHostAndPort(
      _host.text.trim(),
      int.tryParse(_port.text.trim()),
    );
    return normalized.useHttps;
  }

  Future<List<int>?> _fileBytes(PlatformFile file) async {
    if (file.size > _maxCertificateFileBytes) {
      throw const ClientCertificateImportException(
        'Certificate file too large.',
      );
    }
    final bytes = file.bytes;
    if (bytes != null) {
      if (bytes.length > _maxCertificateFileBytes) {
        throw const ClientCertificateImportException(
          'Certificate file too large.',
        );
      }
      return bytes;
    }
    final path = file.path;
    if (path == null) return null;
    // Providers can report an unknown (zero) size, and cached files can change.
    // Bound the actual read, not just the picker metadata, before parsing.
    final contents = <int>[];
    await for (final chunk in io.File(
      path,
    ).openRead(0, _maxCertificateFileBytes + 1)) {
      contents.addAll(chunk);
      if (contents.length > _maxCertificateFileBytes) {
        throw const ClientCertificateImportException(
          'Certificate file too large.',
        );
      }
    }
    return contents;
  }

  /// Extensions the desktop picker offers for certificate material.
  static const List<String> _certificatePickerExtensions = [
    'pem',
    'crt',
    'cer',
    'key',
    'p12',
    'pfx',
  ];

  /// Certificate identities are a few KiB; anything larger is a mis-pick and is
  /// rejected before it is read into memory.
  static const int _maxCertificateFileBytes = 1024 * 1024;

  /// Whether the platform's document picker can filter by file extension.
  ///
  /// Android's Storage Access Framework filters on MIME type, and neither `pem`
  /// nor `key` has a `MimeTypeMap` entry while content providers commonly label
  /// PEM files `application/octet-stream` — so an extension filter greys out the
  /// very files the user is trying to import (iOS document types behave the
  /// same). Those platforms pick unfiltered and let
  /// [ClientCertificateService] reject anything that is not certificate
  /// material; desktop pickers match the extension itself, where the filter
  /// still helps.
  bool get _pickerFiltersByExtension => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => false,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.fuchsia => true,
  };

  Future<List<PlatformFile>> _pickCertificateFiles() async {
    final filterByExtension = _pickerFiltersByExtension;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: filterByExtension ? FileType.custom : FileType.any,
        allowedExtensions: filterByExtension
            ? _certificatePickerExtensions
            : null,
        allowMultiple: true,
        // Read through the cached path instead of loading the whole pick into
        // memory: the size check below has to run before the file is read.
        withData: false,
      );
      final files = result?.files ?? const <PlatformFile>[];
      for (final file in files) {
        if (file.size > _maxCertificateFileBytes) {
          if (!mounted) return const <PlatformFile>[];
          setState(() => _error = context.l10n.certificate_import_failed);
          return const <PlatformFile>[];
        }
      }
      return files;
    } catch (_) {
      if (!mounted) return const <PlatformFile>[];
      setState(() => _error = context.l10n.certificate_import_failed);
      return const <PlatformFile>[];
    }
  }

  /// Single entry point for the certificate picker: sniffs each picked file
  /// (PKCS#12 container, combined PEM, or lone certificate/key half) and
  /// stages a lone certificate across picks until its key arrives.
  Future<void> _pickCertificateIdentity() async {
    if (!mounted || !_useClientCertificate || _certificateBusy || _validating) {
      return;
    }
    final selection = ++_certificateSelection;
    _certificateRetryTimer?.cancel();
    setState(() => _pickingCertificate = true);
    try {
      await _certificateFileLease.run(
        () => _pickCertificateIdentityOwned(selection),
      );
    } catch (_) {
      if (_isCurrentCertificateSelection(selection)) {
        setState(() => _error = context.l10n.certificate_import_failed);
      }
    } finally {
      if (mounted) setState(() => _pickingCertificate = false);
    }
  }

  bool _isCurrentCertificateSelection(int selection) =>
      mounted && _useClientCertificate && selection == _certificateSelection;

  Future<void> _pickCertificateIdentityOwned(int selection) async {
    final files = await _pickCertificateFiles();
    if (!_isCurrentCertificateSelection(selection) || files.isEmpty) return;
    _clearPendingCertificatePick();
    for (final file in files) {
      if (!_isCurrentCertificateSelection(selection)) return;
      final bytes = await _fileBytes(file);
      if (!_isCurrentCertificateSelection(selection)) return;
      if (bytes == null) {
        if (!mounted) return;
        setState(() => _error = context.l10n.certificate_import_failed);
        return;
      }
      final config = await _runCertificateImport(
        () => _certificateService.importIdentityDocument(
          bytes: bytes,
          password: _certificatePassword.text,
          label: file.name,
          stagedCertificateBytes: _pemCertificateBytes,
          stagedCertificateName: _pemCertificateName,
          stagedPrivateKeyBytes: _pemPrivateKeyBytes,
        ),
      );
      if (!_isCurrentCertificateSelection(selection)) return;
      if (config == null) {
        // A lone half: remember it and wait for its counterpart.
        if (_looksLikeCertificateBytes(bytes)) {
          _pemCertificateBytes = bytes;
          _pemCertificateName = file.name;
        } else if (_looksLikePrivateKeyBytes(bytes)) {
          _pemPrivateKeyBytes = bytes;
          _pemPrivateKeyName = file.name;
        }
        // A password-protected file arrives here with the bytes retained so the
        // password field can retry without asking the user to pick again.
        _pendingCertificateBytes = _pendingPasswordBytes ? bytes : null;
        _pendingCertificateName = _pendingPasswordBytes ? file.name : null;
        if (mounted) setState(() {});
      } else {
        _clearPendingCertificatePick();
        _pemCertificateBytes = null;
        _pemCertificateName = null;
        _pemPrivateKeyBytes = null;
        _pemPrivateKeyName = null;
      }
      if (_clientCertificate != null) return;
    }
  }

  void _clearPendingCertificatePick() {
    _certificateRetryTimer?.cancel();
    _pendingCertificateBytes = null;
    _pendingCertificateName = null;
    _pendingPasswordBytes = false;
  }

  /// Debounced so typing a password does not run a parse per keystroke.
  void _onCertificatePasswordChanged() {
    if (!_pendingPasswordBytes && _pendingCertificateBytes == null) return;
    _certificateRetryTimer?.cancel();
    _certificateRetryTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_retryPendingCertificateImport());
    });
  }

  /// Re-runs the import for a pick that failed because it needs a password.
  ///
  /// Picking a certificate and then typing its password is the natural order,
  /// so the first attempt is always made with whatever the password field
  /// holds (usually nothing). A password failure keeps the bytes; this retries
  /// as soon as the user types, and keeps the error visible while it is wrong.
  Future<void> _retryPendingCertificateImport() async {
    final bytes = _pendingCertificateBytes;
    final name = _pendingCertificateName;
    if (bytes == null || name == null) return;
    if (_certificatePassword.text.isEmpty) return;
    if (!mounted || !_useClientCertificate || _certificateBusy || _validating) {
      return;
    }

    final config = await _runCertificateImport(
      () => _certificateService.importIdentityDocument(
        bytes: bytes,
        password: _certificatePassword.text,
        label: name,
        stagedCertificateBytes: _pemCertificateBytes,
        stagedCertificateName: _pemCertificateName,
        stagedPrivateKeyBytes: _pemPrivateKeyBytes,
      ),
    );
    if (!mounted) return;
    if (config != null) {
      _clearPendingCertificatePick();
      _pemCertificateBytes = null;
      _pemCertificateName = null;
      _pemPrivateKeyBytes = null;
      _pemPrivateKeyName = null;
      if (_clientCertificate != null) setState(() {});
    }
  }

  static bool _looksLikePrivateKeyBytes(List<int> bytes) {
    try {
      final text = String.fromCharCodes(bytes);
      return text.contains('PRIVATE KEY-----');
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeCertificateBytes(List<int> bytes) {
    if (bytes.length > 2 && bytes[0] == 0x30 && bytes[1] == 0x82) {
      return false;
    }
    try {
      final text = String.fromCharCodes(bytes);
      return text.contains('-----BEGIN CERTIFICATE-----');
    } catch (_) {
      return false;
    }
  }

  Future<ClientCertificateConfig?> _runCertificateImport(
    Future<ClientCertificateConfig?> Function() import,
  ) => _certificateFileLease.run(
    () => _importCertificate(import, _certificateSelection),
  );

  Future<ClientCertificateConfig?> _importCertificate(
    Future<ClientCertificateConfig?> Function() import,
    int selection,
  ) async {
    if (!_isCurrentCertificateSelection(selection)) return null;
    _scheduleCertificateCleanup();
    setState(() {
      _importingCertificate = true;
      _error = null;
    });
    try {
      final config = await import();
      if (config == null) {
        // A lone certificate half: staged by the caller, waiting for its key.
        if (mounted) {
          setState(() => _importingCertificate = false);
        }
        return null;
      }
      if (!_isCurrentCertificateSelection(selection)) {
        // The dialog closed while parsing: never leave the imported key behind.
        await _certificateService.discard(config);
        _certificateFileLease.releaseIdentity(config);
        return null;
      }
      // Replacing an earlier staged pick must not leave that key on disk.
      final previous = _clientCertificate;
      if (previous != null) {
        await _certificateService.discard(previous);
        _certificateFileLease.releaseIdentity(previous);
      }
      if (!_isCurrentCertificateSelection(selection)) {
        await _certificateService.discard(config);
        _certificateFileLease.releaseIdentity(config);
        return null;
      }
      setState(() {
        _clientCertificate = config;
        _useClientCertificate = true;
        _certificateSaved = false;
        _pemCertificateBytes = null;
        _pemCertificateName = null;
        _pemPrivateKeyBytes = null;
        _pemPrivateKeyName = null;
        _pendingCertificateBytes = null;
        _pendingCertificateName = null;
        _pendingPasswordBytes = false;
        _importingCertificate = false;
      });
      return config;
    } on ClientCertificateImportException catch (e) {
      if (!mounted) return null;
      setState(() {
        _error = e.message;
        _pendingPasswordBytes = e.passwordRelated;
        _importingCertificate = false;
      });
      return null;
    } catch (_) {
      if (!mounted) return null;
      setState(() {
        _error = context.l10n.certificate_import_failed;
        _importingCertificate = false;
      });
      return null;
    }
  }

  void _removeClientCertificate() {
    _certificateSelection++;
    final previous = _clientCertificate;
    if (previous != null && !_certificateSaved) {
      // A staged import that was never saved is simply abandoned.
      unawaited(_certificateService.discard(previous));
      _certificateFileLease.releaseIdentity(previous);
    }
    setState(() {
      _clientCertificate = null;
      _useClientCertificate = false;
      _certificateSaved = false;
      _pemCertificateBytes = null;
      _pemCertificateName = null;
      _pemPrivateKeyBytes = null;
      _pemPrivateKeyName = null;
    });
    _clearPendingCertificatePick();
  }

  Future<void> _validateAndSave() =>
      _certificateFileLease.run(_validateAndSaveOwned);

  Future<void> _validateAndSaveOwned() async {
    _scheduleCertificateCleanup();
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();

    // A blank Port field means "not supplied": normalizeHostAndPort then infers
    // 8642 for HTTP and 443 for HTTPS.
    if (label.isEmpty || host.isEmpty || (port != null && port <= 0)) return;
    if (_certificateBusy) return;
    final clientCertificate = _useClientCertificate ? _clientCertificate : null;
    if (_useClientCertificate && clientCertificate == null) {
      // A file was picked but could not be opened yet. Saying "load a client
      // certificate" here reads as though the pick was never made.
      setState(() {
        _error = _pendingPasswordBytes
            ? context.l10n.enter_the_certificate_password_to_finish_loading_it
            : context.l10n.client_certificate_required;
      });
      return;
    }

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
        clientCertificate: clientCertificate,
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
          desktopGatewayUrl.isNotEmpty ||
          dashboardPrefix.isNotEmpty ||
          _dashboardProxied) {
        final dashClient = DashboardClient.fromConnection(
          SavedConnection(
            id: '',
            label: '',
            host: normalized.host,
            port: normalized.port,
            apiKey: '',
            useHttps: normalized.useHttps,
            dashboardPortOverride: dashPort,
            dashboardPrefix: dashboardPrefix,
            dashboardProxied: _dashboardProxied,
            dashboardUsername: dashUser.isEmpty ? null : dashUser,
            dashboardPassword: dashPass.isEmpty ? null : dashPass,
            desktopGatewayUrl: desktopGatewayUrl,
            gatewayProfile: gatewayProfile,
            clientCertificate: clientCertificate,
          ),
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

      // Keep the validated identity leased across queueing, commit, rollback
      // and native cleanup. A thrown save does not prove physical rollback.
      var savedCertificate = clientCertificate;
      if (savedCertificate != null &&
          await _certificateService.isStaged(savedCertificate)) {
        savedCertificate = await _certificateService.commit(savedCertificate);
        // Retain the new paths for retry and disposal even if save reports an
        // uncertain commit. The old staging directory no longer exists.
        _clientCertificate = savedCertificate;
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
        clientCertificate: savedCertificate,
        clearClientCertificate: savedCertificate == null,
      );
      _certificateSaved = true;
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
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
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
                      color: HermesTokens.of(context).muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.custom_proxy_and_dashboard_details,
                      style: TextStyle(
                        color: HermesTokens.of(context).muted,
                        fontSize: 13,
                      ),
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
                  style: TextStyle(
                    color: HermesTokens.of(context).muted,
                    fontSize: 12,
                  ),
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
            if (_isHttpsInput || _useClientCertificate) ...[
              const Divider(height: 24),
              SwitchListTile(
                key: const Key('connection_client_certificate_toggle'),
                contentPadding: EdgeInsets.zero,
                value: _useClientCertificate,
                title: Text(context.l10n.client_certificate_mtls),
                subtitle: Text(
                  _isHttpsInput
                      ? context.l10n.client_certificate_mtls_description
                      : context.l10n.client_certificate_https_only,
                ),
                onChanged: _validating || _certificateBusy
                    ? null
                    : (value) {
                        final previous = _clientCertificate;
                        if (!value && previous != null && !_certificateSaved) {
                          unawaited(_certificateService.discard(previous));
                          _certificateFileLease.releaseIdentity(previous);
                        }
                        setState(() {
                          _useClientCertificate = value;
                          if (!value) {
                            _certificateSelection++;
                            _clearPendingCertificatePick();
                            _certificateSaved = false;
                            _clientCertificate = null;
                            _pemCertificateBytes = null;
                            _pemCertificateName = null;
                            _pemPrivateKeyBytes = null;
                            _pemPrivateKeyName = null;
                            _pendingCertificateBytes = null;
                            _pendingCertificateName = null;
                            _pendingPasswordBytes = false;
                          }
                        });
                      },
              ),
              if (_useClientCertificate) ...[
                if (_clientCertificate case final certificate?) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified_user_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.l10n.client_certificate_loaded(
                                  certificate.label,
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        // Stacked, not side by side: a long label next to the
                        // button squeezed the file name into an unreadable
                        // sliver.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const Key(
                              'connection_client_certificate_remove',
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _validating || _certificateBusy
                                ? null
                                : _removeClientCertificate,
                            child: Text(context.l10n.remove_certificate),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('connection_client_certificate_pick'),
                      onPressed: _validating || _certificateBusy
                          ? null
                          : _pickCertificateIdentity,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(context.l10n.choose_certificate),
                    ),
                  ),
                  if (_pemCertificateName != null ||
                      _pemPrivateKeyName != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          ?_pemCertificateName,
                          ?_pemPrivateKeyName,
                        ].join('  ·  '),
                        style: TextStyle(
                          color: HermesTokens.of(context).muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  // Shown only when the picked file actually asked for a
                  // password. Rendering it up front implied the password had to
                  // be supplied before choosing a certificate.
                  if (_pendingPasswordBytes) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('connection_client_certificate_password'),
                      controller: _certificatePassword,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.certificate_password,
                        helperText:
                            context.l10n.this_certificate_is_password_protected,
                        helperMaxLines: 2,
                      ),
                      obscureText: true,
                      enabled: !_validating && !_certificateBusy,
                    ),
                  ],
                ],
                if (_certificateBusy) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
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
          onPressed: _validating || _certificateBusy ? null : _validateAndSave,
          child: _validating
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HermesTokens.of(context).onSurface,
                  ),
                )
              : Text(
                  _isEditing ? context.l10n.save_changes : context.l10n.connect,
                ),
        ),
      ],
    );
  }

  void _scheduleCertificateCleanup() {
    // Register once with the asynchronous file owner. Disposal only closes it;
    // cleanup runs after admitted work, independently of the route's lifetime.
    _certificateCleanup ??= _certificateFileLease.whenClosed.then(
      (_) => _releaseCertificateFiles(),
    );
  }

  Future<void> _releaseCertificateFiles() async {
    try {
      final certificate = _clientCertificate;
      if (certificate != null) await _certificateService.discard(certificate);
    } catch (_) {
      // Best-effort; the shared physical reference check below is authoritative.
    }
    await widget.onCertificateFilesReleased();
  }

  @override
  void dispose() {
    _certificateSelection++;
    unawaited(_certificateFileLease.close());
    _certificateRetryTimer?.cancel();
    _certificatePassword.removeListener(_onCertificatePasswordChanged);
    _host.removeListener(_onHostChanged);
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
    _certificatePassword.dispose();
    super.dispose();
  }
}

class LanDiscoverySheet extends StatefulWidget {
  final LanDiscoveryService service;

  const LanDiscoverySheet({super.key, required this.service});

  @override
  State<LanDiscoverySheet> createState() => _LanDiscoverySheetState();
}

class _LanDiscoverySheetState extends State<LanDiscoverySheet> {
  List<DiscoveredHermesServer> _servers = [];
  bool _scanning = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  @override
  void dispose() {
    widget.service.cancel();
    super.dispose();
  }

  Future<void> _startDiscovery() async {
    try {
      final servers = await widget.service.discover();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Discovery failed: $e';
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Find Hermes on LAN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_scanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_scanning && _servers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text('No Hermes servers found on the local network.'),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                return ListTile(
                  leading: Icon(
                    Icons.router,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(server.label),
                  subtitle: Text(server.displayName),
                  onTap: () {
                    Navigator.pop(context, [server]);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
