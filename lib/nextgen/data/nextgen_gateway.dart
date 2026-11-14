// One signed-in gateway for NextGen: its REST client and one authenticated
// `/api/ws` JSON-RPC connection kept alive with a fresh single-use ticket per
// attempt, exponential backoff, and terminal states for an expired sign-in or
// a Host/Origin guard rejection.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/services/connection_manager.dart';
import '../../core/services/dashboard_api_client.dart';
import '../../core/services/desktop_gateway_client.dart';
import '../../core/services/hermes_sign_in.dart';
import '../../core/services/ws_client.dart';
import '../nextgen_l10n.dart';

enum NgConnectionPhase {
  idle,
  connecting,
  connected,
  reconnecting,
  sessionExpired,
  failed,
}

@immutable
class NgConnectionState {
  final NgConnectionPhase phase;
  final int attempt;
  final DateTime? retryAt;
  final String? reason;
  const NgConnectionState(
    this.phase, {
    this.attempt = 0,
    this.retryAt,
    this.reason,
  });

  bool get isConnected => phase == NgConnectionPhase.connected;

  String get label => switch (phase) {
    NgConnectionPhase.idle => ngL.ng_offline,
    NgConnectionPhase.connecting => ngL.ng_connecting,
    NgConnectionPhase.connected => ngL.ng_connected,
    NgConnectionPhase.reconnecting => ngL.ng_reconnecting,
    NgConnectionPhase.sessionExpired => ngL.ng_signed_out,
    NgConnectionPhase.failed => ngL.ng_connection_failed,
  };
}

/// A server→client request (approval, clarify, sudo, secret…) routed to the
/// chat whose runtime session it names.
class NgServerRequest {
  final GatewayServerRequest raw;
  final String? sessionId;
  NgServerRequest(this.raw) : sessionId = raw.params['session_id']?.toString();

  String get id => raw.id;
  String get method => raw.method;
  Map<String, dynamic> get params => raw.params;
}

class NextGenGateway extends ChangeNotifier {
  NextGenGateway(this.connection, {DashboardClient? dashboard})
    : url = GatewayUrl.parse(
        connection.singleLoginUrl ??
            DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
      ),
      dashboard = dashboard ?? DashboardClient.fromConnection(connection) {
    // NextGen reads chats from the dashboard for every connection, so stored
    // ids always match the ones its `/api/ws` socket resumes.
    api = DashboardApiClient.withDashboard(this.dashboard, profile: profile);
    writes = DashboardSessionWrites(this.dashboard, profile: profile);
  }

  final SavedConnection connection;
  final GatewayUrl url;
  final DashboardClient dashboard;

  /// Session/history REST surface (dashboard-backed for single sign-in).
  /// Assignable so tests can serve history pages.
  late DashboardApiClient api;
  late final DashboardSessionWrites writes;

  String? get profile {
    final p = connection.gatewayProfile?.trim();
    return p == null || p.isEmpty ? null : p;
  }

  NgConnectionState _state = const NgConnectionState(NgConnectionPhase.idle);
  NgConnectionState get state => _state;

  WsClient? _ws;
  WsClient? get socket => _ws;
  Map<String, dynamic>? readyFrame;

  final _events = StreamController<StreamEvent>.broadcast();
  final _requests = StreamController<NgServerRequest>.broadcast();
  final _reconnected = StreamController<void>.broadcast();

  /// Every server event on the current socket.
  Stream<StreamEvent> get events => _events.stream;

  /// Server→client requests on the current socket.
  Stream<NgServerRequest> get serverRequests => _requests.stream;

  /// Fires after each successful (re)connection, so open chats can resume.
  Stream<void> get reconnected => _reconnected.stream;

  /// Requests not yet answered, by id, so a chat opened later still sees them.
  final Map<String, NgServerRequest> openRequests = {};

  /// Live session id → stored session id, for every chat opened on this
  /// socket, so the sidebar can tell which stored chats are waiting on you.
  final Map<String, String> _storedByRuntime = {};

  void bindRuntime(String runtimeId, String storedId) {
    if (_storedByRuntime[runtimeId] == storedId) return;
    _storedByRuntime[runtimeId] = storedId;
    if (!_disposed) notifyListeners();
  }

