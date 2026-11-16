// NextGen parity: a single drag must select across the whole reply, not just
// one block. The assistant message renders inside one SelectionArea with plain
// text prose and code, so a long-press-drag runs from the first paragraph,
// across a code fence, into the last.
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hermes_sign_in.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HermesSignInVault.resetForTesting(MemorySignInSecretStore());
  });

  testWidgets(
    'NextGen reply lets one drag select across paragraphs and code',
    (WidgetTester tester) async {
      const firstParagraph = 'First paragraph opens the reply.';
      const lastParagraph = 'Final paragraph closes the reply.';
      const message =
          '$firstParagraph\n\nSecond paragraph continues it.\n\n'
          '```\nfirst code line\nsecond code line\n```\n\n$lastParagraph';

      final gateway = NextGenGateway(
        SavedConnection(
          id: 'c1',
          label: 'Home',
          host: '10.0.0.5',
          port: 9119,
          apiKey: '',
          desktopGatewayUrl: 'http://10.0.0.5:9119',
          singleLogin: true,
          signInMethod: 'none',
        ),
      );
      final chat = NgChatController(gateway, sessionId: 'stored')
        ..runtimeId = 'rt';
      chat.debugApplyHistory([
        {'role': 'user', 'content': 'Question'},
        {'role': 'assistant', 'content': message},
      ]);
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nextGenTheme(Brightness.light, NextGenLook.instance),
          home: NgScope(
            connManager: ConnectionManager(prefs),
            gateway: gateway,
            connections: [gateway.connection],
            switchTo: (_) async {},
            addGateway: () async {},
            signOut: (_) async {},
            reload: () async {},
            signInAgain: () async {},
            child: Scaffold(
              body: NgChatView(
                chat: chat,
                onOpenSidebar: () {},
                onNewChat: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // One SelectionArea owns the whole reply; no block inside it keeps a
      // private SelectableText island that would confine the drag.
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(SelectableText),
        ),
        findsNothing,
      );

      final first = _paragraph(tester, firstParagraph);
      final last = _paragraph(tester, lastParagraph);

      // Long-press in the first paragraph, then drag across the code block
      // into the final paragraph.
      final gesture = await tester.startGesture(_textPosition(first, 2));
      addTearDown(gesture.removePointer);
      await tester.pump(kLongPressTimeout);
      await gesture.moveTo(_textPosition(last, lastParagraph.length - 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // The drag is not confined to one block: it runs from the first
      // paragraph through to the last.
      expect(first.selections, isNotEmpty);
      expect(first.selections.first.end, firstParagraph.length);
      expect(last.selections, isNotEmpty);
      expect(last.selections.first.isCollapsed, isFalse);

      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );
}

RenderParagraph _paragraph(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byType(SelectionArea),
      matching: find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == text,
      ),
    ),
  );
}

Offset _textPosition(RenderParagraph paragraph, int offset) {
  const caret = Rect.fromLTWH(0.0, 0.0, 2.0, 20.0);
  final localOffset =
      paragraph.getOffsetForCaret(TextPosition(offset: offset), caret) +
      Offset(0.0, paragraph.preferredLineHeight);
  return paragraph.localToGlobal(localOffset) + const Offset(0.0, -2.0);
}
