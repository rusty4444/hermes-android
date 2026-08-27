import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/connection.dart';
import 'websocket_transport.dart';

class MtlsCertificate {
  final String alias;
  final String label;

  const MtlsCertificate({required this.alias, required this.label});

  factory MtlsCertificate.fromMap(Map<Object?, Object?> map) {
    final alias = map['alias'];
    final label = map['label'];
    if (alias is! String ||
        alias.isEmpty ||
        label is! String ||
        label.isEmpty) {
      throw const FormatException('Invalid mTLS certificate response');
    }
    return MtlsCertificate(alias: alias, label: label);
  }
}

class MtlsRequest {
  final String requestId;
  final String alias;
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Uint8List? body;

  const MtlsRequest({
    required this.requestId,
    required this.alias,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
}

class MtlsResponseHead {
  final int statusCode;
  final String? reasonPhrase;
  final int? contentLength;
  final Map<String, String> headers;

  const MtlsResponseHead({
    required this.statusCode,
    required this.reasonPhrase,
    required this.contentLength,
    required this.headers,
  });

  factory MtlsResponseHead.fromMap(Map<Object?, Object?> map) {
    final statusCode = map['statusCode'];
    if (statusCode is! int) {
      throw const FormatException('Invalid mTLS response status');
    }
    final rawHeaders = map['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        if (entry.key is String && entry.value is String) {
          headers[entry.key as String] = entry.value as String;
        }
      }
    }
    final length = map['contentLength'];
    return MtlsResponseHead(
      statusCode: statusCode,
      reasonPhrase: map['reasonPhrase'] as String?,
      contentLength: length is int && length >= 0 ? length : null,
      headers: headers,
    );
  }
}

sealed class MtlsResponseEvent {
  final String requestId;

  const MtlsResponseEvent(this.requestId);
}

class MtlsDataEvent extends MtlsResponseEvent {
  final Uint8List data;

  const MtlsDataEvent(super.requestId, this.data);
}

class MtlsDoneEvent extends MtlsResponseEvent {
  const MtlsDoneEvent(super.requestId);
}

class MtlsErrorEvent extends MtlsResponseEvent {
  final String message;

  const MtlsErrorEvent(super.requestId, this.message);
}

class MtlsWebSocketDataEvent extends MtlsResponseEvent {
  final String data;

  const MtlsWebSocketDataEvent(super.requestId, this.data);
}

class MtlsWebSocketClosedEvent extends MtlsResponseEvent {
  final int code;
  final String reason;

  const MtlsWebSocketClosedEvent(
    super.requestId, {
    required this.code,
    required this.reason,
  });
}

class MtlsWebSocketErrorEvent extends MtlsResponseEvent {
  final String message;

  const MtlsWebSocketErrorEvent(super.requestId, this.message);
}

abstract interface class MtlsTransport {
  Stream<MtlsResponseEvent> get events;

  Future<MtlsCertificate?> chooseCertificate({
    String? host,
    int? port,
    String? alias,
  });

  Future<MtlsCertificate?> describeCertificate(String alias);

  Future<MtlsResponseHead> startRequest(MtlsRequest request);

  Future<bool> cancelRequest(String requestId);
}

abstract interface class MtlsWebSocketTransport {
  Stream<MtlsResponseEvent> get events;

  Future<void> startWebSocket({
    required String socketId,
    required String alias,
    required Uri url,
  });

  Future<void> sendWebSocket({required String socketId, required String data});

  Future<void> closeWebSocket({
    required String socketId,
    int code = 1000,
    String reason = '',
  });
}

