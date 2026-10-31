// Debug-only entry point for the local emulator fixture. Never use this target
// for distribution: it seeds only an explicitly named test connection.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart' as app;

void main() {
  if (!kDebugMode) {
    throw UnsupportedError('The background smoke target is debug-only.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    app.StartupApp(
      createConnectionManager: (prefs) async {
        final manager = await ConnectionManager.create(prefs);
        const label = 'Local background smoke fixture';
        var matches = manager.getConnections().where(
          (connection) => connection.label == label,
        );
        if (matches.isEmpty) {
          await manager.saveConnection(
            label,
            '127.0.0.1',
            18643,
            'background-smoke-fixture-key', // Test fixture, not a real secret.
            desktopGatewayUrl: 'http://127.0.0.1:18643',
            dashboardPort: 18643,
            dashboardUsername: 'fixture',
            dashboardPassword: 'fixture-password',
          );
          matches = manager.getConnections().where(
            (connection) => connection.label == label,
          );
        }
        await prefs.setString('last_connection_id', matches.single.id);
        return manager;
      },
    ),
  );
}
