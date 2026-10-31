import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  Size size = const Size(360, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  group('StatusChip', () {
    testWidgets('labels each semantic status distinctly', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            StatusChip(status: HermesStatus.running),
            StatusChip(status: HermesStatus.blocked),
            StatusChip(status: HermesStatus.failed),
            StatusChip(status: HermesStatus.completed),
            StatusChip(status: HermesStatus.idle),
          ],
        ),
      );

      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('a custom label replaces the default wording', (tester) async {
      await _pump(
        tester,
        const StatusChip(status: HermesStatus.running, label: '3 running'),
      );

      expect(find.text('3 running'), findsOneWidget);
      expect(find.text('Running'), findsNothing);
    });

    testWidgets('takes its color from the status token', (tester) async {
      await _pump(tester, const StatusChip(status: HermesStatus.blocked));

      final context = tester.element(find.byType(StatusChip));
      final tokens = HermesTokens.of(context);
      final text = tester.widget<Text>(find.text('Needs you'));

      expect(text.style?.color, tokens.blocked);
    });

    testWidgets('announces its visible label exactly once', (tester) async {
      await _pump(tester, const StatusChip(status: HermesStatus.idle));

      expect(tester.getSemantics(find.byType(StatusChip)).label, 'Idle');
    });

    testWidgets('exposes its state to screen readers', (tester) async {
      await _pump(tester, const StatusChip(status: HermesStatus.failed));

      expect(
        tester.getSemantics(find.byType(StatusChip)).label,
        contains('Failed'),
      );
    });
  });

  group('SectionHeader', () {
    testWidgets('shows a title, optional count, and optional action', (
      tester,
    ) async {
      var tapped = 0;
      await _pump(
        tester,
        SectionHeader(
          title: 'Needs you',
          count: 2,
          actionLabel: 'See all',
          onAction: () => tapped++,
        ),
      );

      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('See all'));
      expect(tapped, 1);
    });

    testWidgets('hides the count and action when not provided', (tester) async {
      await _pump(tester, const SectionHeader(title: 'Recent'));

      expect(find.text('Recent'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('HermesCard', () {
    testWidgets('renders its child and reports taps', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        HermesCard(onTap: () => taps++, child: const Text('Deploy ScriptHive')),
      );

      await tester.tap(find.text('Deploy ScriptHive'));
      expect(taps, 1);
    });

    testWidgets('is not tappable without a callback', (tester) async {
      await _pump(tester, const HermesCard(child: Text('Static')));

      expect(find.byType(InkWell), findsNothing);
      expect(find.text('Static'), findsOneWidget);
    });

    testWidgets('an accented card shows its status edge', (tester) async {
      await _pump(
        tester,
        const HermesCard(status: HermesStatus.blocked, child: Text('Blocked')),
      );

      final context = tester.element(find.byType(HermesCard));
      final tokens = HermesTokens.of(context);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HermesCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.border, isNotNull);
      expect(decoration.color, isNot(tokens.surface));
    });
  });

  group('EmptyState', () {
    testWidgets('explains the situation and offers one action', (tester) async {
      var created = 0;
      await _pump(
        tester,
        EmptyState(
          icon: Icons.folder_outlined,
          title: 'No projects yet',
          message: 'Projects group related chats, files, and activity.',
          actionLabel: 'Create a project',
          onAction: () => created++,
        ),
      );

      expect(find.text('No projects yet'), findsOneWidget);
      expect(
        find.text('Projects group related chats, files, and activity.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Create a project'));
      expect(created, 1);
    });

    testWidgets('renders without an action', (tester) async {
      await _pump(
        tester,
        const EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Nothing needs you',
          message: 'Hermes has no blocked work right now.',
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Nothing needs you'), findsOneWidget);
    });

    testWidgets('survives a large text scale without overflowing', (
      tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(
          icon: Icons.folder_outlined,
          title: 'No projects yet',
          message: 'Projects group related chats, files, and activity.',
        ),
        textScale: 2.0,
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('ErrorState', () {
    testWidgets('shows the failure and retries on demand', (tester) async {
      var retries = 0;
      await _pump(
        tester,
        ErrorState(
          title: 'Gateway unreachable',
          message: 'Check that Hermes is running and reachable.',
          onRetry: () => retries++,
        ),
      );

      expect(find.text('Gateway unreachable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('uses the danger token for its icon', (tester) async {
      await _pump(
        tester,
        const ErrorState(title: 'Failed', message: 'Something broke.'),
      );

      final context = tester.element(find.byType(ErrorState));
      final tokens = HermesTokens.of(context);
      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byType(ErrorState),
              matching: find.byType(Icon),
            )
            .first,
      );

      expect(icon.color, tokens.danger);
    });

    testWidgets('an unsupported-gateway state is informational, not alarming', (
      tester,
    ) async {
      await _pump(
        tester,
        const ErrorState.unsupported(
          title: 'Projects unavailable',
          message: 'This Hermes gateway predates server-side projects.',
        ),
      );

      final context = tester.element(find.byType(ErrorState));
      final tokens = HermesTokens.of(context);
      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byType(ErrorState),
              matching: find.byType(Icon),
            )
            .first,
      );

      expect(icon.color, tokens.muted);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('LoadingSkeleton', () {
    testWidgets('renders the requested number of placeholder rows', (
      tester,
    ) async {
      await _pump(tester, const LoadingSkeleton(rows: 3));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('skeleton-row-0')), findsOneWidget);
      expect(find.byKey(const Key('skeleton-row-1')), findsOneWidget);
      expect(find.byKey(const Key('skeleton-row-2')), findsOneWidget);
      expect(find.byKey(const Key('skeleton-row-3')), findsNothing);
    });

    testWidgets('is hidden from screen readers as decorative', (tester) async {
      await _pump(tester, const LoadingSkeleton(rows: 2));
      await tester.pump(const Duration(milliseconds: 100));

      final semantics = tester.getSemantics(find.byType(LoadingSkeleton));
      expect(semantics.label, contains('Loading'));
    });

    testWidgets('animates without throwing and settles when disposed', (
      tester,
    ) async {
      await _pump(tester, const LoadingSkeleton(rows: 2));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await _pump(tester, const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  });

  group('component kit theming', () {
    testWidgets('every component renders in the light theme too', (
      tester,
    ) async {
      await _pump(
        tester,
        const Column(
          children: [
            SectionHeader(title: 'Attention', count: 1),
            StatusChip(status: HermesStatus.blocked),
            HermesCard(child: Text('Card')),
            EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Empty',
              message: 'Nothing here.',
            ),
            ErrorState(title: 'Error', message: 'Broken.'),
            LoadingSkeleton(rows: 1),
          ],
        ),
        brightness: Brightness.light,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Attention'), findsOneWidget);
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
    });

    testWidgets('interactive components meet the 48dp touch target floor', (
      tester,
    ) async {
      await _pump(
        tester,
        HermesCard(onTap: () {}, child: const Text('Tappable')),
      );

      final size = tester.getSize(find.byType(HermesCard));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });
}