class MethodChannelMtlsTransport
    implements MtlsTransport, MtlsWebSocketTransport {
  static const _methodChannel = MethodChannel(
    'com.hermesagent.hermes_android/mtls',
  );
  static const _eventChannel = EventChannel(
    'com.hermesagent.hermes_android/mtls_events',
  );
  static final MethodChannelMtlsTransport instance =
      MethodChannelMtlsTransport._();

  late final Stream<MtlsResponseEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map(_decodeEvent);

  MethodChannelMtlsTransport._();

  @override
  Stream<MtlsResponseEvent> get events => _events;

  @override
  Future<MtlsCertificate?> chooseCertificate({
    String? host,
    int? port,
    String? alias,
  }) async {
    _requireAndroid();
    final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'chooseCertificate',
      <String, Object?>{'host': host, 'port': port, 'alias': alias},
    );
    return result == null ? null : MtlsCertificate.fromMap(result);
  }

  @override
  Future<MtlsCertificate?> describeCertificate(String alias) async {
    _requireAndroid();
    final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'describeCertificate',
      <String, Object?>{'alias': alias},
    );
    return result == null ? null : MtlsCertificate.fromMap(result);
  }

  @override
  Future<MtlsResponseHead> startRequest(MtlsRequest request) async {
    _requireAndroid();
    await _methodChannel.invokeMethod<void>('waitUntilEventStreamReady');
    final result = await _methodChannel
        .invokeMapMethod<Object?, Object?>('startRequest', <String, Object?>{
          'requestId': request.requestId,
          'alias': request.alias,
          'method': request.method,
          'url': request.url.toString(),
          'headers': request.headers,
          'body': request.body,
        });
    if (result == null) {
      throw PlatformException(
        code: 'invalid_response',
        message: 'The native mTLS client returned no response.',
      );
    }
    return MtlsResponseHead.fromMap(result);
  }

  @override
  Future<bool> cancelRequest(String requestId) async {
    _requireAndroid();
    return await _methodChannel.invokeMethod<bool>(
          'cancelRequest',
          <String, Object?>{'requestId': requestId},
        ) ??
        false;
  }

  @override
  Future<void> startWebSocket({
    required String socketId,
    required String alias,
    required Uri url,
  }) async {
    _requireAndroid();
    await _methodChannel.invokeMethod<void>('waitUntilEventStreamReady');
    await _methodChannel.invokeMethod<void>('startWebSocket', <String, Object?>{
      'socketId': socketId,
      'alias': alias,
      'url': url.toString(),
    });
  }

  @override
  Future<void> sendWebSocket({
    required String socketId,
    required String data,
  }) async {
    _requireAndroid();
    final sent = await _methodChannel.invokeMethod<bool>(
      'sendWebSocket',
      <String, Object?>{'socketId': socketId, 'data': data},
    );
    if (sent != true) {
      throw PlatformException(
        code: 'websocket_send_failed',
        message: 'The secure WebSocket message could not be sent.',
      );
    }
  }

  @override
  Future<void> closeWebSocket({
    required String socketId,
    int code = 1000,
    String reason = '',
  }) async {
    _requireAndroid();
    await _methodChannel.invokeMethod<void>('closeWebSocket', <String, Object?>{
      'socketId': socketId,
      'code': code,
      'reason': reason,
    });
  }

  static MtlsResponseEvent _decodeEvent(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid mTLS response event');
    }
    final requestId = value['requestId'];
    final type = value['type'];
    if (requestId is! String || type is! String) {
      throw const FormatException('Invalid mTLS response event');
    }
    switch (type) {
      case 'data':
        final data = value['data'];
        if (data is Uint8List) return MtlsDataEvent(requestId, data);
        if (data is List) {
          return MtlsDataEvent(requestId, Uint8List.fromList(data.cast<int>()));
        }
        throw const FormatException('Invalid mTLS response data');
      case 'done':
        return MtlsDoneEvent(requestId);
      case 'error':
        return MtlsErrorEvent(
          requestId,
          value['message'] is String
              ? value['message'] as String
              : 'The mTLS request failed.',
        );
      case 'websocketData':
        final data = value['data'];
        if (data is! String) {
          throw const FormatException('Invalid mTLS WebSocket data');
        }
        return MtlsWebSocketDataEvent(requestId, data);
      case 'websocketClosed':
        final code = value['code'];
        final reason = value['reason'];
        if (code is! int || reason is! String) {
          throw const FormatException('Invalid mTLS WebSocket close event');
        }
        return MtlsWebSocketClosedEvent(requestId, code: code, reason: reason);
      case 'websocketError':
        return MtlsWebSocketErrorEvent(
          requestId,
          value['message'] is String
              ? value['message'] as String
              : 'The secure WebSocket connection failed.',
        );
      default:
        throw const FormatException('Unknown mTLS response event');
    }
  }

  static void _requireAndroid() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('mTLS gateway connections require Android.');
    }
  }
}

