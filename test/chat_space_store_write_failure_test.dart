import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RejectingPreferences extends InMemorySharedPreferencesStore {
  _RejectingPreferences() : super.withData({});

  bool reject = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (reject && key == 'flutter.chat_spaces_v1_gateway') return false;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final operation in ['create', 'rename', 'assign', 'unassign']) {
    test(
      'rejected $operation is not success or cached authority (#207 L8)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final original = SharedPreferencesStorePlatform.instance;
        final physical = _RejectingPreferences();
        SharedPreferencesStorePlatform.instance = physical;
        addTearDown(() => SharedPreferencesStorePlatform.instance = original);
        final prefs = await SharedPreferences.getInstance();
        final store = ChatSpaceStore(prefs, connectionId: 'gateway');
        final existing = await store.createSpace('Existing');
        if (operation == 'unassign') {
          await store.assignSession('chat', existing.id);
        }
        final before = prefs.getString('chat_spaces_v1_gateway');
        physical.reject = true;
        Future<void> change() async {
          switch (operation) {
            case 'create':
              await store.createSpace('New');
            case 'rename':
              await store.renameSpace(existing.id, 'New');
            case 'assign':
              await store.assignSession('chat', existing.id);
            case 'unassign':
              await store.assignSession('chat', null);
          }
        }

        await expectLater(change(), throwsStateError);
        expect(
          prefs.getString('chat_spaces_v1_gateway'),
          before,
          reason: 'discard SharedPreferences speculative cache after false',
        );
        final live = await store.load();
        expect(live.spaces.single.name, 'Existing');
        expect(
          live.spaceIdForSession('chat'),
          operation == 'unassign' ? existing.id : null,
        );
        await prefs.reload();
        expect(prefs.getString('chat_spaces_v1_gateway'), before);
        final reopened = ChatSpaceStore(prefs, connectionId: 'gateway');
        expect((await reopened.load()).spaces.single.name, 'Existing');

        physical.reject = false;
        await change();
        await prefs.reload();
        final saved = await reopened.load();
        if (operation == 'create') {
          expect(saved.spaces.map((s) => s.name), ['Existing', 'New']);
        }
        if (operation == 'rename') expect(saved.spaces.single.name, 'New');
        if (operation == 'assign') {
          expect(saved.spaceIdForSession('chat'), existing.id);
        }
        if (operation == 'unassign') {
          expect(saved.spaceIdForSession('chat'), isNull);
        }
      },
    );
  }
}
