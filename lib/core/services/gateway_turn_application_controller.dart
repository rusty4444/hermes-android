import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/connection.dart';
import 'desktop_gateway_client.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'gateway_turn_recovery.dart';
import 'normal_gateway_application_session.dart';
import 'operational_activity_store.dart';
import 'connection_manager.dart';
import 'chat_presentation_state.dart';
import 'turn_notification_service.dart';
import 'connection_mutation_barrier.dart';

typedef GatewayTurnApplicationSessionFactory =
    GatewayTurnApplicationSession Function(SavedConnection connection);
typedef GatewayTurnJournalFactory = GatewayTurnJournal Function();

/// Connection-scoped recovery surface retained by the application owner.
abstract interface class GatewayTurnApplicationSession {
  /// Routes interactive server requests for one mounted chat screen.
  ///
  /// The application session outlives individual routes, so listeners are
  /// keyed by local session id rather than replacing one connection-wide
  /// callback whenever the user opens another chat.
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  );

  /// Detaches only this owner's exact registration. Safe after [close], even
  /// while asynchronous cleanup is pending; it never acquires a new owner.
  void removeAsyncEventListener(String localSessionId, Object registration);

  /// Registers the mounted owner of one local session's terminal callbacks.
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  );

  /// Removes [registration] without disturbing a replacement route owner.
  void removeTurnSettledListener(String localSessionId, Object registration);

  /// Whether the exact approval is still unresolved on this session's socket.
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  });

  /// Responds only when this recovery session owns the request.
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  });

  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  });

  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  });

  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  });

  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  });

  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  });

  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  });

  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  });

  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  });

  Future<void> close();

  /// Registers the mounted owner of one session's durable binding callbacks.
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  );

  /// Removes [registration] without disturbing a replacement route owner.
  void removeSessionBoundListener(String localSessionId, Object registration);

  /// True while this session has an unresolved turn (in flight, recovering,
  /// or awaiting reconcile). The background keep-alive policy aggregates
  /// this across sessions to bound the foreground service to real work.
  bool get hasActiveTurn;

  /// Registers an observer notified when [hasActiveTurn] may have changed.
  Object addTurnActivityListener(void Function() listener);

  void removeTurnActivityListener(Object token);
}

/// Optional local admission guard for callers whose consent can be revoked
/// while connection setup or durable write-ahead is suspended. No wire changes.
abstract interface class GuardedGatewayTurnSubmission {
  Future<GatewayTurnRecoveryState> submitGuarded({
    required String localSessionId,
    required String text,
    required bool Function() maySubmit,
    GatewayTurnStateCallback? onState,
  });
}

Future<GatewayTurnRecoveryState> submitGuardedGatewayTurn(
  GatewayTurnApplicationSession session, {
  required String localSessionId,
  required String text,
  required bool Function() maySubmit,
  GatewayTurnStateCallback? onState,
}) {
  if (session is! GuardedGatewayTurnSubmission || !maySubmit()) {
    return Future.error(const GatewayTurnAdmissionRevoked());
  }
  return (session as GuardedGatewayTurnSubmission).submitGuarded(
    localSessionId: localSessionId,
    text: text,
    maySubmit: maySubmit,
    onState: onState,
  );
}

/// Owns recovery registries above screen and Navigator lifetimes.
///
/// A screen may detach its callbacks when disposed, but this owner keeps the
/// coordinator, socket, and process-local recovery authority alive until the
/// whole application is disposed. A changed connection configuration receives
/// a distinct scope without retaining plaintext credentials in the key.
class GatewayTurnApplicationController {
  /// Legacy embedders without an injected root still get a process owner,
  /// never a socket whose lifetime is tied to a ChatScreen route.
  static final standalone = GatewayTurnApplicationController();
  final GatewayTurnApplicationSessionFactory _sessionFactory;
  final OperationalActivityStore _activityStore;
  final Map<String, GatewayTurnApplicationSession> _sessions = {};
  final Map<String, Object?> _sessionMutations = {};
  final Map<String, NormalGatewayApplicationSession> _normalSessions = {};
  final Map<String, String> _normalScopeByConnection = {};
  final Map<String, ChatPresentationRegistry> _presentations = {};
  final Map<String, String> _presentationScopes = {};
  bool _background = false;
  bool _backgroundWorkEnabled = true;
  final Map<Object, void Function()> _activityListeners = {};
  final Set<GatewayTurnApplicationSession> _forwardedSessions = {};
  final Set<Object> _legacyTurns = {};
  bool _closed = false;

