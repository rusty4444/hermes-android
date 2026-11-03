import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_draft_lifecycle_test.dart' as fixture;

Future<String?> read(String id, {String connection = 'handoff'}) =>
    ComposerDraftStore.read(connectionId: connection, sessionId: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  for (final latest in ['local latest before remount', '']) {
    test(
      'local remount before hydration preserves explicit intent "$latest"',
      () async {
        final registry = ChatPresentationRegistry('handoff');
        final canonical = registry.chatFor('stored').openWriter()
          ..edit('canonical prior');
        await canonical.close();
        final local = registry.chatFor('local').openWriter()..edit(latest);
        await local.close();
        final replacement = registry.chatFor('local').openWriter();
        registry.bind('local', 'stored');
        for (var i = 0; i < 6; i++) {
          await read('stored');
        }
        expect(await replacement.read(), latest);
        await replacement.close();
        await (await SharedPreferences.getInstance()).reload();
        expect(await read('stored'), latest.isEmpty ? isNull : latest);
        registry.close();
      },
    );
  }

  for (final latest in ['newest resumed local draft', '']) {
    test(
      'binding keeps most recent explicit local intent "$latest" durable',
      () async {
        final registry = ChatPresentationRegistry('handoff');
        final local = registry.chatFor('local').openWriter()
          ..edit('local initial');
        await local.flush();
        final canonical = registry.chatFor('stored').openWriter()
          ..edit('canonical prior');
        await canonical.flush();
        await canonical.close();
        local.edit(latest);
        await local.flush();
        registry.bind('local', 'stored');
        expect(local.isCurrent, isTrue);
        expect(canonical.isCurrent, isFalse);
        expect(await local.read(), latest);
        await local.close();
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final replacement = registry.chatFor('stored').openWriter();
        final restored = await replacement.read();
        debugPrint(
          'HANDOFF latest="$latest" restored="$restored" local=${await read('local')} stored=${await read('stored')}',
        );
        await replacement.close();
        registry.close();
        expect(restored, latest);
        expect(await read('stored'), latest.isEmpty ? isNull : latest);
      },
    );
  }

  for (final canonicalText in ['canonical newest', '']) {
    test(
      'canonical remount preserves newer canonical text/clear "$canonicalText" against old local',
      () async {
        final registry = ChatPresentationRegistry('handoff');
        final local = registry.chatFor('local').openWriter()
          ..edit('stale local');
        await local.flush();
        final firstCanonical = registry.chatFor('stored').openWriter()
          ..edit(canonicalText);
        await firstCanonical.flush();
        await firstCanonical.close();
        final mountedCanonical = registry.chatFor('stored').openWriter();
        expect(await mountedCanonical.read(), canonicalText);
        registry.bind('local', 'stored');
        // Drain the production shared queue (bind + _persist) through a read.
        for (var i = 0; i < 6; i++) {
          await read('stored');
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final actual = await read('stored');
        debugPrint(
          'CANONICAL_REMOUNT expected="$canonicalText" actual="$actual" current=${mountedCanonical.isCurrent}',
        );
        await local.close();
        await mountedCanonical.close();
        registry.close();
        expect(actual, canonicalText.isEmpty ? isNull : canonicalText);
      },
    );
  }

  for (final canonicalText in ['Canonical newest', '']) {
    testWidgets(
      'real canonical remount: latest canonical text/clear "$canonicalText" survives alias',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final remote = fixture.Remote();
        await fixture.open(tester, controller, remote, draft: true);
        await tester.enterText(find.byType(TextField), 'Stale local draft');
        await fixture.open(
          tester,
          controller,
          remote,
          id: 'stored',
          push: true,
        );
        await tester.enterText(
          find.byType(TextField),
          'Canonical intermediate',
        );
        await tester.enterText(find.byType(TextField), canonicalText);
        Navigator.of(tester.element(find.byType(TextField))).pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await fixture.open(
          tester,
          controller,
          remote,
          id: 'stored',
          push: true,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          canonicalText,
        );
        controller.presentationFor(fixture.connection).bind('local', 'stored');
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        final during = await read('stored', connection: fixture.connection.id);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        await fixture.open(tester, controller, remote, id: 'stored');
        final reopened = tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text;
        debugPrint(
          'CANONICAL_NAV expected="$canonicalText" during="$during" reopened="$reopened" submits=${remote.submissions}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(reopened, canonicalText);
        expect(remote.submissions, 0);
      },
    );
  }

  test(
    'canonical current explicit edit is a passing handoff control',
    () async {
      final registry = ChatPresentationRegistry('handoff');
      final local = registry.chatFor('local').openWriter()..edit('stale local');
      await local.flush();
      final canonical = registry.chatFor('stored').openWriter()
        ..edit('canonical newest');
      await canonical.flush();
      registry.bind('local', 'stored');
      for (var i = 0; i < 6; i++) {
        await read('stored');
      }
      expect(await read('stored'), 'canonical newest');
      expect(canonical.isCurrent, isTrue);
      expect(local.isCurrent, isFalse);
      await local.close();
      await canonical.close();
      registry.close();
    },
  );

  testWidgets(
    'real Navigator return: latest local edit survives delayed alias',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = fixture.Remote();
      await fixture.open(tester, controller, remote, draft: true);
      await tester.enterText(find.byType(TextField), 'Local initial');
      await fixture.open(tester, controller, remote, id: 'stored', push: true);
      await tester.enterText(find.byType(TextField), 'Canonical prior');
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(
        find.byType(TextField),
        'Newest resumed local draft',
      );
      controller.presentationFor(fixture.connection).bind('local', 'stored');
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Newest resumed local draft',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await fixture.open(tester, controller, remote, id: 'stored');
      final reopened = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      debugPrint(
        'NAV_HANDOFF reopened="$reopened" submits=${remote.submissions}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(reopened, 'Newest resumed local draft');
      expect(remote.submissions, 0);
    },
  );
}
