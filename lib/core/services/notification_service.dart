import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Manages local push notifications for incoming Hermes messages.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Initialize notification channels and plugin.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create the message channel
    const channel = AndroidNotificationChannel(
      'hermes_messages',
      'Hermes Messages',
      description: 'Notifications for new Hermes agent responses',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Show a notification for a new message.
  static Future<void> showMessage({
    required String sessionTitle,
    required String message,
    String? sessionId,
  }) async {
    await _plugin.show(
      sessionTitle.hashCode, // unique ID per session
      sessionTitle,
      message.length > 120 ? '${message.substring(0, 120)}…' : message,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'hermes_messages',
          'Hermes Messages',
          channelDescription: 'Notifications for new Hermes agent responses',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: sessionId,
    );
  }

  /// Handle notification tap — payload contains session ID.
  static void _onNotificationTap(NotificationResponse response) {
    // Navigation is handled by the app's router when it resumes
  }
}
