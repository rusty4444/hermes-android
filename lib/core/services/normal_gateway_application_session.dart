import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import '../models/chat_message_time.dart';

import '../models/chat_timeline.dart';
import '../models/received_scope_outcome.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';
import '../models/normal_gateway_persisted_turn.dart';
import '../utils/chat_conversation_projection.dart';
import '../utils/android_prompt_context.dart';
import '../utils/generated_media.dart';
import '../utils/message_content.dart';
import 'connection_manager.dart';
import 'composer_draft_store.dart';
import 'chat_history_window.dart';
import 'chat_presentation_state.dart';
import 'desktop_gateway_client.dart';
import 'normal_gateway_pending_store.dart';
import 'operational_activity_store.dart';
import 'notification_prefs.dart';
import 'turn_notification_service.dart';
import 'notification_approval_authority.dart';
import 'connection_mutation_barrier.dart';
import 'ws_client.dart';

typedef NormalGatewayPromptSubmit =
    Future<void> Function({
      required String sessionId,
      required String text,
      required StreamCallback onEvent,
      required void Function() onSent,
    });
typedef NormalGatewayResume =
    Future<ResumedGatewaySession> Function({
      required String localSessionId,
      required String storedSessionId,
    });
typedef NormalGatewayHistory =
    Future<List<Map<String, dynamic>>> Function(String id);
typedef NormalGatewaySteer =
    Future<bool> Function({required String sessionId, required String text});

enum NormalGatewayTurnPhase {
  idle,
  preparing,
  submitting,
  running,
  reconciling,
  reconciledUnknown,
  completed,
  failed,
}

/// Plain metadata consumed by the application root, never a widget or callback.
class NormalGatewayChatActivity {
  final String connectionId;
  final String localSessionId;
  final String? storedSessionId;
  final String title;
  final String turnId;
  final String status;
  const NormalGatewayChatActivity({
    required this.connectionId,
    required this.localSessionId,
    required this.storedSessionId,
    required this.title,
    required this.turnId,
    required this.status,
  });
}

/// Exact admitted operation outcome and live public final, never a history row.
class NormalGatewayTurnTerminal {
  const NormalGatewayTurnTerminal({
    required this.turnId,
    required this.completed,
    required this.publicFinalText,
  });
  final String turnId;
  final bool? completed;
  final String? publicFinalText;
}

/// Durable history and transient presentation are deliberately separate. Never
/// write displayRows into the history window: they have no durable row identity.
class NormalGatewayChatSnapshot {
  final String? turnId;
  final NormalGatewayTurnTerminal? terminal;
  final String? storedSessionId;
  final NormalGatewayTurnPhase phase;
  final bool wireEmitted;
  final bool steering;
  final int? rowFloor;
  final List<Map<String, dynamic>> displayRows;
  final List<Map<String, dynamic>> historyRows;

  /// Bounded raw canonical context for presentation, including receipt handoffs.
  /// Never latest/admission authority, receipt confirmation, or a paging cursor.
  final List<Map<String, dynamic>> historyPresentationRows;

  final List<GatewayToolActivity> tools;
  final List<GatewaySubagentActivity> subagents;
  final List<StreamEvent> pendingInput;
  final List<StreamEvent> inputUpdates;
  final List<StreamEvent> auxiliaryEvents;
  final GatewayTurnStatus? status;
  final String? error;

  /// Presentation revocation precedes durable permission to release admission.
  final String? responseFailure;
  final String? rejectedDraft;
  final DesktopConnectionState connectionState;
  final ChatTimeline timeline;
  final List<ReceivedScopeOutcome> receivedOutcomes;
  const NormalGatewayChatSnapshot({
    required this.turnId,
    this.terminal,
    required this.storedSessionId,
    required this.phase,
    required this.wireEmitted,
    this.steering = false,
    required this.rowFloor,
    required this.displayRows,
    required this.historyRows,
    this.historyPresentationRows = const [],
    required this.tools,
    required this.subagents,
    required this.pendingInput,
    required this.inputUpdates,
    required this.auxiliaryEvents,
    required this.status,
    required this.error,
    this.responseFailure,
    required this.rejectedDraft,
    required this.connectionState,
    this.timeline = const ChatTimeline(),
    this.receivedOutcomes = const [],
  });
  bool get hasActiveTurn => const {
    NormalGatewayTurnPhase.preparing,
    NormalGatewayTurnPhase.submitting,
    NormalGatewayTurnPhase.running,
    NormalGatewayTurnPhase.reconciling,
  }.contains(phase);
  bool get reconciling => phase == NormalGatewayTurnPhase.reconciling;
}

/// One stock client and independent history client per configuration scope.
/// Routes only subscribe; this object owns ingress, recovery and notifications.
class NormalGatewayApplicationSession {
  static const activityHeartbeatInterval = Duration(seconds: 30);
  static const activityRetryInterval = Duration(seconds: 30);
  final SavedConnection connection;
  final Map<String, String> _approvalOrigin;
  final Object? _accountMutation;
  final String scope;
  final DesktopGatewayClient? client;
  final ApiClient? _historyClient;
  final NormalGatewayPendingStore pendingStore;
  final OperationalActivityStore activityStore;
  final int Function() _activityNowEpochMs;
  final NormalGatewayPromptSubmit _submit;
  final NormalGatewaySteer? _steer;
  final bool _usesClientSubmit;
  final NormalGatewayResume _resume;
  final NormalGatewayHistory _history;
  final TurnNotificationService notifications;
  final void Function()? onActivityChanged;
  final ChatPresentationRegistry? presentation;
  final Map<String, NormalGatewayChatOwner> _aliases = {};
  final Map<String, NormalGatewayPendingMarker> _retiringMarkers = {};
  Timer? _retirementTimer;
  bool _retiring = false;
  int _retirementRetry = 0;
  late final Future<void> ready;
  bool _initialized = false;
  int _historyObservation = 0;
  int _childObservation = 0;
  int _presentationObservation = 0;
  bool _closed = false;
  bool _background = false;
  bool _backgroundWorkEnabled = true;
  Future<void>? _activityWrite;
  final Map<String, _PendingActivityWrite> _pendingActivity = {};
  DesktopConnectionState _connectionState = DesktopConnectionState.disconnected;

  NormalGatewayApplicationSession({
    required this.connection,
    required this.scope,
    DesktopGatewayClient? client,
    ApiClient? historyClient,
    NormalGatewayPendingStore? pendingStore,
    OperationalActivityStore? activityStore,
    int Function()? activityNowEpochMs,
    NormalGatewayPromptSubmit? submit,
    NormalGatewaySteer? steer,
    NormalGatewayResume? resume,
    NormalGatewayHistory? history,
    TurnNotificationService? notifications,
    this.onActivityChanged,
    this.presentation,
  }) : client = client,
       _approvalOrigin = NotificationApprovalAuthority.origin(connection),
       _accountMutation = ConnectionMutationBarrier.capture(connection.id),
       _historyClient = historyClient,
       pendingStore = pendingStore ?? NormalGatewayPendingStore(),
       activityStore = activityStore ?? OperationalActivityStore(),
       _activityNowEpochMs =
           activityNowEpochMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       notifications = notifications ?? TurnNotificationService.shared,
       _submit = submit ?? client!.submitPrompt,
       _steer = steer ?? client?.steerPrompt,
       _usesClientSubmit = submit == null,
       _resume = resume ?? client!.resumeSubmittedSession,
       _history =
           history ??
           ((id) => historyClient!.getMessages(id, limit: 50, latest: true)) {
    client?.setSessionBoundListener(
      (local, stored) {
        final owner = _aliases[local];
        if (owner != null) _bind(owner, stored);
      },
      onCreated: (local, stored) {
        final owner = _aliases[local];
        if (!_closed && owner != null && !owner.wireEmitted) {
          owner._createdEmptySessionId = stored;
        }
      },
    );
    client?.setSessionEventListener(receiveEvent);
    client?.setAsyncEventListener((local, event) {
      // Raw stream frames have a separate, single ingress. This path carries
      // only socket-owned requests (including transformed identities). Resume
      // state is reduced after its await/generation check, never via a stale
      // synthetic terminal side-channel.
      if (_interactive(event.type)) {
        receiveEvent(local, event);
      }
    }, acceptsSession: _aliases.containsKey);
    client?.setConnectionListener(connectionChanged);
    ready = _restore();
    ready.ignore();
    unawaited(this.notifications.ensureInitialized());
  }

