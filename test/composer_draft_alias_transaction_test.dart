import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

enum AliasFailure { reject, throwBefore, lostAck, throwAfter }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final failure in AliasFailure.values) {
    for (final editedId in ['local', 'stored']) {
      for (final latest in ['new instruction', '']) {
        test(
          '$failure: $editedId edit "$latest" between failure and retry survives physical reload',
          () async {
            await _save('local', 'legacy');
            final original = SharedPreferencesStorePlatform.instance;
            final platform = _AliasPlatform(await original.getAll(), failure);
            SharedPreferencesStorePlatform.instance = platform;
            addTearDown(
              () => SharedPreferencesStorePlatform.instance = original,
            );
            await _bind();
            final physical = await platform.getAll();
            expect(physical[_key('local', 'composer_draft_alias')], isNull);
            expect(physical[_key('stored')], isNull);
            expect(physical[_key('stored', 'composer_draft_written')], isNull);
            expect(await _read('local'), 'legacy');
            expect(await _read('stored'), isNull);
            await _save(editedId, latest);
            platform.failure = null;
            await _bind();
            final prefs = await SharedPreferences.getInstance();
            await prefs.reload();
            expect(
              (await platform.getAll())[_key('local', 'composer_draft_alias')],
              'stored',
            );
            expect(
              (await platform.getAll())[_key(
                'stored',
                'composer_draft_written',
              )],
              true,
            );
            for (final id in ['local', 'stored']) {
              expect(await _read(id), latest.isEmpty ? isNull : latest);
            }
            // Another late legacy alias must not resurrect an explicitly cleared
            // source that was migrated without a string entry.
            await _save('other-local', 'obsolete other draft');
            await ComposerDraftStore.bind(
              connectionId: 'connection',
              localSessionId: 'other-local',
              storedSessionId: 'stored',
            );
            await prefs.reload();
            expect(await _read('stored'), latest.isEmpty ? isNull : latest);
          },
        );
      }
    }
  }

  test(
    'durable alias survives lost ACK and rejected rollback without deleting its target',
    () async {
      await _save('local', 'legacy');
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _AliasPlatform(
        await original.getAll(),
        AliasFailure.lostAck,
      )..rejectAliasRemoval = true;
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      await _bind();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(
        (await platform.getAll())[_key('local', 'composer_draft_alias')],
        'stored',
      );
      expect(await _read('local'), 'legacy');
      expect(await _read('stored'), 'legacy');
      platform.failure = null;
      await _save('local', 'newer via physically committed alias');
      await _bind();
      await prefs.reload();
      expect(await _read('local'), 'newer via physically committed alias');
      expect(await _read('stored'), 'newer via physically committed alias');
    },
  );
}

Future<void> _bind() => ComposerDraftStore.bind(
  connectionId: 'connection',
  localSessionId: 'local',
  storedSessionId: 'stored',
);
Future<void> _save(String id, String text) => ComposerDraftStore.save(
  connectionId: 'connection',
  sessionId: id,
  text: text,
);
Future<String?> _read(String id) =>
    ComposerDraftStore.read(connectionId: 'connection', sessionId: id);
String _key(String id, [String prefix = 'composer_draft']) =>
    'flutter.$prefix.${base64Url.encode(utf8.encode('connection\u0000$id')).replaceAll('=', '')}';

class _AliasPlatform extends InMemorySharedPreferencesStore {
  _AliasPlatform(super.data, this.failure) : super.withData();
  AliasFailure? failure;
  bool rejectAliasRemoval = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _key('local', 'composer_draft_alias')) {
      switch (failure) {
        case AliasFailure.reject:
          return false;
        case AliasFailure.throwBefore:
          throw StateError('Rejected before physical alias write');
        case AliasFailure.lostAck:
          await super.setValue(valueType, key, value);
          return false;
        case AliasFailure.throwAfter:
          await super.setValue(valueType, key, value);
          throw StateError('Lost ACK after physical alias write');
        case null:
          break;
      }
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (rejectAliasRemoval && key == _key('local', 'composer_draft_alias')) {
      return false;
    }
    return super.remove(key);
  }
}
