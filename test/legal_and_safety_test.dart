import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/legal_links.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  test('public legal and AI report links use HTTPS GitHub destinations', () {
    expect(aresPrivacyPolicyUri.scheme, 'https');
    expect(aresPrivacyPolicyUri.host, 'github.com');
    expect(aresPrivacyPolicyUri.path, endsWith('/PRIVACY.md'));
    expect(aresAiOutputReportUri.scheme, 'https');
    expect(aresAiOutputReportUri.host, 'github.com');
    expect(aresAiOutputReportUri.path, endsWith('/issues/new'));
    expect(
      aresAiOutputReportUri.queryParameters['body'],
      isNot(contains('chat content')),
    );
  });

  for (final isUser in [false, true]) {
    testWidgets('Classic message report action is assistant-only: $isUser', (
      tester,
    ) async {
      final launches = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_launcher, (call) async {
            launches.add(call);
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_launcher, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: MessageBubble(content: 'An answer', isUser: false),
          ),
        ),
      );
      if (isUser) {
        // Rebuild as a user bubble without sharing report state.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: MessageBubble(content: 'A prompt', isUser: true),
            ),
          ),
        );
      }
      await tester.longPress(find.byKey(const ValueKey('message-bubble')));
      await tester.pumpAndSettle();
      if (isUser) {
        expect(find.text('Report AI output'), findsNothing);
        return;
      }
      await tester.tap(find.text('Report AI output'));
      await tester.pumpAndSettle();
      expect(launches, hasLength(1));
      final args = Map<Object?, Object?>.from(launches.single.arguments as Map);
      expect(args['url'], aresAiOutputReportUri.toString());
    });
  }
}