  factory NormalGatewayApplicationSession.fromConnection(
    SavedConnection connection, {
    required String scope,
    ChatPresentationRegistry? presentation,
    OperationalActivityStore? activityStore,
    void Function()? onActivityChanged,
  }) {
    return NormalGatewayApplicationSession(
      connection: connection,
      scope: scope,
      presentation: presentation,
      activityStore: activityStore,
      client: DesktopGatewayClient.fromConnection(connection),
      historyClient: ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: connection.apiKey,
        pathPrefix: connection.gatewayPrefix ?? '',
        clientCertificate: connection.clientCertificate,
      ),
      onActivityChanged: onActivityChanged,
    );
  }

  Iterable<NormalGatewayChatOwner> get chats => _aliases.values.toSet();
  bool get hasActiveTurn =>
      !_closed && chats.any((chat) => chat.snapshot.hasActiveTurn);
  Iterable<NormalGatewayChatActivity> get activeChatActivities => chats
      .where((chat) => chat.snapshot.hasActiveTurn && chat.turnId != null)
      .map(
        (chat) => NormalGatewayChatActivity(
          connectionId: connection.id,
          localSessionId: chat.localSessionId,
          storedSessionId: chat.storedSessionId,
          title: chat.title,
          turnId: chat.turnId!,
          status: chat.phase.name,
        ),
      );
  NormalGatewayChatOwner? findChat(String id) => _aliases[id];

  NormalGatewayChatOwner chatFor(
    String localSessionId, {
    String? storedSessionId,
    String? lineageRootId,
    required String title,
    String? workingDirectory,
  }) {
    if (_closed) {
      throw StateError('Normal gateway application session is closed.');
    }
    var owner =
        _aliases[localSessionId] ??
        _aliases[storedSessionId] ??
        NormalGatewayChatOwner._(this, localSessionId, title, workingDirectory);
    _aliases[localSessionId] = owner;
    owner.title = title;
    owner._lineageRootId = lineageRootId ?? owner._lineageRootId;
    if (storedSessionId != null) {
      owner = _bind(owner, storedSessionId, localAlias: localSessionId);
    }
    if (owner.storedSessionId != null) {
      client?.bindStoredSession(localSessionId, owner.storedSessionId!);
    }
    return owner;
  }

  NormalGatewayChatOwner _bind(
    NormalGatewayChatOwner owner,
    String stored, {
    String? localAlias,
  }) {
    owner = owner._root;
    if (_closed) return owner;
    final other = _aliases[stored];
    final coalescing = other != null && !identical(other, owner);
    if (coalescing) {
      owner = _coalesce(owner, other, stored);
    }
    final changed = owner.storedSessionId != stored || !identical(other, owner);
    owner.storedSessionId = stored;
    _aliases[stored] = owner;
    unawaited(
      ComposerDraftStore.bind(
        connectionId: connection.id,
        localSessionId: owner.localSessionId,
        storedSessionId: stored,
      ),
    );
    // Restoration can race a route opened directly through the stored id. In
    // that case the retained owner's primary id is already canonical, but the
    // receipt's original local id still owns the pre-existing composer bucket.
    if (localAlias != null && localAlias != owner.localSessionId) {
      unawaited(
        ComposerDraftStore.bind(
          connectionId: connection.id,
          localSessionId: localAlias,
          storedSessionId: stored,
        ),
      );
    }
    client?.bindStoredSession(owner.localSessionId, stored);
    // A canonical route may have created this owner before receipt hydration.
    // Its immutable localSessionId is then canonical, not the receipt's alias.
    presentation?.bind(localAlias ?? owner.localSessionId, stored);
    // A notification route can attach to this same owner while its previous
    // ChatScreen remains mounted. An unchanged binding is not a state change,
    // and synchronous fan-out here would dirty that sibling during its build.
    if (changed && !coalescing) owner._notify();
    return owner;
  }

  NormalGatewayChatOwner _coalesce(
    NormalGatewayChatOwner source,
    NormalGatewayChatOwner canonical,
    String stored,
  ) {
    // A published stored id can be opened before its original create reply.
    // Preserve the ongoing operation, never combine two turn generations.
    final sourceOnWire = source.wireEmitted && source.snapshot.hasActiveTurn;
    final canonicalOnWire =
        canonical.wireEmitted && canonical.snapshot.hasActiveTurn;
    if (sourceOnWire && canonicalOnWire) {
      throw StateError('Cannot combine independently emitted gateway turns.');
    }
    final winner = sourceOnWire || !canonical.snapshot.hasActiveTurn
        ? source
        : canonical;
    final loser = identical(winner, source) ? canonical : source;
    // Merge presentation first: a rejected old prompt cannot borrow a newer
    // canonical composer's authority during its rejection callback.
    presentation?.bind(source.localSessionId, stored);
    final retiredListeners = loser._listeners.entries.toList(growable: false);
    winner._adoptSettledPresentation(loser);
    final rejection = loser._rejectForHandoff();
    winner._adoptPreWireHistory(loser, stored);
    winner._adoptChildObservers(loser);
    winner._lineageRootId ??= loser._lineageRootId;
    // Ownership transferred, not copied into a second retained body owner.
    // External immutable snapshots may still exist; these losing buffers no
    // longer own presentation and must not survive a later terminal close.
    loser._display.clear();
    loser._priorDisplay.clear();
    loser._timeline = loser._timeline.clear();
    loser._tools.clear();
    loser._subagents.clear();
    loser._observedSubagents.clear();
    loser._historyConfirmationRows = [];
    loser._historyPresentation.clear();
    loser._historyPresentationObservation = 0;
    final settledIds = {
      ...loser._settledWireTurnIds,
      ...winner._settledWireTurnIds,
    };
    winner._settledWireTurnIds
      ..clear()
      ..addAll(settledIds);
    while (winner._settledWireTurnIds.length > 32) {
      winner._settledWireTurnIds.remove(winner._settledWireTurnIds.first);
    }
    // Empty-create proof belongs to the original admission only. In
    // particular it cannot seed an already-active canonical unknown floor.
    if (!identical(winner, source) || canonical.turnId != null) {
      winner._createdEmptySessionId = null;
    }
    winner._listeners.addAll(loser._listeners);
    loser._listeners.clear();
    loser._redirect = winner;
    for (final alias in _aliases.keys.toList()) {
      if (identical(_aliases[alias], loser)) _aliases[alias] = winner;
    }
    client?.bindStoredSession(loser._localSessionId, stored);
    // Publish the complete transition before any callback can reenter reserve
    // or chatFor. Only the retiring route sees its immutable pre-wire rejection;
    // every retained subscriber then observes the single winning operation.
    final generation = winner._generation;
    scheduleMicrotask(() {
      if (_closed) return;
      if (rejection != null && winner._current(generation)) {
        final revision = winner._notificationRevision;
        for (final entry in retiredListeners) {
          if (!winner._current(generation) ||
              winner._notificationRevision != revision) {
            return;
          }
          if (identical(winner._listeners[entry.key], entry.value)) {
            entry.value(rejection);
          }
        }
      }
      winner._root._notify();
    });
    return winner;
  }

  Future<void> _restore() async {
    var loaded = false;
    try {
      final markers = await pendingStore.load(scope);
      if (_closed) return;
      // Prefer an emitted receipt for display identity, but retain every
      // unresolved WAL. A failed retirement followed by a crash cannot prove
      // that its write-ahead receipt never reached the wire.
      markers.sort((a, b) {
        final emitted = (b.phase == 'emitted' ? 1 : 0).compareTo(
          a.phase == 'emitted' ? 1 : 0,
        );
        if (emitted != 0) return emitted;
        final created = b.createdAt.compareTo(a.createdAt);
        return created != 0 ? created : a.key.compareTo(b.key);
      });
      for (final marker in markers) {
        final chat = chatFor(
          marker.localSessionId,
          storedSessionId: marker.storedSessionId,
          title: 'Chat',
        );
        chat._restore(marker);
      }
      loaded = true;
    } finally {
      _initialized = loaded;
      if (!_closed) {
        for (final chat in chats) {
          chat._notify();
          chat.requestRecovery();
        }
      }
    }
  }

  void receiveEvent(String localSessionId, StreamEvent event) {
    if (!_closed) _aliases[localSessionId]?._event(event);
  }

  void connectionChanged(DesktopConnectionState state) {
    if (_closed) return;
    final changed = _connectionState != state;
    _connectionState = state;
    if (state == DesktopConnectionState.connected) _retryRetirements();
    for (final chat in chats) {
      if (state != DesktopConnectionState.connected) {
        chat._pendingInput.clear(); // exact socket identity is no longer valid
        if (chat.wireEmitted && chat.snapshot.hasActiveTurn) {
          chat.phase = NormalGatewayTurnPhase.reconciling;
        }
      }
      chat._notify();
      if (state == DesktopConnectionState.connected && changed) {
        chat._retry = 0;
        chat.requestRecovery();
      }
    }
  }

  void setLifecycle({required bool background, bool? backgroundWorkEnabled}) {
    _background = background;
    if (backgroundWorkEnabled != null) {
      _backgroundWorkEnabled = backgroundWorkEnabled;
    }
    client?.setReconnectAllowed(_canRecover);
    if (_canRecover) {
      _retryRetirements();
    } else {
      _retirementTimer?.cancel();
      _retirementTimer = null;
    }
    for (final chat in chats) {
      if (_canRecover) {
        chat.requestRecovery();
      } else {
        chat._retryTimer?.cancel();
        chat._retryTimer = null;
      }
    }
  }

  bool get _canRecover => !_closed && (!_background || _backgroundWorkEnabled);

  void _retirePreWireMarker(NormalGatewayPendingMarker marker) {
    _retiringMarkers[marker.key] = marker;
    _retryRetirements();
  }

  void _retryRetirements() {
    if (!_canRecover || _retiring || _retiringMarkers.isEmpty) return;
    _retirementTimer?.cancel();
    _retirementTimer = null;
    unawaited(_drainRetirements());
  }

  Future<void> _drainRetirements() async {
    _retiring = true;
    try {
      for (final marker in _retiringMarkers.values.toList()) {
        if (_closed) return;
        try {
          await pendingStore.put(marker.withPhase('settled'));
          if (_closed) return;
          await pendingStore.remove(marker);
          _retiringMarkers.remove(marker.key);
        } catch (_) {
          // Keep cleanup ownership after failed writes and lost ACKs. Only
          // known unsent receipts enter this queue, never uncertain wire WALs.
        }
      }
    } finally {
      _retiring = false;
      if (_retiringMarkers.isEmpty) _retirementRetry = 0;
      if (_canRecover && _retiringMarkers.isNotEmpty) {
        final shift = (_retirementRetry++).clamp(0, 6);
        _retirementTimer = Timer(
          Duration(milliseconds: (500 * (1 << shift)).clamp(500, 30000)),
          _retryRetirements,
        );
      }
    }
  }

  void _recordActivity(OperationalActivityRecord record) {
    if (_closed) return;
    _pendingActivity[record.key] = _PendingActivityWrite(record);
    // Retain repair ownership by turn, not by the chat's latest turn. Include
    // in-flight records too: their write may fail after this batch is accepted.
    // The store serializes both snapshots, so an old completion cannot win.
    _writeActivity(_pendingActivity.values.toList(growable: false));
  }

  void _retryActivity() {
    if (_closed) return;
    final now = _activityNowEpochMs();
    final retry = _pendingActivity.values
        .where((pending) {
          final notBefore = pending.retryNotBeforeEpochMs;
          return pending.flights == 0 &&
              (notBefore == null || now >= notBefore);
        })
        .toList(growable: false);
    if (retry.isEmpty) return;
    for (final pending in retry) {
      // Permit one immediate repair probe, then back off independently of
      // token delivery and failed-write completion. No timer or retry spin:
      // later real progress can probe again, and a new accepted observation
      // always carries older dirty turns along in its single physical write.
      pending.retryNotBeforeEpochMs =
          now + activityRetryInterval.inMilliseconds;
    }
    _writeActivity(retry);
  }

  void _writeActivity(List<_PendingActivityWrite> accepted) {
    for (final pending in accepted) {
      pending.flights++;
    }
    final records = accepted.map((pending) => pending.record).toList();
    // Single observations retain the put contract; multi-turn repairs share
    // a read/modify/write and failure reload instead of multiplying disk I/O.
    final flight = records.length == 1
        ? activityStore.put(records.single)
        : activityStore.putAll(records);
    final write = flight
        .then<void>(
          (_) {
            for (final pending in accepted) {
              if (identical(_pendingActivity[pending.record.key], pending)) {
                _pendingActivity.remove(pending.record.key);
              }
            }
          },
          onError: (Object _, StackTrace _) {
            // Optional presentation metadata must never change turn authority.
            // Keep the exact failed observation (including its original time).
          },
        )
        .whenComplete(() {
          for (final pending in accepted) {
            pending.flights--;
          }
        });
    _activityWrite = write;
    write.whenComplete(() {
      if (identical(_activityWrite, write)) _activityWrite = null;
    }).ignore();
  }

  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) {
    final chat = _aliases[sessionId];
    return chat != null &&
        (client?.ownsApprovalRequest(
              chat.localSessionId,
              requestId: requestId,
            ) ??
            false);
  }

  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String requestId,
    required String choice,
  }) async {
    final chat = _aliases[sessionId];
    if (_closed ||
        chat == null ||
        !ownsApprovalRequest(sessionId: sessionId, requestId: requestId)) {
      return false;
    }
    final pending = chat._pendingInput[requestId];
    await client!.respondToApproval(
      sessionId: chat.localSessionId,
      choice: choice,
      serverRequestId: requestId,
    );
    if (!_closed && identical(chat._pendingInput[requestId], pending)) {
      chat._pendingInput.remove(requestId);
      chat._notify();
    }
    return true;
  }

  void forgetAnsweredInput(String requestId) {
    for (final chat in chats) {
      if (chat._pendingInput.remove(requestId) != null) chat._notify();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true; // synchronous fence before any resource cleanup
    prunePendingNotificationApprovals();
    _retirementTimer?.cancel();
    _retirementTimer = null;
    for (final chat in chats) {
      chat._close();
    }
    client?.close();
    _historyClient?.close();
    // Closing fences new metadata synchronously, then joins the last accepted
    // write. Its global queue also covers every earlier write from this owner.
    await _activityWrite;
    _pendingActivity.clear();
  }

  bool get isClosed => _closed;
  bool get hasCurrentAccount =>
      !_closed &&
      ConnectionMutationBarrier.isCurrent(connection.id, _accountMutation);
}

class _PendingActivityWrite {
  final OperationalActivityRecord record;
  int flights = 0;
  int? retryNotBeforeEpochMs;

  _PendingActivityWrite(this.record);
}

class NormalGatewayChatOwner {
  final NormalGatewayApplicationSession _session;
  NormalGatewayChatOwner? _redirect;
  NormalGatewayChatOwner get _root => _redirect?._root ?? this;
  final String _localSessionId;
  String get localSessionId => _root._localSessionId;
  String? _storedSessionId;
  String? get storedSessionId => _root._storedSessionId;
  set storedSessionId(String? value) => _root._storedSessionId = value;
  String _title;
  String get title => _root._title;
  set title(String value) => _root._title = value;
  final String? _workingDirectory;
  String? get workingDirectory => _root._workingDirectory;
  NormalGatewayTurnTerminal? _voiceTerminal;
  String? _voicePublicFinal;
  bool _voiceFinalKnown = false;
  bool _voiceCompletionSeen = false;
  String? _turnId;
  String? get turnId => _root._turnId;
  set turnId(String? value) => _root._turnId = value;
  NormalGatewayTurnPhase _phase = NormalGatewayTurnPhase.idle;
  NormalGatewayTurnPhase get phase => _root._phase;
  set phase(NormalGatewayTurnPhase value) => _root._phase = value;
  bool _wireEmitted = false;
  bool get wireEmitted => _root._wireEmitted;
  set wireEmitted(bool value) => _root._wireEmitted = value;
  StateError? _handoffRejection;
  String? _storedLineageRootId;
  String? get _lineageRootId => _root._storedLineageRootId;
  set _lineageRootId(String? value) => _root._storedLineageRootId = value;
  String? _wireTurnId;
  final Set<String> _settledWireTurnIds = {};
  bool _sawResponseActivity = false;
  bool _ownedSuccessfulCompletion = false;
  int? _floor;
  int _generation = 0;
  Object? _reservation;
  NormalGatewayPendingMarker? _marker;
  final Map<String, NormalGatewayPendingMarker> _additionalRestoredMarkers = {};
  final List<Map<String, dynamic>> _display = [];
  final List<Map<String, dynamic>> _priorDisplay = [];
  final List<_SettledGatewayPresentation> _settledPresentation = [];
  final List<ReceivedScopeOutcome> _receivedOutcomes = [];
  final Map<String, _ReceivedTurnPersistence> _persistedTurns = {};
  int? _receivedObservation;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _historyConfirmationRows = [];
  List<_HistoryPresentationRow> _historyPresentation = [];
  int _historyPresentationObservation = 0;
  bool _historyKnown = false;
  int _historyObservation = 0;
  String? _createdEmptySessionId;
  final List<GatewayToolActivity> _tools = [];
  final List<GatewaySubagentActivity> _subagents = [];
  final List<GatewaySubagentActivity> _activityChildren = [];
  bool _hasTurnSubagentPresentation = false;
  // Observer identity outlives parent presentation and its canonical hydration.
  final List<({GatewaySubagentActivity activity, int observation, int? anchor})>
  _observedSubagents = [];
  ChatTimeline _timeline = const ChatTimeline();
  final Map<String, StreamEvent> _pendingInput = {};
  final List<StreamEvent> _inputUpdates = [];
  final List<StreamEvent> _auxiliaryEvents = [];
  final Map<Object, void Function(NormalGatewayChatSnapshot)> _listeners = {};
  int _notificationRevision = 0;
  GatewayTurnStatus? _status;
  String? _error;
  String? _draftToRestore;
  bool _draftRestoreAllowed = false;
  ComposerDraftHandle? _draftHandle;
  Timer? _retryTimer;
  Timer? _baselineTimer;
  Completer<_GatewayHistoryObservation?>? _baselineRead;
  int _retry = 0;
  bool _recovering = false;

