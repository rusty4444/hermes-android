import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/legal_links.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _connection() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
  dashboardProxied: true,
);

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _app(
  NgChatController chat,
  NextGenGateway gateway,
  ConnectionManager connections,
) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: nextGenTheme(Brightness.dark, NextGenLook.instance),
  home: NgScope(
    connManager: connections,
    gateway: gateway,
    connections: [gateway.connection],
    switchTo: (_) async {},
    addGateway: () async {},
    signOut: (_) async {},
    reload: () async {},
    signInAgain: () async {},
    child: Scaffold(
      body: NgChatView(chat: chat, onOpenSidebar: () {}, onNewChat: () {}),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NextGenLook.instance
      ..themeMode = ThemeMode.dark
      ..accent = NgAccent.blue
      ..pureBlack = false
      ..glow = true;
  });

  test('selected NextGen chips keep readable labels in every accent', () {
    for (final brightness in Brightness.values) {
      for (final accent in NgAccent.values) {
        NextGenLook.instance
          ..themeMode = brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light
          ..accent = accent;
        final theme = nextGenTheme(brightness, NextGenLook.instance);
        final colours = theme.extension<NgColors>()!;
        final background = Color.alphaBlend(
          theme.chipTheme.selectedColor!,
          colours.surface2,
        );
        final label = theme.chipTheme.secondaryLabelStyle?.color;
        expect(label, isNotNull);
        expect(
          _contrast(label!, background),
          greaterThanOrEqualTo(4.5),
          reason: '$brightness $accent selected chip label',
        );
      }
    }
  });

  testWidgets('composer tap explicitly reopens the Android keyboard', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null);
    });
    final prefs = await SharedPreferences.getInstance();
    final gateway = NextGenGateway(_connection());
    final chat = NgChatController(gateway, sessionId: 'stored');
    await tester.pumpWidget(_app(chat, gateway, ConnectionManager(prefs)));
    await tester.pump(const Duration(milliseconds: 300));

    final finder = find.byKey(const ValueKey('ng-composer-field'));
    final field = tester.widget<TextField>(finder);
    expect(field.onTap, isNotNull);
    field.focusNode!.requestFocus();
    await tester.pump();
    calls.clear();

    // Back can hide the IME while the field keeps focus. A fresh tap must still
    // ask Android to show it.
    await tester.tap(finder);
    await tester.pump();
    expect(calls.where((call) => call.method == 'TextInput.show'), isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    chat.dispose();
    gateway.dispose();
  });

  testWidgets('provider chips filter and clear the composer model list', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/model/options')) {
        return http.Response(
          jsonEncode({
            'providers': [
              {
                'slug': 'openai',
                'name': 'OpenAI',
                'models': ['gpt-5.2', 'gpt-5-mini'],
              },
              {
                'slug': 'anthropic',
                'name': 'Anthropic',
                'models': ['claude-sonnet-4'],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });
    final dashboard = DashboardClient(
      host: '10.0.0.5',
      proxied: true,
      httpClient: client,
    );
    final gateway = NextGenGateway(_connection(), dashboard: dashboard);
    final prefs = await SharedPreferences.getInstance();
    final chat = NgChatController(gateway, sessionId: 'stored');
    await tester.pumpWidget(_app(chat, gateway, ConnectionManager(prefs)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('ng-model-picker')));
    await tester.pumpAndSettle();

    expect(find.text('gpt-5.2', skipOffstage: false), findsOneWidget);
    expect(find.text('claude-sonnet-4', skipOffstage: false), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ng-model-provider-openai')));
    await tester.pumpAndSettle();
    expect(find.text('gpt-5.2', skipOffstage: false), findsOneWidget);
    expect(find.text('gpt-5-mini', skipOffstage: false), findsOneWidget);
    expect(find.text('claude-sonnet-4', skipOffstage: false), findsNothing);

    // A second tap clears that provider. The All chip does the same explicitly.
    await tester.tap(find.byKey(const ValueKey('ng-model-provider-openai')));
    await tester.pumpAndSettle();
    expect(find.text('claude-sonnet-4', skipOffstage: false), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ng-model-provider-anthropic')));
    await tester.pumpAndSettle();
    expect(find.text('gpt-5.2', skipOffstage: false), findsNothing);
    expect(find.text('claude-sonnet-4', skipOffstage: false), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ng-model-provider-all')));
    await tester.pumpAndSettle();
    expect(find.text('gpt-5.2', skipOffstage: false), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ng-model-search')),
      'not-a-model',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No models match these filters.', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('gpt-5.2', skipOffstage: false), findsNothing);
    expect(find.text('claude-sonnet-4', skipOffstage: false), findsNothing);

    await tester.pumpWidget(const SizedBox());
    chat.dispose();
    gateway.dispose();
    client.close();
  });

  testWidgets('NextGen assistant reply exposes the AI output report action', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final launches = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          launches.add(call);
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final prefs = await SharedPreferences.getInstance();
    final gateway = NextGenGateway(_connection());
    final chat = NgChatController(gateway, sessionId: 'stored');
    chat.debugApplyHistory([
      {'role': 'assistant', 'content': 'A completed answer'},
    ]);
    await tester.pumpWidget(_app(chat, gateway, ConnectionManager(prefs)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Report AI output'));
    await tester.pumpAndSettle();
    expect(launches, hasLength(1));
    final args = Map<Object?, Object?>.from(launches.single.arguments as Map);
    expect(args['url'], aresAiOutputReportUri.toString());

    await tester.pumpWidget(const SizedBox());
    chat.dispose();
    gateway.dispose();
  });
}