class MtlsWebSocketChannel implements GatewayWebSocketChannel {
  static const _uuid = Uuid();

  final String alias;
  final MtlsWebSocketTransport transport;
  final String _socketId = _uuid.v4();
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final Completer<void> _readyCompleter = Completer<void>();
  final Completer<void> _doneCompleter = Completer<void>();
  late final StreamSubscription<MtlsResponseEvent> _eventSubscription;
  late final _MtlsWebSocketSink _sink;
  Future<void> _sendChain = Future.value();
  bool _closing = false;
  bool _closed = false;

  MtlsWebSocketChannel._({
    required this.alias,
    required this.transport,
    required Uri url,
  }) {
    _sink = _MtlsWebSocketSink(this);
    _eventSubscription = transport.events.listen(
      _handleEvent,
      onError: _handleTransportError,
    );
    unawaited(_start(url));
  }

  factory MtlsWebSocketChannel.connect(
    Uri url, {
    required String alias,
    MtlsWebSocketTransport? transport,
  }) {
    if (url.scheme.toLowerCase() != 'wss') {
      throw ArgumentError.value(url, 'url', 'mTLS WebSockets require WSS');
    }
    return MtlsWebSocketChannel._(
      alias: alias,
      transport: transport ?? MethodChannelMtlsTransport.instance,
      url: url,
    );
  }

  Future<void> _start(Uri url) async {
    try {
      await transport.startWebSocket(
        socketId: _socketId,
        alias: alias,
        url: url,
      );
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  StreamSink<dynamic> get sink => _sink;

  @override
  Stream<dynamic> get stream => _controller.stream;

  Future<void> _enqueue(Object? data) {
    if (_closing || _closed) {
      return Future.error(StateError('The WebSocket is closing.'));
    }
    if (data is! String) {
      return Future.error(
        ArgumentError.value(data, 'data', 'Only text messages are supported'),
      );
    }
    _sendChain = _sendChain.then((_) async {
      await ready;
      if (_closed) throw StateError('The WebSocket is closed.');
      await transport.sendWebSocket(socketId: _socketId, data: data);
    });
    _sendChain.catchError(_fail);
    return _sendChain;
  }

  Future<void> _close([int? code, String? reason]) async {
    if (_closed || _closing) return _doneCompleter.future;
    _closing = true;
    try {
      await transport
          .closeWebSocket(
            socketId: _socketId,
            code: code ?? 1000,
            reason: reason ?? '',
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Local teardown must not wait indefinitely for a dead native socket.
    }
    _finish();
    return _doneCompleter.future;
  }

  void _handleEvent(MtlsResponseEvent event) {
    if (event.requestId != _socketId || _closed) return;
    switch (event) {
      case MtlsWebSocketDataEvent():
        _controller.add(event.data);
      case MtlsWebSocketClosedEvent():
        _finish();
      case MtlsWebSocketErrorEvent():
        _fail(StateError(event.message));
      case MtlsDataEvent() || MtlsDoneEvent() || MtlsErrorEvent():
        return;
    }
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    _fail(error, stackTrace);
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, stackTrace);
    }
    _controller.addError(error, stackTrace);
    _finish();
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(
        StateError('The secure WebSocket closed before connecting.'),
      );
    }
    unawaited(_eventSubscription.cancel());
    unawaited(_controller.close());
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}

class _MtlsWebSocketSink implements StreamSink<dynamic> {
  final MtlsWebSocketChannel _channel;

  const _MtlsWebSocketSink(this._channel);