  GatewayTurnApplicationController({
    GatewayTurnApplicationSessionFactory? sessionFactory,
    GatewayTurnJournalFactory? journalFactory,
    OperationalActivityStore? activityStore,
  }) : _activityStore = activityStore ?? OperationalActivityStore(),
       _sessionFactory =
           sessionFactory ??
           ((connection) => _CoordinatorGatewayTurnApplicationSession(
             DesktopGatewayClient.fromConnection(connection),
             journal: journalFactory?.call(),
           ));

  GatewayTurnApplicationSession sessionFor(SavedConnection connection) {
    if (_closed) throw StateError('Gateway turn application owner is closed.');
    final key = _connectionScopeKey(connection);
    if (_sessionMutations.containsKey(key) &&
        !ConnectionMutationBarrier.isCurrent(
          connection.id,
          _sessionMutations[key],
        )) {
      final previous = _sessions.remove(key);
      if (previous != null) {
        _forwardedSessions.remove(previous);
        unawaited(previous.close());
      }
    }
    _sessionMutations[key] = ConnectionMutationBarrier.capture(connection.id);
    final session = _sessions.putIfAbsent(
      key,
      () => _sessionFactory(connection),
    );
    if (_activityListeners.isNotEmpty) {
      _forwardActivityFrom(session);
    }
    return session;
  }

  ChatPresentationRegistry presentationFor(SavedConnection connection) {
    if (_closed) throw StateError('Gateway turn application owner is closed.');
    final key = _connectionScopeKey(connection);
    final previous = _presentationScopes[connection.id];
    if (previous != null && previous != key) {
      _presentations.remove(previous)?.close();
    }
    _presentationScopes[connection.id] = key;
    return _presentations.putIfAbsent(
      key,
      () => ChatPresentationRegistry(connection.id),
    );
  }

  /// Stock and recovery-v2 lifetimes are separate; existing v2 callers keep
  /// their contract while normal chats retain their socket above Navigator.
  NormalGatewayApplicationSession normalSessionFor(
    SavedConnection connection, {
    NormalGatewayPromptSubmit? submit,
    NormalGatewaySteer? steer,
    NormalGatewayResume? resume,
    NormalGatewayHistory? history,
    TurnNotificationService? notifications,
  }) {
    if (_closed) throw StateError('Gateway turn application owner is closed.');
    final key = _connectionScopeKey(connection);
    final old = _normalScopeByConnection[connection.id];
    if (old != null &&
        (old != key || _normalSessions[old]?.hasCurrentAccount == false)) {
      final previous = _normalSessions.remove(old);
      if (previous != null) unawaited(previous.close());
      _notifyActivityListeners();
    }
    _normalScopeByConnection[connection.id] = key;
    return _normalSessions.putIfAbsent(key, () {
      final session = submit == null
          ? NormalGatewayApplicationSession.fromConnection(
              connection,
              scope: key,
              presentation: presentationFor(connection),
              activityStore: _activityStore,
              onActivityChanged: _notifyActivityListeners,
            )
          : NormalGatewayApplicationSession(
              connection: connection,
              scope: key,
              presentation: presentationFor(connection),
              activityStore: _activityStore,
              submit: submit,
              steer: steer,
              resume:
                  resume ??
                  ({required localSessionId, required storedSessionId}) async {
                    throw StateError('Test gateway is disconnected.');
                  },
              history: history ?? (id) async => [],
              notifications: notifications,
              onActivityChanged: _notifyActivityListeners,
            );
      session.setLifecycle(
        background: _background,
        backgroundWorkEnabled: _backgroundWorkEnabled,
      );
      return session;
    });
  }