  bool _recoveryQueued = false;
  bool _settling = false;
  bool _submissionPending = false;
  Object? _steerFlight;
  ({bool? completed, String? error, int generation})? _terminalReceipt;
  OperationalActivityRecord? _lastActivityRecord;
  NormalGatewayChatOwner._(
    this._session,
    this._localSessionId,
    this._title,
    this._workingDirectory,
  );

  bool get _hasReceivedPresentation =>
      _timeline.runs.isNotEmpty ||
      _tools.isNotEmpty ||
      _hasTurnSubagentPresentation ||
      [..._priorDisplay, ..._display].any(
        (row) =>
            row['role'] == 'assistant' &&
            (row['content']?.toString().isNotEmpty ?? false),
      );

  NormalGatewayChatSnapshot get snapshot => _redirect != null
      ? _root.snapshot
      : NormalGatewayChatSnapshot(
          turnId: turnId,
          storedSessionId: storedSessionId,
          phase: phase,
          wireEmitted: wireEmitted,
          terminal: _voiceTerminal,
          steering: _steerFlight != null,
          rowFloor: _floor,
          displayRows:
              [
                    for (final settled in _settledPresentation) ...settled.rows,
                    ..._priorDisplay,
                    ..._display,
                  ]
                  .map((row) => Map<String, dynamic>.unmodifiable(row))
                  .toList(growable: false),
          historyRows: _history
              .map((row) => Map<String, dynamic>.unmodifiable(row))
              .toList(growable: false),
          historyPresentationRows: List.unmodifiable(
            _historyPresentation.map((entry) => entry.row),
          ),
          tools: List.unmodifiable([
            for (final settled in _settledPresentation) ...settled.tools,
            ..._tools,
          ]),
          subagents: List.unmodifiable(_subagents),
          pendingInput: List.unmodifiable(_pendingInput.values),
          inputUpdates: List.unmodifiable(_inputUpdates),
          auxiliaryEvents: List.unmodifiable(_auxiliaryEvents),
          status: _status,
          error: _error,
          responseFailure: _terminalReceipt?.completed == false
              ? _terminalReceipt!.error ?? 'Gateway turn failed'
              : null,
          rejectedDraft:
              phase == NormalGatewayTurnPhase.failed &&
                  !wireEmitted &&
                  _draftRestoreAllowed
              ? _draftToRestore
              : null,
          connectionState: _session._connectionState,
          timeline: _timeline.precededBy(
            _settledPresentation.map((settled) => settled.timeline),
          ),
          receivedOutcomes: List.unmodifiable([
            for (final settled in _settledPresentation) ...settled.outcomes,
            ..._receivedOutcomes,
          ]),
        );

  void bindStoredSession(String storedSessionId) {
    if (this.storedSessionId != storedSessionId) {
      _session._bind(this, storedSessionId);
    }
  }

  Object subscribe(void Function(NormalGatewayChatSnapshot) listener) {
    if (_redirect != null) return _root.subscribe(listener);
    final token = Object();
    _listeners[token] = listener;
    listener(snapshot); // reattachment is immediate, not a later stream tick
    return token;
  }

  void unsubscribe(Object token) => _root._listeners.remove(token);

  /// The route retains revision authority. Any later edit, including an edit
  /// followed by clearing, permanently relinquishes this restoration receipt.
  void invalidateDraftRecovery() {
    if (_redirect != null) return _root.invalidateDraftRecovery();
    _draftRestoreAllowed = false;
    _draftToRestore = null;
  }

  /// Capture immediately BEFORE the physical offset-zero latest GET. Carry the
  /// same token through success, failure and any multi-page/callback awaits.
  NormalGatewayHistoryRead beginHistoryRead(String stored) =>
      _root._captureHistoryRead(stored, ++_session._historyObservation);

  /// Older paging owns a cursor, not a new latest observation. A newer accepted
  /// success invalidates this fence; merely issuing/failing a read does not.
  NormalGatewayHistoryRead historyReadFence(String stored) =>
      _root._captureHistoryRead(stored, _root._historyObservation);

  NormalGatewayHistoryRead _captureHistoryRead(
    String stored,
    int observation,
  ) => NormalGatewayHistoryRead._(
    this,
    localSessionId,
    storedSessionId,
    stored,
    _generation,
    observation,
  );

  /// Accept only a fresh latest batch, never a retained/older paging window.
  /// Reads during a turn cannot seed its admission baseline or replace it.
  /// Tokenless calls remain a TRUSTED external-observation compatibility seam:
  /// they assert freshness at ingress, not physical request-start freshness.
  /// Production physical readers must supply their pre-I/O [read].
  /// [confirmedRows], when supplied, is raw context fetched under that same
  /// fence (including [rows]), never an accumulated/older paging window. It
  /// confirms receipt coverage only; [rows] alone remains latest authority.
  bool observeHistory(
    List<Map<String, dynamic>> rows, {
    NormalGatewayHistoryRead? read,
    List<Map<String, dynamic>>? confirmedRows,
  }) {
    if (_redirect != null) {
      return _root.observeHistory(
        rows,
        read: read,
        confirmedRows: confirmedRows,
      );
    }
    if (_session._closed || snapshot.hasActiveTurn) return false;
    final captured =
        read ?? beginHistoryRead(storedSessionId ?? localSessionId);
    if (!identical(captured._owner, this) ||
        !_acceptHistory(
          _GatewayHistoryObservation(rows, captured),
          confirmedRows: confirmedRows,
        )) {
      return false;
    }
    _cleanCompletedEmptySubmission(rows);
    _notify();
    return captured.isCurrent;
  }

  Future<_GatewayHistoryObservation> _readLatestHistory(String stored) async {
    final read = beginHistoryRead(stored);
    final rows = await _session._history(stored);
    return _GatewayHistoryObservation(rows, read);
  }

  bool _acceptHistory(
    _GatewayHistoryObservation fresh, {
    List<Map<String, dynamic>>? confirmedRows,
  }) {
    if (!identical(fresh.read._owner, this) || !fresh.read.isCurrent) {
      return false;
    }
    _history = fresh.rows.map((row) => Map<String, dynamic>.from(row)).toList();
    // Optional context is the same fenced physical read's complete raw batch,
    // not a retained paging window or a new latest/admission observation.
    // Latest rows still win if the context repeats an address: a typed older
    // body must never override the latest row's explicit partial/failure veto.
    final latestById = {
      for (final row in _history)
        if (row['id'] is int) row['id']: row,
    };
    _historyConfirmationRows = (confirmedRows ?? fresh.rows)
        .map((row) => Map<String, dynamic>.from(latestById[row['id']] ?? row))
        .toList();
    _historyKnown = true;
    _historyObservation = fresh.observation;
    _retainHistoryPresentation(
      _historyConfirmationRows.map(
        (row) => _HistoryPresentationRow(row, fresh.observation),
      ),
      fresh.observation,
    );
    _reconcilePersistedTurns();
    _boundSettledPresentation();
    return true;
  }

  void _retainHistoryPresentation(
    Iterable<_HistoryPresentationRow> incoming,
    int observation,
  ) {
    final accepted = incoming.toList(growable: false);
    final anonymous = observation >= _historyPresentationObservation
        ? accepted
        : _historyPresentation;
    final byId = <int, _HistoryPresentationRow>{};
    for (final entry in [..._historyPresentation, ...accepted]) {
      final id = entry.row['id'];
      if (id is! int) continue;
      final previous = byId[id];
      // Alias winners need not own the most recent value of every retained row.
      if (previous == null || entry.observation >= previous.observation) {
        byId[id] = entry;
      }
    }
    final ids = byId.keys.toList()..sort();
    final merged = [
      for (final id in ids) byId[id]!,
      // Unaddressed legacy rows cannot be unioned safely across observations.
      for (final entry in anonymous)
        if (entry.row['id'] is! int) entry,
    ];
    // Match the bounded cold/context scan, not an unbounded transcript cache.
    const budget =
        ChatHistoryWindow.pageSize * ChatHistoryWindow.initialPageBudget;
    _historyPresentation = merged.length <= budget
        ? merged
        : merged.sublist(merged.length - budget);
    if (observation > _historyPresentationObservation) {
      _historyPresentationObservation = observation;
    }
  }

  /// An explicit receipt can require context beyond the latest raw page. The
  /// key is only a bounded-fetch hint, never permission to retire presentation.
  String? persistedTurnContextKey(List<Map<String, dynamic>> rows) {
    if (_redirect != null) return _root.persistedTurnContextKey(rows);
    final present = {
      for (final row in rows)
        if (row['id'] is int) row['id'],
    };
    final pending = [
      for (final entry in _persistedTurns.entries)
        if (entry.value.settled &&
            present.contains(entry.value.receipt.finalAssistantRowId) &&
            entry.value.receipt.rowIds.any((id) => !present.contains(id)))
          entry.key,
    ];
    return pending.isEmpty ? null : pending.join(':');
  }

  void _capturePersistedTurn(Map<String, dynamic> data) {
    final id = turnId;
    if (id == null) return;
    // A later invalid completion cannot retain an earlier claim for this turn.
    _persistedTurns.remove(id);
    if (!isSuccessfulResponseReceipt(data)) return;
    final receipt = NormalGatewayPersistedTurn.fromWire(data['persisted_turn']);
    if (receipt == null ||
        _display.where((row) => row['role'] == 'user').length > 1) {
      return;
    }
    final scopes = _display
        .map((row) => row['_normal_projection_id'])
        .whereType<String>()
        .toSet();
    if (scopes.isEmpty || scopes.length != _display.length) return;
    _persistedTurns[id] = _ReceivedTurnPersistence(
      receipt: receipt,
      scopes: scopes,
      tools: _tools,
      afterObservation: _historyObservation,
    );
  }

  void _reconcilePersistedTurns() {
    // Deliver the confirming read's replacement, not a truncated context or an
    // alias's newer row borrowing this owner's older confirmation.
    final presentedIds = {
      for (final entry in _historyPresentation)
        if (entry.row['id'] is int && entry.observation == _historyObservation)
          entry.row['id'],
    };
    final covered = _persistedTurns.entries
        .where(
          (entry) =>
              entry.value.settled &&
              _historyObservation > entry.value.afterObservation &&
              entry.value.receipt.isConfirmedBy(_historyConfirmationRows) &&
              // Bounding context must not retire half of a canonical turn.
              // Presence here protects replacement delivery, never proves it.
              entry.value.receipt.rowIds.every(presentedIds.contains),
        )
        .toList(growable: false);
    if (covered.isEmpty) return;
    final scopes = {for (final entry in covered) ...entry.value.scopes};
    final tools = Set<GatewayToolActivity>.identity();
    for (final entry in covered) {
      tools.addAll(entry.value.tools);
      _persistedTurns.remove(entry.key);
    }
    bool coveredRow(Map<String, dynamic> row) =>
        scopes.contains(row['_normal_projection_id']);
    ChatTimeline withoutCoveredScopes(ChatTimeline timeline) {
      if (!timeline.scopes.any(scopes.contains)) return timeline;
      final retained = timeline.scopes.where(
        (scope) => !scopes.contains(scope),
      );
      return retained.isEmpty
          ? timeline.clear()
          : timeline.retainScopes(retained);
    }

    // One synchronous presentation transition. No listener can see a saved
    // handoff with its old local prompt/reply or a fallback tool left behind.
    _display.removeWhere(coveredRow);
    _priorDisplay.removeWhere(coveredRow);
    _timeline = withoutCoveredScopes(_timeline);
    _tools.removeWhere(tools.contains);
    final outcomes = _uncoveredOutcomes(_receivedOutcomes, scopes);
    _receivedOutcomes
      ..clear()
      ..addAll(outcomes);
    for (var i = _settledPresentation.length - 1; i >= 0; i--) {
      final previous = _settledPresentation[i];
      if (!previous.rows.any(coveredRow) &&
          !previous.timeline.scopes.any(scopes.contains)) {
        continue;
      }
      final rows = previous.rows.where((row) => !coveredRow(row)).toList();
      final timeline = withoutCoveredScopes(previous.timeline);
      final retainedTools = previous.tools
          .where((tool) => !tools.contains(tool))
          .toList();
      if (rows.isEmpty && timeline.runs.isEmpty && retainedTools.isEmpty) {
        _settledPresentation.removeAt(i);
      } else {
        _settledPresentation[i] = _SettledGatewayPresentation(
          observation: previous.observation,
          rows: rows,
          tools: retainedTools,
          timeline: timeline,
          outcomes: _uncoveredOutcomes(previous.outcomes, scopes),
        );
      }
    }
  }

