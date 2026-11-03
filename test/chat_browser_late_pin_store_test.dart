import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'default Chats hydrates pins when the root supplies its store after mount',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalChatPinStore(prefs, connectionId: 'late-store');
      await store.setPinned('old', pinned: true);
      final data = WorkspaceSessionsData(
        sessions: [
          for (final id in ['new', 'old'])
            Session(
              id: id,
              title: id,
              model: 'test',
              source: 'gateway',
              messageCount: 1,
              isActive: false,
              preview: '',
              startedAt: 1,
              lastActive: id == 'new' ? 2 : 1,
            ),
        ],
      );
      final held = Completer<WorkspaceSessionsData>();
      final key = GlobalKey<WorkspaceSessionsScreenState>();
      Widget app(LocalChatPinStore? pins) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceSessionsScreen(
          key: key,
          title: 'Chats',
          view: WorkspaceSessionView.all,
          embedded: true,
          initialData: data,
          pinStore: pins,
          load: () => held.future,
          onOpenSession: (_) {},
        ),
      );
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      final state = key.currentState;
      expect(find.text('Pinned on this device'), findsNothing);
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(key.currentState, same(state));
      expect(find.text('Pinned on this device'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('old')).dy,
        lessThan(tester.getTopLeft(find.text('new')).dy),
      );
      held.complete(data);
      await tester.pumpAndSettle();
      expect(find.text('Pinned on this device'), findsOneWidget);
      expect(await store.load(), ['old']);
    },
  );
}
