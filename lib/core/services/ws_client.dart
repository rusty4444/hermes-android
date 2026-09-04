// WebSocket client for the Hermes gateway JSON-RPC API (/api/ws).
// Supports both request-response calls AND server-pushed streaming events.
//
// Wire protocol: newline-delimited JSON-RPC 2.0, same as the TUI gateway.
// After submitting a prompt, the server pushes stream events and finally
// a JSON-RPC response with the same id.
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';

Object? _deepFreezeJson(Object? value) {
  if (value is Map) {
    final copy = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) continue;
      copy[entry.key as String] = _deepFreezeJson(entry.value);
    }
    return Map<String, dynamic>.unmodifiable(copy);
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_deepFreezeJson));
  }
  return value;
}

Map<String, dynamic> _deepFreezeJsonMap(Map<String, dynamic> value) {
  return _deepFreezeJson(value)! as Map<String, dynamic>;
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.whereType<String>().toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalJsonValue(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJsonValue).toList();
  return value;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalJsonValue(value));

/// A JSON-RPC error response from the gateway.
class JsonRpcError implements Exception {
  final String method;
  final String message;
  final int? code;
  final String? reason;
  final Map<String, dynamic> data;

  JsonRpcError(
    this.method,
    this.message, {
    this.code,
    this.reason,
    Map<String, dynamic>? data,
  }) : data = _deepFreezeJsonMap(data ?? const <String, dynamic>{});