  List<ReceivedScopeOutcome> _uncoveredOutcomes(
    List<ReceivedScopeOutcome> outcomes,
    Set<String> covered,
  ) => [
    for (final fact in outcomes)
      if (fact.scopes.any((scope) => !covered.contains(scope)))
        if (!fact.scopes.any(covered.contains))
          fact
        else
          ReceivedScopeOutcome(
            id: fact.id,
            scopes: fact.scopes.where((scope) => !covered.contains(scope)),
            outcome: fact.outcome,
          ),
  ];

  void _adoptSettledPresentation(NormalGatewayChatOwner other) {
    _retainHistoryPresentation(
      other._historyPresentation,
      other._historyPresentationObservation,
    );
    _persistedTurns.addAll(other._persistedTurns);
    other._persistedTurns.clear();
    _settledPresentation.addAll(other._settledPresentation);
    if (other._hasReceivedPresentation) {
      final retainedRows = [
        ...other._priorDisplay,
        // A submitting loser has only an unsent current scaffold. Preparing
        // has not yet moved the previous received turn into priorDisplay.
        if (!other.snapshot.hasActiveTurn ||
            other.phase == NormalGatewayTurnPhase.preparing)
          ...other._display,
      ];
      _settledPresentation.add(
        _SettledGatewayPresentation(
          observation:
              other._receivedObservation ?? ++_session._presentationObservation,
          rows: retainedRows.map(Map<String, dynamic>.from).toList(),
          tools: List.of(other._tools),
          timeline: other._timeline,
          outcomes: List.of(other._receivedOutcomes),
        ),
      );
    }
    other._settledPresentation.clear();
    other._receivedOutcomes.clear();
    _settledPresentation.sort((a, b) => a.observation.compareTo(b.observation));
    _reconcilePersistedTurns();
    _boundSettledPresentation();
  }

  void _boundSettledPresentation() {
    // Prefer recent presentation within the same budgets as the live owner.
    // Eviction is not hydration and grants no history/admission authority.
    while (_settledPresentation.isNotEmpty) {
      final timelines = [
        for (final settled in _settledPresentation) settled.timeline,
        _timeline,
      ];
      final rows =
          _priorDisplay.length +
          _display.length +
          _settledPresentation.fold<int>(0, (sum, p) => sum + p.rows.length);
      final tools =
          _tools.length +
          _settledPresentation.fold<int>(0, (sum, p) => sum + p.tools.length);
      if (rows <= 256 &&
          tools <= 512 &&
          timelines.fold<int>(0, (sum, t) => sum + t.runs.length) <=
              ChatTimeline.maxRuns &&
          timelines.fold<int>(
                0,
                (sum, t) =>
                    sum + t.runs.fold<int>(0, (sum, r) => sum + r.text.length),
              ) <=
              ChatTimeline.maxTextCodeUnits &&
          timelines.fold<int>(
                0,
                (sum, t) => sum + t.retainedToolIdentityCount,
              ) <=
              ChatTimeline.maxEvictedTools) {
        break;
      }
      _settledPresentation.removeAt(0);
    }
    // Metadata shares retained anchors' lifetime, not an independent journal.
    final retained = <Object>{
      for (final row in [..._priorDisplay, ..._display])
        if (row['_normal_projection_id'] != null) row['_normal_projection_id']!,
      for (final run in _timeline.runs) run.scope,
    };
    final allRetained = <Object>{
      ...retained,
      for (final settled in _settledPresentation) ...[
        for (final row in settled.rows)
          if (row['_normal_projection_id'] != null)
            row['_normal_projection_id']!,
        for (final run in settled.timeline.runs) run.scope,
      ],
    };
    _persistedTurns.removeWhere(
      (_, claim) => !claim.scopes.any(allRetained.contains),
    );
    // Bound address/tool metadata as well as body anchors. Dropping an optional
    // claim leaves received output intact; it never grants reconciliation.
    var addressCount = _persistedTurns.values.fold<int>(
      0,
      (sum, claim) => sum + claim.receipt.rowIds.length,
    );
    while (addressCount > NormalGatewayPersistedTurn.maxRowIds) {
      final first = _persistedTurns.keys.first;
      addressCount -= _persistedTurns.remove(first)!.receipt.rowIds.length;
    }
    for (var i = _receivedOutcomes.length - 1; i >= 0; i--) {
      final fact = _receivedOutcomes[i];
      final scopes = fact.scopes.where(retained.contains).toSet();
      if (scopes.isEmpty) {
        _receivedOutcomes.removeAt(i);
      } else if (scopes.length != fact.scopes.length) {
        _receivedOutcomes[i] = ReceivedScopeOutcome(
          id: fact.id,
          scopes: scopes,
          outcome: fact.outcome,
        );
      }
    }
  }

  void _adoptPreWireHistory(NormalGatewayChatOwner other, String stored) {
    // A verified alias may have observed the conversation after allocation but
    // before the delayed create reply. Only an unused, newer latest observation
    // can replace admission context; a receipt's floor is already immutable.
    if (wireEmitted ||
        _marker != null ||
        other.storedSessionId != stored ||
        !other._historyKnown ||
        other._historyObservation <= _historyObservation) {
      return;
    }
    _history = other._history.map(Map<String, dynamic>.from).toList();
    _historyConfirmationRows = other._historyConfirmationRows
        .map(Map<String, dynamic>.from)
        .toList();
    _historyKnown = true;
    _historyObservation = other._historyObservation;
    _createdEmptySessionId = null;
    _reconcilePersistedTurns();
    _boundSettledPresentation();
  }

  void _adoptChildObservers(NormalGatewayChatOwner other) {
    // Observer identity is independent of parent admission/presentation. Do not
    // copy the losing parent's turn, timeline or tools along with its children.
    for (final child in other._observedSubagents) {
      _mergeObservedChild(
        child.activity,
        observation: child.observation,
        anchor: child.anchor,
      );
    }
    final visible = [..._subagents, ...other._subagents];
    _subagents.clear();
    for (final child in visible) {
      final index = _observedSubagents.indexWhere(
        (observed) => observed.activity.matchesTask(child),
      );
      if (index >= 0) _mergeVisibleChild(_observedSubagents[index].activity);
    }
  }

  GatewaySubagentActivity _mergeObservedChild(
    GatewaySubagentActivity update, {
    int? observation,
    int? anchor,
  }) {
    final received = observation ?? ++_session._childObservation;
    final index = _observedSubagents.indexWhere(
      (agent) => agent.activity.matchesTask(update),
    );
    final previous = index < 0 ? null : _observedSubagents.removeAt(index);
    final incomingAnchor =
        anchor ?? (update.childSessionId == null ? null : received);
    final firstAnchor =
        previous?.anchor == null ||
            incomingAnchor != null && incomingAnchor < previous!.anchor!
        ? incomingAnchor
        : previous!.anchor;
    final firstChild = firstAnchor == incomingAnchor
        ? update.childSessionId
        : previous!.activity.childSessionId;
    final incomingIsNewer =
        previous == null || received >= previous.observation;
    final merged = previous == null
        ? update
        : incomingIsNewer
        ? previous.activity.merge(update, firstChildSessionId: firstChild)
        : update.merge(previous.activity, firstChildSessionId: firstChild);
    _observedSubagents.add((
      activity: merged,
      observation: incomingIsNewer ? received : previous.observation,
      anchor: firstAnchor,
    ));
    // Bound by recent observation, not which alias happened to win admission.
    _observedSubagents.sort((a, b) => a.observation.compareTo(b.observation));
    if (_observedSubagents.length > 128) _observedSubagents.removeAt(0);
    return merged;
  }

  void _mergeVisibleChild(GatewaySubagentActivity update) {
    final index = _subagents.indexWhere((agent) => agent.matchesTask(update));
    if (index < 0) {
      _subagents.add(update);
    } else {
      _subagents[index] = update;
    }
    if (_subagents.length > 128) _subagents.removeAt(0);
  }

  void _notify({bool meaningfulActivity = false}) {
    if (_session._closed || _redirect != null) return;
    final generation = _generation;
    final revision = ++_notificationRevision;
    // Queue before notifying app-wide readers: a listener's read must join
    // this exact transition, not observe the previous persisted state.
    _recordActivity(meaningfulActivity: meaningfulActivity);
    final state = snapshot;
    for (final entry in _listeners.entries.toList(growable: false)) {
      if (!_current(generation) || revision != _notificationRevision) return;
      if (identical(_listeners[entry.key], entry.value)) entry.value(state);
    }
    if (_current(generation) && revision == _notificationRevision) {
      _session.onActivityChanged?.call();
    }
  }

  void _recordActivity({
    int? updatedAtEpochMs,
    String? restoredLocalId,
    bool meaningfulActivity = false,
  }) {
    final id = turnId;
    if (_session._closed || id == null) return;
    // Reservation/preparation is not submitted work. In particular, opening a
    // chat or cancelling preparation must not resurrect its preceding turn.
    final state = switch (phase) {
      NormalGatewayTurnPhase.idle || NormalGatewayTurnPhase.preparing => null,
      NormalGatewayTurnPhase.submitting => OperationalActivityState.submitted,
      NormalGatewayTurnPhase.running => OperationalActivityState.running,
      NormalGatewayTurnPhase.reconciling =>
        OperationalActivityState.reconciling,
      NormalGatewayTurnPhase.reconciledUnknown =>
        OperationalActivityState.unknown,
      NormalGatewayTurnPhase.completed => OperationalActivityState.completed,
      NormalGatewayTurnPhase.failed => OperationalActivityState.failed,
    };
    if (state == null) return;
    final active = const {
      OperationalActivityState.submitted,
      OperationalActivityState.running,
      OperationalActivityState.reconciling,
    }.contains(state);
    final effectiveState = active && _pendingInput.isNotEmpty
        ? OperationalActivityState.needsInput
        : state;
    final previous = _lastActivityRecord;
    final local =
        restoredLocalId ??
        (previous?.turnId == id ? previous!.localSessionId : localSessionId);
    final unchanged =
        previous != null &&
        previous.turnId == id &&
        previous.localSessionId == local &&
        previous.storedSessionId == storedSessionId &&
        previous.lineageRootId == _lineageRootId &&
        previous.state == effectiveState;
    final now = _session._activityNowEpochMs();
    final heartbeat =
        unchanged &&
        active &&
        meaningfulActivity &&
        now - previous.updatedAtEpochMs >=
            NormalGatewayApplicationSession
                .activityHeartbeatInterval
                .inMilliseconds;
    if (unchanged && !heartbeat) {
      if (meaningfulActivity) _session._retryActivity();
      return;
    }
    final record = OperationalActivityRecord(
      scope: _session.scope,
      localSessionId: local,
      storedSessionId: storedSessionId,
      lineageRootId: _lineageRootId,
      turnId: id,
      state: effectiveState,
      updatedAtEpochMs:
          updatedAtEpochMs ??
          (unchanged && !heartbeat ? previous.updatedAtEpochMs : now),
    );
    _lastActivityRecord = record;
    // Activity is an optional index, never a prerequisite for submitting,
    // settling or recovering real work. New unchanged progress observations
    // are heartbeat-bounded; dirty retries have a separate bounded cooldown.
    _session._recordActivity(record);
  }

  bool _current(int generation) =>
      !_session._closed && _redirect == null && generation == _generation;

  bool _submissionCurrent(int generation) {
    if (_handoffRejection != null) throw _handoffRejection!;
    return _current(generation);
  }

  /// Synchronous admission across duplicate routes and both durable/local ids.
  Object? reserve() {
    if (_redirect != null) return _root.reserve();
    if (_session._closed ||
        !_session._initialized ||
        snapshot.hasActiveTurn ||
        _steerFlight != null) {
      return null;
    }
    _generation++;
    turnId = const Uuid().v4();
    _voiceTerminal = null;
    _voicePublicFinal = null;
    _voiceFinalKnown = false;
    _voiceCompletionSeen = false;
    _reservation = Object();
    phase = NormalGatewayTurnPhase.preparing;
    wireEmitted = false;
    _wireTurnId = null;
    _sawResponseActivity = false;
    _ownedSuccessfulCompletion = false;
    _activityChildren.clear();
    _error = null;
    _status = null;
    _notify();
    return _reservation;
  }

  void cancelPreparation(Object reservation) {
    if (_redirect != null) return _root.cancelPreparation(reservation);
    if (!identical(_reservation, reservation) ||
        phase != NormalGatewayTurnPhase.preparing) {
      return;
    }
    _reservation = null;
    phase = NormalGatewayTurnPhase.idle;
    _notify();
  }

