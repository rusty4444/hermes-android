import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_approval.dart';
import 'package:hermes_android/core/widgets/gateway_approval_dialog.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  group('GatewayApprovalRequest', () {
    test('uses all official choices when the gateway allows them', () {
      final request = GatewayApprovalRequest.fromEventData({
        'command': 'echo fixture',
        'description': 'Run a fixture command',
        'allow_permanent': true,
        'choices': ['once', 'session', 'always', 'deny'],
      });

      expect(request.command, 'echo fixture');
      expect(request.allowPermanent, isTrue);
      expect(request.choices, GatewayApprovalChoice.values);
    });

    test('removes permanent approval when Hermes disallows it', () {
      final request = GatewayApprovalRequest.fromEventData({
        'allow_permanent': false,
        'choices': ['once', 'session', 'always'],
      });

      expect(request.allowPermanent, isFalse);
      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.session,
        GatewayApprovalChoice.deny,
      ]);
    });

    test('smart denied approvals can only be run once or denied', () {
      final request = GatewayApprovalRequest.fromEventData({
        'smart_denied': true,
        'choices': ['once', 'session', 'always', 'deny'],
      });

      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.deny,
      ]);
    });

    test('falls back to the official non-permanent choices', () {
      final request = GatewayApprovalRequest.fromEventData({
        'allow_permanent': false,
        'choices': ['unknown'],
      });

      expect(request.choices, [
        GatewayApprovalChoice.once,
        GatewayApprovalChoice.session,
        GatewayApprovalChoice.deny,
      ]);
    });
  });

  group('GatewayApprovalDialog', () {
    testWidgets('sends allow once and closes only after success', (
      tester,
    ) async {
      GatewayApprovalChoice? sentChoice;
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => GatewayApprovalDialog(
                    request: GatewayApprovalRequest.fromEventData({
                      'command': 'echo fixture',
                      'description': 'Run the fixture command',
                      'choices': ['once', 'deny'],
                    }),
                    onRespond: (choice) async => sentChoice = choice,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('echo fixture'), findsOneWidget);

      await tester.tap(find.byKey(const Key('approval-once')));
      await tester.pumpAndSettle();

      expect(sentChoice, GatewayApprovalChoice.once);
      expect(find.text('Approval needed'), findsNothing);
    });

    testWidgets('requires a second confirmation for permanent approval', (
      tester,
    ) async {
      var sends = 0;
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GatewayApprovalDialog(
              request: GatewayApprovalRequest.fromEventData({
                'command': 'echo fixture',
                'choices': ['always', 'deny'],
              }),
              onRespond: (_) async => sends++,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('approval-always')));
      await tester.pump();
      expect(sends, 0);
      expect(find.text('Confirm always allow'), findsOneWidget);

      await tester.tap(find.byKey(const Key('approval-always')));
      await tester.pump();
      expect(sends, 1);
    });

    testWidgets('keeps the dialog open when the gateway rejects a response', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GatewayApprovalDialog(
              request: GatewayApprovalRequest.fromEventData({
                'choices': ['once', 'deny'],
              }),
              onRespond: (_) async => throw Exception('fixture failure'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('approval-once')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('approval-error')), findsOneWidget);
      expect(find.byKey(const Key('approval-deny')), findsOneWidget);
    });
  });
}
