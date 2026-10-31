import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/spaces_screen.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Session testSession(String id, {double startedAt = 1}) => Session(
  id: id,
  title: 'Chat $id',
  model: 'test',
  source: 'api',
  messageCount: 1,
  isActive: false,
  preview: '',
  startedAt: startedAt,
);

Future<void> pumpSpaces(
  WidgetTester tester, {
  required ChatSpaceStore store,
  required List<Session> sessions,
  required ValueChanged<ChatSpaceScope> onSelected,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SpacesScreen(
        store: store,
        sessions: sessions,
        onScopeSelected: onSelected,
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows all chats, unassigned, and each named space with counts', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');
    final android = await store.createSpace('Hermes Android');
    await store.assignSession('one', android.id);

    await pumpSpaces(
      tester,
      store: store,
      sessions: [testSession('one'), testSession('two')],
      onSelected: (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.text('All chats'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Hermes Android'), findsOneWidget);
    expect(find.text('2 chats'), findsOneWidget);
    expect(find.text('1 chat'), findsNWidgets(2));
  });

  testWidgets('selecting a space returns its scope', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');
    final android = await store.createSpace('Hermes Android');
    ChatSpaceScope? selected;

    await pumpSpaces(
      tester,
      store: store,
      sessions: const [],
      onSelected: (scope) => selected = scope,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hermes Android'));

    expect(selected?.kind, ChatSpaceScopeKind.space);
    expect(selected?.spaceId, android.id);
  });

  testWidgets('creates a named space from the add action', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');

    await pumpSpaces(
      tester,
      store: store,
      sessions: const [],
      onSelected: (_) {},
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-space')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('space-name')), 'ScriptHive');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('ScriptHive'), findsOneWidget);
    expect((await store.load()).spaces.single.name, 'ScriptHive');
  });

  testWidgets('renames an existing space from its menu', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');
    final space = await store.createSpace('Android');

    await pumpSpaces(
      tester,
      store: store,
      sessions: const [],
      onSelected: (_) {},
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('space-menu-${space.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-space-name')),
      'Hermes Android',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
    expect((await store.load()).spaces.single.name, 'Hermes Android');
  });
}
