import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'rejected migration target keeps source and retries without stale cache',
    () async {
      await ComposerDraftStore.save(
        connectionId: 'connection',
        sessionId: 'local',
        text: 'legacy',
      );
      final original = SharedPreferencesStorePlatform.instance;
      final store = _ControlledStore(await original.getAll())
        ..rejectKey = _key('stored');
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      await ComposerDraftStore.bind(
        connectionId: 'connection',
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      expect(await _read('local'), 'legacy');
      expect(await _read('stored'), isNull);
      store.rejectKey = null;
      await ComposerDraftStore.bind(
        connectionId: 'connection',
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(await _read('stored'), 'legacy');
      expect(await _read('local'), 'legacy');
    },
  );

  for (final latest in ['newer instruction', '']) {
    test(
      'held physical write and rollback cannot finish after newer intent: "$latest"',
      () async {
        final original = SharedPreferencesStorePlatform.instance;
        final store = _ControlledStore(await original.getAll())
          ..holdKey = _key('chat');
        SharedPreferencesStorePlatform.instance = store;
        addTearDown(() => SharedPreferencesStorePlatform.instance = original);
        final registry = ChatPresentationRegistry('connection');
        final state = registry.chatFor('chat');
        final old = state.openWriter()..edit('old');
        final oldWrite = old.flush();
        await store.started.future;
        final current = state.openWriter()..edit(latest);
        final newWrite = current.flush();
        // The old platform flight fails after newer intent is admitted. Its
        // rollback must join the same physical queue as the replacement write.
        store.release.complete(false);
        await Future.wait([oldWrite, newWrite]);
        await old.close();
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(await _read('chat'), latest.isEmpty ? isNull : latest);
        registry.close();
      },
    );
  }
}

Future<String?> _read(String id) =>
    ComposerDraftStore.read(connectionId: 'connection', sessionId: id);
String _key(String id) =>
    'flutter.composer_draft.${base64Url.encode(utf8.encode('connection\u0000$id')).replaceAll('=', '')}';

class _ControlledStore extends InMemorySharedPreferencesStore {
  _ControlledStore(super.data) : super.withData();
  String? rejectKey;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<bool>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == rejectKey) return false;
    if (key == holdKey) {
      holdKey = null;
      started.complete();
      if (!await release.future) return false;
    }
    return super.setValue(valueType, key, value);
  }
}
