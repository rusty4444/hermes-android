// NextGen parity: attachments, client certificates, notification routing,
// wider discovery and localized text.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hermes_sign_in.dart';
import 'package:hermes_android/core/services/lan_discovery_service.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_l10n.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/connect_screen.dart';
import 'package:hermes_android/nextgen/ui/main_page.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/internal_background_message_fixture.dart';

class _Secrets implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HermesSignInVault.resetForTesting(MemorySignInSecretStore());
    nextGenEnabled.value = false;
    nextGenOpenRequest.value = null;
  });

  group('attachments', () {
    test('history @file: lines become file pills, not text', () {
      final (body, files) = splitFileRefs(
        'Look at these\n\n@file:/tmp/up/photo.jpg\n@file:`/srv/a b.pdf`',
      );
      expect(body, 'Look at these');
      expect(files, ['photo.jpg', 'a b.pdf']);
    });

    test('text without references is unchanged', () {
      final (body, files) = splitFileRefs('Email me at a@file:x');
      expect(body, 'Email me at a@file:x');
      expect(files, isEmpty);
    });
  });

  group('notification taps', () {
    test('go to NextGen only while it is on and name a chat', () {
      expect(routeNotificationToNextGen('c1', 's1'), isFalse);
      expect(nextGenOpenRequest.value, isNull);

      nextGenEnabled.value = true;
      expect(routeNotificationToNextGen('c1', null), isFalse);
      expect(routeNotificationToNextGen('', 's1'), isFalse);
      expect(routeNotificationToNextGen('c1', 's1'), isTrue);
      expect(nextGenOpenRequest.value, (connectionId: 'c1', sessionId: 's1'));
    });
  });

  group('discovery', () {
    test('probes saved hosts first, then sweeps every port', () {
      final service = LanDiscoveryService.dashboards(
        extraPorts: [9200],
        extraTargets: const [DiscoveryTarget('box.tail1234.ts.net', 9119)],
      );
      final targets = service.candidateTargets([
        InternetAddress('192.168.4.7'),
      ]);
      expect(targets.first, const DiscoveryTarget('box.tail1234.ts.net', 9119));
      expect(targets, contains(const DiscoveryTarget('192.168.4.1', 9119)));
      expect(targets, contains(const DiscoveryTarget('192.168.4.1', 9200)));
      expect(targets.length, 1 + 254 * 2);
      expect(targets.toSet().length, targets.length);
    });

    test('rejects invalid extra ports', () {
      expect(
        () => LanDiscoveryService(extraPorts: [70000]),
        throwsArgumentError,
      );
    });

    test('finds a dashboard on a saved Tailscale host', () async {
      final seen = <Uri>[];
      final service = LanDiscoveryService.dashboards(
        resolveAddresses: () async => [],
        extraTargets: const [DiscoveryTarget('100.64.0.9', 9119)],
        clientFactory: () => MockClient((request) async {
          seen.add(request.url);
          if (request.url.scheme == 'http') {
            return http.Response(
              jsonEncode({'version': '0.9', 'auth_required': true}),
              200,
            );
          }
          return http.Response('', 404);
        }),
      );
      final found = await service.discover();
      expect(found.single.connectionUrl, 'http://100.64.0.9:9119');
      expect(seen.first.path, '/api/status');
    });

    test('saved connections supply their hosts and dashboard ports', () {
      final targets = knownDiscoveryTargets([
        SavedConnection(
          id: 'a',
          label: 'Tail',
          host: 'box.tail1234.ts.net',
          port: 443,
          apiKey: '',
          useHttps: true,
          desktopGatewayUrl: 'https://box.tail1234.ts.net',
          singleLogin: true,
        ),
        SavedConnection(
          id: 'b',
          label: 'Lan',
          host: '10.0.0.5',
          port: 8642,
          apiKey: 'k',
          dashboardPortOverride: 9200,
        ),
      ]);
      expect(
        targets,
        containsAll(const [
          DiscoveryTarget('box.tail1234.ts.net', 443),
          DiscoveryTarget('box.tail1234.ts.net', 9119),
          DiscoveryTarget('10.0.0.5', 9200),
          DiscoveryTarget('10.0.0.5', 9119),
        ]),
      );
    });
  });

  group('client certificates', () {
    test('a single-login save can replace or clear the certificate', () async {
      final prefs = await SharedPreferences.getInstance();
      final manager = ConnectionManager(prefs, credentialStore: _Secrets());
      final url = GatewayUrl.parse('https://hermes.example.com');
      const cert = ClientCertificateConfig(
        label: 'phone',
        certificatePemPath: '/nonexistent/cert.pem',
        privateKeyPemPath: '/nonexistent/key.pem',
      );
      final saved = await manager.saveSingleLoginConnection(
        url: url,
        signInMethod: 'none',
        clientCertificate: cert,
      );
      expect(saved.clientCertificate?.label, 'phone');

      final kept = await manager.saveSingleLoginConnection(
        url: url,
        signInMethod: 'none',
      );
      expect(kept.clientCertificate?.label, 'phone');

      final cleared = await manager.saveSingleLoginConnection(
        url: url,
        signInMethod: 'none',
        clearClientCertificate: true,
      );
      expect(cleared.clientCertificate, isNull);
    });
  });

  group('localized text', () {
    test('every ng_ key is translated in every locale', () {
      final dir = Directory('lib/l10n');
      final en =
          jsonDecode(File('${dir.path}/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final keys = en.keys.where((k) => k.startsWith('ng_')).toList();
      expect(keys.length, greaterThan(300));
      final placeholder = RegExp(r'\{(\w+)\}');
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.arb') || file.path.endsWith('app_en.arb')) {
          continue;
        }
        final other =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final key in keys) {
          expect(other[key], isA<String>(), reason: '${file.path} $key');
          final want = placeholder
              .allMatches(en[key] as String)
              .map((m) => m[1])
              .toSet();
          final got = placeholder
              .allMatches(other[key] as String)
              .map((m) => m[1])
              .toSet();
          expect(got, want, reason: '${file.path} $key');
        }
      }
    });

    testWidgets('NextGen text follows the app language', (tester) async {
      Widget app(Locale locale) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => NgLocalizationScope(child: child!),
        home: Builder(builder: (_) => Text(ngL.ng_new_chat)),
      );
      await tester.pumpWidget(app(const Locale('en')));
      expect(find.text('New chat'), findsOneWidget);
      await tester.pumpWidget(app(const Locale('de')));
      await tester.pump();
      final german = lookupAppLocalizations(const Locale('de')).ng_new_chat;
      expect(german, isNot('New chat'));
      expect(find.text(german), findsOneWidget);
      expect(NgConnectionPhase.connected.name, 'connected');
      // Back to English so other tests read English.
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pump();
    });
  });

  testWidgets('back opens the sidebar, then leaves the app', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final conn = SavedConnection(
      id: 'c1',
      label: 'Home',
      host: '10.0.0.5',
      port: 9119,
      apiKey: '',
      desktopGatewayUrl: 'http://10.0.0.5:9119',
      singleLogin: true,
      signInMethod: 'none',
    );
    final gateway = NextGenGateway(conn);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: nextGenTheme(Brightness.light, NextGenLook.instance),
        home: NgScope(
          connManager: ConnectionManager(prefs),
          gateway: gateway,
          connections: [conn],
          switchTo: (_) async {},
          addGateway: () async {},
          signOut: (_) async {},
          reload: () async {},
          signInAgain: () async {},
          child: NavigatorPopHandler(
            onPopWithResult: (_) => navigator.currentState?.maybePop(),
            child: Navigator(
              key: navigator,
              onGenerateInitialRoutes: (_, _) => [
                MaterialPageRoute<void>(builder: (_) => const NgMainPage()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    ScaffoldState scaffold() =>
        tester.state<ScaffoldState>(find.byType(Scaffold).first);
    expect(scaffold().isDrawerOpen, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(scaffold().isDrawerOpen, isTrue);
    expect(calls, isNot(contains('SystemNavigator.pop')));

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls, contains('SystemNavigator.pop'));

    await tester.pumpWidget(const SizedBox());
    gateway.dispose();
  });

  group('background results and runtime notices', () {
    late NextGenGateway gateway;
    late NgChatController chat;
    setUp(() {
      gateway = NextGenGateway(
        SavedConnection(
          id: 'c1',
          label: 'Home',
          host: '10.0.0.5',
          port: 9119,
          apiKey: '',
          desktopGatewayUrl: 'http://10.0.0.5:9119',
          singleLogin: true,
          signInMethod: 'none',
        ),
      );
      chat = NgChatController(gateway, sessionId: 'stored')..runtimeId = 'rt';
    });
    tearDown(() {
      chat.dispose();
      gateway.dispose();
    });

    test('every backend notice collapses into a card', () {
      for (final entry in internalBackgroundMessageFixtures().entries) {
        final row = Map<String, dynamic>.from(entry.value['row'] as Map);
        chat.debugApplyHistory([
          {'role': 'user', 'content': 'Question'},
          row,
          {'role': 'assistant', 'content': 'Answer'},
        ]);
        final cards = chat.items.whereType<NgSystemItem>().toList();
        expect(cards, hasLength(1), reason: entry.key);
        expect(
          cards.single.kind,
          entry.value['expected'] == 'process'
              ? NgSystemKind.process
              : NgSystemKind.task,
          reason: entry.key,
        );
        expect(cards.single.expanded, isFalse);
        expect(chat.items.whereType<NgUserItem>().single.text, 'Question');
        // The card stays between the question and the next answer.
        expect(chat.items[1], isA<NgSystemItem>(), reason: entry.key);
      }
    });

    test('hidden rows are skipped and merged human input stays', () {
      chat.debugApplyHistory([
        {'role': 'user', 'content': 'secret', 'display_kind': 'hidden'},
        ...mergedInternalBackgroundMessageFixtures().values.map(
          (v) => Map<String, dynamic>.from(v['api'] as Map),
        ),
      ]);
      expect(chat.items.whereType<NgSystemItem>(), isEmpty);
      expect(chat.items.whereType<NgUserItem>(), isNotEmpty);
    });

    test('a long live notice collapses, a short one stays a line', () async {
      final batch =
          '[ASYNC DELEGATION BATCH — COMPLETE — deleg_d29132bc]\n'
          'A background fan-out unit you dispatched earlier has finished.\n'
          '${'Detail line. ' * 30}';
      gateway.debugEmit(
        StreamEvent(type: 'notice', data: {'message': batch}, sessionId: 'rt'),
      );
      gateway.debugEmit(
        StreamEvent(
          type: 'notice',
          data: const {'message': 'Switched to fallback model'},
          sessionId: 'rt',
        ),
      );
      await pumpEventQueue();
      final card = chat.items.whereType<NgSystemItem>().single;
      expect(card.body, batch.trim());
      expect(card.preview, startsWith('ASYNC DELEGATION BATCH'));
      expect(
        chat.items.whereType<NgNoticeItem>().single.text,
        'Switched to fallback model',
      );
    });
  });

  group('delivered files', () {
    test('code fences are kept apart and verbatim', () {
      const text = 'Before\n```\nMEDIA:/tmp/a.apk\n```\nAfter';
      final runs = ngSplitCodeFences(text);
      expect(runs.map((r) => r.$2), [false, true, false]);
      expect(runs.map((r) => r.$1).join(), text);
      expect(runs[1].$1, '```\nMEDIA:/tmp/a.apk\n```\n');
      expect(ngSplitCodeFences('```\nopen').single, ('```\nopen', true));
    });

    testWidgets('MEDIA: lines in a reply become file cards', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final conn = SavedConnection(
        id: 'c1',
        label: 'Home',
        host: '10.0.0.5',
        port: 9119,
        apiKey: '',
        desktopGatewayUrl: 'http://10.0.0.5:9119',
        singleLogin: true,
        signInMethod: 'none',
      );
      final gateway = NextGenGateway(conn);
      final chat = NgChatController(gateway, sessionId: 'stored');
      chat.debugApplyHistory([
        {'role': 'user', 'content': 'Build it'},
        {
          'role': 'assistant',
          'content':
              'Done:\n\nMEDIA:/tmp/parallax-build-d784060def3d-arm64.apk\n\n'
              '```\nMEDIA:/tmp/example.apk\n```',
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nextGenTheme(Brightness.light, NextGenLook.instance),
          home: NgScope(
            connManager: ConnectionManager(prefs),
            gateway: gateway,
            connections: [conn],
            switchTo: (_) async {},
            addGateway: () async {},
            signOut: (_) async {},
            reload: () async {},
            signInAgain: () async {},
            child: Scaffold(
              body: NgChatView(
                chat: chat,
                onOpenSidebar: () {},
                onNewChat: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final card = tester.widget<MediaArtifactCard>(
        find.byType(MediaArtifactCard),
      );
      expect(card.ref.path, '/tmp/parallax-build-d784060def3d-arm64.apk');
      expect(
        find.textContaining('MEDIA:/tmp/parallax-build', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('MEDIA:/tmp/example.apk', findRichText: true),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
      gateway.dispose();
    });
  });
}