  factory JsonRpcError.fromGateway(
    String method,
    Map<dynamic, dynamic> error, {
    required String fallbackMessage,
  }) {
    final rawData = error['data'];
    final data = rawData is Map
        ? <String, dynamic>{
            for (final entry in rawData.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : const <String, dynamic>{};
    return JsonRpcError(
      method,
      error['message'] is String ? error['message'] as String : fallbackMessage,
      code: error['code'] is int ? error['code'] as int : null,
      reason: data['reason'] is String ? data['reason'] as String : null,
      data: data,
    );
  }

  /// Server guidance only. Callers must never automatically resubmit a turn.
  bool get safeToResubmit => data['safe_to_resubmit'] == true;

  @override
  String toString() => 'JsonRpcError($method): $message';
}

JsonRpcError _gatewayResponseError(
  String method,
  Object? error, {
  required String fallbackMessage,
}) {
  if (error is Map) {
    return JsonRpcError.fromGateway(
      method,
      error,
      fallbackMessage: fallbackMessage,
    );
  }
  return JsonRpcError(method, fallbackMessage);
}

/// Event types streamed from the gateway during a prompt submission.
class StreamEvent {
  final String type; // 'tool_call', 'tool_result', 'assistant', 'session', etc.
  final Map<String, dynamic> data;
  final bool isComplete; // true when the assistant message is done
  final String? sessionId;
  final String? turnId;
  final int? seq;
  final String? messageId;
  final Map<String, dynamic> envelope;

  StreamEvent({
    required this.type,
    required Map<String, dynamic> data,
    this.isComplete = false,
    this.sessionId,
    this.turnId,
    this.seq,
    this.messageId,
    Map<String, dynamic>? envelope,
  }) : data = _deepFreezeJsonMap(data),
       envelope = _deepFreezeJsonMap(envelope ?? const <String, dynamic>{});
}

/// Gateway-side file reference returned by `file.attach`.
class RemoteFileAttachment {
  final String name;
  final String path;
  final String refText;
  final bool uploaded;
  final bool? atlasIntakeAccepted;
  final String? atlasIntakeStatus;
  final String? atlasRelativePath;

  const RemoteFileAttachment({
    required this.name,
    required this.path,
    required this.refText,
    required this.uploaded,
    this.atlasIntakeAccepted,
    this.atlasIntakeStatus,
    this.atlasRelativePath,
  });
}

typedef StreamCallback = void Function(StreamEvent event);
typedef ConnectionCallback = void Function(bool connected);
typedef GatewayReadyCallback = void Function(Map<String, dynamic> frame);

/// WebSocket client for the Hermes JSON-RPC gateway.
class WsClient {
  final String baseUrl;
  final String? _token;
  final String? _ticket;
  IOWebSocketChannel? _channel;
  bool _connected = false;
  int _nextId = 1;
  int _connectionGeneration = 0;
  int _nextConnectionClosedListenerToken = 1;

  /// Pending requests: id -> (completer, timer).
  final Map<int, _Pending> _pending = {};

  /// Active stream subscriptions: id -> callback.
  final Map<int, List<StreamCallback>> _streams = {};

  /// Gateway events are emitted independently of a JSON-RPC request ID. Keep
  /// per-session listeners so one active session cannot consume another one's
  /// streamed response.
  final Map<String, List<StreamCallback>> _sessionStreams = {};
  final Map<int, _ConnectionClosedListener> _connectionClosedListeners = {};
  Completer<Map<String, dynamic>>? _gatewayReadyCompleter;
  Map<String, dynamic>? _gatewayReadyFrame;
  String? _gatewayReadyCanonical;
  JsonRpcError? _gatewayReadyFailure;

  /// Global stream listener (receives all untargeted events).
  StreamCallback? onStreamEvent;
  ConnectionCallback? onConnectionChanged;
  GatewayReadyCallback? onGatewayReady;

  factory WsClient(String baseUrl, {String? token, String? ticket}) {
    return WsClient._(baseUrl, token, ticket);
  }

  WsClient._(this.baseUrl, this._token, this._ticket);

  /// Connect to the WebSocket gateway.
  Future<void> connect() async {
    if (_connected) return;
    if (_channel != null) {
      throw StateError('A WebSocket connection is already in progress');
    }
    final generation = ++_connectionGeneration;
    _gatewayReadyFrame = null;
    _gatewayReadyCanonical = null;
    _gatewayReadyFailure = null;
    final readyCompleter = Completer<Map<String, dynamic>>();
    _gatewayReadyCompleter = readyCompleter;
    // A transport can close before a caller starts waiting for gateway.ready.
    // Observe that error future immediately; the waiter still receives it.
    readyCompleter.future.ignore();
    final wsUrl = buildWebSocketUrl(baseUrl, token: _token, ticket: _ticket);
    final channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _channel = channel;
    channel.stream.listen(
      (message) => _handleMessage(message, generation),
      onError: (_) => _handleClosedConnection(generation),
      onDone: () {
        _handleClosedConnection(generation);
      },
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 15));
      if (generation != _connectionGeneration || _channel != channel) {
        throw JsonRpcError(
          'connect',
          'Connection closed during WebSocket setup',
          reason: 'connection_closed',
        );
      }
      _connected = true;
      try {
        onConnectionChanged?.call(true);
      } catch (_) {
        // Transport observers cannot turn a live socket into setup failure.
      }
    } catch (_) {
      _handleClosedConnection(generation);
      try {
        await channel.sink.close();
      } catch (_) {
        // Preserve the original setup failure after closing this exact socket.
      }
      rethrow;
    }
  }

