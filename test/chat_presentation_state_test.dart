import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/tool_activity_group_pins.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'shared generation fences an already queued old checkpoint and clear',
    () async {
      final registry = ChatPresentationRegistry('connection');
      final state = registry.chatFor('chat');
      final old = state.openWriter()..edit('old');
      final oldWrite = old.flush();
      final current = state.openWriter()..edit('latest');
      await Future.wait([oldWrite, current.flush(), old.flush()]);
      expect(await _read(), 'latest');
      current.edit('');
      await current.flush();
      await old.save('old');
      expect(await _read(), isNull);
      old.edit('explicit resumed edit');
      await old.flush();
      expect(await _read(), 'explicit resumed edit');
      registry.close();
    },
  );

  test(
    'binding retries a held local read against canonical identity',
    () async {
      final registry = ChatPresentationRegistry('connection');
      final writer = registry.chatFor('local').openWriter();
      final held = Completer<String?>();
      final reads = <String>[];
      final result = writer.read(
        reader: ({required connectionId, required sessionId}) {
          reads.add(sessionId);
          return reads.length == 1 ? held.future : Future.value('canonical');
        },
      );
      registry.bind('local', 'stored');
      held.complete('obsolete local');
      expect(await result, 'canonical');
      expect(reads, ['local', 'stored']);
      registry.close();
    },
  );

  test(
    'canonical newer clear wins alias merge and stale restored content',
    () async {
      final registry = ChatPresentationRegistry('connection');
      final local = registry.chatFor('local').openWriter()..edit('old local');
      final canonical = registry.chatFor('stored').openWriter()..edit('');
      await canonical.flush();
      registry.bind('local', 'stored');
      await local.close();
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'local',
        ),
        isNull,
      );
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'stored',
        ),
        isNull,
      );
      expect(canonical.isCurrent, isTrue);
      registry.close();
    },
  );

  test(
    'a legacy local value migrates but never overrides canonical clear',
    () async {
      await ComposerDraftStore.save(
        connectionId: 'connection',
        sessionId: 'local',
        text: 'legacy',
      );
      await ComposerDraftStore.remove(
        connectionId: 'connection',
        sessionId: 'stored',
      );
      await ComposerDraftStore.bind(
        connectionId: 'connection',
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'local',
        ),
        isNull,
      );
      // Recreate the preference cache to prove the marker/alias, not memory,
      // prevents restart resurrection.
      final prefs = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues({
        for (final k in prefs.getKeys()) k: prefs.get(k)!,
      });
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'stored',
        ),
        isNull,
      );
    },
  );

  test(
    'closing invalidates held reads, queued writes and writer reclaim',
    () async {
      final registry = ChatPresentationRegistry('connection');
      final writer = registry.chatFor('chat').openWriter();
      final held = Completer<String?>();
      final read = writer.read(
        reader: ({required connectionId, required sessionId}) => held.future,
      );
      writer.edit('old credential scope');
      final save = writer.flush();
      registry.close();
      held.complete('stale');
      expect(await read, isNull);
      await save;
      writer.edit('must not reclaim');
      await writer.flush();
      expect(await _read(), isNull);
    },
  );

  test(
    'expansion state is bounded and aliases share it, never other credentials or chats',
    () async {
      final controller = GatewayTurnApplicationController();
      final connection = SavedConnection(
        id: 'connection',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'first',
      );
      final registry = controller.presentationFor(connection);
      final state = registry.chatFor('local');
      final toolPins = state.openToolVisit();
      // MAIN81D policy: explicit visit, not application-global manual values.
      final reasoningPins = state.openReasoningVisit();
      for (var i = 0; i < 150; i++) {
        reasoningPins.pin('r-$i', true);
        toolPins.pin('t-$i', false);
        state.aliasTool('t-$i', 'durable-$i');
      }
      registry.bind('local', 'stored');
      expect(identical(registry.chatFor('stored'), state), isTrue);
      expect(reasoningPins.length, ToolActivityGroupPins.maxPins);
      expect(toolPins.length, ToolActivityGroupPins.maxPins);
      expect(reasoningPins['r-149'], isTrue);
      expect(registry.chatFor('sibling').openReasoningVisit()['r-149'], isNull);
      final replacement = controller.presentationFor(
        SavedConnection(
          id: connection.id,
          label: connection.label,
          host: connection.host,
          port: connection.port,
          apiKey: 'second',
        ),
      );
      expect(
        replacement.chatFor('stored').openReasoningVisit()['r-149'],
        isNull,
      );
      expect(reasoningPins.length, 0);
      expect(() => registry.chatFor('local'), throwsStateError);
      controller.revokeConnection(connection.id);
      expect(() => replacement.chatFor('stored'), throwsStateError);
      await controller.close();
    },
  );

  for (final reverse in [false, true]) {
    test(
      'prebinding visits keep independent pins after alias reverse=$reverse',
      () async {
        final registry = ChatPresentationRegistry('visits');
        final local = registry.chatFor('local');
        final canonical = registry.chatFor('stored');
        final localVisit = local.openToolVisit()..pin('anonymous', true);
        final canonicalVisit = canonical.openToolVisit()
          ..pin('anonymous', false);
        final reasoningVisit = local.openReasoningVisit()
          ..pin('reasoning', true);
        final writer = canonical.openWriter()..edit('newer canonical draft');
        if (reverse) {
          registry.bind('stored', 'local');
        } else {
          registry.bind('local', 'stored');
        }
        canonical.aliasTool('anonymous', 'tool:learned');
        expect(localVisit['tool:learned'], isTrue);
        expect(canonicalVisit['tool:learned'], isFalse);
        expect(await writer.read(), 'newer canonical draft');
        local.closeToolVisit(localVisit);
        expect(localVisit.length, 0);
        expect(canonicalVisit['tool:learned'], isFalse);
        final reopened = local.openToolVisit();
        expect(reopened['anonymous'], isNull);
        expect(reopened['tool:learned'], isNull);
        expect(reasoningVisit['reasoning'], isTrue);
        expect(canonical.openReasoningVisit()['reasoning'], isNull);
        canonical.aliasTool('next-local', 'tool:next');
        reopened.pin('next-local', true);
        expect(reopened['tool:next'], isTrue);
        expect(canonicalVisit['tool:next'], isNull);
        await writer.close();
        registry.close();
        expect(reopened.length, 0);
        expect(canonicalVisit.length, 0);
        expect(() => local.openToolVisit(), throwsStateError);
      },
    );
  }
}

Future<String?> _read() =>
    ComposerDraftStore.read(connectionId: 'connection', sessionId: 'chat');
