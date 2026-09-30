// Auto-messaging service platform channel for Android Auto / Android TV.
// This is the Dart side of the method channel used to start new chats,
// receive voice replies, and refresh the persistent notification entry.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection.dart';

/// Method channel exposed by the Android side.
const MethodChannel _channel = MethodChannel(
  'com.hermesagent.hermes_android/auto',
);

/// Sentinel session id used by Android Auto "start new conversation" replies.
const String newSessionSentinel = '__new__';

/// Callback signature for a "start new conversation" tap from Android Auto.
typedef NewChatCallback = void Function(SavedConnection? connection);

/// Callback signature for a voice reply from Android Auto.
typedef VoiceReplyCallback = void Function(
  String sessionId,
  String message,
  SavedConnection? connection,
);

/// Pending voice reply stored when no callback is registered yet.
typedef _PendingVoiceReply = ({String sessionId, String message, SavedConnection? connection});

// Registers the Android Auto method channel and exposes callbacks.
class AutoMessagingService {
  static NewChatCallback? _onNewChat;
  static VoiceReplyCallback? _onVoiceReply;
  static _PendingVoiceReply? _pendingVoiceReply;

  static bool _initialized = false;

  static const String _prefsName = 'hermes_auto';
  static const String _pendingSessionKey = 'pending_voice_reply_session';
  static const String _pendingMessageKey = 'pending_voice_reply_message';
  static const String _pendingConnectionKey = 'pending_voice_reply_connection';

  /// Callback for a "start new conversation" tap from Android Auto.
  static set onNewChat(NewChatCallback? callback) {
    _onNewChat = callback;
  }

  static NewChatCallback? get onNewChat => _onNewChat;

  /// Callback for a voice reply from Android Auto. Pending replies are delivered
  /// immediately when a listener is attached.
  static set onVoiceReply(VoiceReplyCallback? callback) {
    _onVoiceReply = callback;
    _flushPendingVoiceReply();
  }

  static VoiceReplyCallback? get onVoiceReply => _onVoiceReply;

  /// Initialize once from main(). Starts the Android foreground service if
  /// there is at least one saved connection, so background voice replies keep
  /// working even when the phone is dozing.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    _loadPendingVoiceReply();
    startForegroundService();
  }

  /// Ask Android to keep the app alive in the background.
  static Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {
      // Method channel may be unavailable on non-Android platforms.
    }
  }

  /// Stop the background keep-alive service.
  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {
      // Method channel may be unavailable on non-Android platforms.
    }
  }

  static Future<void> _loadPendingVoiceReply() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString(_pendingSessionKey);
      final message = prefs.getString(_pendingMessageKey);
      final connectionJson = prefs.getString(_pendingConnectionKey);
      if (sessionId == null ||
          sessionId.isEmpty ||
          message == null ||
          message.isEmpty) {
        return;
      }
      SavedConnection? connection;
      if (connectionJson != null && connectionJson.isNotEmpty) {
        try {
          connection = SavedConnection.fromMap(
            jsonDecode(connectionJson) as Map<String, dynamic>,
          );
        } catch (_) {
          connection = null;
        }
      }
      _pendingVoiceReply = (sessionId: sessionId, message: message, connection: connection);
      // Defer flush until after main() finishes so listeners can attach.
      Future.delayed(const Duration(milliseconds: 100), _flushPendingVoiceReply);
    } catch (_) {
      // Ignore platform errors.
    }
  }

  static void _flushPendingVoiceReply() {
    final callback = _onVoiceReply;
    final pending = _pendingVoiceReply;
    if (callback == null || pending == null) return;
    _pendingVoiceReply = null;
    callback(pending.sessionId, pending.message, pending.connection);
  }

  static Future<void> _storePendingVoiceReply(
    String sessionId,
    String message,
    String connectionJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingSessionKey, sessionId);
      await prefs.setString(_pendingMessageKey, message);
      await prefs.setString(_pendingConnectionKey, connectionJson);
    } catch (_) {
      // Ignore platform errors.
    }
  }

  static Future<void> _clearPendingVoiceReply() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingSessionKey);
      await prefs.remove(_pendingMessageKey);
      await prefs.remove(_pendingConnectionKey);
    } catch (_) {
      // Ignore platform errors.
    }
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>? ?? {};
    final connectionJson = args['connectionJson'] as String?;
    SavedConnection? connection;
    if (connectionJson != null && connectionJson.isNotEmpty) {
      try {
        connection = SavedConnection.fromMap(
          jsonDecode(connectionJson) as Map<String, dynamic>,
        );
      } catch (_) {
        connection = null;
      }
    }

    switch (call.method) {
      case 'newChat':
        _onNewChat?.call(connection);
        return null;
      case 'voiceReply':
        final sessionId = args['sessionId'] as String? ?? '';
        final message = args['message'] as String? ?? '';
        final callback = _onVoiceReply;
        if (callback != null) {
          _clearPendingVoiceReply();
          callback(sessionId, message, connection);
        } else {
          // Buffer the reply and persist it so it survives app restart.
          _pendingVoiceReply = (
            sessionId: sessionId,
            message: message,
            connection: connection,
          );
          await _storePendingVoiceReply(
            sessionId,
            message,
            connectionJson ?? '',
          );
        }
        return null;
      default:
        return null;
    }
  }

  /// Show or refresh the persistent Android Auto "start new conversation" entry.
  static Future<void> showNewChatEntry({String? connectionJson}) async {
    try {
      await _channel.invokeMethod('showNewChatEntry', {
        'connectionJson': connectionJson ?? '',
      });
    } catch (_) {
      // Method channel may be unavailable on non-Android platforms.
    }
  }

  /// Update or create a conversation notification for a specific session.
  static Future<void> showAssistantMessage({
    required String sessionId,
    required String title,
    required String body,
    String? connectionJson,
  }) async {
    try {
      await _channel.invokeMethod('showAssistantMessage', {
        'sessionId': sessionId,
        'title': title,
        'body': body,
        'connectionJson': connectionJson ?? '',
      });
    } catch (_) {
      // Ignore platform errors.
    }
  }

  /// Start or stop the foreground service for background keep-alive.
  static Future<void> setKeepAlive({required bool active}) async {
    try {
      await _channel.invokeMethod(
        active ? 'startForegroundService' : 'stopForegroundService',
        {},
      );
    } catch (_) {
      // Ignore platform errors.
    }
  }
}
