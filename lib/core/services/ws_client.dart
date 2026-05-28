/// WebSocket client for the Hermes gateway JSON-RPC API (/api/ws).
/// Supports both request-response calls AND server-pushed streaming events.
///
/// Wire protocol: newline-delimited JSON-RPC 2.0, same as the TUI gateway.
/// After submitting a prompt, the server pushes stream events and finally
/// a JSON-RPC response with the same id.
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';

/// A JSON-RPC error response from the gateway.
class JsonRpcError implements Exception {
  final String method;
  final String message;
  final int? code;

  JsonRpcError(this.method, this.message, {this.code});

  @override
  String toString() => 'JsonRpcError($method): $message';
}

/// Event types streamed from the gateway during a prompt submission.
class StreamEvent {
  final String type; // 'tool_call', 'tool_result', 'assistant', 'session', etc.
  final Map<String, dynamic> data;
  final bool isComplete; // true when the assistant message is done

  const StreamEvent({
    required this.type,
    required this.data,
    this.isComplete = false,
  });
}

typedef StreamCallback = void Function(StreamEvent event);

/// WebSocket client for the Hermes JSON-RPC gateway.
class WsClient {
  final String baseUrl;
  final String? _token;
  IOWebSocketChannel? _channel;
  bool _connected = false;
  int _nextId = 1;

  /// Pending requests: id -> (completer, timer).
  final Map<int, _Pending> _pending = {};

  /// Active stream subscriptions: id -> callback.
  final Map<int, List<StreamCallback>> _streams = {};

  /// Global stream listener (receives all untargeted events).
  StreamCallback? onStreamEvent;

  WsClient(this.baseUrl, {String? token}) : _token = token;

  /// Connect to the WebSocket gateway.
  Future<void> connect() async {
    if (_connected) return;
    var wsUrl = '${baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://')}/api/ws';
    // Pass session token as query param if available
    if (_token != null && _token!.isNotEmpty) {
      wsUrl = '$wsUrl?token=${Uri.encodeQueryComponent(_token!)}';
    }
    _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _connected = true;
    _channel!.stream.listen(_handleMessage, onDone: () {
      _connected = false;
      _channel = null;
      // Reject all pending requests
      for (var entry in _pending.values) {
        entry.timer?.cancel();
        if (!entry.completer.isCompleted) {
          entry.completer.completeError(Exception('Connection closed'));
        }
      }
      _pending.clear();
    });
  }

  /// Handle inbound messages.
  void _handleMessage(dynamic msg) {
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

      // Server-pushed event (has method but no id)
      if (method != null && id == null && params != null) {
        _dispatchEvent(method, params is Map<String, dynamic> ? params : {});
        return;
      }

      // Response to a request (has id, may have method for streaming completion)
      if (id != null) {
        final pending = _pending[id];
        if (pending != null) {
          // If this is a stream completion (method field present), also dispatch
          if (method != null && params != null) {
            _dispatchStreamEvent(id, method, params is Map<String, dynamic> ? params : {});
          }
          _pending.remove(id);
          pending.timer?.cancel();
          pending.completer.complete(data);
          return;
        }
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  /// Dispatch a server-pushed event to registered listeners.
  void _dispatchEvent(String type, Map<String, dynamic> data) {
    final event = StreamEvent(type: type, data: data, isComplete: type == 'done' || type == 'error');
    onStreamEvent?.call(event);
  }

  /// Dispatch a streaming event to a specific request's subscribers.
  void _dispatchStreamEvent(int id, String type, Map<String, dynamic> data) {
    final listeners = _streams[id];
    if (listeners == null) return;
    final event = StreamEvent(type: type, data: data, isComplete: type == 'done' || type == 'error');
    for (var listener in listeners) {
      listener(event);
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
    _channel!.sink.add(jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': id,
    }));

    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      _pending.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(JsonRpcError(method, 'Timeout'));
      }
    });

    _pending[id] = _Pending(completer, timer);
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

    _channel!.sink.add(jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': id,
    }));

    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      _pending.remove(id);
      _streams.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(JsonRpcError(method, 'Timeout'));
      }
    });

    _pending[id] = _Pending(completer, timer);
    return completer.future;
  }

  /// Resume an existing session.
  Future<String> resumeSession(String sessionId) async {
    final result = await send('session.resume', {'session_id': sessionId});
    if (result['error'] != null) {
      final errMap = result['error'] as Map<String, dynamic>;
      final errorMsg = errMap['message'] as String?;
      throw JsonRpcError('session.resume', errorMsg ?? 'Unknown error');
    }
    return result['result']?['session_id'] as String? ?? sessionId;
  }

  /// Submit a message to the active session with streaming.
  /// Returns the final response and streams events via callback.
  Future<String> sendMessageStreaming(
    String message, {
    StreamCallback? onEvent,
  }) async {
    final result = await sendStreaming('prompt.submit', {'message': message}, onEvent: onEvent);
    if (result['error'] != null) {
      final errMap = result['error'] as Map<String, dynamic>;
      final errorMsg = errMap['message'] as String?;
      throw JsonRpcError('prompt.submit', errorMsg ?? 'Unknown error');
    }
    return result['result']?['session_id'] as String? ?? '';
  }

  /// Submit a message to the active session (non-streaming, backward-compatible).
  Future<String> sendMessage(String message) async {
    final result = await send('prompt.submit', {'message': message});
    if (result['error'] != null) {
      final errMap = result['error'] as Map<String, dynamic>;
      final errorMsg = errMap['message'] as String?;
      throw JsonRpcError('prompt.submit', errorMsg ?? 'Unknown error');
    }
    return result['result']?['session_id'] as String? ?? '';
  }

  /// Create a new chat session.
  Future<String> createSession({String? model}) async {
    final params = <String, dynamic>{};
    if (model != null) params['model'] = model;
    final result = await send('session.create', params);
    if (result['error'] != null) {
      final errMap = result['error'] as Map<String, dynamic>;
      final errorMsg = errMap['message'] as String?;
      throw JsonRpcError('session.create', errorMsg ?? 'Unknown error');
    }
    return result['result']?['session_id'] as String? ?? '';
  }

  bool get isConnected => _connected;

  /// Close the connection.
  void close() {
    for (var entry in _pending.values) {
      entry.timer?.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(Exception('Connection closed'));
      }
    }
    _pending.clear();
    _streams.clear();
    _connected = false;
    _channel?.sink.close();
    _channel = null;
  }
}

class _Pending {
  final Completer<Map<String, dynamic>> completer;
  final Timer? timer;
  _Pending(this.completer, this.timer);
}
