import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/background_report.dart';
import 'package:hermes_android/core/widgets/background_report_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'neutral $brightness card builds full selectable body only on demand',
      (tester) async {
        String? copiedText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        const body =
            ' \r\n<untrusted_tool_result>kept verbatim</untrusted_tool_result>'
            '\n literal \\n\n  FINAL_MARKER  \n ';
        final report = BackgroundReport.fromMessage({
          'display_kind': 'async_delegation_complete',
          'content': body,
          'display_metadata': {
            'display_text': 'Short summary',
            'has_issues': true,
          },
        })!;
        final choices = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BackgroundReportCard(
                report: report,
                onExpansionChanged: choices.add,
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(BackgroundReportCard));
        final colors = Theme.of(context).colorScheme;
        expect(
          tester.widget<Card>(find.byType(Card)).color,
          colors.surfaceContainerHighest,
        );
        expect(find.text('Background task'), findsOneWidget);
        expect(find.text('Short summary'), findsOneWidget);
        expect(
          find.text('Issues reported — expand for details.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(find.text('Expand report'), findsOneWidget);
        expect(find.byType(SelectionArea), findsNothing);
        expect(find.text(body, skipOffstage: false), findsNothing);
        final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
        expect(tile.controller!.isExpanded, isFalse);
        expect(tile.children, isEmpty);
        await tester.tap(find.text('Expand report'));
        await tester.pumpAndSettle();
        expect(tile.controller!.isExpanded, isTrue);
        expect(find.text(body), findsOneWidget);
        expect(find.byType(SelectionArea), findsOneWidget);
        // Selection is registered with the platform selection region, not a
        // Markdown reinterpretation or a text field with edit/resend actions.
        expect(find.byType(SelectableRegion), findsOneWidget);
        final region = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        region.selectAll(SelectionChangedCause.keyboard);
        await tester.pump();
        region.contextMenuButtonItems
            .singleWhere((button) => button.type == ContextMenuButtonType.copy)
            .onPressed!();
        await tester.pump();
        expect(copiedText, body);
        expect(find.byType(EditableText), findsNothing);
        expect(find.text('Collapse report'), findsOneWidget);
        await tester.tap(find.text('Collapse report'));
        await tester.pumpAndSettle();
        expect(tile.controller!.isExpanded, isFalse);
        expect(find.text(body, skipOffstage: false), findsNothing);
        expect(find.byType(SelectionArea), findsNothing);
        expect(choices, [true, false]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'long multiline report has no collapsed body work and expands through its tail',
    (tester) async {
      final body =
          '  ${List.generate(1000, (i) => 'Report line $i').join('\n')}'
          '\n<untrusted_tool_result>FINAL_LONG_TAIL</untrusted_tool_result>  \n';
      final report = BackgroundReport.fromMessage({
        'display_kind': 'process_complete',
        'content': body,
        'display_metadata': {'display_text': 'x' * 10000},
      })!;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackgroundReportCard(
                report: report,
                onExpansionChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.text(body, skipOffstage: false), findsNothing);
      final preview = tester.widget<Text>(find.text(report.summary!));
      expect(preview.maxLines, 2);
      expect(preview.data!.length, 240);
      await tester.tap(find.text('Expand report'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(body)).data, body);
      expect(find.byType(SelectionArea), findsOneWidget);
      await tester.tap(find.text('Collapse report'));
      await tester.pumpAndSettle();
      expect(find.text(body, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'separate reports do not share expansion; remount accepts visit pin',
    (tester) async {
      final report = BackgroundReport.fromMessage({
        'display_kind': 'process_complete',
        'content': 'Same complete body',
      })!;
      final pins = <int, bool>{};
      Widget app({bool remount = false}) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              for (final id in [1, 2])
                BackgroundReportCard(
                  key: ValueKey((id, remount)),
                  report: report,
                  initiallyExpanded: pins[id] ?? false,
                  onExpansionChanged: (value) => pins[id] = value,
                ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.tap(find.text('Expand report').first);
      await tester.pumpAndSettle();
      expect(find.text('Same complete body'), findsOneWidget);
      expect(find.text('Expand report'), findsOneWidget);
      await tester.pumpWidget(app(remount: true));
      await tester.pumpAndSettle();
      expect(find.text('Same complete body'), findsOneWidget);
      expect(find.text('Expand report'), findsOneWidget);
      expect(pins, {1: true});
    },
  );
}
