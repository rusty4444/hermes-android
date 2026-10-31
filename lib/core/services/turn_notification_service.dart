import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../l10n/l10n.dart' show resolvePreferredLocale;
import 'notification_prefs.dart';
import 'notification_approval_authority.dart';

/// Delivered to the app root when the user taps a notification body or one of
/// its action buttons. Set once by the root widget; every service instance
/// wires its plugin to this single handler so tap routing cannot depend on
/// which screen happened to initialise last.
void Function(NotificationResponse response)? notificationResponseHandler;

/// The Android/iOS notification channel a [TurnNotification] belongs to.
///
/// Phase 3 of the daily-driver roadmap replaces the single Hermes Turns
/// channel with four prioritized channels; describing the channel as data
/// keeps that change testable.
class TurnNotificationChannel {
  final String id;
  final String name;
  final String description;

  const TurnNotificationChannel({
    required this.id,
    required this.name,
    required this.description,
  });
}

/// Visual urgency for a notification: [high] lets the OS show a heads-up card
/// (attention kinds), [low] keeps finished background work quiet.
enum TurnNotificationImportance { low, defaultImportance, high }

/// An action button rendered on the notification itself. Pressing it brings
/// the app forward (`showsUserInterface`) so the live app answers the request
/// instead of a background isolate that cannot reach the gateway.
class TurnNotificationAction {
  final String id;
  final String label;

  const TurnNotificationAction({required this.id, required this.label});
}

/// A notification Hermes wants Android to post, described as plain data.
class TurnNotification {
  final int id;
  final String title;
  final String body;
  final String payload;
  final TurnNotificationChannel channel;
  final List<TurnNotificationAction> actions;
  final TurnNotificationImportance importance;
  final bool ongoing;
  final bool silent;
  final bool onlyAlertOnce;

  const TurnNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.channel,
    this.actions = const [],
    this.importance = TurnNotificationImportance.defaultImportance,
    this.ongoing = false,
    this.silent = false,
    this.onlyAlertOnce = false,
  });
}

/// The platform seam [TurnNotificationService] posts through.
///
/// The production implementation is [PluginTurnNotificationSink]; tests supply
/// a recording double so notification behaviour can be verified without a
/// platform channel.
abstract class TurnNotificationSink {
  Future<void> initialize();

  /// Reads current OS authorisation without displaying a permission prompt.
  /// Returns null only when the platform has no notification permission gate.
  Future<bool?> checkPermission();

  /// Asks the platform for permission to post notifications.
  ///
  /// Returns `true` when granted, `false` when denied, and `null` when the
  /// platform has no notification implementation — in which case posting
  /// has no permission gate here.
  Future<bool?> requestPermission();

  /// The tap or action that launched a terminated app, when the platform
  /// reports one. Consumed once by the service so a cold start still routes.
  Future<NotificationResponse?> takeInitialLaunchResponse();

  Future<void> show(TurnNotification notification);

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

/// Default sink backed by `flutter_local_notifications`.
class PluginTurnNotificationSink implements TurnNotificationSink {
  final FlutterLocalNotificationsPlugin _plugin;

  PluginTurnNotificationSink({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        notificationResponseHandler?.call(response);
      },
    );
  }

