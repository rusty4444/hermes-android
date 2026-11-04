// Issue #253 remaining scope: an API-key-only connection sending into a
// Dashboard-owned chat gets an in-band `permission_denied` refusal from the
// gateway's canonical session authority. The refusal is intentional server
// policy, so this coverage pins the *diagnostics* contract only:
//
//   * the server's own refusal text survives verbatim (it is a strict prefix
//     of the richer message, in every shipped locale);
//   * the extra guidance appears only for an access-control denial on a
//     connection that genuinely has no Dashboard credentials and no explicit
//     Desktop Gateway origin;
//   * nothing about transport, principal selection or retry changes — the
//     failing send still issues exactly one POST and is never replayed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/widgets/chat_activity_bar.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/l10n_test_utils.dart';
import 'support/pump_chat_updates.dart';

/// The reporter's connection: an API-server bearer key and nothing else.
SavedConnection _apiOnly({int port = 8642}) => SavedConnection(
  id: 'api-only',
  label: 'API only',
  host: '127.0.0.1',
  port: port,
  apiKey: 'fixture-key',
);

void main() {
  setUp(mockChatImageRecovery);

  group('shouldExplainApiOnlyPermissionDenial', () {
    test('explains an API-only permission_denied refusal', () {
      expect(
        shouldExplainApiOnlyPermissionDenial(_apiOnly(), 'permission_denied'),
        isTrue,
      );
      expect(
        shouldExplainApiOnlyPermissionDenial(
          _apiOnly(),
          'RuntimeStoreError: permission_denied',
        ),
        isTrue,
      );
    });

    test('stays silent for refusals that are not access denials', () {
      for (final error in const [
        'HTTP 500: internal server error',
        'TimeoutException after 0:00:30.000000',
        'Connection closed before full header was received',
        'SocketException: Connection refused',
        'HTTP 429: rate limited',
      ]) {
        expect(
          shouldExplainApiOnlyPermissionDenial(_apiOnly(), error),
          isFalse,
          reason: error,
        );
      }
    });

    test('stays silent when Dashboard credentials are configured', () {
      expect(
        shouldExplainApiOnlyPermissionDenial(
          SavedConnection(
            id: 'dash',
            label: 'Dashboard',
            host: '127.0.0.1',
            port: 8642,
            apiKey: 'fixture-key',
            dashboardUsername: 'admin',
            dashboardPassword: 'fixture-password',
          ),
          'permission_denied',
        ),
        isFalse,
      );
    });

    test('stays silent for a dashboard-proxied connection', () {
      expect(
        shouldExplainApiOnlyPermissionDenial(
          SavedConnection(
            id: 'proxied',
            label: 'Proxied',
            host: '127.0.0.1',
            port: 8642,
            apiKey: 'fixture-key',
            dashboardProxied: true,
          ),
          'permission_denied',
        ),
        isFalse,
      );
    });

    test('stays silent when an explicit Desktop Gateway URL is set', () {
      expect(
        shouldExplainApiOnlyPermissionDenial(
          SavedConnection(
            id: 'desktop',
            label: 'Desktop',
            host: '127.0.0.1',
            port: 8642,
            apiKey: 'fixture-key',
            desktopGatewayUrl: 'http://127.0.0.1:9119',
          ),
          'permission_denied',
        ),
        isFalse,
      );
    });

    test('treats blank credentials as absent, not as Dashboard access', () {
      expect(
        shouldExplainApiOnlyPermissionDenial(
          SavedConnection(
            id: 'blank',
            label: 'Blank',
            host: '127.0.0.1',
            port: 8642,
            apiKey: 'fixture-key',
            dashboardUsername: '  ',
            dashboardPassword: '  ',
            desktopGatewayUrl: '  ',
          ),
          'permission_denied',
        ),
        isTrue,
      );
      // A username without a password is not Dashboard access either.
      expect(
        shouldExplainApiOnlyPermissionDenial(
          SavedConnection(
            id: 'half',
            label: 'Half',
            host: '127.0.0.1',
            port: 8642,
            apiKey: 'fixture-key',
            dashboardUsername: 'admin',
          ),
          'permission_denied',
        ),
        isTrue,
      );
    });

    test('is pure: no transport, principal or retry is reachable from it', () {
      // The helper only reads value fields off the connection plus the error
      // string, so it cannot resend, reroute or switch principals. Calling it
      // repeatedly must be free of observable effects.
      final connection = _apiOnly();
      final results = List.generate(
        5,
        (_) => shouldExplainApiOnlyPermissionDenial(
          connection,
          'permission_denied',
        ),
      );
      expect(results, everyElement(isTrue));
    });
  });

  group('send_failed_api_only_permission_denied copy', () {
    test('appends guidance without replacing the server refusal', () async {
      final l10n = await loadTestL10n();
      const refusal = 'permission_denied';
      final plain = l10n.send_failed(refusal);
      final guided = l10n.send_failed_api_only_permission_denied(refusal);

      expect(plain, 'Send failed: permission_denied');
      // Strictly additive: the untouched refusal is still the whole opening.
      expect(guided, startsWith(plain));
      expect(guided, contains(refusal));
      expect(guided.length, greaterThan(plain.length));
    });

    test('phrases the cause conditionally, never as a diagnosis', () async {
      final l10n = await loadTestL10n();
      final guided = l10n.send_failed_api_only_permission_denied(
        'permission_denied',
      );
      // Possible cause plus what to check...
      expect(guided, contains('may let it send'));
      // ...and an explicit acknowledgement that the denial can be policy.
      expect(guided, contains('may also be refusing deliberately'));
      // Never asserts that the denial *is* a credentials problem.
      expect(guided, isNot(contains('because')));
      expect(guided.toLowerCase(), isNot(contains('you must')));
    });
  });

  group('l10n coverage', () {
    test('every shipped ARB defines a non-empty translation', () {
      final arbs = Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb'))
          .toList();
      expect(arbs, hasLength(AppLocalizations.supportedLocales.length));
      for (final file in arbs) {
        final catalogue =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final value =
            catalogue['send_failed_api_only_permission_denied'] as String?;
        expect(value, isNotNull, reason: file.path);
        expect(value!.trim(), isNotEmpty, reason: file.path);
        expect(value, contains('{error}'), reason: file.path);
      }
    });

    for (final locale in AppLocalizations.supportedLocales) {
      final code = locale.toString();
      test('$code renders a real translation that stays additive', () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final english = await AppLocalizations.delegate.load(
          const Locale('en'),
        );
        const refusal = 'permission_denied';
        final guided = l10n.send_failed_api_only_permission_denied(refusal);

        expect(guided.trim(), isNotEmpty);
        // The gateway's own words are preserved in every locale.
        expect(guided, contains(refusal));
        expect(guided, startsWith(l10n.send_failed(refusal)));
        expect(
          guided.length,
          greaterThan(l10n.send_failed(refusal).length),
          reason: '$code must add guidance, not just restate the refusal',
        );
        if (locale.languageCode != 'en') {
          expect(
            guided,
            isNot(english.send_failed_api_only_permission_denied(refusal)),
            reason: '$code must not fall back to English',
          );
        }
      });
    }
  });

  testWidgets(
    'API-only refusal shows guidance, keeps the refusal and never resends',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final fixture = await tester.runAsync(_ApiOnlyGateway.start);
      final gateway = fixture!;
      final controller = GatewayTurnApplicationController();
      addTearDown(() async {
        await controller.close();
        await gateway.close();
      });
      final connection = _apiOnly(port: gateway.server.port);
      final l10n = await loadTestL10n();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(
            connection: connection,
            session: const Session(
              id: 'S1',
              title: 'Dashboard-owned chat',
              model: 'fixture',
              source: 'desktop',
              messageCount: 2,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            turnApplicationController: controller,
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await _flush(tester);
      await tester.enterText(find.byType(TextField), 'Routing probe');
      await tester.tap(find.byTooltip('Send'));
      await _flush(tester);

      // Unchanged routing: one API-server completion as the key principal.
      expect(gateway.completions, hasLength(1));
      expect(gateway.completions.single['authorization'], 'Bearer fixture-key');
      // No dashboard principal was ever reached for.
      expect(gateway.loginBodies, isEmpty);
      expect(gateway.ticketRequests, 0);

      final notice = tester
          .widgetList<ChatActivityBar>(find.byType(ChatActivityBar))
          .where((bar) => bar.isTerminalNotice)
          .single;
      // The server's refusal is still shown verbatim, with guidance appended.
      expect(notice.text, contains('permission_denied'));
      expect(notice.text, contains('API key principal'));
      expect(notice.text, contains('may also be refusing deliberately'));

      // Recover whatever the transport reported by splitting the template on a
      // sentinel, so the refusal text itself is never assumed.
      const sentinel = '\u0000';
      final template = l10n.send_failed_api_only_permission_denied(sentinel);
      final head = template.split(sentinel).first;
      final tail = template.split(sentinel).last;
      expect(notice.text, startsWith(head));
      expect(notice.text, endsWith(tail));
      final reported = notice.text.substring(
        head.length,
        notice.text.length - tail.length,
      );
      expect(reported, contains('permission_denied'));
      expect(
        notice.text,
        l10n.send_failed_api_only_permission_denied(reported),
      );
      // The plain message is a strict prefix: nothing was rewritten or hidden.
      expect(notice.text, startsWith(l10n.send_failed(reported)));

      // Settling further must not replay the refused write.
      await _flush(tester);
      expect(gateway.completions, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.close);
      await _flush(tester);
    },
  );
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Stock gateway v0.22.5 behaviour for an API-key principal writing into a
/// Dashboard-owned chat: reads succeed, and the write is refused in band with
/// an HTTP 200 SSE error frame. No ACL engine is simulated or claimed.
class _ApiOnlyGateway {
  _ApiOnlyGateway(this.server);
  final HttpServer server;
  final completions = <Map<String, dynamic>>[];
  final loginBodies = <Object?>[];
  final apiReads = <String>[];
  int ticketRequests = 0;

  static Future<_ApiOnlyGateway> start() async {
    final gateway = _ApiOnlyGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen(gateway.handle);
    return gateway;
  }

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/auth/password-login') {
      loginBodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.write('{"ok":true}');
    } else if (path == '/api/auth/ws-ticket') {
      ticketRequests++;
      request.response.statusCode = 401;
    } else if (path == '/v1/chat/completions') {
      completions.add({
        'authorization': request.headers.value('authorization'),
        'body': jsonDecode(await utf8.decoder.bind(request).join()),
      });
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"error"}],'
        '"usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0},'
        '"error":{"message":"permission_denied","type":"RuntimeStoreError"}}\n\n'
        'data: [DONE]\n\n',
      );
    } else if (request.method == 'GET') {
      apiReads.add(path);
      request.response.write(
        jsonEncode({
          'object': 'list',
          'data': <Object>[],
          'session': {'id': 'S1', 'user_id': 'basic:admin', 'archived': false},
        }),
      );
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  Future<void> close() async => server.close(force: true);
}
