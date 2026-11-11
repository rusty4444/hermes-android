import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// Compatible with HermesLoginLease; call only from an explicit sign-in action.
Future<Future<void> Function()> acquireNativeLoginLease() =>
    NativeLoginKeepAlive().acquire();

class NativeLoginLeaseException implements Exception {
  const NativeLoginLeaseException();

  @override
  String toString() => 'Unable to keep browser sign-in active.';
}

/// A short, user-initiated Android foreground lease for the in-memory PKCE flow.
///
/// Pass [acquire] as `acquireLoginLease`. It acknowledges foreground promotion
/// before the caller opens the browser, and throws a secret-free exception if
/// Android refuses it. Other platforms are a no-op. Method calls are bounded;
/// Android independently stops the non-sticky service after six minutes, even
/// if Dart dies or release is lost. Never use this for refresh or background work.
/// No provider URL, state, authorization code or credential crosses the channel.
class NativeLoginKeepAlive {
  final MethodChannel _channel;
  final TargetPlatform _platform;
  final bool _isWeb;
  final Duration channelTimeout;

  NativeLoginKeepAlive({
    MethodChannel? channel,
    TargetPlatform? platform,
    bool? isWeb,
    this.channelTimeout = const Duration(seconds: 3),
  }) : _channel =
           channel ??
           const MethodChannel('com.hermesagent.hermes_android/native_login'),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  Future<Future<void> Function()> acquire() async {
    if (_isWeb || _platform != TargetPlatform.android) return () async {};
    final arguments = <String, Object>{'leaseId': const Uuid().v4()};
    try {
      if (await _channel
              .invokeMethod<Object?>('acquire', arguments)
              .timeout(channelTimeout) !=
          true) {
        throw const NativeLoginLeaseException();
      }
    } catch (_) {
      await _release(arguments);
      throw const NativeLoginLeaseException();
    }
    Future<void>? released;
    return () => released ??= _release(arguments);
  }

  Future<void> _release(Map<String, Object> arguments) async {
    try {
      await _channel
          .invokeMethod<void>('release', arguments)
          .timeout(channelTimeout);
    } catch (_) {
      // Native hard cap is the final backstop; never expose platform details.
    }
  }
}
