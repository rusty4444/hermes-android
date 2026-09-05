import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'capability_registry.dart';
import 'connection_manager.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'projects_gateway_client.dart';
import 'ws_client.dart';

typedef DesktopAsyncEventCallback =
    void Function(String mobileSessionId, StreamEvent event);
typedef DesktopConnectionCallback =
    void Function(DesktopConnectionState connectionState);

enum DesktopConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Authenticated JSON-RPC transport for a Hermes Desktop remote gateway.
///
/// The mobile OpenAI-compatible endpoint remains available for legacy
/// profiles. When a connection supplies [SavedConnection.desktopGatewayUrl],
/// chat writes and interactive events use this one Desktop session transport.
class DesktopGatewayClient {
  final String _connectionId;
  final String _baseUrl;
  final DashboardClient _dashboard;
  final String _documentProfile;
  WsClient? _ws;
  final Map<String, String> _gatewaySessionIds = {};
  DesktopAsyncEventCallback? _asyncEventListener;
  DesktopConnectionCallback? _connectionListener;
  GatewayTurnCoordinatorRegistry? _turnCoordinatorRegistry;
  ProjectsGatewayClient? _projects;
  final CapabilityRegistry _capabilities = CapabilityRegistry();

  static const _asyncEventTypes = {
    'background.complete',
    'review.summary',
    'notification.show',
    'notification.clear',
    'subagent.spawn_requested',
    'subagent.start',
    'subagent.thinking',
    'subagent.tool',
    'subagent.progress',
    'subagent.complete',
  };

  DesktopGatewayClient._({
    required this._connectionId,
    required this._baseUrl,
    required this._dashboard,
    required this._documentProfile,
  });

