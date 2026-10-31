import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  testWidgets('rapid IME, dialog, and owner-route back teardown stays safe', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (homeContext) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.push<void>(
                homeContext,
                MaterialPageRoute(
                  builder: (routeContext) => Scaffold(
                    body: FilledButton(
                      onPressed: () => showSessionNameDialog(
                        context: routeContext,
                        title: 'Rename chat',
                        initialValue: 'Existing chat',
                        actionLabel: 'Rename',
                      ),
                      child: const Text('Open rename'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open session list'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open session list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open rename'));
    await tester.pumpAndSettle();

    expect(find.text('Rename chat'), findsOneWidget);
    expect(tester.testTextInput.isRegistered, isTrue);
    await tester.enterText(find.byType(TextFormField), 'Renamed chat');

    tester.testTextInput.hide();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Open session list'), findsOneWidget);
    await tester.tap(find.text('Open session list'));
    await tester.pumpAndSettle();
    expect(find.text('Open rename'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
