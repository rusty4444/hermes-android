import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'dashboard_auth_onboarding_test.dart' show openAdd, selectMode;
import 'dashboard_oidc_edit_security_test.dart' show openEdit;
import 'dashboard_native_auth_security_test.dart' show RealHttp;

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _turn(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in [
    'mutate',
    'unsafe-url',
    'edit-mutate',
    'unchanged',
    'dismiss',
    'failure',
  ]) {
    testWidgets('OIDC consent remains bound across held health: $action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paths = PathProviderPlatform.instance;
      final support = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('consent-race-'),
      ))!;
      PathProviderPlatform.instance = _Paths(support.path);
      addTearDown(() async {
        PathProviderPlatform.instance = paths;
        await support.delete(recursive: true);
      });
      final overrides = HttpOverrides.current;
      HttpOverrides.global = RealHttp();
      addTearDown(() => HttpOverrides.global = overrides);
      final entered = Completer<void>();
      final release = Completer<void>();
      final requests = <String>[];
      late HttpServer api;
      await tester.runAsync(() async {
        api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        api.listen((request) async {
          requests.add(request.uri.path);
          if (!entered.isCompleted) entered.complete();
          await release.future;
          request.response.statusCode = action == 'failure' ? 503 : 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
          await request.response.close();
        });
      });
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await api.close(force: true);
      });
      final manager = await openAdd(tester);
      if (action == 'edit-mutate') {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await manager.saveConnection(
          'Existing',
          '127.0.0.1',
          api.port,
          'consented-key',
        );
        await openEdit(tester, manager);
      }
      final before = manager.getConnections().map((c) => c.toMap()).toList();
      final launches = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        launches.add((call.arguments as Map)['url'] as String);
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<void> fill(String label, String value) =>
          tester.enterText(find.widgetWithText(TextField, label), value);
      await fill('Host', '127.0.0.1');
      await fill('Port', '${api.port}');
      await fill('API Key', 'consented-key');
      await selectMode(tester, 'OIDC');
      await fill(
        'Desktop Gateway URL (optional)',
        'https://consented.example.test/proxy',
      );
      await fill('Hermes profile (optional)', 'research');
      await tester.tap(find.text('Custom proxy and dashboard details'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      final values = {
        for (final field in fields)
          field.decoration!.labelText!: field.controller!.text,
      };
      final preview = tester
          .widget<Text>(find.byKey(const Key('dashboard_resolved_destination')))
          .data;
      expect(preview, contains('https://consented.example.test:443/proxy'));
      await tester.tap(
        action == 'edit-mutate'
            ? find.widgetWithText(OutlinedButton, 'Save & sign in with browser')
            : find.widgetWithText(FilledButton, 'Save & sign in with browser'),
      );
      for (var i = 0; i < 200 && !entered.isCompleted; i++) {
        await _turn(tester);
      }
      expect(
        entered.isCompleted,
        isTrue,
        reason: 'health fixture must be held before mutation',
      );
      expect(manager.getConnections().map((c) => c.toMap()).toList(), before);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse, reason: field.decoration?.labelText);
      }
      expect(
        tester
            .widget<DropdownButtonFormField<dynamic>>(
              find.byKey(const Key('dashboard_auth_mode')),
            )
            .onChanged,
        isNull,
      );
      for (final toggle in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(toggle.onChanged, isNull);
      }
      if (action == 'mutate' || action == 'edit-mutate') {
        // Adversarial controller changes supplement the disabled-input checks:
        // security must not depend solely on UI event suppression.
        for (final field in fields) {
          field.controller!.text = switch (field.decoration!.labelText) {
            'Host' => 'attacker.invalid',
            'Port' || 'Dashboard Port' => '1234',
            'Desktop Gateway URL (optional)' =>
              'http://user@attacker.invalid/unsafe?secret=yes#fragment',
            'Hermes profile (optional)' => 'attacker',
            _ => 'changed',
          };
        }
        await tester.pump();
      }
      if (action == 'unsafe-url') {
        fields
                .singleWhere(
                  (field) =>
                      field.decoration?.labelText ==
                      'Desktop Gateway URL (optional)',
                )
                .controller!
                .text =
            'http://user@attacker.invalid/unsafe?secret=yes#fragment';
        await tester.pump();
      }
      if (action == 'mutate' || action == 'unsafe-url') {
        expect(
          tester
              .widget<Text>(
                find.byKey(const Key('dashboard_resolved_destination')),
              )
              .data,
          preview,
        );
      }
      if (action == 'dismiss') {
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        // Release before reverse transition unmounts the dialog.
        await tester.pump();
      }
      release.complete();
      for (
        var i = 0;
        i < 200 &&
            (action == 'dismiss' || action == 'failure'
                ? i < 40
                : launches.isEmpty);
        i++
      ) {
        await _turn(tester);
      }
      if (action == 'dismiss' || action == 'failure') {
        expect(manager.getConnections(), isEmpty);
        expect(launches, isEmpty);
        if (action == 'failure') {
          for (final field in tester.widgetList<TextField>(
            find.byType(TextField),
          )) {
            expect(field.controller!.text, values[field.decoration!.labelText]);
            expect(field.enabled, isNot(false));
          }
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
      } else {
        expect(manager.getConnections(), hasLength(1));
        final saved = manager.getConnections().single;
        expect(saved.host, '127.0.0.1');
        expect(saved.port, api.port);
        expect(saved.apiKey, 'consented-key');
        expect(saved.gatewayProfile, 'research');
        expect(saved.desktopGatewayUrl, 'https://consented.example.test/proxy');
        expect(
          DesktopGatewayClient.normalizedGatewayBaseUrl(saved),
          'https://consented.example.test:443/proxy',
        );
        expect(launches, hasLength(1));
        expect(
          Uri.parse(launches.single).origin,
          'https://consented.example.test',
        );
        expect(Uri.parse(launches.single).path, '/proxy/auth/native/authorize');
        expect(requests, contains('/health'));
        expect(
          requests.where(
            (path) => path.contains('auth/') || path.contains('model/info'),
          ),
          isEmpty,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await _turn(tester);
      }
    });
  }
}
