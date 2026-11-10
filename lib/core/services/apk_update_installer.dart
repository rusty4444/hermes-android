import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_update_service.dart';

/// The Android side owns the private download file and hands it only to the
/// system installer. Keeping bytes and file paths off the channel avoids large
/// platform messages and stops other apps from replacing the verified APK.
class ApkUpdateInstaller {
  ApkUpdateInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.hermesagent.hermes_android/apk_update';
  final MethodChannel _channel;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // MethodChannel handlers belong to the messenger, not this object. Keep
  // concurrent dialog instances from replacing one another's progress handler.
  static bool _downloadActive = false;
  bool _ownsDownload = false;
  bool _mayCancelPrepared = false;

  Future<List<String>> supportedAbis() async {
    if (!supported || await _channel.invokeMethod<bool>('canUpdate') != true) {
      return const [];
    }
    return (await _channel.invokeListMethod<String>('supportedAbis')) ??
        const [];
  }

  /// Resume only a fully verified APK retained across process recreation.
  Future<bool> hasPreparedUpdate(AppReleaseApk apk, String tag) async {
    if (!supported) return false;
    final prepared =
        await _channel.invokeMethod<bool>('hasPreparedUpdate', {
          'tag': tag,
          'name': apk.name,
          'sha256': apk.sha256,
          'size': apk.size,
        }) ??
        false;
    _mayCancelPrepared = prepared;
    return prepared;
  }

  Future<void> download({
    required AppReleaseApk apk,
    required String tag,
    required void Function(int received, int total) onProgress,
  }) async {
    if (_downloadActive) {
      throw StateError('An update download is already in progress');
    }
    _downloadActive = true;
    _ownsDownload = true;
    _mayCancelPrepared = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final received = args['received'];
      final total = args['total'];
      if (received is int &&
          total is int &&
          total > 0 &&
          received >= 0 &&
          received <= total) {
        onProgress(received, total);
      }
    });
    try {
      await _channel.invokeMethod<void>('download', {
        'tag': tag,
        'url': apk.url.toString(),
        'name': apk.name,
        'sha256': apk.sha256,
        'size': apk.size,
      });
    } finally {
      _channel.setMethodCallHandler(null);
      _ownsDownload = false;
      _downloadActive = false;
    }
  }

  /// Either opens the installer or Android's one-time unknown-source setting.
  /// Only a subsequent explicit tap after granting permission launches install.
  Future<String> install() async =>
      await _channel.invokeMethod<String>('install') ?? 'failed';

  Future<void> cancel() async {
    if (!_ownsDownload && (!_mayCancelPrepared || _downloadActive)) return;
    _mayCancelPrepared = false;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No Android platform is attached.
    }
  }
}
