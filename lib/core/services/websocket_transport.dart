import 'dart:async';

import 'package:web_socket_channel/io.dart';

abstract interface class GatewayWebSocketChannel {
  Stream<dynamic> get stream;

  StreamSink<dynamic> get sink;

  Future<void> get ready;
}

typedef GatewayWebSocketChannelFactory =
    GatewayWebSocketChannel Function(Uri uri);

class IoGatewayWebSocketChannel implements GatewayWebSocketChannel {
  final IOWebSocketChannel _channel;

  IoGatewayWebSocketChannel.connect(Uri uri)
    : _channel = IOWebSocketChannel.connect(uri);

  @override
  Future<void> get ready => _channel.ready;

  @override
  StreamSink<dynamic> get sink => _channel.sink;

  @override
  Stream<dynamic> get stream => _channel.stream;
}