  @override
  void add(dynamic data) {
    unawaited(_channel._enqueue(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _channel._fail(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      await _channel._enqueue(data);
    }
  }

  @override
  Future<void> close() => _channel._close();

  @override
  Future<void> get done => _channel._doneCompleter.future;
}

class GatewayHttpClientFactory {
  static http.Client create(
    SavedConnection connection, {
    MtlsTransport? mtlsTransport,
  }) {
    if (!connection.mtlsEnabled) return http.Client();
    final alias = connection.mtlsCertificateAlias?.trim();
    if (alias == null || alias.isEmpty) {
      return _UnavailableMtlsHttpClient();
    }
    return MtlsHttpClient(
      alias: alias,
      transport: mtlsTransport ?? MethodChannelMtlsTransport.instance,
    );
  }
}

class MtlsHttpClient extends http.BaseClient {
  static const _uuid = Uuid();

  final String alias;
  final MtlsTransport transport;
  final Map<String, StreamController<List<int>>> _responses = {};
  final Set<String> _cancelledRequestIds = {};
  late final StreamSubscription<MtlsResponseEvent> _eventSubscription;
  bool _closed = false;

  MtlsHttpClient({required this.alias, required this.transport}) {
    _eventSubscription = transport.events.listen(
      _handleEvent,
      onError: _handleTransportError,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw StateError('The mTLS HTTP client is closed.');
    if (request.url.scheme.toLowerCase() != 'https') {
      throw ArgumentError.value(
        request.url,
        'request.url',
        'mTLS requests require HTTPS',
      );
    }

    final requestId = _uuid.v4();
    late final StreamController<List<int>> responseController;
    responseController = StreamController<List<int>>(
      onCancel: () async {
        if (_responses.remove(requestId) != null) {
          await transport.cancelRequest(requestId);
        }
      },
    );
    _responses[requestId] = responseController;

    try {
      final body = await request.finalize().toBytes();
      if (_cancelledRequestIds.remove(requestId)) {
        throw http.ClientException(
          'The mTLS request was cancelled.',
          request.url,
        );
      }
      final head = await transport.startRequest(
        MtlsRequest(
          requestId: requestId,
          alias: alias,
          method: request.method,
          url: request.url,
          headers: Map<String, String>.from(request.headers),
          body: body.isEmpty ? null : Uint8List.fromList(body),
        ),
      );
      if (_cancelledRequestIds.remove(requestId)) {
        throw http.ClientException(
          'The mTLS request was cancelled.',
          request.url,
        );
      }
      return http.StreamedResponse(
        responseController.stream,
        head.statusCode,
        contentLength: head.contentLength,
        request: request,
        headers: head.headers,
        reasonPhrase: head.reasonPhrase,
        isRedirect: head.statusCode >= 300 && head.statusCode < 400,
      );
    } catch (_) {
      _cancelledRequestIds.remove(requestId);
      _responses.remove(requestId);
      if (!responseController.isClosed) {
        unawaited(responseController.close());
      }

      rethrow;
    }
  }

  void _handleEvent(MtlsResponseEvent event) {
    final controller = _responses[event.requestId];
    if (controller == null || controller.isClosed) return;
    switch (event) {
      case MtlsDataEvent():
        controller.add(event.data);
      case MtlsDoneEvent():
        _cancelledRequestIds.remove(event.requestId);
        _responses.remove(event.requestId);
        unawaited(controller.close());
      case MtlsErrorEvent():
        _cancelledRequestIds.remove(event.requestId);
        _responses.remove(event.requestId);
        controller.addError(http.ClientException(event.message));
        unawaited(controller.close());
      case MtlsWebSocketDataEvent() ||
          MtlsWebSocketClosedEvent() ||
          MtlsWebSocketErrorEvent():
        return;
    }
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    final controllers = _responses.values.toList();
    _responses.clear();
    for (final controller in controllers) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        unawaited(controller.close());
      }
    }
  }

  Future<bool> cancelPendingRequests() async {
    final requestIds = _responses.keys.toList();
    if (requestIds.isEmpty) return false;
    _cancelledRequestIds.addAll(requestIds);
    await Future.wait(
      requestIds.map(transport.cancelRequest),
      eagerError: false,
    );
    return true;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final requestIds = _responses.keys.toList();
    _cancelledRequestIds.addAll(requestIds);
    final controllers = _responses.values.toList();
    _responses.clear();
    for (final requestId in requestIds) {
      unawaited(transport.cancelRequest(requestId));
    }
    for (final controller in controllers) {
      if (!controller.isClosed) unawaited(controller.close());
    }
    unawaited(_eventSubscription.cancel());
  }
}

class _UnavailableMtlsHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('The mTLS connection has no selected certificate.');
  }
}