  Iterable<NormalGatewayChatActivity> get activeChatActivities =>
      _normalSessions.values.expand((session) => session.activeChatActivities);

  /// Uses exactly the owner's credential-inclusive configuration scope, but
  /// does not create sockets, recovery coordinators or normal chat owners.
  Future<List<OperationalActivityRecord>> readActivityRecords(
    SavedConnection connection, {
    Map<String, String> sessionRoots = const {},
  }) => _activityStore.load(
    _connectionScopeKey(connection),
    sessionRoots: sessionRoots,
  );

  void setLifecycle({required bool background, bool? backgroundWorkEnabled}) {
    _background = background;
    if (backgroundWorkEnabled != null) {
      _backgroundWorkEnabled = backgroundWorkEnabled;
    }
    for (final session in _normalSessions.values) {
      session.setLifecycle(
        background: background,
        backgroundWorkEnabled: _backgroundWorkEnabled,
      );
    }
  }

  void revokeConnection(String connectionId) {
    _presentations.remove(_presentationScopes.remove(connectionId))?.close();
    final scope = _normalScopeByConnection.remove(connectionId);
    final session = _normalSessions.remove(scope);
    if (session != null) unawaited(session.close());
    _notifyActivityListeners();
  }

  void retainConnections(Set<String> connectionIds) {
    for (final id in _presentationScopes.keys.toList(growable: false)) {
      if (!connectionIds.contains(id)) revokeConnection(id);
    }
    for (final id in _normalScopeByConnection.keys.toList(growable: false)) {
      if (!connectionIds.contains(id)) revokeConnection(id);
    }
  }

  /// True while any retained session has an unresolved turn OR a legacy
  /// (stock-gateway) send is in flight. The app-root keep-alive policy
  /// uses this to bound the foreground service to user-visible work
  /// instead of merely-live sockets.
  bool get hasActiveTurn =>
      _legacyTurns.isNotEmpty ||
      _sessions.values.any((s) => s.hasActiveTurn) ||
      _normalSessions.values.any((s) => s.hasActiveTurn);

  /// Registers a legacy (stock-gateway) send as an app-wide active turn.
  /// Stock gateways — and every stored chat on any gateway — submit
  /// through `_sendDesktopGatewayMessage` and never enter the recovery-v2
  /// coordinator, so without this slot the keep-alive would be a no-op on
  /// exactly the transport the app ships against. Returns an opaque token
  /// for [endLegacyTurn]; after [close] it returns an inert token.
  Object beginLegacyTurn() {
    final token = Object();
    if (_closed) return token;
    _legacyTurns.add(token);
    _notifyActivityListeners();
    return token;
  }

  /// Releases a token from [beginLegacyTurn]. Unknown tokens and tokens
  /// ended twice are no-ops — a settle racing app shutdown must never
  /// throw from a `finally`.
  void endLegacyTurn(Object token) {
    if (!_legacyTurns.remove(token)) return;
    _notifyActivityListeners();
  }

  /// Registers an app-level observer notified when [hasActiveTurn] may have
  /// changed, across every session — including sessions created later.
  Object addTurnActivityListener(void Function() listener) {
    if (_closed) throw StateError('Gateway turn application owner is closed.');
    final token = Object();
    _activityListeners[token] = listener;
    for (final session in _sessions.values) {
      _forwardActivityFrom(session);
    }
    return token;
  }

  void removeTurnActivityListener(Object token) {
    _activityListeners.remove(token);
  }