  bool get canSteer => _redirect != null
      ? _root.canSteer
      : _session.hasCurrentAccount &&
            phase == NormalGatewayTurnPhase.running &&
            wireEmitted &&
            !_settling &&
            _terminalReceipt?.generation != _generation &&
            _steerFlight == null;

  /// One steering flight per app-owned chat, including duplicate routes and
  /// local/stored aliases. This is guidance for the existing turn, not a new
  /// prompt reservation, completion receipt or permission to resend.
  Future<bool> steer(String text) async {
    if (_redirect != null) return _root.steer(text);
    final guidance = text.trim();
    if (!canSteer || guidance.isEmpty) return false;
    final send = _session._steer;
    if (send == null) {
      throw StateError('This gateway does not support steering');
    }
    final generation = _generation;
    final flight = _steerFlight = Object();
    _notify();
    try {
      if (!_current(generation) || !snapshot.hasActiveTurn) return false;
      final accepted = await send(sessionId: localSessionId, text: guidance);
      if (!accepted) return false;
      if (!_current(generation) ||
          !snapshot.hasActiveTurn ||
          _settling ||
          _terminalReceipt?.generation == generation) {
        // The server queued it, but this ended/replaced run can no longer
        // confirm a live handoff. Keep the caller's draft; never claim a
        // rejection or automatically resend an already accepted instruction.
        // A terminal stays decisive if settlement persistence must retry.
        throw StateError('The run ended before steering could be confirmed.');
      }
      // Confirmed guidance advances this turn's response scope: the
      // pre-steer completion receipt no longer proves the current scope.
      // A later matching completion can re-establish it.
      _ownedSuccessfulCompletion = false;
      // Place guidance before the live response, but do not make it a new
      // prompt boundary. A reused preview can later remove that response's
      // placeholder; ingress still finds the assistant across this row.
      final assistant = _display.lastIndexWhere(
        (row) => row['role'] == 'assistant',
      );
      _display.insert(assistant < 0 ? _display.length : assistant, {
        'role': 'user',
        'display_kind': 'steer',
        'content': guidance,
        ChatMessageTime.observedAtKey: DateTime.now().millisecondsSinceEpoch,
        ChatMessageTime.sourceKey: 'sent',
        '_normal_projection_id': const Uuid().v4(),
      });
      return true;
    } finally {
      if (identical(_steerFlight, flight)) {
        _steerFlight = null;
        _notify();
      }
    }
  }

  /// An interrupt ack is not a terminal receipt. Keep the marker active until
  /// the terminal event or an authoritative resume/history reconciliation.
  Future<bool> interrupt() async {
    if (_redirect != null) return _root.interrupt();
    if (!snapshot.hasActiveTurn || !wireEmitted) return false;
    return await _session.client?.interruptPrompt(sessionId: localSessionId) ??
        false;
  }

