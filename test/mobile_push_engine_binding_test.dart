import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'mobile_push_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh consent refreshes metadata hydrated before an abandoned engine commit',
    () async {
      notificationPrefs.value = NotificationPrefs.defaults;
      final f = fixture.Fixture();
      await f.setup();
      addTearDown(f.close);
      await f.service.initialize(f.manager);
      final stale = f.connection;
      final changed = stale.copyWith(host: 'replacement.invalid');
      // Physical metadata finishes after this replacement manager's cached
      // hydration; credentials are deliberately unchanged. This provider write
      // models the native old-engine commit, not a new Dart mutation/epoch.
      await SharedPreferencesStorePlatform.instance.setValue(
        'StringList',
        'flutter.saved_connections',
        [jsonEncode(changed.toMap())],
      );
      expect(f.manager.getConnections().single.host, stale.host);
      await f.service.enableAutomatic(stale);
      expect(f.methods, contains('connectionFence'));
      expect(f.manager.getConnections().single.host, 'replacement.invalid');
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
      expect(f.requests, isEmpty);
      expect(f.service.enabled, isFalse);
    },
  );

  test(
    'consent preserves an older metadata shape without adding defaults or secrets',
    () async {
      notificationPrefs.value = NotificationPrefs.defaults;
      final f = fixture.Fixture();
      await f.setup();
      addTearDown(f.close);
      final older = f.connection.toMap()..remove('dashboard_port');
      await f.manager.prefs.setStringList('saved_connections', [
        jsonEncode(older),
      ]);
      await f.service.initialize(f.manager);
      await f.service.enableAutomatic(f.manager.getConnections().single);
      expect(f.native['enabled'], isTrue);
      expect(f.native['connection_metadata'], older);
      final metadata = f.native['connection_metadata'] as Map;
      expect(metadata, isNot(contains('dashboard_port')));
      expect(metadata, isNot(contains('api_key')));
      expect(metadata, isNot(contains('dashboard_password')));
      expect(jsonEncode(metadata), isNot(contains('gateway-test-key')));
      expect(jsonEncode(metadata), isNot(contains('fixture-password')));
    },
  );
}