  /// Each session gets exactly one forwarding registration, ever; the
  /// session set makes repeat calls idempotent. The forwarder outlives
  /// app-level listener removal by design — it fires into an empty
  /// listener map, which is cheap — so re-adding a listener never
  /// double-registers a session.
  void _forwardActivityFrom(GatewayTurnApplicationSession session) {
    if (_forwardedSessions.contains(session)) return;
    _forwardedSessions.add(session);
    session.addTurnActivityListener(_notifyActivityListeners);
  }

  void _notifyActivityListeners() {
    for (final listener in _activityListeners.values.toList(growable: false)) {
      listener();
    }
  }

  int get retainedSessionCount => _sessions.length;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final hadTrackedTurns = hasActiveTurn;
    for (final presentation in _presentations.values) {
      presentation.close();
    }
    _presentations.clear();
    _presentationScopes.clear();
    final sessions = _sessions.values.toList(growable: false);
    final normalSessions = _normalSessions.values.toList(growable: false);
    _normalSessions.clear();
    _normalScopeByConnection.clear();
    _legacyTurns.clear();
    _sessions.clear();
    _sessionMutations.clear();
    // Listeners must observe the true→false flip even when both a legacy
    // send and a retained recovery session were active at shutdown.
    if (hadTrackedTurns) _notifyActivityListeners();
    Object? firstError;
    StackTrace? firstStack;
    for (final session in normalSessions) {
      await session.close();
    }
    for (final session in sessions) {
      try {
        await session.close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}

class _CoordinatorGatewayTurnApplicationSession
    implements GatewayTurnApplicationSession, GuardedGatewayTurnSubmission {
  final DesktopGatewayClient _client;
  final Map<String, _ApplicationAsyncEventRegistration> _asyncEventListeners =
      {};
  late final GatewayTurnCoordinatorRegistry _registry;
  bool _closed = false;

  _CoordinatorGatewayTurnApplicationSession(
    this._client, {
    GatewayTurnJournal? journal,
  }) {
    _registry = _client.enableTurnRecoveryCoordinator(journal: journal);
  }

  void _syncAsyncEventDispatcher() {
    if (_asyncEventListeners.isEmpty) {
      _client.setAsyncEventListener(null);
      return;
    }
    _client.setAsyncEventListener((localSessionId, event) {
      _asyncEventListeners[localSessionId]?.listener.call(
        localSessionId,
        event,
      );
    }, acceptsSession: _asyncEventListeners.containsKey);
  }

  void _requireOpen() {
    if (_closed) {
      throw StateError('Gateway turn application session is closed.');
    }
  }

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) {
    _requireOpen();
    final token = Object();
    _asyncEventListeners[localSessionId] = _ApplicationAsyncEventRegistration(
      token,
      listener,
    );
    _syncAsyncEventDispatcher();
    _client.replayServerRequestsForSession(localSessionId);
    return token;
  }

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {
    // close() synchronously clears this owner's registrations/dispatcher.
    // A retained route may detach later, including during registry shutdown.
    // Cleanup is not admission and must not touch a replacement's requests.
    if (_closed) return;
    final current = _asyncEventListeners[localSessionId];
    if (current == null || !identical(current.token, registration)) return;
    _asyncEventListeners.remove(localSessionId);
    _client.rejectServerRequestsForSession(localSessionId);
    _syncAsyncEventDispatcher();
  }

  @override
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) {
    _requireOpen();
    return _registry.setTurnSettledListener(localSessionId, listener);
  }

  @override
  bool get hasActiveTurn => _registry.hasActiveTurn;

  @override
  Object addTurnActivityListener(void Function() listener) {
    _requireOpen();
    return _registry.addTurnActivityListener(listener);
  }

  @override
  void removeTurnActivityListener(Object token) {
    _registry.removeTurnActivityListener(token);
  }

