import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hermes_android/core/services/android_launch_intent_service.dart';
import 'package:hermes_android/core/services/android_share_intent_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingCredentialStore implements CredentialStore {
  final readResult = Completer<String?>();
  final values = <String, String>{};
  final cache = <String, String>{};
  int reads = 0;
  int deletes = 0;
  bool holdVerification = false;

  @override
  String? readCached(String key) => cache[key];

  @override
  Future<String?> read(String key) async {
    reads++;
    // Migration reads the existing bundle before writing. Let that prerequisite
    // succeed when this fixture specifically targets the post-write read-back.
    if (holdVerification && reads == 1) return null;
    final value = await readResult.future;
    if (value != null) cache[key] = value;
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    values.remove(key);
    cache.remove(key);
  }
}

String _savedConnection({bool legacy = false}) => jsonEncode({
  'id': 'saved-id',
  'label': 'Saved',
  'host': 'example.invalid',
  'port': 8642,
  'use_https': false,
  if (legacy) 'api_key': 'test-credential',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const shareChannel = MethodChannel(AndroidShareIntentService.channelName);
  const launchChannel = MethodChannel(AndroidLaunchIntentService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    // Recovery constructs the production wrapper, not the failing migration
    // store injected into creation. Supply that separate physical boundary.
    FlutterSecureStorage.setMockInitialValues({});
    messenger.setMockMethodCallHandler(shareChannel, (_) async => null);
    messenger.setMockMethodCallHandler(launchChannel, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(launchChannel, null);
  });

  testWidgets('first Flutter frame is visible while Keystore read is pending', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_connections': [_savedConnection()],
    });
    final credentials = _PendingCredentialStore();
    var shareProbes = 0;
    var launchProbes = 0;
    messenger.setMockMethodCallHandler(shareChannel, (_) async {
      shareProbes++;
      return null;
    });
    messenger.setMockMethodCallHandler(launchChannel, (_) async {
      launchProbes++;
      return null;
    });

    await tester.pumpWidget(
      StartupApp(
        createConnectionManager: (prefs) =>
            ConnectionManager.create(prefs, credentialStore: credentials),
      ),
    );
    // The frame is a real MaterialApp/Scaffold, not an empty runApp placeholder.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(HermesApp), findsNothing);
    await tester.pump();
    expect(credentials.reads, 1);
    expect(shareProbes, 1);
    expect(launchProbes, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    credentials.readResult.complete(jsonEncode({'api_key': 'test-credential'}));
    await tester.pumpAndSettle();
    expect(find.byType(HermesApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(home.connManager.getConnections().single.apiKey, 'test-credential');
  });

  testWidgets(
    'share bridge PlatformException leaves startup usable after required hydration',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hydration = Completer<void>();
      var shareProbes = 0;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'getInitialShare');
        shareProbes++;
        throw PlatformException(code: 'share_unavailable');
      });
      messenger.setMockMethodCallHandler(
        launchChannel,
        (_) async => 'quickChat',
      );

      await tester.pumpWidget(
        StartupApp(
          createConnectionManager: (prefs) async {
            await hydration.future;
            return ConnectionManager.create(prefs);
          },
        ),
      );
      await tester.pump();
      expect(find.byType(HermesApp), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      hydration.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HermesApp), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Reset saved connections'), findsNothing);
      final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
      expect(home.launchIntents!.takePendingQuickChat(), isTrue);
      expect(home.shareIntents!.pendingShare.value, isNull);
      // Initial-share failure must not unregister the warm-share handler.
      await messenger.handlePlatformMessage(
        shareChannel.name,
        shareChannel.codec.encodeMethodCall(
          const MethodCall('shareText', 'A later shared draft'),
        ),
        (_) {},
      );
      expect(
        home.shareIntents!.takePendingShare()!.text,
        'A later shared draft',
      );
      expect(home.shareIntents!.takePendingShare(), isNull);
      await home.shareIntents!.initialize();
      expect(shareProbes, 1);
    },
  );

  testWidgets(
    'optional share failure does not hide a corrupt persisted connection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'saved_connections': ['not valid JSON'],
        'unrelated_preference': 'keep',
      });
      messenger.setMockMethodCallHandler(shareChannel, (_) async {
        throw PlatformException(code: 'share_unavailable');
      });
      await tester.pumpWidget(const StartupApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HermesApp), findsNothing);
      expect(find.text('Reset saved connections'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('saved_connections'), ['not valid JSON']);
      expect(prefs.getString('unrelated_preference'), 'keep');
    },
  );

  for (final failVerification in [false, true]) {
    testWidgets(
      'failed credential migration shows recovery and reset can retry (verification=$failVerification)',
      (tester) async {
        final original = _savedConnection(legacy: true);
        SharedPreferences.setMockInitialValues({
          'saved_connections': [original],
          'unrelated_preference': 'keep',
        });
        final credentials = _PendingCredentialStore()
          ..holdVerification = failVerification;
        const physicalCredentials = FlutterSecureStorage();
        final encodedId = base64Url
            .encode(utf8.encode('saved-id'))
            .replaceAll('=', '');
        final credentialKey = 'connection_credentials_v1.$encodedId';
        await physicalCredentials.write(
          key: credentialKey,
          value: 'raw-bundle',
        );
        messenger.setMockMethodCallHandler(shareChannel, (_) async {
          throw PlatformException(code: 'share_unavailable');
        });
        var attempts = 0;
        await tester.pumpWidget(
          StartupApp(
            createConnectionManager: (prefs) {
              attempts++;
              if (attempts == 2) throw StateError('retry unavailable');
              return ConnectionManager.create(
                prefs,
                credentialStore: credentials,
              );
            },
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.pump();
        expect(credentials.reads, failVerification ? 2 : 1);
        credentials.readResult.completeError(
          PlatformException(code: 'keystore_unavailable'),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HermesApp), findsNothing);
        expect(find.text('Reset saved connections'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('saved_connections'), [original]);
        expect(credentials.values, failVerification ? hasLength(1) : isEmpty);

        await tester.tap(find.text('Reset saved connections'));
        await tester.pumpAndSettle();
        expect(find.text('Reset saved connections'), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);

        await tester.tap(find.text('Reset saved connections'));
        await tester.pumpAndSettle();
        expect(attempts, 3);
        expect(find.byType(HermesApp), findsOneWidget);
        expect(
          tester
              .widget<HomeScreen>(find.byType(HomeScreen))
              .connManager
              .getConnections(),
          isEmpty,
        );
        expect(prefs.getStringList('saved_connections'), isNull);
        expect(prefs.getString('unrelated_preference'), 'keep');
        expect(await physicalCredentials.read(key: credentialKey), isNull);
        expect(credentials.deletes, 0);
      },
    );
  }

  testWidgets('cold-start intents are collected before Home mounts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final initialShare = Completer<String?>();
    messenger.setMockMethodCallHandler(
      shareChannel,
      (_) => initialShare.future,
    );
    messenger.setMockMethodCallHandler(launchChannel, (_) async => 'quickChat');

    await tester.pumpWidget(const StartupApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    expect(find.byType(HomeScreen), findsNothing);
    initialShare.complete('Shared draft');
    await tester.pumpAndSettle();

    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(home.shareIntents?.pendingShare.value?.text, 'Shared draft');
    expect(home.launchIntents?.pendingQuickChat.value, isTrue);
  });
}
