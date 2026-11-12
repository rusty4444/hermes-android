import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dashboard_auth_onboarding_test.dart' show openAdd;
import 'dashboard_native_auth_security_test.dart' show RealHttp, MemoryStore;
import 'dashboard_oidc_edit_security_test.dart' show openEdit, drain;

class _HeldStore extends MemoryStore {
  Completer<void>? entered;
  Completer<void>? release;
  @override
  Future<String?> read(String key) async {
    final gate = release;
    if (gate != null) {
      release = null;
      entered!.complete();
      await gate.future;
    }
    return super.read(key);
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late PathProviderPlatform paths;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('dashboard-review-');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await support.delete(recursive: true);
  });
  test(
    'queued optimistic edit rechecks after another transaction commits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _HeldStore();
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: store,
        nativePushSupported: false,
      );
      final old = await manager.saveConnection(
        'Original',
        '127.0.0.1',
        8642,
        '',
      );
      final epoch = ConnectionMutationBarrier.capture(old.id);
      store.entered = Completer<void>();
      final release = store.release = Completer<void>();
      final blocker = manager.saveConnection('Other', '127.0.0.1', 8642, '');
      await store.entered!.future;
      final stale = manager.updateConnection(
        old.id,
        'Stale',
        old.host,
        old.port,
        '',
        expectedConnection: old,
        expectedMutationEpoch: epoch,
      );
      final rejected = expectLater(
        stale,
        throwsA(isA<CredentialStorageException>()),
      );
      final external = manager.updateConnection(
        old.id,
        'External',
        old.host,
        old.port,
        '',
      );
      release.complete();
      await blocker;
      await rejected;
      await external;
      expect(
        manager.getConnections().firstWhere((c) => c.id == old.id).label,
        'External',
      );
    },
  );
  test(
    'legacy credential bundles retain historical whitespace normalization',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = MemoryStore();
      final prefs = await SharedPreferences.getInstance();
      final manager = ConnectionManager(
        prefs,
        credentialStore: store,
        nativePushSupported: false,
      );
      await manager.saveConnection(
        'Basic',
        '127.0.0.1',
        8642,
        '',
        dashboardUsername: 'alice',
        dashboardPassword: 'secret',
      );
      final key = store.values.keys.singleWhere(
        (key) =>
            jsonDecode(store.values[key]!) is Map &&
            (jsonDecode(store.values[key]!) as Map).containsKey(
              'dashboard_password',
            ),
      );
      store.values[key] = jsonEncode({'dashboard_password': '  legacy  '});
      await manager.initialize();
      expect(manager.getConnections().single.dashboardPassword, 'legacy');
    },
  );
  test(
    'optimistic epoch rejects ABA edits despite identical restored metadata',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: MemoryStore(),
        nativePushSupported: false,
      );
      final old = await manager.saveConnection(
        'Original',
        '127.0.0.1',
        8642,
        '',
      );
      final epoch = ConnectionMutationBarrier.capture(old.id);
      await manager.updateConnection(
        old.id,
        'Temporary',
        old.host,
        old.port,
        '',
      );
      await manager.updateConnection(old.id, old.label, old.host, old.port, '');
      await expectLater(
        manager.updateConnection(
          old.id,
          'Stale',
          old.host,
          old.port,
          '',
          expectedConnection: old,
          expectedMutationEpoch: epoch,
        ),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(manager.getConnections().single.label, 'Original');
    },
  );
  testWidgets(
    'Dashboard settings saves existing native HTTP loopback configuration',
    (tester) async {
      final manager = await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await manager.saveConnection(
        'Native',
        '127.0.0.1',
        8642,
        '',
        requireDashboardNativeSignIn: true,
      );
      await openEdit(tester, manager);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard / Proxy Settings'));
      await tester.pumpAndSettle();
      final profile = find.widgetWithText(
        TextField,
        'Hermes profile (optional)',
      );
      await tester.ensureVisible(profile);
      await tester.enterText(profile, 'research');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(manager.getConnections().single.gatewayProfile, 'research');
      expect(
        await manager.dashboardNativeAuthStatus(
          manager.getConnections().single,
        ),
        DashboardNativeSessionStatus.signedOut,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final url in [
    'http://remote.example.test',
    'http://127.0.0.1:9119/?secret=1',
    'http://user@127.0.0.1:9119',
    'http://127.0.0.1:9119/#fragment',
  ]) {
    testWidgets('Dashboard native settings rejects unsafe destination $url', (
      tester,
    ) async {
      final manager = await openAdd(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final old = await manager.saveConnection(
        'Native',
        '127.0.0.1',
        8642,
        '',
        requireDashboardNativeSignIn: true,
      );
      await openEdit(tester, manager);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard / Proxy Settings'));
      await tester.pumpAndSettle();
      final origin = find.widgetWithText(
        TextField,
        'Dashboard URL / trusted origin',
      );
      await tester.ensureVisible(origin);
      await tester.enterText(origin, url);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await drain(tester);
      expect(
        find.text(
          'Browser sign-in requires an HTTPS dashboard URL without credentials, query parameters or fragments.',
        ),
        findsOneWidget,
      );
      expect(manager.getConnections().single.toMap(), old.toMap());
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('held health edit cannot overwrite an external saved mutation', (
    tester,
  ) async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = RealHttp();
    addTearDown(() => HttpOverrides.global = overrides);
    final arrived = Completer<void>();
    final release = Completer<void>();
    late HttpServer api;
    await tester.runAsync(() async {
      api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api.listen((request) async {
        if (!arrived.isCompleted) arrived.complete();
        await release.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
    });
    addTearDown(() => api.close(force: true));
    final manager = await openAdd(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final old = await manager.saveConnection(
      'Original',
      '127.0.0.1',
      api.port,
      '',
      requireDashboardNativeSignIn: true,
    );
    await openEdit(tester, manager);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && !arrived.isCompleted; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(arrived.isCompleted, isTrue);
    await tester.runAsync(
      () => manager.updateConnection(
        old.id,
        'External',
        '127.0.0.1',
        api.port,
        '',
        gatewayProfile: 'new-profile',
        requireDashboardNativeSignIn: true,
      ),
    );
    release.complete();
    await drain(tester);
    expect(manager.getConnections().single.label, 'External');
    expect(manager.getConnections().single.gatewayProfile, 'new-profile');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
