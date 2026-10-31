import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The plugin's platform seam lets these tests hold/fail actual durable writes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'aliases persist across preference/process replacement and stay connection scoped',
    () async {
      final local = ComposerDraftStore.open(
        connectionId: 'a',
        sessionId: 'local',
      );
      await local.save('Next draft');
      await _bind();
      await local.save('Updated next draft');
      expect(await _read('canonical'), 'Updated next draft');
      expect(await _read('canonical', connection: 'b'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(_key('local')),
        'Next draft',
        reason:
            'successful migration retains its source until explicit deletion',
      );
      SharedPreferences.setMockInitialValues({
        for (final key in prefs.getKeys()) key: prefs.get(key)!,
      });
      expect(await _read('canonical'), 'Updated next draft');
      expect(await _read('local'), 'Updated next draft');
      await ComposerDraftStore.remove(
        connectionId: 'a',
        sessionId: 'canonical',
      );
      expect(await _read('local'), isNull);
      await ComposerDraftStore.save(
        connectionId: 'b',
        sessionId: 'local',
        text: 'Other connection',
      );
      await ComposerDraftStore.removeConnection('a');
      expect(await _read('local'), isNull);
      expect(await _read('local', connection: 'b'), 'Other connection');
    },
  );

  for (final canonical in ['Newer canonical draft', '']) {
    test(
      'binding preserves canonical text/clear over stale local disposal: "$canonical"',
      () async {
        final local = ComposerDraftStore.open(
          connectionId: 'a',
          sessionId: 'local',
        );
        await local.save('Old local draft');
        await ComposerDraftStore.save(
          connectionId: 'a',
          sessionId: 'canonical',
          text: canonical,
        );
        await _bind();
        await local.save('Old route late disposal');
        expect(
          await _read('canonical'),
          canonical.isEmpty ? isNull : canonical,
        );
        expect(await _read('local'), canonical.isEmpty ? isNull : canonical);
        local.edited();
        await local.save('Intentional new edit after binding');
        expect(await _read('canonical'), 'Intentional new edit after binding');
      },
    );
  }

  test(
    'a replacement canonical route fences old local-route writes and rejection restoration',
    () async {
      final local = ComposerDraftStore.open(
        connectionId: 'a',
        sessionId: 'local',
      );
      await local.save('Local draft');
      await _bind();
      final replacement = ComposerDraftStore.open(
        connectionId: 'a',
        sessionId: 'canonical',
      );
      await replacement.save('New route draft');
      await local.save('Old route dispose or failed-send restoration');
      expect(await _read('canonical'), 'New route draft');
      replacement.edited();
      await replacement.save('');
      await local.save('Must not resurrect after deliberate clear');
      expect(await _read('local'), isNull);
    },
  );

  test(
    'held binding hands the merged identity to a newer canonical writer',
    () async {
      final platform = _ControlledStore();
      SharedPreferencesStorePlatform.instance = platform;
      final local = ComposerDraftStore.open(
        connectionId: 'a',
        sessionId: 'local',
      );
      await local.save('Local before binding');
      platform.heldKey = 'flutter.${_key('canonical')}';
      final binding = _bind();
      await platform.entered.future;
      final replacement = ComposerDraftStore.open(
        connectionId: 'a',
        sessionId: 'canonical',
      );
      final newer = replacement.save('New canonical while binding was held');
      final stale = local.save('Stale dispose queued behind the new route');
      platform.release.complete();
      await Future.wait([binding, newer, stale]);
      expect(await _read('local'), 'New canonical while binding was held');
      expect(await _read('canonical'), 'New canonical while binding was held');
      final disk = await platform.getAll();
      expect(disk['flutter.${_key('local')}'], 'Local before binding');
    },
  );

  for (final failure in ['copy', 'alias']) {
    test(
      'failed $failure retains source on disk and retries without a phantom cached alias',
      () async {
        final platform = _ControlledStore();
        SharedPreferencesStorePlatform.instance = platform;
        await ComposerDraftStore.save(
          connectionId: 'a',
          sessionId: 'local',
          text: 'Only local copy',
        );
        platform.failedKey = failure == 'copy'
            ? 'flutter.${_key('canonical')}'
            : 'flutter.composer_draft_alias.${_key('local').split('.').last}';
        await _bind();
        final disk = await platform.getAll();
        expect(disk['flutter.${_key('local')}'], 'Only local copy');
        expect(
          disk.keys.where((key) => key.contains('composer_draft_alias.')),
          isEmpty,
        );
        expect(await _read('local'), 'Only local copy');
        platform.failedKey = null;
        await _bind();
        expect(await _read('canonical'), 'Only local copy');
        await ComposerDraftStore.save(
          connectionId: 'a',
          sessionId: 'local',
          text: 'After successful retry',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(await _read('canonical'), 'After successful retry');
        expect(await _read('local'), 'After successful retry');
      },
    );
  }
}

Future<void> _bind() => ComposerDraftStore.bind(
  connectionId: 'a',
  localSessionId: 'local',
  storedSessionId: 'canonical',
);
Future<String?> _read(String id, {String connection = 'a'}) =>
    ComposerDraftStore.read(connectionId: connection, sessionId: id);
String _key(String id) =>
    'composer_draft.${base64Url.encode(utf8.encode('a\u0000$id')).replaceAll('=', '')}';

class _ControlledStore extends InMemorySharedPreferencesStore {
  _ControlledStore() : super.empty();
  String? heldKey;
  String? failedKey;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == heldKey && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    if (key == failedKey) return false;
    return super.setValue(valueType, key, value);
  }
}