  /// The boundary at which a prepared submission leaves the route. Nothing
  /// below captures screen state; even a route disposed during write-ahead
  /// cannot drop callbacks, clear activity or close the client.
  Future<void> submitPrepared({
    required Object reservation,
    required String text,
    required String localContent,
    NormalGatewayPromptSubmit? submit,
    String? knownStoredSessionId,
    String? rawDraftText,
    bool canRestoreDraft = false,
    ComposerDraftHandle? draftHandle,
    bool Function()? maySubmit,
  }) async {
    if (_redirect != null) {
      return _root.submitPrepared(
        reservation: reservation,
        text: text,
        localContent: localContent,
        submit: submit,
        knownStoredSessionId: knownStoredSessionId,
        rawDraftText: rawDraftText,
        canRestoreDraft: canRestoreDraft,
        draftHandle: draftHandle,
        maySubmit: maySubmit,
      );
    }
    if (!identical(_reservation, reservation) ||
        phase != NormalGatewayTurnPhase.preparing) {
      throw StateError('Submission reservation is no longer owned.');
    }
    _reservation = null;
    final generation = _generation;
    _draftToRestore = rawDraftText;
    _draftRestoreAllowed = canRestoreDraft;
    _draftHandle = draftHandle;
    phase = NormalGatewayTurnPhase.submitting;
    // A newer turn's baseline cannot retroactively correlate an older,
    // genuinely received unknown-floor reply retained in the same projection.
    final protectUnknownPresentation =
        _floor == null && _hasReceivedPresentation;
    _priorDisplay.addAll(_display);
    if (_priorDisplay.length > 256) {
      _priorDisplay.removeRange(0, _priorDisplay.length - 256);
    }
    _display.clear();
    _tools.clear();
    _subagents.clear();
    _pendingInput.clear();
    _display.add({
      'role': 'user',
      'content': localContent,
      AndroidPromptContext.localUserTextKey: true,
      '_normal_projection_id': const Uuid().v4(),
    });
    _display.add({
      'role': 'assistant',
      'content': '',
      '_normal_projection_id': const Uuid().v4(),
      '_gateway_pending_response': true,
    });
    _receivedObservation = null;
    _boundSettledPresentation();
    _notify();
    try {
      if (storedSessionId == null && knownStoredSessionId != null) {
        _session._bind(this, knownStoredSessionId);
      }
      if (storedSessionId == null) {
        await _session.client!.ensureSession(
          localSessionId,
          workingDirectory: workingDirectory,
        );
        if (!_submissionCurrent(generation)) return;
        if (maySubmit?.call() == false) {
          throw StateError('Voice admission revoked');
        }
        final stored = _session.client!.storedSessionKeyFor(localSessionId);
        if (stored == null) {
          throw StateError('No durable session binding before submit.');
        }
        _session._bind(this, stored);
      }
      if (!_submissionCurrent(generation)) return;
      if (maySubmit?.call() == false) {
        throw StateError('Voice admission revoked');
      }
      // Allocation-time emptiness is consumed once, unless a newer verified
      // alias observation has superseded it. Resume/unknown/404 are never empty.
      final createdEmpty = _createdEmptySessionId == storedSessionId;
      _createdEmptySessionId = null;
      if (!_historyKnown && !createdEmpty) {
        final stored = storedSessionId!;
        final baseline = await _readAdmissionBaseline(stored);
        if (!_submissionCurrent(generation)) return;
        if (maySubmit?.call() == false) {
          throw StateError('Voice admission revoked');
        }
        if (stored == storedSessionId && baseline != null) {
          _acceptHistory(baseline);
        }
      }
      _floor = protectUnknownPresentation
          ? null
          : _historyKnown
          ? _numericFloor(_history)
          : createdEmpty
          ? 0
          : null;
      _historyKnown = false;
      if (!_submissionCurrent(generation)) return;
      if (maySubmit?.call() == false) {
        throw StateError('Voice admission revoked');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      _marker = NormalGatewayPendingMarker(
        scope: _session.scope,
        localSessionId: localSessionId,
        storedSessionId: storedSessionId!,
        turnId: turnId!,
        rowFloor: _floor,
        phase: 'write_ahead',
        createdAt: now,
        updatedAt: now,
      );
      await _session.pendingStore.put(_marker!);
      if (!_submissionCurrent(generation)) return;
      if (maySubmit?.call() == false) {
        throw StateError('Voice admission revoked');
      }
      _submissionPending = true;
      final NormalGatewayPromptSubmit submitPrompt =
          submit ??
          (!_session._usesClientSubmit || _session.client == null
              ? _session._submit
              : ({
                  required String sessionId,
                  required String text,
                  required StreamCallback onEvent,
                  required void Function() onSent,
                }) => _session.client!.submitPrompt(
                  sessionId: sessionId,
                  text: text,
                  onEvent: onEvent,
                  onSent: onSent,
                  maySend: () =>
                      _current(generation) &&
                      snapshot.hasActiveTurn &&
                      maySubmit?.call() != false,
                ));
      await submitPrompt(
        sessionId: localSessionId,
        text: text,
        // Production ingress is the global observer; the seam feeds exactly
        // the same reducer, rather than bypassing the owner in widget tests.
        onEvent: submit == null
            ? (_) {}
            : (event) {
                if (_current(generation)) _event(event);
              },
        onSent: () {
          if (!_current(generation) || !snapshot.hasActiveTurn) return;
          wireEmitted = true;
          for (final row in _display.where((row) => row['role'] == 'user')) {
            ChatMessageTime.observe(row, source: ChatMessageTimeSource.sent);
          }
          invalidateDraftRecovery();
          phase = NormalGatewayTurnPhase.running;
          _marker = _marker!.withPhase('emitted');
          // The write-ahead receipt already covers this crash window. Failure
          // to update its phase must not convert a sent prompt to a rejection.
          unawaited(
            _session.pendingStore.put(_marker!).catchError((Object _) {}),
          );
          _notify();
        },
      );
      if (_current(generation)) _submissionPending = false;
      if (!_current(generation) || !snapshot.hasActiveTurn || _settling) return;
      // A completed RPC future is NOT terminal evidence (including test seams).
      phase = NormalGatewayTurnPhase.reconciling;
      _notify();
      requestRecovery();
    } catch (error) {
      if (_handoffRejection != null) throw _handoffRejection!;
      if (_current(generation)) _submissionPending = false;
      if (!_current(generation) || !snapshot.hasActiveTurn || _settling) return;
      if (wireEmitted) {
        phase = NormalGatewayTurnPhase.reconciling;
        if (error is! JsonRpcError || error.reason != 'stream_terminal') {
          _error = error.toString();
        }
        _notify();
        requestRecovery();
        return;
      }
      await _settle(false, error.toString(), generation: generation);
      rethrow;
    }
  }

  Future<_GatewayHistoryObservation?> _readAdmissionBaseline(
    String stored,
  ) async {
    final read = Completer<_GatewayHistoryObservation?>();
    _baselineRead = read;
    _baselineTimer = Timer(
      const Duration(seconds: 2),
      () => read.complete(null),
    );
    // A late response may finish after timeout, wire emission or close. It
    // resolves only this read, never mutates the owner's baseline/history.
    unawaited(
      _readLatestHistory(stored).then(
        (rows) {
          if (!read.isCompleted) read.complete(rows);
        },
        onError: (Object _, StackTrace _) {
          if (!read.isCompleted) read.complete(null);
        },
      ),
    );
    try {
      return await read.future;
    } finally {
      _baselineTimer?.cancel();
      _baselineTimer = null;
      _baselineRead = null;
    }
  }

  void _restore(NormalGatewayPendingMarker marker) {
    if (_marker != null) {
      if (_marker!.key != marker.key) {
        _additionalRestoredMarkers[marker.key] = marker;
        _floor = null; // ambiguous receipts have no single known boundary
      }
      return;
    }
    _generation++;
    turnId = marker.turnId;
    _floor = marker.rowFloor;
    _marker = marker;
    // Even write_ahead may have emitted before process death. Never resend.
    wireEmitted = true;
    phase = NormalGatewayTurnPhase.reconciling;
    _recordActivity(
      updatedAtEpochMs: marker.updatedAt,
      restoredLocalId: marker.localSessionId,
    );
  }

  void _event(StreamEvent event) {
    if (_session._closed) return;
    if (const {
      'notification.show',
      'notification.clear',
      'background.complete',
      'review.summary',
    }.contains(event.type)) {
      _auxiliaryEvents.add(event);
      if (_auxiliaryEvents.length > 20) _auxiliaryEvents.removeAt(0);
      _notifyAuxiliary(event);
      _notify();
      return;
    }
    if (_interactive(event.type)) {
      final id =
          event.data['server_request_id']?.toString() ??
          event.data['request_id']?.toString() ??
          event.data['id']?.toString();
      if (!event.type.endsWith('.request')) {
        _inputUpdates.add(event);
        if (_inputUpdates.length > 64) _inputUpdates.removeAt(0);
      }
      if (event.type == 'clarify.remaining') {
        final raw = event.data['remaining'];
        final remaining = raw is List
            ? raw.map((value) => value.toString()).toSet()
            : <String>{};
        final previous = _pendingInput[id];
        final questions = previous?.data['questions'];
        if (remaining.isEmpty) {
          _pendingInput.remove(id);
        } else if (previous != null && questions is List) {
          _pendingInput[id!] = StreamEvent(
            type: previous.type,
            data: {
              ...previous.data,
              'questions': questions
                  .where(
                    (question) =>
                        question is Map &&
                        remaining.contains(question['qid']?.toString()),
                  )
                  .toList(),
            },
            sessionId: previous.sessionId,
          );
        }
        _notify();
        return;
      }
      if (event.type == 'request.cancel' || event.type.endsWith('.expire')) {
        _pendingInput.remove(id);
      } else if (id != null) {
        _pendingInput[id] = event;
        if (_pendingInput.length > 64) {
          _pendingInput.remove(_pendingInput.keys.first);
        }
        _notifyAttention(event, id);
      }
      _notify();
      return;
    }
    if (event.type.startsWith('subagent.')) {
      // Child observers can settle after the parent turn. Updating them must
      // neither reopen/resubmit the parent nor require its active wire receipt.
      final update = GatewaySubagentActivity.fromGatewayEvent(
        event.type,
        event.data,
      );
      if (update != null) {
        if (snapshot.hasActiveTurn && wireEmitted) {
          _hasTurnSubagentPresentation = true;
        }
        final known = _observedSubagents.any(
          (child) => child.activity.matchesTask(update),
        );
        final activityIndex = _activityChildren.indexWhere(
          (child) => child.matchesTask(update),
        );
        final current =
            snapshot.hasActiveTurn &&
            wireEmitted &&
            (event.turnId == null || event.turnId == _wireTurnId) &&
            (activityIndex >= 0 || event.type == 'subagent.start' && !known);
        final merged = _mergeObservedChild(update);
        _mergeVisibleChild(merged);
        if (current) {
          if (activityIndex < 0) {
            _activityChildren.add(merged);
          } else {
            _activityChildren[activityIndex] = merged;
          }
        }
        if (current && (!merged.isComplete || _status?.kind == 'subagent')) {
          final active = _activityChildren
              .where((task) => !task.isComplete)
              .lastOrNull;
          _status = active == null
              ? null
              : GatewayTurnStatus(kind: 'subagent', text: active.goal);
        }
      }
      _notify(meaningfulActivity: update != null);
      return;
    }
    if (!snapshot.hasActiveTurn ||
        phase == NormalGatewayTurnPhase.preparing ||
        !wireEmitted ||
        _settling ||
        _terminalReceipt != null) {
      return;
    }
    final wireTurn = event.turnId;
    final terminal = const {
      'message.complete',
      'turn.end',
      'turn.error',
      'error',
    }.contains(event.type);
    if (wireTurn != null) {
      if (_settledWireTurnIds.contains(wireTurn) ||
          _wireTurnId != null && _wireTurnId != wireTurn) {
        return;
      }
      // A terminal cannot establish ownership: it may be A's delayed bookend
      // arriving after B's onSent, before B has emitted any activity.
      if (!terminal) _wireTurnId ??= wireTurn;
    }
    final ownsResponse = wireTurn != null
        ? wireTurn == _wireTurnId
        : _sawResponseActivity;
    if (event.type == 'message.complete' && !ownsResponse) {
      // An ambiguous trailing completion may trigger reconciliation, but must
      // not write A's text or timeline into B before B establishes activity.
      requestRecovery();
      return;
    }
    if (!terminal &&
        (event.type.startsWith('message.') ||
            event.type.startsWith('tool.') ||
            event.type.startsWith('reasoning.'))) {
      // New body activity after a completion is not covered by that earlier
      // persistence proof. A subsequent valid completion may establish a new
      // exact scope claim; lifecycle/status-only updates do not revoke it.
      _persistedTurns.remove(turnId);
      _voiceFinalKnown = false;
      _voicePublicFinal = null;
      _sawResponseActivity = true;
      _ownedSuccessfulCompletion = false;
    }
    if (phase == NormalGatewayTurnPhase.reconciling &&
        (event.type == 'message.delta' || event.type.startsWith('tool.'))) {
      phase = NormalGatewayTurnPhase.running;
    }
    // A restored running turn can receive guidance before assistant activity.
    // A user-only projection must not prevent its response scaffold.
    if (!_display.any((row) => row['role'] == 'assistant') &&
        (event.type.startsWith('message.') ||
            event.type.startsWith('tool.') ||
            event.type.startsWith('reasoning.'))) {
      _display.add({
        'role': 'assistant',
        'content': '',
        '_normal_projection_id': const Uuid().v4(),
        '_gateway_pending_response': true,
      });
    }
    final reasoning = GatewayReasoningUpdate.fromGatewayEvent(
      event.type,
      event.data,
    );
    if (reasoning != null ||
        event.type.startsWith('tool.') ||
        event.type == 'message.delta' ||
        event.type == 'message.interim' ||
        event.type == 'message.complete') {
      _receivedObservation ??= ++_session._presentationObservation;
    }
    final assistantIndex = _display.lastIndexWhere(
      (row) => row['role'] == 'assistant',
    );
    final assistant = assistantIndex < 0 ? null : _display[assistantIndex];
    if (reasoning != null && assistant != null) {
      _status = const GatewayTurnStatus(kind: 'reasoning', text: '');
      _timeline = _timeline.reasoning(
        assistant['_normal_projection_id']!,
        reasoning,
      );
      assistant['_gateway_reasoning'] = reasoning.applyTo(
        assistant['_gateway_reasoning']?.toString() ?? '',
      );
      assistant['_gateway_reasoning_verbose'] = reasoning.verbose;
      assistant['_gateway_reasoning_replaces'] =
          assistant['_gateway_reasoning_replaces'] == true ||
          reasoning.mode == GatewayReasoningEventMode.replace;
    } else if (event.type == 'message.start' && assistant != null) {
      _status = null;
      ChatMessageTime.observe(
        assistant,
        source: ChatMessageTimeSource.received,
        serverTimestamp: event.data['timestamp'],
      );
      assistant.remove('_gateway_interim_boundary');
    } else if (event.type == 'message.delta' && assistant != null) {
      final token = event.data['text']?.toString() ?? '';
      if (token.isNotEmpty) {
        ChatMessageTime.observe(
          assistant,
          source: ChatMessageTimeSource.received,
          serverTimestamp: event.data['timestamp'],
        );
      }
      assistant['content'] = '${assistant['content'] ?? ''}$token';
      // Raw response scope: only streaming observations may feed the
      // completion receipt gate. Completion payload writes update 'content'
      // for presentation but never this key, so a rejected foreign payload
      // cannot manufacture the next completion's evidence.
      assistant['_raw_response_scope'] =
          '${assistant['_raw_response_scope'] ?? ''}$token';
      _timeline = _timeline.appendText(
        assistant['_normal_projection_id']!,
        token,
      );
      _status = null;
    } else if (event.type == 'message.interim' && assistant != null) {
      _status = null;
      if (event.data['text']?.toString().isNotEmpty == true) {
        ChatMessageTime.observe(
          assistant,
          source: ChatMessageTimeSource.received,
          serverTimestamp: event.data['timestamp'],
        );
      }
      final transition = GatewayInterimTransition.resolve(
        currentText: assistant['content']?.toString() ?? '',
        interimText: event.data['text']?.toString() ?? '',
        alreadyStreamed: event.data['already_streamed'] == true,
      );
      assistant['content'] = transition.sealedText;
      assistant['_raw_response_scope'] = transition.sealedText;
      _timeline = _timeline.textSnapshot(
        assistant['_normal_projection_id']!,
        transition.sealedText,
      );
      if (transition.startsNewMessage) {
        assistant['_gateway_interim'] = true;
        assistant['_gateway_pending_response'] = false;
        _display.add({
          'role': 'assistant',
          'content': '',
          '_normal_projection_id': const Uuid().v4(),
          '_gateway_pending_response': true,
          '_gateway_interim_boundary': true,
        });
      }
    } else if (event.type == 'message.complete' && assistant != null) {
      _status = null;
      final text =
          event.data['rendered']?.toString() ??
          event.data['text']?.toString() ??
          '';
      final target = _completionAssistantMessage(
        event.data,
        event.data['text']?.toString() ?? text,
      );
      if (target != null) {
        // Evidence comes from the raw response scope this completion actually
        // selected: the helper may seal and reuse an earlier same-turn
        // preview and remove an empty pending boundary, so the LAST row can
        // be the wrong scope. The raw-scope key is written only by streaming
        // observations (deltas and interim seals), never by completion
        // payloads, so a rejected foreign payload that overwrote 'content'
        // cannot manufacture this or a later completion's evidence. Snapshot
        // BEFORE the payload overwrites presentation; an empty selected
        // scope carries no authority.
        final observedStream = target['_raw_response_scope']?.toString() ?? '';
        ChatMessageTime.observe(
          target,
          source: ChatMessageTimeSource.received,
          serverTimestamp: event.data['timestamp'],
        );
        if (text.isNotEmpty) {
          target['content'] = text;
          _timeline = _timeline.textSnapshot(
            target['_normal_projection_id']!,
            text,
            preservePosition:
                event.data['response_previewed'] == true ||
                event.data['response_reused'] == true ||
                event.data['response_transformed'] == true,
          );
        }
        target['_gateway_pending_response'] = false;
        target['_chat_response_complete'] =
            ownsResponse && isSuccessfulResponseReceipt(event.data);
        // Generation-scoped receipt for recovery: stock resume reports idle,
        // never a terminal status, so an owned successful completion is the
        // wire-side evidence that this turn finished. Reset in reserve() and
        // revoked by later body activity or confirmed steering. An ID-less
        // completion carries no in-band generation identity, so its receipt
        // only counts when its payload carries the exact, non-empty text this
        // turn already streamed — a consistency check, not an identity proof:
        // absent/empty payloads and foreign text are refused, while an
        // identical-text replay from another generation remains
        // indistinguishable in-band (documented residual ambiguity).
        // Wire-ID-matched completions are exempt: the server vouched for the
        // turn identity.
        // The gate compares the payload's streamed representation — 'text';
        // 'rendered' is display formatting of the same content and only
        // stands in when 'text' is absent.
        final completionText =
            event.data['text']?.toString() ??
            event.data['rendered']?.toString() ??
            '';
        final provenCompletion =
            wireTurn != null ||
            (completionText.isNotEmpty && completionText == observedStream);
        _ownedSuccessfulCompletion =
            provenCompletion &&
            ownsResponse &&
            isSuccessfulResponseReceipt(event.data);
        _capturePersistedTurn(event.data);
        // This is the admitted operation's live completion, not a history row.
        // Preserve explicit empty/hidden public delivery instead of borrowing
        // an older same-text assistant from a retained presentation.
        _voiceFinalKnown = true;
        _voiceCompletionSeen = true;
        final public = <String, dynamic>{
          ...event.data,
          'role': 'assistant',
          'content': text,
        };
        _voicePublicFinal =
            ownsResponse &&
                isSuccessfulResponseReceipt(event.data) &&
                isPublicDeliveryMessage(public)
            ? stripToolResultText(publicDeliveryText(public)).trim()
            : null;
      }
    } else if (event.type.startsWith('tool.')) {
      final update = GatewayToolActivity.fromGatewayEvent(
        event.type,
        event.data,
        observedAt: DateTime.now(),
      );
      if (update != null && !_timeline.excludesTool(update)) {
        final index = toolActivityUpdateIndex(_tools, update, event.type);
        if (index < 0) {
          _tools.add(update);
        } else {
          _tools[index] = _tools[index].merge(update);
        }
        final activity = index < 0 ? _tools.last : _tools[index];
        if (!activity.isTerminal || _status?.kind == 'tool') {
          _status = GatewayTurnStatus.forRunningTool(_tools);
        }
        final toolId = activity.toolId;
        if (toolId != null) {
          _session.presentation
              ?.chatFor(storedSessionId ?? localSessionId)
              .aliasTool(activity.identity, 'tool:$toolId');
        }
        if (assistant != null) {
          _timeline = _timeline.tool(
            assistant['_normal_projection_id']!,
            activity,
          );
          _tools.removeWhere(
            (tool) =>
                tool.identity == activity.identity &&
                !_timeline.runs.any(
                  (run) => run.activity?.identity == tool.identity,
                ),
          );
        }
        if (_tools.length > 512) _tools.removeAt(0);
      }
    } else {
      _status =
          GatewayTurnStatus.fromGatewayEvent(event.type, event.data) ?? _status;
    }
    // Bound transient memory, but never turn a truncated projection into
    // canonical history. The server remains the only transcript authority.
    if (_display.length > 256) _display.removeRange(1, _display.length - 255);
    for (final row in _display) {
      for (final key in ['content', '_gateway_reasoning']) {
        final value = row[key];
        if (value is String && value.length > 262144) {
          row[key] = value.substring(value.length - 262144);
        }
      }
    }
    _timeline = _timeline.retainScopes(
      [
        ..._priorDisplay,
        ..._display,
      ].map((row) => row['_normal_projection_id']).whereType<String>(),
    );
    final failure = _failure(event.data);
    _tools.removeWhere(_timeline.excludesTool);
    _boundSettledPresentation();
    final ownedLifecycleTerminal =
        wireTurn != null &&
        wireTurn == _wireTurnId &&
        _additionalRestoredMarkers.isEmpty &&
        const {'turn.end', 'turn.error'}.contains(event.type);
    if (ownedLifecycleTerminal &&
        (event.type == 'turn.error' || failure != null)) {
      unawaited(
        _settle(
          false,
          failure ?? event.data['message']?.toString() ?? 'Gateway turn failed',
        ),
      );
    } else if (ownedLifecycleTerminal) {
      if (isSuccessfulResponseReceipt(event.data) &&
          assistant != null &&
          assistant['_chat_response_complete'] != false &&
          assistant['_gateway_interim'] != true) {
        assistant['_chat_response_complete'] = true;
      }
      unawaited(_settle(true, null));
    } else if (terminal) {
      // Stock message.complete precedes running=false (prompt_turn.py), and
      // stock does not promise turn.end. Neither an ID-less trailing bookend
      // nor a message completion proves the admitted lifecycle is settled.
      // Resume/history are the authority; never infer ownership from arrival.
      requestRecovery();
    }
    _notify(
      meaningfulActivity:
          event.type.startsWith('message.') ||
          event.type.startsWith('tool.') ||
          reasoning != null,
    );
  }

  Map<String, dynamic>? _completionAssistantMessage(
    Map<String, dynamic> data,
    String rawCompleteText,
  ) {
    final pendingIndex = _display.lastIndexWhere(
      (message) => message['role'] == 'assistant',
    );
    if (pendingIndex < 0) return null;
    final pending = _display[pendingIndex];
    if (pending['_gateway_pending_response'] != true ||
        (pending['content']?.toString() ?? '').isNotEmpty ||
        pending['_gateway_interim_boundary'] != true) {
      return pending;
    }
    // Flags describe the final response, but do not identify which interim
    // it settles. Only an exact raw-text match may consume a sealed interim.
    if (data['response_previewed'] != true &&
        data['response_transformed'] != true &&
        data['response_reused'] != true) {
      return pending;
    }
    if (rawCompleteText.isEmpty) return pending;

    // A completion settles a matching preview from this turn, not the empty
    // bubble prepared for a continuation or distinct interim commentary.
    for (var index = pendingIndex - 1; index >= 0; index--) {
      final candidate = _display[index];
      if (candidate['role'] == 'user' && candidate['display_kind'] != 'steer') {
        break;
      }
      if (candidate['role'] != 'assistant' ||
          candidate['_gateway_interim'] != true ||
          candidate['content'] != rawCompleteText) {
        continue;
      }
      final pendingReasoning = pending['_gateway_reasoning']?.toString() ?? '';
      if (pendingReasoning.isNotEmpty) {
        final currentReasoning =
            candidate['_gateway_reasoning']?.toString() ?? '';
        candidate['_gateway_reasoning'] = GatewayReasoningUpdate(
          text: pendingReasoning,
          mode: pending['_gateway_reasoning_replaces'] == true
              ? GatewayReasoningEventMode.replace
              : GatewayReasoningEventMode.append,
          verbose: pending['_gateway_reasoning_verbose'] == true,
        ).applyTo(currentReasoning);
        candidate['_gateway_reasoning_verbose'] =
            pending['_gateway_reasoning_verbose'] == true;
      }
      _timeline = _timeline.reassignScope(
        pending['_normal_projection_id']!,
        candidate['_normal_projection_id']!,
        replaceReasoning: pending['_gateway_reasoning_replaces'] == true,
      );
      _display.removeAt(pendingIndex);
      candidate.remove('_gateway_interim');
      return candidate;
    }
    return pending;
  }

  void requestRecovery() {
    if (_redirect != null) return _root.requestRecovery();
    if (!snapshot.hasActiveTurn ||
        (!wireEmitted && _terminalReceipt == null) ||
        _settling ||
        !_session._canRecover) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _recoveryQueued = true;
    if (!_recovering) unawaited(_recover());
  }

  Future<void> _recover() async {
    if (_recovering || !_session._canRecover) return;
    _recovering = true;
    _recoveryQueued = false;
    final generation = _generation;

    try {
      final terminal = _terminalReceipt;
      if (terminal != null && terminal.generation == generation) {
        await _settle(
          terminal.completed,
          terminal.error,
          generation: generation,
        );
        return;
      }
      final stored = storedSessionId;
      if (stored == null) return; // no safe recovery without a durable identity
      // Recovery may attach while the submit wait is pending, but that read
      // cannot become settlement authority merely by arriving after the ACK.
      // Generation plus this immutable observation boundary identify its epoch.
      final submissionWasPending = _submissionPending;
      final resumed = await (_session.client == null
          ? _session._resume(
              localSessionId: localSessionId,
              storedSessionId: stored,
            )
          : _session.client!.resumeSubmittedSession(
              localSessionId: localSessionId,
              storedSessionId: stored,
              acceptsResult: () =>
                  _current(generation) &&
                  snapshot.hasActiveTurn &&
                  _terminalReceipt == null &&
                  !submissionWasPending &&
                  !_submissionPending,
            ));
      if (!_current(generation) || !snapshot.hasActiveTurn || _settling) return;
      if (_terminalReceipt != null) {
        // An owned terminal received during this read outranks the older
        // recovery observation, including after a rejected tombstone write.
        _recoveryQueued = true;
        return;
      }
      if (!_session._canRecover) return;
      // The submit completion queues a fresh recovery. Never inspect retained
      // errors, idle status or history from a pre-wait observation, even if its
      // response is delivered after this submission's wait has finished.
      if (submissionWasPending || _submissionPending) return;
      final status = (resumed.inflight?['status'] ?? resumed.status)
          ?.toString()
          .toLowerCase();
      final running =
          resumed.running == true ||
          const {'running', 'queued', 'pending', 'streaming'}.contains(status);
      final inactive =
          resumed.running == false ||
          const {'completed', 'complete', 'done', 'idle'}.contains(status);
      final failure = _failure({
        ...?resumed.inflight,
        'status': resumed.inflight?['status'] ?? resumed.status,
      });
      if (!running && failure != null) {
        await _settle(
          _additionalRestoredMarkers.isEmpty ? false : null,
          _additionalRestoredMarkers.isEmpty ? failure : null,
          generation: generation,
        );
        return;
      }
      final fresh = await _readLatestHistory(stored);
      if (!_current(generation) || !snapshot.hasActiveTurn || _settling) return;
      if (_terminalReceipt != null) {
        _recoveryQueued = true;
        return;
      }
      if (!_session._canRecover) return;
      if (!_acceptHistory(fresh)) return;
      // Idle alone proves only that work ended: stock may retain partial prose
      // after interruption. An outcome needs an explicit terminal status or an
      // owned successful completion receipt from this turn's wire.
      if (running) phase = NormalGatewayTurnPhase.running;
      final completed = const {
        'completed',
        'complete',
        'done',
      }.contains(status);
      // Stock resume never reports a terminal status; the owned successful
      // receipt settles through the same durable fresh-response-row authority
      // the resumed-completed path already uses.
      final settledByReceipt = completed || _ownedSuccessfulCompletion;
      if (inactive && !running && _additionalRestoredMarkers.isNotEmpty) {
        // Authoritative idle releases all restored uncertainties, but cannot
        // assign one recovered turn's successful outcome to every receipt.
        await _settle(null, null, generation: generation);
      } else if (settledByReceipt &&
          !running &&
          _floor != null &&
          fresh.rows.any((row) => _responseRow(row, _floor!))) {
        await _settle(true, null, generation: generation);
      } else if (inactive &&
          !running &&
          (!settledByReceipt ||
              (_ownedSuccessfulCompletion && !completed && _floor == null))) {
        // Release admission without resubmitting or inventing success/failure.
        // No row/count heuristic is needed to know the server is now idle.
        // An owned receipt without the durable response-row floor cannot
        // establish success either: later history reads never repair an
        // unknown floor, so release as unknown instead of leaving the turn
        // busy indefinitely. A completed resume status with an unknown floor
        // stays retained — its reply may belong to an older turn.
        await _settle(null, null, generation: generation);
      } else {
        _notify(meaningfulActivity: running);
      }
    } catch (_) {
      // A failed resume/history read is unknown, never an empty completion.
    } finally {
      _recovering = false;

      // Old flight A must hand off to a queued generation B, even when A was
      // invalidated by terminal settlement while its read was held.
      if (_redirect != null) {
        // A retired owner's held read cannot start another recovery timer or
        // mutate the shared winner after it unwinds.
        _recoveryQueued = false;
      } else if (!_session._closed && _recoveryQueued && _session._canRecover) {
        requestRecovery();
      } else if (snapshot.hasActiveTurn &&
          (wireEmitted || _terminalReceipt != null) &&
          !_settling &&
          _session._canRecover) {
        final shift = (_retry++).clamp(0, 6);
        _retryTimer = Timer(
          Duration(milliseconds: (500 * (1 << shift)).clamp(500, 30000)),
          requestRecovery,
        );
      }
    }
  }

  Future<void> _settle(
    bool? completed,
    String? error, {
    int? generation,
  }) async {
    final owned = generation ?? _generation;
    if (!_current(owned) || _settling || !snapshot.hasActiveTurn) return;
    final settledTurnId = turnId;
    String? publicFinal = _voicePublicFinal;
    if (!_voiceFinalKnown &&
        !_voiceCompletionSeen &&
        completed == true &&
        wireEmitted) {
      final assistant = _display.lastWhere(
        (row) => row['role'] == 'assistant',
        orElse: () => <String, dynamic>{},
      );
      if (assistant['_chat_response_complete'] == true &&
          assistant['_gateway_interim'] != true &&
          isPublicDeliveryMessage(assistant)) {
        publicFinal = stripToolResultText(publicDeliveryText(assistant)).trim();
      }
    }
    final settledWireEmitted = wireEmitted;
    final settledSessionId = storedSessionId ?? localSessionId;
    final settledTitle = title;
    _terminalReceipt = (completed: completed, error: error, generation: owned);
    _settling = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final marker = _marker;
    try {
      if (completed == false) {
        _persistedTurns.remove(settledTurnId);
        // The owned failure already disproves these responses. Do not wait for
        // tombstone I/O to hide them, or let a retry revive their final markers.
        for (final row in _display) {
          row['_chat_response_complete'] = false;
        }
        _notify();
        if (!_current(owned)) return;
      }
      for (final receipt in [?marker, ..._additionalRestoredMarkers.values]) {
        await _session.pendingStore.put(receipt.withPhase('settled'));
        if (!_current(owned)) return;
        // A durable tombstone prevents restart from resurrecting this turn if
        // the optional physical removal fails.
        await _session.pendingStore.remove(receipt).catchError((Object _) {});
        if (!_current(owned)) return;
      }
      if (completed == false &&
          !wireEmitted &&
          _listeners.isEmpty &&
          _draftRestoreAllowed &&
          _draftToRestore != null) {
        bool canRestore() =>
            _current(owned) &&
            _draftRestoreAllowed &&
            _listeners.isEmpty &&
            _session.presentation?.isClosed != true;
        final handle = _draftHandle;
        await (handle != null
            ? _restoreDraft(handle, _draftToRestore!, canRestore)
            : ComposerDraftStore.save(
                connectionId: _session.connection.id,
                sessionId: localSessionId,
                text: _draftToRestore!,
                isCurrent: canRestore,
              ));
        if (!_current(owned)) return;
      }
      if (settledTurnId != null) {
        _voiceTerminal = NormalGatewayTurnTerminal(
          turnId: settledTurnId,
          completed: completed,
          publicFinalText: completed == true ? publicFinal : null,
        );
      }
      phase = completed == null
          ? NormalGatewayTurnPhase.reconciledUnknown
          : completed
          ? NormalGatewayTurnPhase.completed
          : NormalGatewayTurnPhase.failed;
      if (_wireTurnId != null) {
        _settledWireTurnIds.add(_wireTurnId!);
        if (_settledWireTurnIds.length > 32) {
          _settledWireTurnIds.remove(_settledWireTurnIds.first);
        }
      }
      if (!wireEmitted) {
        _display.clear();
        _timeline = _timeline.retainScopes(
          _priorDisplay
              .map((row) => row['_normal_projection_id'])
              .whereType<String>(),
        );
      }
      // Successful lifecycle settlement cannot establish an HTTP row match.
      if (wireEmitted && turnId != null && _display.isNotEmpty) {
        _receivedOutcomes.add(
          ReceivedScopeOutcome(
            id: turnId!,
            scopes: _display
                .map((row) => row['_normal_projection_id'])
                .whereType<String>(),
            outcome: completed == null
                ? ReceivedLifecycleOutcome.unknown
                : completed
                ? ReceivedLifecycleOutcome.completed
                : ReceivedLifecycleOutcome.failed,
          ),
        );
      }
      _cleanCompletedEmptySubmission(_history);
      _boundSettledPresentation();
      _error = error;
      _status = completed == null
          ? const GatewayTurnStatus(
              kind: 'reconciled_unknown',
              text:
                  'The gateway is idle. The previous turn’s outcome could not be confirmed.',
            )
          : null;
      _pendingInput.clear();
      if (wireEmitted) {
        _session.client?.forgetSettledServerRequestsForSession(localSessionId);
      }
      for (final row in _display) {
        row['_gateway_pending_response'] = false;
        if (completed == false) row['_chat_response_complete'] = false;
      }
      if (completed != false) {
        final claim = _persistedTurns[settledTurnId];
        if (claim != null) {
          _persistedTurns[settledTurnId!] = claim.asSettled();
        }
      }
      _reconcilePersistedTurns();
      _boundSettledPresentation();
      _marker = null;
      _additionalRestoredMarkers.clear();
      _terminalReceipt = null;
      _settling = false;
      _notify();
      // Avoid a redundant physical read when recovery already accepted a
      // post-admission page. This is a fetch decision only, never retirement or
      // proof of correspondence between any saved row and a received scope.
      if (wireEmitted &&
          !(_floor != null &&
              _history.any((row) => _responseRow(row, _floor!)))) {
        unawaited(_refreshSettledHistory(owned));
      }
      if (settledWireEmitted &&
          completed != null &&
          _session._background &&
          settledTurnId != null) {
        final kind = completed
            ? HermesNotificationKind.turnDone
            : HermesNotificationKind.turnError;
        if (notificationKindEnabled(kind)) {
          await _session.notifications.showKind(
            kind: kind,
            title: completed ? 'Hermes response ready' : 'Hermes turn failed',
            body: settledTitle,
            eventId: settledTurnId,
            sessionId: settledSessionId,
            connectionId: _session.connection.id,
            payload: jsonEncode({
              'sessionId': settledSessionId,
              'connectionId': _session.connection.id,
              'turnId': settledTurnId,
            }),
          );
        }
      }
    } catch (_) {
      if (_current(owned) && snapshot.hasActiveTurn) {
        phase = NormalGatewayTurnPhase.reconciling;
        _notify();
      }
    } finally {
      if (_current(owned)) {
        _settling = false;
        // The recovery flight owns its retry/backoff. Requeueing from inside
        // it would spin on a permanently rejected tombstone write.
        if (snapshot.hasActiveTurn && !_recovering) requestRecovery();
      }
    }
  }

  void _notifyAuxiliary(StreamEvent event) {
    if (!_session._background) return;
    final notification = event.type == 'notification.show'
        ? GatewayNotification.fromEventData(event.data)
        : null;
    final notice = GatewayNotice.fromGatewayEvent(event.type, event.data);
    if (notification == null && notice == null) return;
    final kind = notification != null
        ? (notification.key.startsWith('credits.')
              ? HermesNotificationKind.credits
              : HermesNotificationKind.plugin)
        : (notice!.kind == GatewayNoticeKind.background
              ? HermesNotificationKind.backgroundDone
              : HermesNotificationKind.plugin);
    unawaited(
      _session.notifications
          .showKind(
            kind: kind,
            title: 'Hermes — $title',
            body: notification?.text ?? notice!.text,
            eventId: notification?.key ?? notice!.identity,
            sessionId: storedSessionId ?? localSessionId,
            connectionId: _session.connection.id,
            payload: jsonEncode({
              'sessionId': storedSessionId ?? localSessionId,
              'connectionId': _session.connection.id,
            }),
          )
          .catchError((Object _) => false),
    );
  }

  void _notifyAttention(StreamEvent event, String requestId) {
    if (!_session._background) return;
    final approval = event.type == 'approval.request';
    unawaited(
      _session.notifications
          .showKind(
            kind: approval
                ? HermesNotificationKind.approval
                : HermesNotificationKind.input,
            title: approval
                ? 'Approval needed — $title'
                : 'Input needed — $title',
            // Sensitive request text and secrets never enter a notification.
            body: approval
                ? 'Open the chat to review the requested action.'
                : 'Open the chat to respond.',
            eventId: requestId,
            sessionId: storedSessionId ?? localSessionId,
            connectionId: _session.connection.id,
            actions: approval
                ? const [
                    TurnNotificationAction(id: 'approve', label: 'Approve'),
                    TurnNotificationAction(id: 'reject', label: 'Deny'),
                  ]
                : const [],
            payload: jsonEncode({
              'sessionId': storedSessionId ?? localSessionId,
              'connectionId': _session.connection.id,
              'requestId': requestId,
              ..._session._approvalOrigin,
            }),
          )
          .catchError((Object _) => false),
    );
  }

  Future<void> _refreshSettledHistory(int generation) async {
    final stored = storedSessionId;
    if (stored == null) return;
    try {
      final fresh = await _readLatestHistory(stored);
      if (!_current(generation) || snapshot.hasActiveTurn) return;
      if (!_acceptHistory(fresh)) return;
      _cleanCompletedEmptySubmission(fresh.rows);
      _notify();
    } catch (_) {
      /* keep the received final response */
    }
  }

  bool _cleanCompletedEmptySubmission(List<Map<String, dynamic>> fresh) {
    // Optional local prompt/empty-assistant scaffolds are not received output.
    // Never erase materialized scopes, imported scopes or child observers here.
    if (phase != NormalGatewayTurnPhase.completed ||
        !_canCleanEmptySubmission(fresh)) {
      return false;
    }
    _display.clear();
    _priorDisplay.clear();
    return true;
  }

  bool _canCleanEmptySubmission(List<Map<String, dynamic>> fresh) {
    // A stale page cannot clean even empty scaffolds. The floor is a read
    // eligibility guard here, never correlation for materialized receipts.
    if (_floor != null && !fresh.any((row) => _responseRow(row, _floor!))) {
      return false;
    }
    if (_timeline.runs.isNotEmpty ||
        _tools.isNotEmpty ||
        _hasTurnSubagentPresentation) {
      return false;
    }
    final rows = [..._priorDisplay, ..._display];
    if (rows.isEmpty || rows.length.isOdd) return false;
    for (var i = 0; i < rows.length; i += 2) {
      if (rows[i]['role'] != 'user' ||
          rows[i + 1]['role'] != 'assistant' ||
          (rows[i + 1]['content']?.toString().isNotEmpty ?? false) ||
          (rows[i + 1]['_gateway_reasoning']?.toString().isNotEmpty ?? false)) {
        return false;
      }
    }
    final user = fresh.lastIndexWhere((row) => row['role'] == 'user');
    return user >= 0 && fresh.skip(user + 1).any(_displayableResponseRow);
  }

  NormalGatewayChatSnapshot? _rejectForHandoff() {
    if (!snapshot.hasActiveTurn) return null;
    assert(!wireEmitted);
    _handoffRejection = StateError(
      'This chat was opened through its stored identity while another turn '
      'was admitted. The unsent prompt was not sent; retry explicitly after '
      'that turn finishes.',
    );
    _generation++; // fences held ensure/history/write-ahead and submit starts
    _reservation = null;
    _retryTimer?.cancel();
    _baselineTimer?.cancel();
    final baseline = _baselineRead;
    if (baseline != null && !baseline.isCompleted) baseline.complete(null);
    phase = NormalGatewayTurnPhase.failed;
    _error = _handoffRejection.toString();
    _display.clear();

    if (_listeners.isEmpty && _draftRestoreAllowed && _draftToRestore != null) {
      final handle = _draftHandle;
      if (handle != null) {
        unawaited(
          _restoreDraft(
            handle,
            _draftToRestore!,
            () => !_session._closed && _draftRestoreAllowed,
          ),
        );
      }
    }
    final marker = _marker;
    if (marker != null) {
      _session._retirePreWireMarker(marker);
    }
    return snapshot;
  }

  void _close() {
    _generation++;
    _retryTimer?.cancel();
    _baselineTimer?.cancel();
    final baseline = _baselineRead;
    if (baseline != null && !baseline.isCompleted) baseline.complete(null);
    _listeners.clear();
    _pendingInput.clear();
    _display.clear();
    _priorDisplay.clear();
    _settledPresentation.clear();
    _receivedOutcomes.clear();
    _persistedTurns.clear();
    _historyConfirmationRows = [];
    _historyPresentation.clear();
    _historyPresentationObservation = 0;
    _timeline = _timeline.clear();
    _tools.clear();
    _subagents.clear();
    _observedSubagents.clear();
    _inputUpdates.clear();
    _auxiliaryEvents.clear();
    _hasTurnSubagentPresentation = false;
  }

  Future<void> _restoreDraft(
    ComposerDraftHandle handle,
    String text,
    bool Function() isCurrent,
  ) =>
      _session.presentation?.restoreRejectedDraft(
        handle: handle,
        text: text,
        isCurrent: isCurrent,
      ) ??
      handle.save(text, isCurrent: isCurrent);
}

/// Session/account-scoped physical read authority. A redirect is NOT permission
/// to lend a losing owner's in-flight read to the winner. Admission and close
/// invalidate synchronously; only accepted success advances freshness.
class NormalGatewayHistoryRead {
  const NormalGatewayHistoryRead._(
    this._owner,
    this._local,
    this._binding,
    this._stored,
    this._generation,
    this._observation,
  );
  final NormalGatewayChatOwner _owner;
  final String _local;
  final String? _binding;
  final String _stored;
  final int _generation;
  final int _observation;

