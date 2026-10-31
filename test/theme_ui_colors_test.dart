import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/chat_context_header.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/markdown_code_block.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Widget _app(ThemeData theme, Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: theme,
  themeAnimationDuration: Duration.zero,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [child],
      ),
    ),
  ),
);

BoxDecoration _bubbleDecoration(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

List<Color> _codeColors(SelectableText code) {
  final colors = <Color>[];
  void visit(TextSpan span, Color inherited) {
    final color = span.style?.color ?? inherited;
    if (span.text?.isNotEmpty == true) colors.add(color);
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) visit(child, color);
    }
  }

  visit(code.textSpan!, code.style!.color!);
  return colors;
}

void main() {
  for (final palette in HermesPalette.values) {
    for (final brightness in Brightness.values) {
      final label = '${palette.name} ${brightness.name}';
      final theme = hermesTheme(brightness, palette: palette);
      final tokens = theme.extension<HermesTokens>()!;

      testWidgets('$label message prose and inline code use paired tokens', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            theme,
            const Column(
              children: [
                MessageBubble(
                  key: Key('themed-user'),
                  content: 'User **prose** and `code`.',
                  isUser: true,
                ),
                MessageBubble(
                  key: Key('themed-assistant'),
                  content: 'Assistant **prose** and `code`.',
                  isUser: false,
                ),
              ],
            ),
          ),
        );
        expect(
          _bubbleDecoration(tester, const Key('themed-user')).color,
          tokens.accent,
        );
        expect(
          _bubbleDecoration(tester, const Key('themed-assistant')).color,
          tokens.raised,
        );
        for (final isUser in [true, false]) {
          final key = Key(isUser ? 'themed-user' : 'themed-assistant');
          final markdown = tester.widget<MarkdownBody>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(MarkdownBody),
            ),
          );
          final sheet = markdown.styleSheet!;
          final foreground = isUser ? tokens.onAccent : tokens.onSurface;
          final background = isUser ? tokens.accent : tokens.raised;
          for (final style in [
            sheet.p,
            sheet.h1,
            sheet.h2,
            sheet.h3,
            sheet.h4,
            sheet.h5,
            sheet.h6,
            sheet.em,
            sheet.strong,
            sheet.del,
            sheet.blockquote,
            sheet.checkbox,
            sheet.listBullet,
            sheet.tableHead,
            sheet.tableBody,
          ]) {
            expect(style?.color, foreground);
            expect(
              contrastRatio(style!.color!, background),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(sheet.code!.backgroundColor, tokens.accentContainer);
          expect(sheet.code!.color, tokens.onAccentContainer);
          expect(
            contrastRatio(sheet.code!.color!, sheet.code!.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
          expect(sheet.a!.color, isUser ? tokens.onAccent : tokens.accent);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label fenced code syntax is theme-derived and readable', (
        tester,
      ) async {
        const source =
            'void main() { // comment\n  final value = 42;\n  print("Hermes");\n}\n';
        await tester.pumpWidget(
          _app(theme, const MarkdownCodeBlock(code: source, language: 'dart')),
        );
        final container = tester.widget<Container>(
          find.byKey(const Key('markdown-code-block')),
        );
        expect((container.decoration! as BoxDecoration).color, tokens.raised);
        final code = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(code.textSpan!.toPlainText(), source);
        final colors = _codeColors(code);
        expect(colors.toSet().length, greaterThanOrEqualTo(3));
        for (final color in colors) {
          expect(
            contrastRatio(color, tokens.raised),
            greaterThanOrEqualTo(4.5),
          );
        }
        final selection = Theme.of(
          tester.element(find.byType(SelectableText)),
        ).textSelectionTheme;
        expect(selection.selectionHandleColor, tokens.accent);
        expect(selection.selectionColor, isNotNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        '$label connection state and semantic notices stay readable',
        (tester) async {
          late List<SnackBar> notices;
          await tester.pumpWidget(
            _app(
              theme,
              Builder(
                builder: (context) {
                  notices = [
                    for (final status in HermesStatus.values)
                      hermesStatusSnackBar(
                        context,
                        message: status.name,
                        status: status,
                      ),
                  ];
                  return const Column(
                    children: [
                      ChatContextHeader(
                        model: 'model',
                        reasoningEffort: 'none',
                        connectionLabel: 'Gateway',
                        connectionStatus: ChatConnectionStatus.connected,
                      ),
                      StatusChip(status: HermesStatus.completed),
                      StatusChip(status: HermesStatus.failed),
                      StatusChip(status: HermesStatus.blocked),
                    ],
                  );
                },
              ),
            ),
          );
          expect(
            tester.widget<Icon>(find.byIcon(Icons.circle)).color,
            tokens.success,
          );
          for (final notice in notices) {
            final text = notice.content as Text;
            expect(text.style!.color, foregroundFor(notice.backgroundColor!));
            expect(
              contrastRatio(text.style!.color!, notice.backgroundColor!),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'mounted bubbles and cached code recolour within one brightness',
    (tester) async {
      const child = Column(
        children: [
          MessageBubble(
            key: Key('persistent-user'),
            content: 'A `code` message.',
            isUser: true,
          ),
          MarkdownCodeBlock(
            key: Key('persistent-code'),
            code: 'final value = "Hermes";',
            language: 'dart',
          ),
        ],
      );
      final blue = hermesTheme(Brightness.dark, palette: HermesPalette.blue);
      await tester.pumpWidget(_app(blue, child));
      await tester.tap(find.byTooltip('Wrap lines'));
      await tester.pump();
      final previousState = tester.state(
        find.byKey(const Key('persistent-code')),
      );
      final previousColors = _codeColors(
        tester.widget<SelectableText>(find.byType(SelectableText)),
      );

      final pink = hermesTheme(Brightness.dark, palette: HermesPalette.pink);
      await tester.pumpWidget(_app(pink, child));
      await tester.pump();
      final tokens = pink.extension<HermesTokens>()!;
      expect(
        tester.state(find.byKey(const Key('persistent-code'))),
        same(previousState),
      );
      expect(find.byTooltip('Scroll horizontally'), findsOneWidget);
      expect(
        _bubbleDecoration(tester, const Key('persistent-user')).color,
        tokens.accent,
      );
      final colors = _codeColors(
        tester.widget<SelectableText>(find.byType(SelectableText)),
      );
      expect(colors, isNot(previousColors));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown fenced languages preserve selectable original text', (
    tester,
  ) async {
    const source = 'unrecognised <source> stays verbatim';
    await tester.pumpWidget(
      _app(
        hermesTheme(Brightness.light, palette: HermesPalette.teal),
        const MarkdownCodeBlock(code: source, language: 'not-a-language'),
      ),
    );
    final code = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(code.textSpan!.toPlainText(), source);
    expect(tester.takeException(), isNull);
  });
}