  void _handleClosedConnection(int generation) {
    if (generation != _connectionGeneration) return;
    // Invalidate this socket before any completion or observer can enqueue
    // more work. Buffered callbacks from it now fail the generation guard.
    _connectionGeneration = generation + 1;
    final wasConnected = _connected || _channel != null;
    _connected = false;
    _channel = null;
    // Reject all pending request-response calls.
    for (var entry in _pending.values) {
      entry.timer?.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(
          JsonRpcError(
            entry.method,
            'Desktop gateway connection closed',
            reason: 'connection_closed',
          ),
        );
      }
    }
    _pending.clear();
    final closeError =
        _gatewayReadyFailure ??
        JsonRpcError(
          'gateway.ready',
          'Connection closed before gateway.ready',
          reason: 'connection_closed',
        );
    _gatewayReadyFailure = closeError;
    _gatewayReadyFrame = null;
    _gatewayReadyCanonical = null;
    final ready = _gatewayReadyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(closeError);
    }
    _gatewayReadyCompleter = null;
    final listenersToNotify = _connectionClosedListeners.entries
        .where((entry) => entry.value.generation == generation)
        .map((entry) => entry.value.callback)
        .toList(growable: false);
    _connectionClosedListeners.removeWhere(
      (_, listener) => listener.generation == generation,
    );
    _streams.clear();
    _sessionStreams.clear();
    for (final listener in listenersToNotify) {
      try {
        listener();
      } catch (_) {
        // One watcher cannot prevent the remaining close cleanup.
      }
    }
    if (wasConnected) {
      try {
        onConnectionChanged?.call(false);
      } catch (_) {
        // Observer failures cannot keep a rejected socket logically active.
      }
    }
  }

  int _addConnectionClosedListener(void Function() callback) {
    final token = _nextConnectionClosedListenerToken++;
    _connectionClosedListeners[token] = _ConnectionClosedListener(
      _connectionGeneration,
      callback,
    );
    return token;
  }

  void _removeConnectionClosedListener(int token) {
    _connectionClosedListeners.remove(token);
  }

  /// Produces the gateway `/api/ws` URL. Secured Desktop gateways use a
  /// single-use ticket; insecure legacy gateways still use a session token.
  static String buildWebSocketUrl(
    String baseUrl, {
    String? token,
    String? ticket,
  }) {
    final socketBase = baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$socketBase/api/ws');
    final credential = ticket?.trim().isNotEmpty == true
        ? {'ticket': ticket!.trim()}
        : token?.trim().isNotEmpty == true
        ? {'token': token!.trim()}
        : const <String, String>{};
    return uri.replace(queryParameters: credential).toString();
  }

  /// Handle inbound messages.
  void _handleMessage(dynamic msg, int generation) {
    if (generation != _connectionGeneration) return;
    try {
      Map<String, dynamic> data;
      if (msg is String) {
        data = jsonDecode(msg) as Map<String, dynamic>;
      } else if (msg is Map<String, dynamic>) {
        data = msg;
      } else {
        return;
      }

      final id = data['id'];
      final method = data['method'] as String?;
      final params = data['params'];

      // Server-pushed events have the JSON-RPC method `event` and carry their
      // actual type/session/payload inside params.
      if (method == 'event' && id == null && params is Map<String, dynamic>) {
        if (params['type'] == 'gateway.ready') {
          _handleGatewayReady(data, generation);
          return;
        }
        final event = parseGatewayEvent(params);
        if (event != null) _dispatchEvent(event);
        return;
      }

      // Response to a request (has id, may have method for streaming completion)
      if (id != null) {
        final pending = _pending[id];
        if (pending != null) {
          _pending.remove(id);
          pending.timer?.cancel();
          if (method == null || params == null) {
            _streams.remove(id);
          }
          pending.completer.complete(data);
          // Internal request state is terminal before observers see the final
          // stream event. Observer failures cannot retain a pending request.
          if (method != null && params != null) {
            _dispatchStreamEvent(
              id,
              method,
              params is Map<String, dynamic> ? params : {},
            );
          }
          return;
        }
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  void _handleGatewayReady(Map<String, dynamic> data, int generation) {
    if (generation != _connectionGeneration) return;
    final frame = _deepFreezeJsonMap(data);
    final canonical = _canonicalJson(frame);
    final pinned = _gatewayReadyCanonical;
    if (pinned == null) {
      _gatewayReadyCanonical = canonical;
      _gatewayReadyFrame = frame;
      final ready = _gatewayReadyCompleter;
      if (ready != null && !ready.isCompleted) ready.complete(frame);
      try {
        onGatewayReady?.call(frame);
      } catch (_) {
        // Capability observers cannot change the pinned socket authority.
      }
      return;
    }
    if (pinned == canonical) return;

    _gatewayReadyFailure = JsonRpcError(
      'gateway.ready',
      'Gateway ready frame changed on the active connection',
      reason: 'gateway_ready_drift',
    );
    final channel = _channel;
    _handleClosedConnection(generation);
    channel?.sink.close();
  }

  /// Dispatch a server-pushed event to registered listeners.
  static StreamEvent? parseGatewayEvent(Map<String, dynamic> params) {
    final rawType = params['type'];
    if (rawType is! String || rawType.isEmpty) return null;
    final payload = params['payload'];
    final data = payload is Map<String, dynamic>
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    final sessionCandidates = <Object?>[params['session_id'], params['sid']];
    String? sessionId;
    for (final candidate in sessionCandidates) {
      if (candidate is String &&
          candidate.isNotEmpty &&
          candidate.length <= 256 &&
          candidate.trim() == candidate &&
          !candidate.codeUnits.any(
            (unit) => unit < 32 || unit >= 127 && unit <= 159,
          )) {
        sessionId = candidate;
        break;
      }
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      data['session_id'] = sessionId;
    }
    final rawTurnId = params['turn_id'];
    final rawSeq = params['seq'];
    final rawMessageId = params['message_id'];
    final turnId =
        rawTurnId is String &&
            rawTurnId.isNotEmpty &&
            rawTurnId.length <= 256 &&
            rawTurnId.trim() == rawTurnId &&
            !rawTurnId.codeUnits.any(
              (unit) => unit < 32 || unit >= 127 && unit <= 159,
            )
        ? rawTurnId
        : null;
    final messageId =
        rawMessageId is String &&
            rawMessageId.isNotEmpty &&
            rawMessageId.length <= 256 &&
            rawMessageId.trim() == rawMessageId &&
            !rawMessageId.codeUnits.any(
              (unit) => unit < 32 || unit >= 127 && unit <= 159,
            )
        ? rawMessageId
        : null;
    return StreamEvent(
      type: rawType,
      data: data,
      isComplete:
          rawType == 'message.complete' ||
          rawType == 'error' ||
          rawType == 'turn.end' ||
          rawType == 'turn.error',
      sessionId: sessionId,
      turnId: turnId,
      seq: rawSeq is int && rawSeq > 0 ? rawSeq : null,
      messageId: messageId,
      envelope: params,
    );
  }

  /// Wait for the capability-bearing greeting emitted by this exact socket.
  Future<Map<String, dynamic>> waitForGatewayReady({
    Duration timeout = const Duration(seconds: 15),
  }) {
    final failure = _gatewayReadyFailure;
    if (failure != null) return Future<Map<String, dynamic>>.error(failure);
    final frame = _gatewayReadyFrame;
    if (frame != null) return Future<Map<String, dynamic>>.value(frame);
    final ready = _gatewayReadyCompleter;
    if (ready == null) {
      throw StateError('connect must run before waiting for gateway.ready');
    }
    return ready.future.timeout(timeout);
  }

  void _dispatchEvent(StreamEvent event) {
    try {
      onStreamEvent?.call(event);
    } catch (_) {
      // Global observers cannot block the session-scoped listener chain.
    }
    final sessionId = event.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    final listeners = _sessionStreams[sessionId];
    if (listeners == null) return;
    for (final listener in List<StreamCallback>.from(listeners)) {
      try {
        listener(event);
      } catch (_) {
        // One session observer cannot block other listeners or cleanup.
      }
    }
  }

  /// Dispatch a streaming event to a specific request's subscribers.
  void _dispatchStreamEvent(int id, String type, Map<String, dynamic> data) {
    final listeners = _streams.remove(id);
    if (listeners == null) return;
    final event = StreamEvent(
      type: type,
      data: data,
      isComplete: type == 'done' || type == 'error',
    );
    for (final listener in List<StreamCallback>.from(listeners)) {
      try {
        listener(event);
      } catch (_) {
        // Stream observers run only after internal completion and cleanup.
      }
    }
  }

  /// Send a JSON-RPC method call and wait for response.
  Future<Map<String, dynamic>> send(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_connected || _channel == null) {
      throw Exception('Not connected');
    }

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      _pending.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(JsonRpcError(method, 'Timeout'));
      }
    });

    _pending[id] = _Pending(method, completer, timer);
    _channel!.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': id,
      }),
    );
    return completer.future;
  }

  /// Send a JSON-RPC method call and receive streaming events.
  /// Returns the final response when the stream completes.
  Future<Map<String, dynamic>> sendStreaming(
    String method,
    Map<String, dynamic> params, {
    StreamCallback? onEvent,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!_connected || _channel == null) {
      throw Exception('Not connected');
    }

    final id = _nextId++;
    if (onEvent != null) {
      _streams[id] = [onEvent];
    }
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      _pending.remove(id);
      _streams.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(JsonRpcError(method, 'Timeout'));
      }
    });

    _pending[id] = _Pending(method, completer, timer);
    _channel!.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': id,
      }),
    );
    return completer.future;
  }

  /// Sends `prompt.submit`, then waits for the gateway's terminal turn event.
  /// The RPC acknowledgement only confirms that the turn was accepted; it is
  /// not the end of streamed model output.
  Future<void> submitPrompt(
    String message, {
    required String sessionId,
    required StreamCallback onEvent,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final completion = Completer<void>();
    final terminalFuture = completion.future;
    // A close before the RPC acknowledgement rejects both the pending request
    // and this terminal watcher. Observe the secondary future immediately so
    // the request error remains the single surfaced failure.
    terminalFuture.ignore();
    late final StreamCallback listener;
    Timer? timer;
    final closeListenerToken = _addConnectionClosedListener(() {
      if (!completion.isCompleted) {
        completion.completeError(
          JsonRpcError(
            'prompt.submit',
            'Desktop gateway connection closed',
            reason: 'connection_closed',
          ),
        );
      }
    });

    listener = (event) {
      if (event.isComplete && !completion.isCompleted) {
        if (event.type == 'error' || event.type == 'turn.error') {
          completion.completeError(
            JsonRpcError(
              'prompt.submit',
              event.data['message']?.toString() ?? 'Gateway turn failed',
            ),
          );
        } else {
          completion.complete();
        }
      }
      try {
        onEvent(event);
      } catch (_) {
        // Terminal state and other session listeners remain authoritative.
      }
    };

    final listeners = _sessionStreams.putIfAbsent(sessionId, () => []);
    listeners.add(listener);
    timer = Timer(timeout, () {
      if (!completion.isCompleted) {
        completion.completeError(JsonRpcError('prompt.submit', 'Timeout'));
      }
    });

    try {
      final response = await send('prompt.submit', {
        'session_id': sessionId,
        'text': message,
      });
      final error = response['error'];
      if (error != null) {
        throw _gatewayResponseError(
          'prompt.submit',
          error,
          fallbackMessage: 'Unknown error',
        );
      }
      await terminalFuture;
    } finally {
      timer.cancel();
      _removeConnectionClosedListener(closeListenerToken);
      final current = _sessionStreams[sessionId];
      current?.remove(listener);
      if (current != null && current.isEmpty) {
        _sessionStreams.remove(sessionId);
      }
    }
  }

  /// Cooperatively interrupts the active turn for one gateway session.
  Future<void> interruptSession(String sessionId) async {
    final response = await send('session.interrupt', {'session_id': sessionId});
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'session.interrupt',
        error,
        fallbackMessage: 'Gateway interrupt failed',
      );
    }
  }

  /// Resolves the single in-flight Hermes approval for one gateway session.
  Future<void> respondToApproval({
    required String sessionId,
    required String choice,
  }) async {
    const allowedChoices = {'once', 'session', 'always', 'deny'};
    if (!allowedChoices.contains(choice)) {
      throw ArgumentError.value(
        choice,
        'choice',
        'Unsupported approval choice',
      );
    }
    final response = await send('approval.respond', {
      'session_id': sessionId,
      'choice': choice,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'approval.respond',
        error,
        fallbackMessage: 'Gateway approval failed',
      );
    }
  }

  Future<void> respondToSudo({
    required String requestId,
    required String password,
  }) {
    return _respondToSensitivePrompt(
      method: 'sudo.respond',
      requestId: requestId,
      valueKey: 'password',
      value: password,
    );
  }

  Future<void> respondToSecret({
    required String requestId,
    required String value,
  }) {
    return _respondToSensitivePrompt(
      method: 'secret.respond',
      requestId: requestId,
      valueKey: 'value',
      value: value,
    );
  }

  Future<void> respondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'A Hermes request ID is required',
      );
    }
    final params = <String, dynamic>{
      'request_id': requestId,
      'answer': answer,
    };
    if (questionId != null && questionId.trim().isNotEmpty) {
      params['question_id'] = questionId;
    }
    final response = await send('clarify.respond', params);
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'clarify.respond',
        error,
        fallbackMessage: 'Gateway clarification failed',
      );
    }
  }

  Future<void> _respondToSensitivePrompt({
    required String method,
    required String requestId,
    required String valueKey,
    required String value,
  }) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'A Hermes request ID is required',
      );
    }
    final response = await send(method, {
      'request_id': requestId,
      valueKey: value,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        method,
        error,
        fallbackMessage: 'Gateway response failed',
      );
    }
  }

  /// Resume an existing session.
  Future<String> resumeSession(String sessionId) async {
    final result = await send('session.resume', {'session_id': sessionId});
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'session.resume',
        result['error'],
        fallbackMessage: 'Unknown error',
      );
    }
    return result['result']?['session_id'] as String? ?? sessionId;
  }

  Future<void> setSessionTitle(String sessionId, String title) async {
    final response = await send('session.title', {
      'session_id': sessionId,
      'title': title,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'session.title',
        error,
        fallbackMessage: 'Could not rename session',
      );
    }
  }

  Future<Map<String, dynamic>> branchSession(
    String sessionId, {
    required String name,
  }) async {
    final response = await send('session.branch', {
      'session_id': sessionId,
      'name': name,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'session.branch',
        error,
        fallbackMessage: 'Could not branch session',
      );
    }
    final result = response['result'];
    if (result is Map<String, dynamic>) return result;
    throw JsonRpcError('session.branch', 'Gateway returned no branch');
  }

  /// Submit a message to the active session with streaming.
  /// Returns the final response and streams events via callback.
  Future<String> sendMessageStreaming(
    String message, {
    required String sessionId,
    StreamCallback? onEvent,
  }) async {
    await submitPrompt(
      message,
      sessionId: sessionId,
      onEvent: onEvent ?? (_) {},
    );
    return sessionId;
  }

  /// Submit a message to the active session (non-streaming, backward-compatible).
  Future<String> sendMessage(String message) async {
    throw UnsupportedError(
      'Use sendMessageStreaming with a gateway session ID instead.',
    );
  }

  /// Uploads one file or image to a remote Desktop gateway and returns the
  /// canonical `@file:` reference that must be included in the following turn.
  Future<RemoteFileAttachment> attachFile({
    required String sessionId,
    required String name,
    required String dataUrl,
    String path = '',
    String? sourceChannel,
    String? sourceProfile,
  }) async {
    final params = <String, dynamic>{
      'session_id': sessionId,
      'name': name,
      'path': path,
      'data_url': dataUrl,
    };
    if (sourceChannel?.isNotEmpty == true) {
      params['source_channel'] = sourceChannel;
    }
    if (sourceProfile?.isNotEmpty == true) {
      params['source_profile'] = sourceProfile;
    }
    final response = await send('file.attach', params);
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'file.attach',
        error,
        fallbackMessage: 'Unknown error',
      );
    }
    final result = response['result'];
    if (result is! Map<String, dynamic> || result['attached'] != true) {
      throw JsonRpcError('file.attach', 'Gateway did not attach the file');
    }
    final refText = result['ref_text']?.toString() ?? '';
    if (refText.isEmpty) {
      throw JsonRpcError('file.attach', 'Gateway returned no file reference');
    }
    final atlasIntake = result['atlas_intake'];
    return RemoteFileAttachment(
      name: result['name']?.toString() ?? name,
      path: result['path']?.toString() ?? path,
      refText: refText,
      uploaded: result['uploaded'] == true,
      atlasIntakeAccepted: atlasIntake is Map<String, dynamic>
          ? atlasIntake['accepted'] == true
          : null,
      atlasIntakeStatus: atlasIntake is Map<String, dynamic>
          ? atlasIntake['status']?.toString()
          : null,
      atlasRelativePath: atlasIntake is Map<String, dynamic>
          ? atlasIntake['relative_path']?.toString()
          : null,
    );
  }

  /// Create a new chat session.
  Future<String> createSession({String? model}) async {
    final params = <String, dynamic>{};
    if (model != null) params['model'] = model;
    final result = await send('session.create', params);
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'session.create',
        result['error'],
        fallbackMessage: 'Unknown error',
      );
    }
    return result['result']?['session_id'] as String? ?? '';
  }

  /// Resume an existing session via session.create (which starts a new
  /// agent process for the given session ID). This works for sessions
  /// that exist in the REST API but aren't active in the gateway.
  Future<String> createOrResumeSession(String sessionId) async {
    final result = await send('session.create', {'session_id': sessionId});
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'session.create',
        result['error'],
        fallbackMessage: 'Unknown error',
      );
    }
    return result['result']?['session_id'] as String? ?? sessionId;
  }

  /// Applies a model only to one live gateway session.  Hermes interprets the
  /// `--session` flag as a persistent per-session override; it must never be
  /// replaced with a profile-wide config write from the mobile client.
  Future<void> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
  }) async {
    final result = await send('config.set', {
      'session_id': sessionId,
      'key': 'model',
      'value': buildSessionModelValue(provider: provider, model: model),
    });
    if (result['error'] != null) {
      throw _gatewayResponseError(
        'config.set',
        result['error'],
        fallbackMessage: 'Model switch failed',
      );
    }
    final payload = result['result'];
    if (payload is Map && payload['confirm_required'] == true) {
      throw JsonRpcError(
        'config.set',
        payload['confirm_message']?.toString() ??
            'This model needs confirmation before it can be selected.',
      );
    }
  }

  /// Returns the effective reasoning effort for one live gateway session.
  Future<String> getSessionReasoning(String sessionId) async {
    final response = await send('config.get', {
      'session_id': sessionId,
      'key': 'reasoning',
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'config.get',
        error,
        fallbackMessage: 'Could not read reasoning effort',
      );
    }
    final result = response['result'];
    if (result is! Map) {
      throw JsonRpcError('config.get', 'Gateway returned no reasoning effort');
    }
    return normalizeReasoningEffort(result['value']);
  }

  /// Applies reasoning effort only to one live gateway session.
  Future<void> setSessionReasoning({
    required String sessionId,
    required String effort,
  }) async {
    final normalized = effort.trim().toLowerCase();
    if (!validReasoningEfforts.contains(normalized)) {
      throw ArgumentError.value(
        effort,
        'effort',
        'Unsupported reasoning effort',
      );
    }
    final response = await send('config.set', {
      'session_id': sessionId,
      'key': 'reasoning',
      'value': normalized,
    });
    final error = response['error'];
    if (error != null) {
      throw _gatewayResponseError(
        'config.set',
        error,
        fallbackMessage: 'Reasoning effort switch failed',
      );
    }
  }

  static const validReasoningEfforts = <String>{
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
    'ultra',
  };

  static String normalizeReasoningEffort(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return validReasoningEfforts.contains(normalized) ? normalized : 'medium';
  }

  /// Builds the gateway `/model` value used for one live session.
  ///
  /// A bare `custom` provider represents the endpoint already stored in the
  /// profile's `model.base_url`; it is not a resolvable named provider before
  /// the deferred agent build finishes. Omitting the redundant provider flag
  /// lets Hermes resolve that endpoint from the active profile immediately.
  static String buildSessionModelValue({
    required String provider,
    required String model,
  }) {
    final normalizedProvider = provider.trim();
    final modelValue = model.trim();
    if (normalizedProvider.isEmpty || normalizedProvider == 'custom') {
      return '$modelValue --session';
    }
    return '$modelValue --provider $normalizedProvider --session';
  }

  bool get isConnected => _connected;

  /// Close the connection.
  void close() {
    if (!_connected && _channel == null) return;
    final generation = _connectionGeneration;
    final channel = _channel;
    _handleClosedConnection(generation);
    channel?.sink.close();
  }
}

class _Pending {
  final String method;
  final Completer<Map<String, dynamic>> completer;
  final Timer? timer;
  _Pending(this.method, this.completer, this.timer);
}

class _ConnectionClosedListener {
  final int generation;
  final void Function() callback;

  const _ConnectionClosedListener(this.generation, this.callback);
}
