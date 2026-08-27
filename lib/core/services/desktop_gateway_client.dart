import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'connection_manager.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_journal.dart';
import 'mtls_client.dart';
import 'websocket_transport.dart';
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
  final GatewayWebSocketChannelFactory _channelFactory;
  WsClient? _ws;
  WsClient? _connectingWs;
  Future<WsClient>? _socketConnection;
  final Map<String, String> _gatewaySessionIds = {};
  final Map<String, Future<_DesktopGatewaySession>> _sessionConnections = {};
  DesktopAsyncEventCallback? _asyncEventListener;
  DesktopConnectionCallback? _connectionListener;
  GatewayTurnCoordinatorRegistry? _turnCoordinatorRegistry;
  int _lifecycleGeneration = 0;
  bool _closed = false;

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
    required this._channelFactory,
  });

  factory DesktopGatewayClient.fromConnection(
    SavedConnection connection, {
    MtlsTransport? mtlsTransport,
    MtlsWebSocketTransport? mtlsWebSocketTransport,
  }) {
    final raw = connection.desktopGatewayUrl?.trim() ?? '';
    if (raw.isEmpty) {
      throw ArgumentError('A Desktop Gateway URL is required for this feature');
    }
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('Desktop Gateway URL must be an http(s) URL');
    }
    if (uri.scheme != 'https') {
      throw ArgumentError('Desktop Gateway credentials require HTTPS');
    }
    final baseUri = uri.replace(query: '', fragment: '');
    final pathPrefix = baseUri.path == '/' ? '' : baseUri.path;
    final port = baseUri.hasPort
        ? baseUri.port
        : baseUri.scheme == 'https'
        ? 443
        : 80;
    final baseUrl = SavedConnection.joinBaseUrl(
      '${baseUri.scheme}://${baseUri.host}:$port',
      pathPrefix,
    );
    final alias = connection.mtlsCertificateAlias?.trim();
    if (connection.mtlsEnabled && (alias == null || alias.isEmpty)) {
      throw ArgumentError(
        'An mTLS certificate is required for the Desktop Gateway',
      );
    }
    final channelFactory = connection.mtlsEnabled
        ? (Uri socketUri) => MtlsWebSocketChannel.connect(
            socketUri,
            alias: alias!,
            transport: mtlsWebSocketTransport,
          )
        : IoGatewayWebSocketChannel.connect;
    return DesktopGatewayClient._(
      connectionId: connection.id,
      baseUrl: baseUrl,
      dashboard: DashboardClient(
        host: baseUri.host,
        port: port,
        useHttps: baseUri.scheme == 'https',
        pathPrefix: pathPrefix,
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
        httpClient: GatewayHttpClientFactory.create(
          connection,
          mtlsTransport: mtlsTransport,
        ),
      ),
      documentProfile: documentIntakeProfileForConnection(connection),
      channelFactory: channelFactory,
    );
  }

  WsClient _createSocketClient(DashboardWebSocketCredential credential) =>
      WsClient(
        _baseUrl,
        token: credential.token,
        ticket: credential.ticket,
        channelFactory: _channelFactory,
      );

  Future<_DesktopGatewaySession> _connect(String mobileSessionId) {
    if (_closed) {
      return Future.error(StateError('The Desktop Gateway client is closed'));
    }
    final existing = _ws;
    if (existing != null && existing.isConnected) {
      final mappedSessionId = _gatewaySessionIds[mobileSessionId];
      if (mappedSessionId != null) {
        return Future.value(_DesktopGatewaySession(existing, mappedSessionId));
      }
    }

    final pending = _sessionConnections[mobileSessionId];
    if (pending != null) return pending;
    final future = _connectSession(mobileSessionId);
    _sessionConnections[mobileSessionId] = future;
    future.then<void>(
      (_) {
        if (identical(_sessionConnections[mobileSessionId], future)) {
          _sessionConnections.remove(mobileSessionId);
        }
      },
      onError: (_, _) {
        if (identical(_sessionConnections[mobileSessionId], future)) {
          _sessionConnections.remove(mobileSessionId);
        }
      },
    );
    return future;
  }

  Future<_DesktopGatewaySession> _connectSession(String mobileSessionId) async {
    final client = await _connectedSocket();
    _requireOpen();
    final mappedSessionId = _gatewaySessionIds[mobileSessionId];
    if (mappedSessionId != null) {
      return _DesktopGatewaySession(client, mappedSessionId);
    }
    final gatewaySessionId = await _resumeOrCreate(client, mobileSessionId);
    _requireOpen();
    if (!identical(_ws, client) || !client.isConnected) {
      throw StateError('The Desktop Gateway connection changed');
    }
    _gatewaySessionIds[mobileSessionId] = gatewaySessionId;
    return _DesktopGatewaySession(client, gatewaySessionId);
  }

  Future<WsClient> _connectedSocket() {
    _requireOpen();
    final existing = _ws;
    if (existing != null && existing.isConnected) return Future.value(existing);
    final pending = _socketConnection;
    if (pending != null) return pending;
    final generation = _lifecycleGeneration;
    final future = _openSocket(generation, existing);
    _socketConnection = future;
    future.then<void>(
      (_) {
        if (identical(_socketConnection, future)) _socketConnection = null;
      },
      onError: (_, _) {
        if (identical(_socketConnection, future)) _socketConnection = null;
      },
    );
    return future;
  }

  Future<WsClient> _openSocket(int generation, WsClient? previous) async {
    _connectionListener?.call(
      previous == null
          ? DesktopConnectionState.connecting
          : DesktopConnectionState.reconnecting,
    );
    _ws = null;
    previous?.close();
    _gatewaySessionIds.clear();
    final credential = await _dashboard.getWebSocketCredential();
    _requireGeneration(generation);
    final client = _createSocketClient(credential);
    _connectingWs = client;
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
      _requireGeneration(generation);
      if (!identical(_connectingWs, client)) {
        throw StateError('The Desktop Gateway connection was superseded');
      }
      _connectingWs = null;
      _ws = client;
      return client;
    } catch (_) {
      client.close();
      if (identical(_connectingWs, client)) _connectingWs = null;
      if (identical(_ws, client)) _ws = null;
      if (!_closed && generation == _lifecycleGeneration) {
        _connectionListener?.call(DesktopConnectionState.disconnected);
      }
      rethrow;
    }
  }

  void _requireOpen() {
    if (_closed) throw StateError('The Desktop Gateway client is closed');
  }

  void _requireGeneration(int generation) {
    _requireOpen();
    if (generation != _lifecycleGeneration) {
      throw StateError('The Desktop Gateway connection was superseded');
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

  /// Creates the source-only recovery-v2 registry without changing any legacy
  /// session, submit, interrupt, or event route in this client.
  GatewayTurnCoordinatorRegistry enableTurnRecoveryCoordinator({
    GatewayTurnJournal? journal,
  }) {
    return _turnCoordinatorRegistry ??= GatewayTurnCoordinatorRegistry(
      connectionId: _connectionId,
      endpointDigest: sha256.convert(utf8.encode(_baseUrl)).toString(),
      journal: journal ?? GatewayTurnJournal(),
      freshSocketFactory: () async {
        _requireOpen();
        final generation = _lifecycleGeneration;
        final credential = await _dashboard.getWebSocketCredential();
        _requireGeneration(generation);
        return _createSocketClient(credential);
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
  }) async {
    final client = _connectedClient();
    await client.respondToClarify(requestId: requestId, answer: answer);
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
    if (_closed) return;
    _closed = true;
    _lifecycleGeneration++;
    _asyncEventListener = null;
    _connectionListener = null;
    _connectingWs?.close();
    _connectingWs = null;
    _ws?.close();
    _ws = null;
    _socketConnection = null;
    _gatewaySessionIds.clear();
    _sessionConnections.clear();
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
