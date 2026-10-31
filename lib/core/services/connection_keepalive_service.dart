import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/services.dart';

/// One Android foreground service protects unresolved user-started work while
/// backgrounded, never idle sockets. This raises process priority; it does not
/// defeat Doze, OEM battery restrictions, process death or a user's force stop.
/// Refused starts fall back to transport recovery on resume.
class ConnectionKeepAliveService {
  static const MethodChannel channel = MethodChannel(
    'com.hermesagent.hermes_android/keepalive',
  );

  bool _active = false;
  bool _starting = false;
  bool _backgrounded = false;
  bool _hasActiveTurn = false;
  bool _enabled = true;
  bool _desiredActive = false;
  bool _pendingStart = false;
  int _cycle = 0;
  final Set<Future<void>> _stops = {};

  bool get isActive => _active;

  Future<void> start() async {
    if (!_enabled) return;
    _desiredActive = true;
    if (_active && _stops.isEmpty) return;
    if (_starting) {
      _pendingStart = true;
      return;
    }
    _starting = true;
    try {
      // A newly earned start must follow every older native stop, including
      // a compensating stop for a stale start. Native replies can be delayed.
      while (_stops.isNotEmpty) {
        await Future.wait(List.of(_stops));
      }
      if (!_desiredActive || !_enabled) return;
      final cycle = _cycle;
      var started = false;
      try {
        started = await channel.invokeMethod<bool>('start') ?? false;
      } on PlatformException {
        // Android 12+ may refuse a background start.
      } on MissingPluginException {
        // Non-Android host.
      }
      if (cycle == _cycle && _desiredActive && _enabled) {
        _active = started;
        _pendingStart = false;
      } else if (started) {
        // A stop may have reached Android before this stale start did. Keep
        // the flight until its compensation completes so no newer start can
        // be stopped by this generation's cleanup.
        await _sendStop();
      }
    } finally {
      _starting = false;
      final retry = _pendingStart && _desiredActive && _enabled;
      _pendingStart = false;
      if (retry) await start();
    }
  }

  Future<void> stop() async {
    _cycle++;
    _desiredActive = false;
    _pendingStart = false;
    _active = false;
    // Unconditional native stop also recovers divergence after engine attach.
    await _sendStop();
  }

  void onAppLifecycleState(
    AppLifecycleState state, {
    required bool hasActiveTurn,
  }) {
    _hasActiveTurn = hasActiveTurn;
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.detached:
        _backgrounded = false;
        unawaited(stop());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // The first transition still has foreground-start eligibility.
        _backgrounded = true;
        _followWork();
    }
  }

  void onTurnActivityChanged(bool hasActiveTurn) {
    // Remember foreground work too: changing policy must not lose ownership.
    _hasActiveTurn = hasActiveTurn;
    if (_backgrounded) _followWork();
  }

  /// Only changes this phone's service. It never interrupts a server turn.
  void onPolicyChanged(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      unawaited(stop());
    } else if (_backgrounded) {
      _followWork();
    }
  }

  void _followWork() {
    if (_enabled && _hasActiveTurn) {
      unawaited(start());
    } else if (_active || _starting || _desiredActive) {
      unawaited(stop());
    }
  }

  Future<void> _sendStop() async {
    final stop = _invokeStop();
    _stops.add(stop);
    try {
      await stop;
    } finally {
      _stops.remove(stop);
    }
  }

  Future<void> _invokeStop() async {
    try {
      await channel.invokeMethod<bool>('stop');
    } on PlatformException {
      // A missing/refused platform must not block the app.
    } on MissingPluginException {
      // Non-Android host.
    }
  }
}