  @override
  void removeTurnSettledListener(String localSessionId, Object registration) {
    if (_closed) return;
    _registry.removeTurnSettledListener(localSessionId, registration);
  }

  @override
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) {
    _requireOpen();
    return _client.ownsApprovalRequest(sessionId, requestId: requestId);
  }

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async {
    _requireOpen();
    if (requestId == null ||
        !_client.ownsServerRequest(requestId, 'approval')) {
      return false;
    }
    await _client.respondToApproval(
      sessionId: sessionId,
      choice: choice,
      serverRequestId: requestId,
    );
    return true;
  }

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    _requireOpen();
    if (!_client.ownsServerRequest(requestId, 'clarify')) return false;
    await _client.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
    return true;
  }

  @override
  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  }) async {
    _requireOpen();
    if (!_client.ownsServerRequest(requestId, 'sudo')) return false;
    await _client.respondToSudo(requestId: requestId, password: password);
    return true;
  }

  @override
  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  }) async {
    _requireOpen();
    if (!_client.ownsServerRequest(requestId, 'secret')) return false;
    await _client.respondToSecret(requestId: requestId, value: value);
    return true;
  }

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) {
    _requireOpen();
    return _registry.stageAttachment(
      localSessionId: localSessionId,
      clientAttachmentId: clientAttachmentId,
      name: name,
      dataUrl: dataUrl,
      byteLength: byteLength,
      mediaType: mediaType,
      kind: kind,
    );
  }

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) {
    _requireOpen();
    return _registry.detachAttachments(
      localSessionId: localSessionId,
      attachments: attachments,
    );
  }

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.submit(
      localSessionId: localSessionId,
      text: text,
      attachments: attachments,
      onState: onState,
    );
  }

  @override
  Future<GatewayTurnRecoveryState> submitGuarded({
    required String localSessionId,
    required String text,
    required bool Function() maySubmit,
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.submit(
      localSessionId: localSessionId,
      text: text,
      maySubmit: maySubmit,
      onState: onState,
    );
  }

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.recoverPending(localSessionId, onState: onState);
  }

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) {
    _requireOpen();
    return _registry.interrupt(
      localSessionId: localSessionId,
      clientTurnId: clientTurnId,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _asyncEventListeners.clear();
    _client.setAsyncEventListener(null);
    try {
      await _registry.closeAll();
    } finally {
      _client.close();
    }
  }

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) {
    _requireOpen();
    return _registry.setSessionBoundListener(localSessionId, listener);
  }

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {
    if (_closed) return;
    _registry.removeSessionBoundListener(localSessionId, registration);
  }
}

class _ApplicationAsyncEventRegistration {
  final Object token;
  final DesktopAsyncEventCallback listener;

  const _ApplicationAsyncEventRegistration(this.token, this.listener);
}

String _connectionScopeKey(SavedConnection connection) {
  final certificate = connection.clientCertificate;
  final credentialDigest = sha256
      .convert(
        utf8.encode(
          // Preserve existing non-mTLS receipt namespaces across this upgrade.
          certificate == null
              ? '${connection.apiKey}\u0000${connection.dashboardPassword ?? ''}'
              : jsonEncode([
                  connection.apiKey,
                  connection.dashboardPassword,
                  certificate.privateKeyPassword,
                ]),
        ),
      )
      .toString();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'id': connection.id,
            'host': connection.host,
            'port': connection.port,
            'https': connection.useHttps,
            'gateway_prefix': connection.gatewayPrefix,
            'profile': connection.gatewayProfile,
            'desktop_gateway_url': connection.desktopGatewayUrl,
            'dashboard_username': connection.dashboardUsername,
            'dashboard_prefix': connection.dashboardPrefix,
            'dashboard_port': connection.dashboardPort,
            'dashboard_proxied': connection.dashboardProxied,
            if (certificate != null) 'client_certificate': certificate.toJson(),
            'credential_digest': credentialDigest,
          }),
        ),
      )
      .toString();
}
