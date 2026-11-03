import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidSharedFile {
  final String path;
  final String name;
  final String mediaType;
  final int byteLength;

  const AndroidSharedFile({
    required this.path,
    required this.name,
    required this.mediaType,
    required this.byteLength,
  });

  factory AndroidSharedFile.fromMap(Map<Object?, Object?> map) {
    return AndroidSharedFile(
      path: (map['path'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      mediaType: (map['mediaType'] as String? ?? 'application/octet-stream')
          .trim(),
      byteLength: (map['byteLength'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isImage => mediaType.toLowerCase().startsWith('image/');
}

class AndroidSharePayload {
  final String? text;
  final List<AndroidSharedFile> files;

  const AndroidSharePayload({this.text, this.files = const []});

  bool get isEmpty => (text == null || text!.isEmpty) && files.isEmpty;

  factory AndroidSharePayload.fromPlatform(Object? raw) {
    if (raw is String) {
      final text = raw.trim();
      return AndroidSharePayload(text: text.isEmpty ? null : text);
    }
    if (raw is! Map) return const AndroidSharePayload();
    final textValue = (raw['text'] as String?)?.trim();
    final rawFiles = raw['files'];
    final files = rawFiles is List
        ? rawFiles
              .whereType<Map>()
              .map(
                (file) => AndroidSharedFile.fromMap(
                  file.map(
                    (key, value) => MapEntry<Object?, Object?>(key, value),
                  ),
                ),
              )
              .where(
                (file) =>
                    file.path.isNotEmpty &&
                    file.name.isNotEmpty &&
                    file.byteLength > 0,
              )
              .toList(growable: false)
        : const <AndroidSharedFile>[];
    return AndroidSharePayload(
      text: textValue == null || textValue.isEmpty ? null : textValue,
      files: files,
    );
  }
}

/// Receives text, URLs, images, and files sent through Android share intents.
class AndroidShareIntentService {
  static const channelName = 'com.hermesagent.hermes_android/share';
  static const _channel = MethodChannel(channelName);

  final ValueNotifier<AndroidSharePayload?> pendingShare =
      ValueNotifier<AndroidSharePayload?>(null);

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      _publish(await _channel.invokeMethod<Object?>('getInitialShare'));
    } on MissingPluginException {
      // Non-Android hosts have no share-intent bridge.
    } on PlatformException {
      // Share capture is optional: a native bridge failure must not strand
      // startup. Keep the handler installed so later warm shares still work.
    }
  }

  AndroidSharePayload? takePendingShare() {
    final value = pendingShare.value;
    pendingShare.value = null;
    return value;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'sharePayload' || call.method == 'shareText') {
      _publish(call.arguments);
    }
  }

  void _publish(Object? raw) {
    final payload = AndroidSharePayload.fromPlatform(raw);
    if (payload.isEmpty) return;
    pendingShare.value = payload;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    pendingShare.dispose();
  }
}
