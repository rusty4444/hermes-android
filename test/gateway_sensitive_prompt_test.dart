import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_sensitive_prompt.dart';
import 'package:hermes_android/core/widgets/gateway_sensitive_prompt_dialog.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  group('GatewaySensitivePromptRequest', () {
    test('parses an official sudo request', () {
      final request = GatewaySensitivePromptRequest.fromEventData(
        kind: GatewaySensitivePromptKind.sudo,
        data: {'request_id': 'sudo-123'},
      );

      expect(request, isNotNull);
      expect(request!.requestId, 'sudo-123');
      expect(request.kind, GatewaySensitivePromptKind.sudo);
      expect(request.fieldLabel, 'Sudo password');
    });

    test('parses the secret label and prompt without retaining a value', () {
      final request = GatewaySensitivePromptRequest.fromEventData(
        kind: GatewaySensitivePromptKind.secret,
        data: {
          'request_id': 'secret-123',
          'env_var': 'FIXTURE_API_TOKEN',
          'prompt': 'Enter a synthetic token',
        },
      );

      expect(request, isNotNull);
      expect(request!.title, 'FIXTURE_API_TOKEN');
      expect(request.description, 'Enter a synthetic token');
    });

    test('ignores a request without request_id', () {
      expect(
        GatewaySensitivePromptRequest.fromEventData(
          kind: GatewaySensitivePromptKind.secret,
          data: {'env_var': 'MISSING_ID'},
        ),
        isNull,
      );
    });
  });

  group('GatewaySensitivePromptDialog', () {
    testWidgets('obscures input and sends a non-empty secret', (tester) async {
      String? sentValue;
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<GatewaySensitivePromptDialogResult>(
                  context: context,
                  builder: (_) => GatewaySensitivePromptDialog(
                    request: GatewaySensitivePromptRequest.fromEventData(
                      kind: GatewaySensitivePromptKind.secret,
                      data: {
                        'request_id': 'secret-123',
                        'env_var': 'FIXTURE_API_TOKEN',
                      },
                    )!,
                    onRespond: (value) async => sentValue = value,
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
      final field = tester.widget<TextField>(
        find.byKey(const Key('sensitive-prompt-field')),
      );
      expect(field.obscureText, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('sensitive-prompt-send')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('sensitive-prompt-field')),
        'synthetic-secret',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sensitive-prompt-send')));
      await tester.pumpAndSettle();

      expect(sentValue, 'synthetic-secret');
      expect(find.text('FIXTURE_API_TOKEN'), findsNothing);
    });

    testWidgets('cancel sends the official empty sudo response', (
      tester,
    ) async {
      String? sentValue;
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<GatewaySensitivePromptDialogResult>(
                  context: context,
                  builder: (_) => GatewaySensitivePromptDialog(
                    request: GatewaySensitivePromptRequest.fromEventData(
                      kind: GatewaySensitivePromptKind.sudo,
                      data: {'request_id': 'sudo-123'},
                    )!,
                    onRespond: (value) async => sentValue = value,
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
      await tester.tap(find.byKey(const Key('sensitive-prompt-cancel')));
      await tester.pumpAndSettle();

      expect(sentValue, '');
      expect(find.text('Administrator password needed'), findsNothing);
    });

    testWidgets('shows a generic error without exposing the entered value', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GatewaySensitivePromptDialog(
              request: GatewaySensitivePromptRequest.fromEventData(
                kind: GatewaySensitivePromptKind.secret,
                data: {
                  'request_id': 'secret-123',
                  'env_var': 'FIXTURE_API_TOKEN',
                },
              )!,
              onRespond: (_) async => throw Exception('server detail'),
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('sensitive-prompt-field')),
        'must-not-appear-in-error',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sensitive-prompt-send')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sensitive-prompt-error')), findsOneWidget);
      final errorText = tester
          .widget<Text>(find.byKey(const Key('sensitive-prompt-error')))
          .data;
      expect(errorText, isNot(contains('must-not-appear')));
      expect(errorText, isNot(contains('server detail')));
    });
  });
}