  @override
  Future<bool?> checkPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final permissions = await ios.checkPermissions();
      return permissions?.isEnabled == true ||
          permissions?.isProvisionalEnabled == true;
    }

    return null;
  }

  @override
  Future<bool?> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return android.requestNotificationsPermission();
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return ios.requestPermissions(alert: true, badge: true, sound: true);
    }

    // No platform implementation resolved: nothing gates posting here.
    return null;
  }

  @override
  Future<NotificationResponse?> takeInitialLaunchResponse() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse;
  }

  @override
  Future<void> show(TurnNotification notification) async {
    final (importance, priority) = switch (notification.importance) {
      TurnNotificationImportance.high => (Importance.high, Priority.high),
      TurnNotificationImportance.low => (Importance.low, Priority.low),
      TurnNotificationImportance.defaultImportance => (
        Importance.defaultImportance,
        Priority.defaultPriority,
      ),
    };
    final androidDetails = AndroidNotificationDetails(
      notification.channel.id,
      notification.channel.name,
      channelDescription: notification.channel.description,
      importance: importance,
      priority: priority,
      autoCancel: !notification.ongoing,
      ongoing: notification.ongoing,
      silent: notification.silent,
      onlyAlertOnce: notification.onlyAlertOnce,
      playSound: !notification.silent,
      enableVibration: !notification.silent,
      actions: [
        for (final action in notification.actions)
          AndroidNotificationAction(
            action.id,
            action.label,
            showsUserInterface: true,
          ),
      ],
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: !notification.silent,
      presentBadge: !notification.silent,
      presentSound: !notification.silent,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notification.id,
      notification.title,
      notification.body,
      details,
      payload: notification.payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Delivers Android notifications when a gateway turn completes while the app
/// is backgrounded, mirroring the Hermes Desktop tray notification behaviour.
///
/// One app-wide sink owns terminal/attention channels and optional ongoing
/// per-chat status entries. Initialization is headless-safe; only foreground
/// callers explicitly opt in to requesting notification permission.
class TurnNotificationService {
  static const turnChannel = TurnNotificationChannel(
    id: 'hermes_turn_notifications',
    name: 'Hermes Turns',
    description: 'Notifications for completed background turns',
  );

  /// Attention kinds get their own high-importance channel so approvals and
  /// input requests can surface as heads-up cards while the app is away.
  static const attentionChannel = TurnNotificationChannel(
    id: 'hermes_attention',
    name: 'Hermes Attention',
    description: 'Approvals and input requests that need you',
  );

  /// Finished background work: quiet by design.
  static const backgroundChannel = TurnNotificationChannel(
    id: 'hermes_background',
    name: 'Hermes Background',
    description: 'Background task completions',
  );

  /// Gateway notices: credits and plugin messages.
  static const noticesChannel = TurnNotificationChannel(
    id: 'hermes_notices',
    name: 'Hermes Notices',
    description: 'Credit and plugin notices',
  );

  /// The app-wide instance used outside tests, so every dispatcher shares one
  /// plugin, one initialisation and one tap handler.
  static TurnNotificationService? _shared;

  static TurnNotificationService get shared =>
      _shared ??= TurnNotificationService();

  static TurnNotificationChannel get ongoingChannel {
    final locale = resolvePreferredLocale(
      PlatformDispatcher.instance.locales,
      AppLocalizations.supportedLocales,
    );
    final strings = lookupAppLocalizations(locale);
    return TurnNotificationChannel(
      id: 'hermes_ongoing_chats',
      name: strings.ongoing_chat_channel_name,
      description: strings.ongoing_chat_channel_description,
    );
  }

  /// Numeric IDs only: no titles, chat contents, credentials or routing data.
  /// Not included in configuration backups.
  static const ongoingIdsStorageKey = 'hermes_ongoing_chat_notification_ids';
  final Set<int> _ongoingIds = {};
  SharedPreferences? _ongoingPrefs;
  Future<void>? _ongoingTail;

  Future<void> _queueOngoing(Future<void> Function() operation) {
    final previous = _ongoingTail;
    final result = previous == null
        ? operation()
        : previous.then((_) => operation());
    late final Future<void> tail;
    void release() {
      if (identical(_ongoingTail, tail)) _ongoingTail = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _ongoingTail = tail;
    return result;
  }

  Future<void> _persistOngoingIds() async {
    final prefs = _ongoingPrefs;
    if (prefs == null ||
        !await prefs.setStringList(
          ongoingIdsStorageKey,
          _ongoingIds.map((id) => id.toString()).toList()..sort(),
        )) {
      throw StateError('Ongoing notification bookkeeping unavailable');
    }
  }

  Future<void> _cleanOrphanedOngoingChats() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Optional ongoing entries need durable bookkeeping. Other notification
      // kinds remain usable if this store is unavailable.
      return;
    }
    _ongoingPrefs = prefs;
    final raw = prefs.get(ongoingIdsStorageKey);
    if (raw is List) {
      for (final value in raw) {
        final id = value is String ? int.tryParse(value) : null;
        // Never cancel native 4705, push or terminal entries, even if a
        // corrupt/imported preference names them.
        if (id != null && id >= 0x20000000 && id <= 0x2fffffff) {
          _ongoingIds.add(id);
        }
      }
    }
    for (final id in _ongoingIds.toList()) {
      await _sink.cancel(id);
      _ongoingIds.remove(id);
    }
    if (raw != null) await _persistOngoingIds();
  }

  /// One replaceable, quiet entry per local chat, independent of turn/stored
  /// identity changes. The native service's mandatory disclosure is separate.
  Future<void> showOngoingChat({
    required String connectionId,
    required String localSessionId,
    String? storedSessionId,
    required String title,
    required String turnId,
    required String status,
  }) => _queueOngoing(() async {
    await ensureInitialized(refreshPermission: false);
    if (!_initialized) return;
    final id = ongoingChatNotificationIdFor(
      connectionId: connectionId,
      localSessionId: localSessionId,
    );
    if (!notificationPrefs.value.enabled || !_permissionGranted) {
      await _cancelOngoingId(id);
      return;
    }
    // If bookkeeping cannot be saved, do not create an uncleanable orphan.
    if (_ongoingPrefs == null) return;
    _ongoingIds.add(id);
    await _persistOngoingIds();
    if (!notificationPrefs.value.enabled || !_permissionGranted) {
      await _cancelOngoingId(id);
      return;
    }
    await _sink.show(
      TurnNotification(
        id: id,
        title: title,
        body: status,
        payload: jsonEncode({
          'connectionId': connectionId,
          'sessionId': storedSessionId?.isNotEmpty == true
              ? storedSessionId
              : localSessionId,
          'localSessionId': localSessionId,
          'turnId': turnId,
        }),
        channel: ongoingChannel,
        importance: TurnNotificationImportance.low,
        ongoing: true,
        silent: true,
        onlyAlertOnce: true,
      ),
    );
  });

  Future<void> cancelOngoingChat({
    required String connectionId,
    required String localSessionId,
  }) => _queueOngoing(() async {
    await ensureInitialized(refreshPermission: false);
    if (!_initialized) return;
    await _cancelOngoingId(
      ongoingChatNotificationIdFor(
        connectionId: connectionId,
        localSessionId: localSessionId,
      ),
    );
  });

  Future<void> _cancelOngoingId(int id) async {
    await _sink.cancel(id);
    _ongoingIds.remove(id);
    if (_ongoingPrefs != null) await _persistOngoingIds();
  }

  /// Targeted cleanup only. Never calls the plugin's broad cancelAll, which
  /// could remove the foreground-service disclosure or attention notifications.
  Future<void> cancelAllOngoingChats() => _queueOngoing(() async {
    await ensureInitialized(refreshPermission: false);
    if (!_initialized) return;
    for (final id in _ongoingIds.toList()) {
      await _cancelOngoingId(id);
    }
  });

  /// The channel a [kind] posts on.
  static TurnNotificationChannel channelFor(HermesNotificationKind kind) =>
      switch (kind) {
        HermesNotificationKind.approval ||
        HermesNotificationKind.input => attentionChannel,
        HermesNotificationKind.turnDone ||
        HermesNotificationKind.turnError => turnChannel,
        HermesNotificationKind.backgroundDone => backgroundChannel,
        HermesNotificationKind.credits ||
        HermesNotificationKind.plugin => noticesChannel,
      };

  /// Visual urgency a [kind] posts with.
  static TurnNotificationImportance importanceFor(
    HermesNotificationKind kind,
  ) => switch (kind) {
    HermesNotificationKind.approval ||
    HermesNotificationKind.input => TurnNotificationImportance.high,
    HermesNotificationKind.backgroundDone => TurnNotificationImportance.low,
    _ => TurnNotificationImportance.defaultImportance,
  };

  final TurnNotificationSink _sink;

  bool _initialized = false;
  bool _permissionGranted = true;
  bool _permissionRequested = false;
  Future<void>? _initializing;
  Future<void>? _requestingPermission;
  Future<void>? _refreshingAuthorization;
  int _permissionRevision = 0;
  int _authorizationDemand = 0;
  int _authorizationSatisfied = 0;

  TurnNotificationService({
    TurnNotificationSink? sink,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _sink = sink ?? PluginTurnNotificationSink(plugin: plugin);

  /// Whether the platform currently allows Hermes to post notifications.
  ///
  /// Refreshed by [ensureInitialized], including after returning from OS
  /// Settings. A denial or unavailable permission check is not a grant.
  bool get permissionGranted => _permissionGranted;

  /// Initialises once and passively refreshes current OS authorisation.
  ///
  /// Only explicit foreground callers may request permission, once after a
  /// successful platform request. Later checks never re-prompt, even after a
  /// denial. Failed platform operations degrade silently and may be retried.
  Future<void> ensureInitialized({
    bool requestPermission = false,
    bool refreshPermission = true,
  }) async {
    if (!_initialized) {
      final flight = _initializing ??= _initialize();
      try {
        await flight;
      } finally {
        if (identical(_initializing, flight)) _initializing = null;
      }
    }
    // Background/headless callers never ask for UI permission. The foreground
    // app root or Settings explicitly opts in, even after headless init.
    if (!_initialized) return;
    if (requestPermission && !_permissionRequested) {
      final flight = _requestingPermission ??= _requestPermission();
      try {
        await flight;
      } finally {
        if (identical(_requestingPermission, flight)) {
          _requestingPermission = null;
        }
      }
    } else if (refreshPermission) {
      await refreshAuthorization();
    }
  }

  Future<void> _initialize() async {
    try {
      await _sink.initialize();
      await _cleanOrphanedOngoingChats();
      _initialized = true;
    } catch (_) {
      // Missing plugins must not break startup; a later call may retry.
    }
  }

  Future<void> _requestPermission() async {
    ++_permissionRevision;
    try {
      _permissionGranted = await _sink.requestPermission() ?? true;
      _permissionRequested = true;
    } catch (_) {
      // Unknown is not a grant. Allow an explicit foreground retry later.
      _permissionGranted = false;
    }
  }

  /// Foreground resume/Settings may observe grants or revocations made in OS
  /// settings. Refreshing is separate from the one-shot permission prompt:
  /// denial never causes repeated dialogs, and headless initialization does
  /// neither. Join an active prompt and fence older passive results behind it.
  Future<void> refreshAuthorization() async {
    // Register demand before initialization awaits. Joining an older platform
    // read is not evidence about an OS change observed by a later caller.
    ++_authorizationDemand;
    if (!_initialized) {
      final flight = _initializing ??= _initialize();
      try {
        await flight;
      } finally {
        if (identical(_initializing, flight)) _initializing = null;
      }
    }
    if (!_initialized) return;
    final request = _requestingPermission;
    if (request != null) await request;
    // Coalesce callers before each read, but drain a fresh trailing read when
    // demand arrives after its snapshot. The watermark also covers callers
    // joining a completed flight before its finalizer has cleared the slot.
    while (_authorizationSatisfied < _authorizationDemand) {
      final flight = _refreshingAuthorization ??= _refreshAuthorization();
      try {
        await flight;
      } finally {
        if (identical(_refreshingAuthorization, flight)) {
          _refreshingAuthorization = null;
        }
      }
    }
  }

  Future<void> _refreshAuthorization() async {
    final demand = _authorizationDemand;
    final revision = _permissionRevision;
    var granted = false;
    try {
      granted = await _sink.checkPermission() ?? true;
    } catch (_) {
      // An unavailable permission read is not a grant.
    }
    if (revision == _permissionRevision && demand == _authorizationDemand) {
      _permissionGranted = granted;
    }
    // A newer explicit prompt owns permission; do not let this passive caller
    // finish against the old cache while that prompt is still unresolved.
    final request = _requestingPermission;
    if (request != null) await request;
    _authorizationSatisfied = demand;
  }

  /// Posts a notification when a gateway turn completes while the app is
  /// backgrounded.
  ///
  /// [turnSummary] is a short description (e.g. session title or prompt
  /// excerpt); [turnId] ensures the notification is stable and replaceable.
  /// [sessionId]/[connectionId] are carried in the payload so a tap can route
  /// back to the originating chat, even across multiple connections.
  Future<void> showTurnCompleted({
    required String title,
    required String turnSummary,
    required String turnId,
    String? sessionId,
    String? connectionId,
  }) async {
    if (!_initialized ||
        !notificationKindEnabled(HermesNotificationKind.turnDone)) {
      return;
    }
    final identity = _turnIdentity(
      turnId: turnId,
      sessionId: sessionId,
      connectionId: connectionId,
    );
    // Replayed settlement callbacks must not alert repeatedly.
    if (_throttled('${HermesNotificationKind.turnDone.name}:$identity')) {
      return;
    }

    await _sink.show(
      TurnNotification(
        id: notificationIdFor(identity),
        title: title,
        body: turnSummary,
        payload: _turnPayload(
          turnId: turnId,
          sessionId: sessionId,
          connectionId: connectionId,
        ),
        channel: turnChannel,
      ),
    );
  }

  /// Cancels a specific turn notification.
  Future<void> cancelTurnCompleted(
    String turnId, {
    String? sessionId,
    String? connectionId,
  }) async {
    if (!_initialized) return;
    await _sink.cancel(
      notificationIdFor(
        _turnIdentity(
          turnId: turnId,
          sessionId: sessionId,
          connectionId: connectionId,
        ),
      ),
    );
  }

  /// Posts the failure counterpart of [showTurnCompleted] on the same channel,
  /// so the two kinds share one Android channel but keep separate toggles.
  Future<void> showTurnFailed({
    required String title,
    required String turnSummary,
    required String turnId,
    String? sessionId,
    String? connectionId,
  }) async {
    if (!_initialized ||
        !notificationKindEnabled(HermesNotificationKind.turnError)) {
      return;
    }
    final identity = _turnIdentity(
      turnId: turnId,
      sessionId: sessionId,
      connectionId: connectionId,
    );
    // Replayed settlement callbacks must not alert repeatedly.
    if (_throttled('${HermesNotificationKind.turnError.name}:$identity')) {
      return;
    }

    await _sink.show(
      TurnNotification(
        id: notificationIdFor(identity),
        title: title,
        body: turnSummary,
        payload: _turnPayload(
          turnId: turnId,
          sessionId: sessionId,
          connectionId: connectionId,
        ),
        channel: turnChannel,
      ),
    );
  }

  /// JSON payload so a tap can route back to the originating chat, even
  /// across multiple connections.
  static String _turnPayload({
    required String turnId,
    String? sessionId,
    String? connectionId,
  }) => jsonEncode({
    'turnId': turnId,
    if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    if (connectionId != null && connectionId.isNotEmpty)
      'connectionId': connectionId,
  });

  static String _turnIdentity({
    required String turnId,
    String? sessionId,
    String? connectionId,
  }) => jsonEncode([connectionId ?? '', sessionId ?? '', turnId]);

  // De-dupe replayed events for the same full event identity. Self-evicting:
  // entries older than the window are pruned on every dispatch, so the map
  // can't grow.
  static const _throttleWindowMs = 1000;
  final Map<String, int> _lastFiredAt = {};

  bool _throttled(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastFiredAt.removeWhere((_, at) => now - at >= _throttleWindowMs);
    if (_lastFiredAt.containsKey(key)) return true;
    _lastFiredAt[key] = now;
    return false;
  }

  /// Posts one native notification for [kind] when the device allows it.
  ///
  /// Callers gate on the app being backgrounded; this method enforces the
  /// user's per-kind preferences and the 1s replay throttle. Returns whether
  /// the notification was handed to the platform.
  Future<bool> showKind({
    required HermesNotificationKind kind,
    required String title,
    required String body,
    required String eventId,
    String? sessionId,
    String? connectionId,
    List<TurnNotificationAction> actions = const [],
    String? payload,
  }) async {
    if (!_initialized) return false;
    if (!notificationKindEnabled(kind)) return false;

    final identity = jsonEncode([
      kind.name,
      connectionId ?? '',
      sessionId ?? '',
      eventId,
    ]);
    if (_throttled(identity)) return false;

    await _sink.show(
      TurnNotification(
        id: notificationIdFor(identity),
        title: title,
        body: body,
        payload: payload ?? '',
        channel: channelFor(kind),
        actions: actions,
        importance: importanceFor(kind),
      ),
    );
    return true;
  }

  /// Settings "send test": bypasses gating like the desktop panel does, so a
  /// silent OS-level permission failure can be told apart from a dead feature.
  Future<bool> sendTestNotification({
    required String title,
    required String body,
  }) async {
    await ensureInitialized(requestPermission: true, refreshPermission: false);
    await refreshAuthorization();
    if (!_initialized || !_permissionGranted) return false;

    try {
      await _sink.show(
        TurnNotification(
          id: notificationIdFor('hermes-notification-test'),
          title: title,
          body: body,
          payload: 'test',
          channel: turnChannel,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _initialLaunchConsumed = false;

  /// The tap or action that launched a terminated app, if any — consumed once
  /// so a cold start still routes to the originating chat.
  Future<NotificationResponse?> takeInitialNotificationResponse() async {
    if (_initialLaunchConsumed) return null;
    _initialLaunchConsumed = true;
    try {
      return await _sink.takeInitialLaunchResponse();
    } catch (_) {
      return null;
    }
  }

  /// Removes all Hermes turn notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _sink.cancelAll();
  }

  /// Stable, non-negative Android notification id derived from [turnId].
  ///
  /// Masking instead of negating keeps the id inside the 31-bit range Android
  /// accepts, and keeps one turn mapped to exactly one notification so a turn
  /// replaces its own notification instead of stacking duplicates.
  static int notificationIdFor(String turnId) =>
      0x10000000 | _stableHash(turnId);

  /// The local id remains stable when a draft gains its canonical stored id.
  static int ongoingChatNotificationIdFor({
    required String connectionId,
    required String localSessionId,
  }) => 0x20000000 | _stableHash(jsonEncode([connectionId, localSessionId]));

  // FNV-1a over UTF-8, explicitly bounded on every multiplication. Do not use
  // String.hashCode: the language does not guarantee it across processes.
  static int _stableHash(String identity) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(identity)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x0fffffff;
  }
}

/// A notification tap or action, parsed from the platform response payload.
///
/// Current payloads are JSON (`sessionId`/`connectionId`/`requestId`); older
/// turn notifications carried a plain turn id, which parses to a route with
/// no routing fields.
@immutable
class NotificationRoute {
  final String? sessionId;
  final String? connectionId;
  final String? requestId;
  final String? actionId;
  final String? localSessionId;
  final String? turnId;
  final String? approvalAccount;
  final String? approvalMutation;

  const NotificationRoute({
    this.sessionId,
    this.connectionId,
    this.requestId,
    this.actionId,
    this.localSessionId,
    this.turnId,
    this.approvalAccount,
    this.approvalMutation,
  });

  static NotificationRoute fromResponse(NotificationResponse response) {
    String? sessionId;
    String? connectionId;
    String? requestId;
    String? localSessionId;
    String? turnId;
    String? approvalAccount;
    String? approvalMutation;
    final raw = response.payload;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          sessionId = decoded['sessionId']?.toString();
          connectionId = decoded['connectionId']?.toString();
          requestId = decoded['requestId']?.toString();
          localSessionId = decoded['localSessionId']?.toString();
          turnId = decoded['turnId']?.toString();
          approvalAccount = decoded['approvalAccount'] as String?;
          approvalMutation = decoded['approvalMutation'] as String?;
        }
      } catch (_) {
        // A plain-string payload (older turns) carries only the turn id.
      }
    }
    return NotificationRoute(
      sessionId: sessionId,
      connectionId: connectionId,
      requestId: requestId,
      actionId: response.actionId,
      localSessionId: localSessionId,
      turnId: turnId,
      approvalAccount: approvalAccount,
      approvalMutation: approvalMutation,
    );
  }

  /// The approval choice an action press maps to, or null for a body tap.
  String? get approvalChoice => switch (actionId) {
    'approve' => 'once',
    'reject' => 'deny',
    _ => null,
  };
}

/// An approval a notification action could not answer directly — the request
/// belongs to an open chat's route-local gateway. That chat screen consumes
/// this and responds through its own gateway.
@immutable
class PendingNotificationApproval {
  /// The connection the notification named, so ids can never cross gateways.
  final String connectionId;
  final String sessionId;
  final String requestId;
  final String choice;

  /// Optional only for decoding/legacy fixture compatibility. Unscoped entries
  /// have no automatic-answer authority and are never admitted to the queue.
  final NotificationApprovalAuthority? authority;

  const PendingNotificationApproval({
    required this.connectionId,
    required this.sessionId,
    required this.requestId,
    required this.choice,
    this.authority,
  });
}

/// Approvals notification actions left behind for open chats to answer.
///
/// A list, not a single slot: several taps in a row (or two sessions on one
/// connection) must not overwrite each other. Entries stay until the owning
/// chat confirms the answer, so a cold start or a throw never loses a tap.
final ValueNotifier<List<PendingNotificationApproval>>
pendingNotificationApprovals = ValueNotifier(const []);

/// Queues only live captured authority; deduplication stays inside that exact
/// account/mutation/owner plus session/request, never across replacements.
void addPendingNotificationApproval(PendingNotificationApproval approval) {
  if (approval.authority?.isCurrent != true) return;
  prunePendingNotificationApprovals();
  final existing = pendingNotificationApprovals.value;
  final duplicate = existing.any(
    (item) =>
        item.connectionId == approval.connectionId &&
        item.sessionId == approval.sessionId &&
        item.requestId == approval.requestId &&
        item.authority?.sameCapture(approval.authority!) == true,
  );
  if (duplicate) return;
  pendingNotificationApprovals.value = [...existing, approval];
}

/// Removes [approval] once its owner confirmed it was answered.
void removePendingNotificationApproval(PendingNotificationApproval approval) {
  if (!pendingNotificationApprovals.value.any(
    (item) => identical(item, approval),
  )) {
    return;
  }
  pendingNotificationApprovals.value = [
    for (final item in pendingNotificationApprovals.value)
      if (!identical(item, approval)) item,
  ];
}

void prunePendingNotificationApprovals() {
  final existing = pendingNotificationApprovals.value;
  final current = existing
      .where((item) => item.authority?.isCurrent == true)
      .toList();
  if (current.length != existing.length) {
    pendingNotificationApprovals.value = current;
  }
}

final _answeringNotificationApprovals = <PendingNotificationApproval>{};

bool claimNotificationApproval(PendingNotificationApproval approval) {
  if (approval.authority?.isCurrent != true ||
      _answeringNotificationApprovals.any(
        (item) =>
            item.authority?.isCurrent == true &&
            item.connectionId == approval.connectionId &&
            item.sessionId == approval.sessionId &&
            item.requestId == approval.requestId &&
            item.authority!.sameCapture(approval.authority!),
      )) {
    return false;
  }
  return _answeringNotificationApprovals.add(approval);
}

void releaseNotificationApproval(PendingNotificationApproval approval) =>
    _answeringNotificationApprovals.remove(approval);