  /// The stored session behind live session [runtimeId], when known.
  String? storedIdFor(String runtimeId) => _storedByRuntime[runtimeId];

  /// Stored ids of chats blocked on an approval, question or secret.
  Set<String> get needsYou => {
    for (final r in openRequests.values)
      if (r.sessionId != null) _storedByRuntime[r.sessionId!] ?? r.sessionId!,
  };

  /// Marks [id] answered (or cancelled) and tells listeners.
  void resolveRequest(String id) {
    if (openRequests.remove(id) != null && !_disposed) notifyListeners();
  }

  bool _running = false;
  bool _disposed = false;
  int _attempt = 0;
  int _ticketRejections = 0;
  Completer<void>? _wake;
  DateTime? _connectedAt;

  static const _backoff = [1, 2, 4, 8, 16, 30];
  static const answerableMethods = {
    'approval',
    'clarify',
    'sudo',
    'secret',
    'vault.unlock_prompt',
    'vault.code',
    'vault.save_login',
  };

  void _set(NgConnectionState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// Starts keeping the socket alive. Safe to call repeatedly.
  void start() {
    if (_running || _disposed) return;
    _running = true;
    unawaited(_loop());
  }

  /// Skips the current backoff wait, or restarts after a failure.
  void retry() {
    if (!_running) {
      _attempt = 0;
      _ticketRejections = 0;
      start();
      return;
    }
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<String?> _mintTicket() async {
    final res = await dashboard.apiRequest('POST', 'auth/ws-ticket');
    if (res.statusCode == 401) {
      _set(const NgConnectionState(NgConnectionPhase.sessionExpired));
      _running = false;
      return null;
    }
    if (res.statusCode == 429) {
      throw _Retry(ngL.ng_rate_limited_by_gateway);
    }
    if (res.statusCode != 200) {
      throw _Retry(
        ngL.ng_couldn_t_open_the_chat_connection(dashboardErrorMessage(res)),
      );
    }
    final data = jsonDecode(res.body);
    final ticket = data is Map ? data['ticket'] : null;
    if (ticket is! String || ticket.isEmpty) {
      throw _Retry(ngL.ng_the_gateway_returned_no_websocket_ticket);
    }
    return ticket;
  }

  Future<void> _loop() async {
    while (_running && !_disposed) {
      _attempt++;
      _set(NgConnectionState(NgConnectionPhase.connecting, attempt: _attempt));
      WsClient? client;
      try {
        String? ticket;
        try {
          ticket = await _mintTicket();
        } on DashboardHttpException catch (e) {
          if (e.statusCode == 401) {
            _set(const NgConnectionState(NgConnectionPhase.sessionExpired));
            _running = false;
            return;
          }
          rethrow;
        }
        if (ticket == null) return;
        client = WsClient(
          dashboard.baseUrl,
          ticket: ticket,
          profile: profile,
          clientCertificate: connection.clientCertificate,
          ticketInSubprotocol: true,
        );
        final closed = Completer<void>();
        client.onStreamEvent = (event) {
          if (!_events.isClosed) _events.add(event);
        };
        client.onServerRequest = (request) {
          if (!answerableMethods.contains(request.method)) return false;
          final wrapped = NgServerRequest(request);
          openRequests[request.id] = wrapped;
          if (!_requests.isClosed) _requests.add(wrapped);
          if (!_disposed) notifyListeners();
          return true;
        };
        client.onConnectionClosed = () {
          if (!closed.isCompleted) closed.complete();
        };
        await client.connect();
        readyFrame = await client.waitForGatewayReady();
        _ws = client;
        _connectedAt = DateTime.now();
        _ticketRejections = 0;
        _set(const NgConnectionState(NgConnectionPhase.connected));
        if (!_reconnected.isClosed) _reconnected.add(null);
        await closed.future;
        _ws = null;
        openRequests.clear();
        _storedByRuntime.clear();
        if (!_running || _disposed) return;
        final held =
            _connectedAt != null &&
            DateTime.now().difference(_connectedAt!) >
                const Duration(seconds: 30);
        if (held) _attempt = 0;
        await _backoffWait(ngL.ng_connection_lost);
      } on _Retry catch (e) {
        client?.close();
        await _backoffWait(e.message);
      } catch (e) {
        client?.close();
        _ws = null;
        if (!_running || _disposed) return;
        final message = e.toString();
        final status = RegExp(
          r"(?:status code:? |HTTP |')(\d{3})",
        ).firstMatch(message)?.group(1);
        if (status == '404') {
          _fail(ngL.ng_this_dashboard_has_no_chat_endpoint_2);
          return;
        }
        if (status == '403' || message.contains('4403')) {
          if (++_ticketRejections > 2) {
            _fail(ngL.ng_the_gateway_refused_the_chat_connection_2);
            return;
          }
        }
        if (message.contains('4401')) {
          if (++_ticketRejections > 2) {
            _set(const NgConnectionState(NgConnectionPhase.sessionExpired));
            _running = false;
            return;
          }
        }
        await _backoffWait(_short(message));
      }
    }
  }

  void _fail(String reason) {
    _running = false;
    _set(NgConnectionState(NgConnectionPhase.failed, reason: reason));
  }

  static String _short(String message) {
    final clean = message
        .replaceFirst('Exception: ', '')
        .replaceFirst(RegExp(r'^JsonRpcError\([^)]*\): '), '');
    return clean.length > 160 ? '${clean.substring(0, 160)}…' : clean;
  }

  Future<void> _backoffWait(String reason) async {
    if (!_running || _disposed) return;
    final seconds = _backoff[(_attempt - 1).clamp(0, _backoff.length - 1)];
    final retryAt = DateTime.now().add(Duration(seconds: seconds));
    _set(
      NgConnectionState(
        NgConnectionPhase.reconnecting,
        attempt: _attempt,
        retryAt: retryAt,
        reason: reason,
      ),
    );
    final wake = _wake = Completer<void>();
    await Future.any([
      wake.future,
      Future<void>.delayed(Duration(seconds: seconds)),
    ]);
  }

  /// Sends one JSON-RPC call on the live socket and returns its `result`.
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final ws = _ws;
    if (ws == null || !ws.isConnected) {
      throw StateError('Not connected to the gateway yet.');
    }
    final response = await ws.send(method, params, timeout: timeout);
    final error = response['error'];
    if (error != null) {
      throw JsonRpcError.fromGateway(
        method,
        error is Map ? error : const {},
        fallbackMessage: ngL.ng_the_gateway_refused(method),
      );
    }
    final result = response['result'];
    return result is Map<String, dynamic>
        ? result
        : result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  /// Waits until connected (or gives up after [timeout]).
  Future<WsClient> connected({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final ws = _ws;
    if (ws != null && ws.isConnected) return ws;
    start();
    retry();
    final done = Completer<WsClient>();
    void check() {
      final current = _ws;
      if (current != null && current.isConnected && !done.isCompleted) {
        done.complete(current);
      } else if ((_state.phase == NgConnectionPhase.sessionExpired ||
              _state.phase == NgConnectionPhase.failed) &&
          !done.isCompleted) {
        done.completeError(StateError(_state.reason ?? _state.label));
      }
    }

    addListener(check);
    check();
    try {
      return await done.future.timeout(timeout);
    } on TimeoutException {
      throw StateError(_state.reason ?? "Couldn't reach the gateway.");
    } finally {
      removeListener(check);
    }
  }

  void forgetRequest(String id) => resolveRequest(id);

  /// Feeds a server event as if it arrived on the socket.
  @visibleForTesting
  void debugEmit(StreamEvent event) => _events.add(event);

  /// Feeds a server request as if it arrived on the socket.
  @visibleForTesting
  void debugRequest(GatewayServerRequest request) {
    final wrapped = NgServerRequest(request);
    openRequests[request.id] = wrapped;
    _requests.add(wrapped);
    notifyListeners();
  }

  void stop() {
    _running = false;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _ws?.close();
    _ws = null;
    _set(const NgConnectionState(NgConnectionPhase.idle));
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    _events.close();
    _requests.close();
    _reconnected.close();
    api.close();
    dashboard.close();
    super.dispose();
  }
}

class _Retry implements Exception {
  final String message;
  const _Retry(this.message);
}
