import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/spaces_screen.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/inert_turn_application_session.dart';

class _PhysicalPreferences extends InMemorySharedPreferencesStore {
  _PhysicalPreferences() : super.withData({});
  bool reject = false;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (reject && key == 'flutter.chat_spaces_v1_ui') return false;
    return super.setValue(type, key, value);
  }
}

Widget _app(Widget child, {Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PhysicalPreferences physical;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previous = SharedPreferencesStorePlatform.instance;
    physical = _PhysicalPreferences();
    SharedPreferencesStorePlatform.instance = physical;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
  });

  testWidgets('real Move rejection retains placement and Retry can save', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'ui');
    final destination = await store.createSpace('Destination');
    final owner = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(owner.close);
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/api/sessions')
              ? {
                  'data': [
                    {
                      'id': 'chat',
                      'title': 'Move fixture',
                      'source': 'gateway',
                      'model': 'test',
                      'message_count': 2,
                      'started_at': 1750000000.0,
                    },
                  ],
                  'has_more': false,
                }
              : {'status': 'ok'},
        ),
        200,
      ),
    );
    await tester.pumpWidget(
      _app(
        SessionListScreen(
          connection: SavedConnection(
            id: 'ui',
            label: 'Fixture',
            host: 'fixture.invalid',
            port: 8642,
            apiKey: 'fixture',
          ),
          turnApplicationController: owner,
          testHttpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'move',
      ),
    );
    await tester.pumpAndSettle();
    physical.reject = true;
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Couldn’t move conversation'), findsOneWidget);
    expect((await store.load()).spaceIdForSession('chat'), isNull);
    await prefs.reload();
    expect(
      (await ChatSpaceStore(
        prefs,
        connectionId: 'ui',
      ).load()).spaceIdForSession('chat'),
      isNull,
    );
    physical.reject = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destination'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await prefs.reload();
    expect(
      (await ChatSpaceStore(
        prefs,
        connectionId: 'ui',
      ).load()).spaceIdForSession('chat'),
      destination.id,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final (rename, languageCode) in [
    (false, 'en'),
    (true, 'en'),
    (false, 'de'),
    (true, 'de'),
  ]) {
    testWidgets(
      'real Space ${rename ? 'rename' : 'create'} rejection has feedback and can retry ($languageCode)',
      (tester) async {
        final locale = Locale(languageCode);
        final l10n = await AppLocalizations.delegate.load(locale);
        final prefs = await SharedPreferences.getInstance();
        final store = ChatSpaceStore(prefs, connectionId: 'ui');
        final existing = await store.createSpace('Existing');
        await tester.pumpWidget(
          _app(
            SpacesScreen(
              store: store,
              sessions: const [],
              onScopeSelected: (_) {},
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        Future<void> edit() async {
          if (rename) {
            await tester.tap(find.byKey(Key('space-menu-${existing.id}')));
            await tester.pumpAndSettle();
            await tester.tap(find.text(l10n.rename));
          } else {
            await tester.tap(find.byKey(const Key('create-space')));
          }
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(Key(rename ? 'rename-space-name' : 'space-name')),
            'New name',
          );
          await tester.tap(find.text(rename ? l10n.save : l10n.create));
          await tester.pumpAndSettle();
        }

        physical.reject = true;
        await edit();
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text(
            languageCode == 'de'
                ? 'Chat-Bereiche konnten auf diesem Gerät nicht gespeichert werden'
                : 'Could not save chat spaces on this device',
          ),
          findsOneWidget,
        );
        expect(find.text('Existing'), findsOneWidget);
        expect((await store.load()).spaces.single.name, 'Existing');
        physical.reject = false;
        await tester.tap(find.text(l10n.retry));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(Key(rename ? 'rename-space-name' : 'space-name')),
          'New name',
        );
        await tester.tap(find.text(rename ? l10n.save : l10n.create));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('New name'), findsOneWidget);
        await prefs.reload();
        expect(
          (await store.load()).spaces.map((s) => s.name),
          rename ? ['New name'] : ['Existing', 'New name'],
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
