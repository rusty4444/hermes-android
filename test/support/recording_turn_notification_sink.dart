import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';

/// In-memory [TurnNotificationSink] used to characterize what Hermes actually
/// posts to Android, without touching the platform plugin.
class RecordingTurnNotificationSink implements TurnNotificationSink {
  final List<TurnNotification> shown = <TurnNotification>[];
  final List<int> cancelled = <int>[];

  int initializeCount = 0;
  int cancelAllCount = 0;
  int permissionRequestCount = 0;
  int permissionCheckCount = 0;

  /// The cold-start response [takeInitialLaunchResponse] returns, if any.
  NotificationResponse? initialLaunchResponse;

  @override
  Future<NotificationResponse?> takeInitialLaunchResponse() async =>
      initialLaunchResponse;

  /// Simulated OS grant returned by passive checks and explicit requests:
  /// true granted, false denied, null when no platform gate exists.
  bool? permissionResult;

  /// When set, [checkPermission] throws it without affecting prompt requests.
  Object? permissionCheckError;

  /// When set, [requestPermission] throws it.
  Object? permissionError;

  @override
  Future<bool?> checkPermission() async {
    permissionCheckCount++;
    final error = permissionCheckError;
    if (error != null) throw error;
    return permissionResult;
  }

  /// When set, [initialize] throws it — mirroring a platform channel that is
  /// unavailable (test environment, missing plugin registration).
  Object? initializeError;

  @override
  Future<void> initialize() async {
    initializeCount++;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<bool?> requestPermission() async {
    permissionRequestCount++;
    final error = permissionError;
    if (error != null) throw error;
    return permissionResult;
  }

  @override
  Future<void> show(TurnNotification notification) async {
    shown.add(notification);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }
}
