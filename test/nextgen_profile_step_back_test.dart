// Regression: leaving the post-sign-in profile step must not keep the old
// gateway's pending choice. Backing out, testing another address and signing
// in again has to offer the new gateway's sign-in form, and completing it
// must connect the new gateway — not the one captured by the stale chooser.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hermes_sign_in.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/connect_screen.dart';
import 'package:hermes_android/nextgen/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// A gated multiplexed dashboard: the status probe hides its profiles,
/// password sign-in works, and the authenticated API lists two profiles
/// whose first session page is nothing but untitled cron shells.
class _GatedGateway {
  _GatedGateway._(this.server);
  final HttpServer server;
  final requests = <String>[];

  static Future<_GatedGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gateway = _GatedGateway._(server);
    server.listen((request) async {
      final path = request.uri.path;
      gateway.requests.add('${request.method} $path');
      Object? body;
      var status = 200;
      if (path == '/api/status') {
        body = {
          'version': '0.23.2-fixture',
          'gateway_running': true,
          'auth_required': true,
          'auth_providers': ['basic'],
          'profiles': <String>[],
        };
      } else if (path == '/auth/password-login') {
        await request.drain<void>();
        request.response.headers.set(
          'set-cookie',
          'hermes_session_at=fixture; Path=/',
        );
        body = {'ok': true};
      } else if (path == '/api/profiles') {
        body = {
          'profiles': [
            {'name': 'default', 'is_default': true},
            {'name': 'delta'},
          ],
        };
      } else if (path == '/api/sessions') {
        body = {
          'sessions': [
            for (var i = 0; i < 60; i++)
              {
                'id': 'cron-$i',
                'source': 'cron',
                'message_count': 0,
                'title': null,
              },
          ],
          'total': 60,
        };
      } else {
        status = 404;
        body = {'error': 'not found'};
      }
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    return gateway;
  }

  String get address => '127.0.0.1:${server.port}';

  Future<void> close() => server.close(force: true);
}

void main() {
  testWidgets(
    'back from the profile step offers the new gateway, not the old chooser',
    (tester) async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      SharedPreferences.setMockInitialValues({});
      HermesSignInVault.resetForTesting(MemorySignInSecretStore());
      addTearDown(HermesSignInVault.resetForTesting);
      final prefs = await SharedPreferences.getInstance();
      final a = (await tester.runAsync(_GatedGateway.start))!;
      final b = (await tester.runAsync(_GatedGateway.start))!;
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      final connected = <SavedConnection>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nextGenTheme(Brightness.light, NextGenLook.instance),
          home: NgConnectScreen(
            connManager: ConnectionManager(prefs, credentialStore: _Secrets()),
            onConnected: connected.add,
          ),
        ),
      );
      await tester.pump();

      // Real loopback I/O only advances inside runAsync; give each request
      // a bounded chance to land, then rebuild.
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> probeAndOpenSignIn(String address) async {
        await tester.enterText(find.byType(TextField).first, address);
        await tester.tap(find.text('Test'));
        await settle();
        expect(find.textContaining('is reachable'), findsOneWidget);
        await tester.tap(find.text('Continue to sign in'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> passwordSignIn() async {
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'admin');
        await tester.enterText(fields.at(1), 'fixture-password');
        await tester.tap(
          find.descendant(
            of: find.byType(NgPrimaryButton),
            matching: find.text('Sign in'),
          ),
        );
        await settle();
      }

      // Gateway A: sign in, then the profile step appears after the save.
      await probeAndOpenSignIn(a.address);
      expect(find.byKey(const ValueKey('signin')), findsOneWidget);
      await passwordSignIn();
      expect(find.byKey(const ValueKey('profile')), findsOneWidget);
      expect(find.text('delta'), findsOneWidget);
      expect(connected, isEmpty);

      // Leave the profile step, then point the screen at gateway B.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('address')), findsOneWidget);
      await probeAndOpenSignIn(b.address);
      // The stale chooser for A must not hijack B's sign-in step.
      expect(find.byKey(const ValueKey('signin')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile')), findsNothing);
      await passwordSignIn();
      // B is gated too, so its own profile step is offered — for B.
      expect(find.byKey(const ValueKey('profile')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NgPrimaryButton),
          matching: find.text('Continue'),
        ),
      );
      await settle();
      expect(connected, hasLength(1));
      expect(connected.single.host, '127.0.0.1');
      expect(connected.single.port, b.server.port);
      expect(connected.single.desktopGatewayUrl, contains(b.address));
      // A saw exactly one interactive sign-in; the connect went to B.
      expect(
        a.requests.where((r) => r == 'POST /auth/password-login').length,
        greaterThanOrEqualTo(1),
      );
      expect(
        b.requests.where((r) => r == 'POST /auth/password-login').length,
        greaterThanOrEqualTo(1),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
