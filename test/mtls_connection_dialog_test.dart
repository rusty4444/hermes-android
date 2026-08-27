import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryCredentialStore implements CredentialStore {
  final Map<String, String> values = {};
  final Map<String, String> _cache = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    _cache.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hermesagent.hermes_android/mtls');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'chooseCertificate':
            case 'describeCertificate':
              return <String, Object?>{
                'alias': 'android-client-cert',
                'label': 'Hermes Client Certificate',
              };
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('mTLS requires explicit HTTPS but HTTP remains valid when off', (
    tester,
  ) async {
    await _asAndroid(() async {
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await tester.pumpWidget(HermesApp(connManager: manager));

      await tester.tap(find.byTooltip('Add Connection'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Host'),
        'http://gateway.example.com',
      );

      await tester.tap(find.text('mTLS (optional)'));
      await tester.pumpAndSettle();
      expect(find.text('Hermes Client Certificate'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(
        find.text('mTLS requires an explicit https:// Gateway host.'),
        findsOneWidget,
      );

      await tester.tap(find.text('mTLS (optional)'));
      await tester.pump();
      expect(
        find.text('mTLS requires an explicit https:// Gateway host.'),
        findsNothing,
      );
    });
  });

  testWidgets('edit connection restores remembered mTLS certificate', (
    tester,
  ) async {
    await _asAndroid(() async {
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await manager.saveConnection(
        'Secure gateway',
        'https://gateway.example.com',
        443,
        'synthetic-api-key',
        mtlsEnabled: true,
        mtlsCertificateAlias: 'android-client-cert',
      );
      await tester.pumpWidget(HermesApp(connManager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Connection'));
      await tester.pumpAndSettle();

      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'mTLS (optional)'),
      );
      expect(switchTile.value, isTrue);
      expect(find.text('Hermes Client Certificate'), findsOneWidget);
    });
  });

  testWidgets('Gateway API keys require an HTTPS host', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: _MemoryCredentialStore(),
    );
    await tester.pumpWidget(HermesApp(connManager: manager));

    await tester.tap(find.byTooltip('Add Connection'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Host'),
      'http://gateway.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'API Key'),
      'synthetic-api-key',
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(
      find.text('Gateway API keys require an explicit https:// host.'),
      findsOneWidget,
    );
  });

  testWidgets('new connection does not preconfigure a Desktop Gateway', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final manager = await ConnectionManager.create(
      prefs,
      credentialStore: _MemoryCredentialStore(),
    );
    await tester.pumpWidget(HermesApp(connManager: manager));

    await tester.tap(find.byTooltip('Add Connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom proxy and dashboard details'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Desktop Gateway URL (optional)'),
    );
    expect(field.controller!.text, isEmpty);
    final dashboardField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Dashboard URL (optional)'),
    );
    expect(dashboardField.controller!.text, isEmpty);
  });

  testWidgets('Desktop Gateway requires an HTTPS URL', (tester) async {
    await _asAndroid(() async {
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentialStore(),
      );
      await tester.pumpWidget(HermesApp(connManager: manager));

      await tester.tap(find.byTooltip('Add Connection'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Host'),
        'https://gateway.example.com',
      );
      final advanced = find.text('Custom proxy and dashboard details');
      await tester.ensureVisible(advanced);
      await tester.tap(advanced);
      await tester.pumpAndSettle();
      final desktopField = find.widgetWithText(
        TextField,
        'Desktop Gateway URL (optional)',
      );
      await tester.ensureVisible(desktopField);
      await tester.enterText(desktopField, 'http://desktop.example.com:42848');

      final connect = find.text('Connect');
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pump();

      expect(
        find.text(
          'The Desktop Gateway URL must be a valid https:// URL because it carries session credentials.',
        ),
        findsOneWidget,
      );
    });
  });
}

Future<void> _asAndroid(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