  /// The canonical gateway origin for [connection].
  ///
  /// Extracted so the recovery-journal scope can be derived without opening a
  /// transport: an omitted default port and an explicit one must resolve to
  /// the same string, or the same gateway would be recorded under two scopes.
  static String normalizedGatewayBaseUrl(SavedConnection connection) {
    final override = connection.desktopGatewayUrl?.trim() ?? '';
    final overrideUri = override.isEmpty
        ? null
        : Uri.tryParse(
            override.contains('://') ? override : 'https://$override',
          );
    final isDistinctOverride =
        overrideUri != null &&
        overrideUri.host.isNotEmpty &&
        overrideUri.host.toLowerCase() != connection.host.toLowerCase();
    final raw = isDistinctOverride
        ? override
        : SavedConnection.joinBaseUrl(
            '${connection.useHttps ? 'https' : 'http'}://'
            '${connection.host}:${connection.dashboardPort}',
            connection.dashboardPrefix ?? '',
          );
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Desktop Gateway URL must be an http(s) URL');
    }
    final baseUri = uri.replace(query: '', fragment: '');
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    final port = baseUri.hasPort
        ? baseUri.port
        : baseUri.scheme == 'https'
        ? 443
        : 80;
    return SavedConnection.joinBaseUrl(
      '${baseUri.scheme}://${baseUri.host}:$port',
      pathPrefix,
    );
  }

  static String _endpointDigest(String baseUrl) =>
      sha256.convert(utf8.encode(baseUrl)).toString();

  /// The recovery-journal endpoint scope for [connection], or `null` when the
  /// connection names no usable Desktop Gateway.
  ///
  /// Returning `null` rather than throwing keeps callers that only want to
  /// *read* journal state — such as the Home digest — free of try/catch around
  /// a plain configuration fact.
  static String? endpointDigestFor(SavedConnection connection) {
    final hasExplicitOverride =
        connection.desktopGatewayUrl?.trim().isNotEmpty == true;
    final hasDashboardAuth =
        connection.dashboardProxied ||
        (connection.dashboardUsername?.trim().isNotEmpty == true &&
            connection.dashboardPassword?.trim().isNotEmpty == true);
    if (!hasExplicitOverride && !hasDashboardAuth) return null;
    try {
      return _endpointDigest(normalizedGatewayBaseUrl(connection));
    } on ArgumentError {
      return null;
    }
  }

  factory DesktopGatewayClient.fromConnection(SavedConnection connection) {
    final baseUrl = normalizedGatewayBaseUrl(connection);
    final baseUri = Uri.parse(baseUrl);
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    return DesktopGatewayClient._(
      connectionId: connection.id,
      baseUrl: baseUrl,
      dashboard: DashboardClient(
        host: baseUri.host,
        // The normalized base URL always carries an explicit port, so this
        // never falls back to a scheme default.
        port: baseUri.port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: pathPrefix,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
      ),
      documentProfile: documentIntakeProfileForConnection(connection),
    );
  }

  Future<_DesktopGatewaySession> _connect(String mobileSessionId) async {
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      final mappedSessionId = _gatewaySessionIds[mobileSessionId];
      if (mappedSessionId != null) {
        return _DesktopGatewaySession(existing, mappedSessionId);
      }
      final gatewaySessionId = await _resumeOrCreate(existing, mobileSessionId);
      _gatewaySessionIds[mobileSessionId] = gatewaySessionId;
      return _DesktopGatewaySession(existing, gatewaySessionId);
    }

    _connectionListener?.call(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    existing?.close();
    _gatewaySessionIds.clear();
    final ticket = await _dashboard.mintWebSocketTicket();
    final client = WsClient(_baseUrl, ticket: ticket);
    _installAsyncEventBridge(client);
    client.onConnectionChanged = (connected) {
      if (connected) {
        _connectionListener?.call(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _connectionListener?.call(DesktopConnectionState.disconnected);
      }
    };
    try {
      await client.connect();
      _ws = client;
      final gatewaySessionId = await _resumeOrCreate(client, mobileSessionId);
      _gatewaySessionIds[mobileSessionId] = gatewaySessionId;
      return _DesktopGatewaySession(client, gatewaySessionId);
    } catch (_) {
      client.close();
      if (identical(_ws, client)) _ws = null;
      _connectionListener?.call(DesktopConnectionState.disconnected);
      rethrow;
    }
  }

  Future<String> _resumeOrCreate(
    WsClient client,
    String mobileSessionId,
  ) async {
    try {
      return await client.resumeSession(mobileSessionId);
    } on JsonRpcError catch (error) {
      if (error.code != 4007 &&
          !error.message.toLowerCase().contains('session not found')) {
        rethrow;
      }
      // New mobile chats do not exist in Hermes yet. Create them with the
      // mobile-generated ID so REST history and the Desktop runtime share one
      // stable identity. Existing sessions always take the resume path.
      return client.createOrResumeSession(mobileSessionId);
    }
  }

  Future<void> ensureSession(String sessionId) async {
    await _connect(sessionId);
  }

  /// Server-owned Hermes Projects for this gateway.
  ///
  /// Projects are connection-scoped, not session-scoped, so this opens the
  /// shared socket without resuming or creating any chat session. An older
  /// gateway without `projects.*` surfaces a [ProjectsUnsupportedException]
  /// instead of an error state, so callers can fall back to local grouping.
  ProjectsGatewayClient get projects {
    return _projects ??= ProjectsGatewayClient((method, params) async {
      final client = await _connectControl();
      return client.send(method, params);
    }, capabilities: _capabilities);
  }

  /// What this gateway advertises or has been proven to support.
  ///
  /// Populated from `gateway.ready` on every connect and refined by the
  /// outcome of real calls, so a feature can degrade politely on an older
  /// gateway instead of failing.
  CapabilityRegistry get capabilities => _capabilities;

  /// Opens (or reuses) the gateway socket without binding it to a session.
  Future<WsClient> _connectControl() async {
    final existing = _ws;
    if (existing != null && existing.isConnected) return existing;

    _connectionListener?.call(
      existing == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    existing?.close();
    _gatewaySessionIds.clear();
    final ticket = await _dashboard.mintWebSocketTicket();
    final client = WsClient(_baseUrl, ticket: ticket);
    _installAsyncEventBridge(client);
    client.onConnectionChanged = (connected) {
      if (connected) {
        _connectionListener?.call(DesktopConnectionState.connected);
      } else if (identical(_ws, client)) {
        _gatewaySessionIds.clear();
        _connectionListener?.call(DesktopConnectionState.disconnected);
      }
    };
    try {
      await client.connect();
      _ws = client;
      return client;
    } catch (_) {
      client.close();
      if (identical(_ws, client)) _ws = null;
      _connectionListener?.call(DesktopConnectionState.disconnected);
      rethrow;
    }
  }

  /// Creates the source-only recovery-v2 registry without changing any legacy
  /// session, submit, interrupt, or event route in this client.
  GatewayTurnCoordinatorRegistry enableTurnRecoveryCoordinator({
    GatewayTurnJournal? journal,
  }) {
    return _turnCoordinatorRegistry ??= GatewayTurnCoordinatorRegistry(
      connectionId: _connectionId,
      endpointDigest: _endpointDigest(_baseUrl),
      journal: journal ?? GatewayTurnJournal(),
      freshSocketFactory: () async {
        final ticket = await _dashboard.mintWebSocketTicket();
        return WsClient(_baseUrl, ticket: ticket);
      },
    );
  }

  void setConnectionListener(DesktopConnectionCallback? listener) {
    _connectionListener = listener;
  }

  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
  }) async {
    final gateway = await _connect(sessionId);
    return gateway.client.attachFile(
      sessionId: gateway.sessionId,
      name: name,
      dataUrl: dataUrl,
      sourceChannel: 'hermes_mobile',
      sourceProfile: _documentProfile,
    );
  }

  Future<void> submitPrompt({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.submitPrompt(
      text,
      sessionId: gateway.sessionId,
      onEvent: onEvent,
    );
  }

  /// Receives only durable, session-scoped events that may arrive after a
  /// prompt's terminal event. Active-turn events continue through [submitPrompt]
  /// so they are never delivered twice.
  void setAsyncEventListener(DesktopAsyncEventCallback? listener) {
    _asyncEventListener = listener;
  }

  void _installAsyncEventBridge(WsClient client) {
    // Every socket greets us with gateway.ready; that greeting is where the
    // capability registry learns what this Hermes instance offers.
    _capabilities.bindTo(client);
    client.onStreamEvent = (event) {
      if (!_asyncEventTypes.contains(event.type)) return;
      final gatewaySessionId = event.data['session_id']?.toString();
      String? mobileSessionId;
      if (gatewaySessionId != null && gatewaySessionId.isNotEmpty) {
        for (final entry in _gatewaySessionIds.entries) {
          if (entry.value == gatewaySessionId) {
            mobileSessionId = entry.key;
            break;
          }
        }
      } else if (_gatewaySessionIds.length == 1) {
        mobileSessionId = _gatewaySessionIds.keys.single;
      }
      if (mobileSessionId == null) return;
      _asyncEventListener?.call(mobileSessionId, event);
    };
  }

  /// Interrupts the active turn in the Desktop gateway runtime.
  Future<bool> interruptPrompt({required String sessionId}) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      return false;
    }
    await client.interruptSession(gatewaySessionId);
    return true;
  }

  /// Resolves an approval against the gateway session mapped to this mobile
  /// chat. Approval requests are session-keyed and do not carry a request ID.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
  }) async {
    final gatewaySessionId = _gatewaySessionIds[sessionId];
    final client = _ws;
    if (gatewaySessionId == null || client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await client.respondToApproval(sessionId: gatewaySessionId, choice: choice);
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) async {
    final client = _connectedClient();
    await client.respondToSudo(requestId: requestId, password: password);
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) async {
    final client = _connectedClient();
    await client.respondToSecret(requestId: requestId, value: value);
  }

  Future<void> respondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    final client = _connectedClient();
    await client.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
  }

  WsClient _connectedClient() {
    final client = _ws;
    if (client == null || !client.isConnected) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    return client;
  }

  /// The profile-scoped catalog and default shown by Hermes Desktop.  Keeping
  /// these reads on the Dashboard endpoint means Android never guesses model
  /// names or providers from the OpenAI-compatible API.
  Future<Map<String, dynamic>> getModelInfo() => _dashboard.getModelInfo();

  Future<Map<String, dynamic>> getModelOptions() =>
      _dashboard.getModelOptions();

  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionModel(
      sessionId: gateway.sessionId,
      provider: provider,
      model: model,
    );
  }

  Future<String> getSessionReasoning(String sessionId) async {
    final gateway = await _connect(sessionId);
    return gateway.client.getSessionReasoning(gateway.sessionId);
  }

  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionReasoning(
      sessionId: gateway.sessionId,
      effort: effort,
    );
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final gateway = await _connect(sessionId);
    await gateway.client.setSessionTitle(gateway.sessionId, title);
  }

  Future<Map<String, dynamic>> branchSession({
    required String sessionId,
    required String name,
  }) async {
    final gateway = await _connect(sessionId);
    return gateway.client.branchSession(gateway.sessionId, name: name);
  }

  void close() {
    _asyncEventListener = null;
    _connectionListener = null;
    _projects = null;
    _ws?.close();
    _ws = null;
    _gatewaySessionIds.clear();
    final turnCoordinatorRegistry = _turnCoordinatorRegistry;
    _turnCoordinatorRegistry = null;
    if (turnCoordinatorRegistry != null) {
      final closing = turnCoordinatorRegistry.closeAll();
      unawaited(closing.then<void>((_) {}, onError: (_, _) {}));
    }
    _dashboard.close();
  }
}

String documentIntakeProfileForConnection(SavedConnection connection) {
  final candidates = <String>[
    connection.gatewayPrefix ?? '',
    Uri.tryParse(connection.desktopGatewayUrl ?? '')?.path ?? '',
  ];
  final segments = candidates
      .expand((value) => value.toLowerCase().split('/'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (segments.contains('personal')) return 'personal';
  if (segments.contains('pro') || segments.contains('professional')) {
    return 'pro';
  }
  return 'organizator';
}

class _DesktopGatewaySession {
  final WsClient client;
  final String sessionId;

  const _DesktopGatewaySession(this.client, this.sessionId);
}
