import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/chat_context_header.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? projectName,
  String model = 'gpt-5.6-sol',
  String reasoning = 'high',
  String connection = 'Miniserver',
  ChatConnectionStatus status = ChatConnectionStatus.connected,
  Size size = const Size(400, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Chat'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: ChatContextHeader(
                projectName: projectName,
                model: model,
                reasoningEffort: reasoning,
                connectionLabel: connection,
                connectionStatus: status,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows project, model, reasoning and connection', (tester) async {
    await _pump(tester, projectName: 'Hermes Android');

    expect(find.text('Hermes Android'), findsOneWidget);
    expect(find.text('gpt-5.6-sol'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Miniserver'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(find.bySemanticsLabel('Miniserver connected'), findsOneWidget);
  });

  testWidgets('labels a chat without a known project as Unassigned', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets(
    'exposes non-connected states with non-color icons and visible state text even for long labels',
    (tester) async {
      await _pump(tester, status: ChatConnectionStatus.offline);

      expect(find.bySemanticsLabel('Miniserver offline'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(find.text('· offline'), findsOneWidget);

      await _pump(
        tester,
        connection: 'A very long connection label that truncates in the chip',
        status: ChatConnectionStatus.reconnecting,
        size: const Size(320, 640),
      );
      expect(
        find.bySemanticsLabel(
          'A very long connection label that truncates in the chip reconnecting',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.text('· reconnecting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('survives narrow width and large text across all connection states', (
    tester,
  ) async {
    for (final scale in [1.8, 2.0]) {
      for (final status in ChatConnectionStatus.values) {
        await _pump(
          tester,
          projectName: 'A very long Project name that must not overflow',
          model: 'a-very-long-provider/a-very-long-model-name',
          connection: 'A very long connection label that truncates in the chip',
          status: status,
          size: const Size(320, 640),
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(ChatContextHeader), findsOneWidget);
        if (status != ChatConnectionStatus.connected) {
          expect(find.text('· ${status.label}'), findsOneWidget);
        }
      }
    }
  });
}