  bool get isAttached =>
      !_owner._session._closed &&
      _owner._redirect == null &&
      _owner.localSessionId == _local &&
      _owner.storedSessionId == _binding &&
      (_binding ?? _local) == _stored;

  bool get isSuperseded => _observation < _owner._historyObservation;

  bool get isCurrent =>
      isAttached && _owner._generation == _generation && !isSuperseded;
}

class _GatewayHistoryObservation {
  const _GatewayHistoryObservation(this.rows, this.read);
  final List<Map<String, dynamic>> rows;
  final NormalGatewayHistoryRead read;
  int get observation => read._observation;
}

/// Per-row read order survives alias transfer without lending latest authority.
class _HistoryPresentationRow {
  _HistoryPresentationRow(Map<String, dynamic> row, this.observation)
    : row = Map<String, dynamic>.unmodifiable({
        for (final entry in row.entries)
          entry.key: _immutableHistoryPresentationValue(entry.value),
      });

  final Map<String, dynamic> row;
  final int observation;
}

Object? _immutableHistoryPresentationValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key: _immutableHistoryPresentationValue(entry.value),
    });
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(
      value.map(_immutableHistoryPresentationValue),
    );
  }
  return value;
}

/// Received historical output, not a second admission or canonical transcript.
/// Observation order belongs to receipts, never a guessed HTTP interval.
class _SettledGatewayPresentation {
  const _SettledGatewayPresentation({
    required this.observation,
    required this.rows,
    required this.tools,
    required this.timeline,
    required this.outcomes,
  });
  final int observation;
  final List<Map<String, dynamic>> rows;
  final List<GatewayToolActivity> tools;
  final ChatTimeline timeline;
  final List<ReceivedScopeOutcome> outcomes;
}

