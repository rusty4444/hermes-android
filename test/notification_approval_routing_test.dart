import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/notification_approval_authority.dart';

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  String? readCached(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    pendingNotificationApprovals.value = const [];
  });

  tearDown(() {
    pendingNotificationApprovals.value = const [];
    notificationResponseHandler = null;
  });

  testWidgets(
    'approval actions retain the exact saved profile on a shared endpoint',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await manager.saveConnection(
        'Profile A',
        '127.0.0.1',
        1,
        'key-a',
        gatewayProfile: 'alpha',
      );
      await manager.saveConnection(
        'Profile B',
        '127.0.0.1',
        1,
        'key-b',
        gatewayProfile: 'beta',
      );
      final profiles = manager.getConnections();
      final target = profiles.firstWhere(
        (connection) => connection.gatewayProfile == 'beta',
      );
      final sibling = profiles.firstWhere(
        (connection) => connection.gatewayProfile == 'alpha',
      );
      expect(target.baseUrl, sibling.baseUrl);
      expect(target.id, isNot(sibling.id));

      await tester.pumpWidget(HermesApp(connManager: manager));
      await tester.pump();

      notificationResponseHandler!(
        NotificationResponse(
          id: 7,
          actionId: 'approve',
          payload: jsonEncode({
            'connectionId': target.id,
            'sessionId': 'shared-session',
            'requestId': 'request-7',
            ...NotificationApprovalAuthority.origin(target),
          }),
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
        ),
      );
      await tester.pump();

      expect(pendingNotificationApprovals.value, hasLength(1));
      expect(pendingNotificationApprovals.value.single.connectionId, target.id);
      expect(
        pendingNotificationApprovals.value.single.connectionId,
        isNot(sibling.id),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
