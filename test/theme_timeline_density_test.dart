import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Widget _app(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  themeAnimationDuration: Duration.zero,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  for (final palette in HermesPalette.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${palette.name} ${brightness.name} preserves density and honest task status colours',
        (tester) async {
          final theme = hermesTheme(brightness, palette: palette);
          final tokens = theme.extension<HermesTokens>()!;
          final statuses = [
            ('completed', Icons.check_circle_outline, tokens.success),
            ('failed', Icons.error_outline, tokens.danger),
            ('interrupted', Icons.pause_circle_outline, tokens.warning),
            ('cancelled', Icons.cancel_outlined, tokens.muted),
            ('unknown', Icons.help_outline, tokens.muted),
          ];
          await tester.pumpWidget(
            _app(
              theme,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final density in ChatDensity.values)
                    for (final isUser in [true, false])
                      MessageBubble(
                        key: ValueKey('${density.name}-$isUser'),
                        content: 'Readable **message** with `code`.',
                        isUser: isUser,
                        density: density,
                      ),
                  GatewaySubagentCard(
                    activities: [
                      for (final (status, _, _) in statuses)
                        GatewaySubagentActivity(
                          id: status,
                          goal: 'Task $status',
                          phase: GatewaySubagentPhase.completed,
                          status: status,
                        ),
                      // A mixed group must retain each terminal row's outcome
                      // after the user expands the collapsed section.
                      const GatewaySubagentActivity(
                        id: 'running',
                        goal: 'Task running',
                        phase: GatewaySubagentPhase.running,
                        status: 'running',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          expect(
            find.byKey(const ValueKey('delegated-task-running')),
            findsNothing,
          );
          final header = find
              .descendant(
                of: find.byType(GatewaySubagentCard),
                matching: find.byType(ListTile),
              )
              .first;
          await tester.ensureVisible(header);
          await tester.tap(header);
          await tester.pump(const Duration(milliseconds: 300));

          for (final density in ChatDensity.values) {
            for (final isUser in [true, false]) {
              final bubble = find.byKey(ValueKey('${density.name}-$isUser'));
              final container = tester.widget<Container>(
                find
                    .descendant(of: bubble, matching: find.byType(Container))
                    .first,
              );
              final fill = isUser ? tokens.accent : tokens.raised;
              final ink = isUser ? tokens.onAccent : tokens.onSurface;
              expect((container.decoration! as BoxDecoration).color, fill);
              expect(container.padding, density.bubblePadding);
              expect(container.margin, density.bubbleMargin);
              final sender = find.descendant(
                of: bubble,
                matching: find.text(isUser ? 'You' : 'Hermes'),
              );
              expect(
                sender,
                density.showsSenderLabel ? findsOneWidget : findsNothing,
              );
              final markdown = tester.widget<MarkdownBody>(
                find.descendant(
                  of: bubble,
                  matching: find.byType(MarkdownBody),
                ),
              );
              expect(markdown.styleSheet!.p!.color, ink);
              expect(contrastRatio(ink, fill), greaterThanOrEqualTo(4.5));
            }
          }

          for (final (status, icon, colour) in statuses) {
            final row = tester.widget<ListTile>(
              find.byKey(ValueKey('delegated-task-$status')),
            );
            final leading = row.leading! as Icon;
            expect(leading.icon, icon);
            expect(leading.color, colour);
            expect(leading.semanticLabel, isNotEmpty);
            expect(
              contrastRatio(colour, tokens.raised),
              greaterThanOrEqualTo(4.5),
            );
          }
          final running = tester.widget<ListTile>(
            find.byKey(const ValueKey('delegated-task-running')),
          );
          final spinner = tester.widget<CircularProgressIndicator>(
            find.descendant(
              of: find.byWidget(running.leading!),
              matching: find.byType(CircularProgressIndicator),
            ),
          );
          expect(spinner.color, tokens.running);
          final strings = AppLocalizations.of(
            tester.element(find.byType(GatewaySubagentCard)),
          )!;
          expect(find.text(strings.delegated_tasks_active(1)), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