/// Immutable received anchors owned by one positive persistence receipt. The
/// lifecycle settlement bit grants presentation cleanup only, never admission.
class _ReceivedTurnPersistence {
  _ReceivedTurnPersistence({
    required this.receipt,
    required Set<String> scopes,
    required List<GatewayToolActivity> tools,
    required this.afterObservation,
    this.settled = false,
  }) : scopes = Set<String>.unmodifiable(scopes),
       tools = List<GatewayToolActivity>.unmodifiable(tools);

  final NormalGatewayPersistedTurn receipt;
  final Set<String> scopes;
  final List<GatewayToolActivity> tools;
  final int afterObservation;
  final bool settled;

  _ReceivedTurnPersistence asSettled() => _ReceivedTurnPersistence(
    receipt: receipt,
    scopes: scopes,
    tools: tools,
    afterObservation: afterObservation,
    settled: true,
  );
}

bool _interactive(String type) => const {
  'approval.request',
  'clarify.request',
  'clarify.remaining',
  'sudo.request',
  'secret.request',
  'sudo.expire',
  'secret.expire',
  'request.cancel',
}.contains(type);

int? _numericFloor(List<Map<String, dynamic>> rows) {
  var floor = 0;
  for (final row in rows) {
    final id = row['id'];
    final value = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (value == null || value < 0) return null;
    if (value > floor) floor = value;
  }
  return floor;
}

// A fresh displayable response, never proof of a successful terminal outcome.
bool _responseRow(Map<String, dynamic> row, int floor) {
  final id = int.tryParse(row['id']?.toString() ?? '');
  return id != null && id > floor && _displayableResponseRow(row);
}

bool _displayableResponseRow(Map<String, dynamic> row) {
  final role = row['role'];
  return (role == 'assistant' || role == 'agent') &&
      (row['tool_calls'] == null ||
          row['tool_calls'] is List && (row['tool_calls'] as List).isEmpty) &&
      row['tool_call_id'] == null &&
      row['_gateway_interim'] != true &&
      row['interim'] != true &&
      row['is_interim'] != true &&
      row['finish_reason'] != 'tool_calls' &&
      (row['content']?.toString().trim().isNotEmpty ?? false);
}

String? _failure(Map<String, dynamic> state) {
  final status = state['status']?.toString().toLowerCase();
  final error = state['error']?.toString().trim() ?? '';
  if (error.isNotEmpty) return error;
  if (const {
    'error',
    'failed',
    'interrupted',
    'cancelled',
    'canceled',
  }.contains(status)) {
    return state['message']?.toString() ?? 'Gateway turn $status';
  }
  return null;
}
