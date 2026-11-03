import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _RejectingPreferences extends InMemorySharedPreferencesStore {
  _RejectingPreferences() : super.withData({});

  bool reject = false;
  bool readFails = false;
  bool throwWrite = false;
  int writes = 0;
  Completer<void>? writeGate;
  final entered = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    if (readFails) throw PlatformException(code: 'private-provider-details');
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.chat_spaces_v1_gateway') {
      writes++;
      final rejected = reject;
      if (writeGate != null) {
        if (!entered.isCompleted) entered.complete();
        await writeGate!.future;
      }
      if (rejected) {
        if (throwWrite) {
          throw PlatformException(code: 'private-provider-details');
        }
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final throwWrite in [false, true]) {
    for (final operation in ['create', 'rename', 'assign', 'unassign']) {
      test(
        'failed $operation repair preserves confirmed shared authority throw=$throwWrite',
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
          physical
            ..reject = true
            ..readFails = true
            ..throwWrite = throwWrite;
          Future<void> change() async {
            switch (operation) {
              case 'create':
                await store.createSpace('Rejected');
              case 'rename':
                await store.renameSpace(existing.id, 'Rejected');
              case 'assign':
                await store.assignSession('chat', existing.id);
              case 'unassign':
                await store.assignSession('chat', null);
            }
          }

          await expectLater(change(), throwsStateError);
          final replacement = ChatSpaceStore(prefs, connectionId: 'gateway');
          for (final reader in [store, replacement]) {
            final state = await reader.load();
            expect(state.spaces.single.name, 'Existing');
            expect(
              state.spaceIdForSession('chat'),
              operation == 'unassign' ? existing.id : null,
            );
          }
          final writes = physical.writes;
          await expectLater(
            replacement.assignSession('successor', existing.id),
            throwsA(
              isA<StateError>().having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('private-provider-details')),
              ),
            ),
          );
          expect(
            physical.writes,
            writes,
            reason: 'no write from an unverified repair baseline',
          );
          physical
            ..readFails = false
            ..reject = false;
          await replacement.assignSession('successor', existing.id);
          final disk =
              jsonDecode(
                    (await physical.getAll())['flutter.chat_spaces_v1_gateway']!
                        as String,
                  )
                  as Map;
          expect((disk['spaces'] as List).single['name'], 'Existing');
          expect((disk['assignments'] as Map)['successor'], existing.id);
          await prefs.reload();
          expect(
            (await ChatSpaceStore(
              prefs,
              connectionId: 'gateway',
            ).load()).spaces.single.name,
            'Existing',
          );
        },
      );
    }
  }

  test(
    'held rejected rename cannot lend optimism to queued sibling read or save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final original = SharedPreferencesStorePlatform.instance;
      final physical = _RejectingPreferences();
      SharedPreferencesStorePlatform.instance = physical;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      final prefs = await SharedPreferences.getInstance();
      final first = ChatSpaceStore(prefs, connectionId: 'gateway');
      final space = await first.createSpace('Existing');
      final gate = Completer<void>();
      physical
        ..reject = true
        ..writeGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final rename = first.renameSpace(space.id, 'Rejected');
      final rejected = expectLater(rename, throwsStateError);
      await physical.entered.future;
      final sibling = ChatSpaceStore(prefs, connectionId: 'gateway');
      final read = sibling.load();
      final assignment = sibling.assignSession('chat', space.id);
      physical
        ..reject = false
        ..writeGate = null;
      gate.complete();
      await rejected;
      expect((await read).spaces.single.name, 'Existing');
      await assignment;
      await prefs.reload();
      final fresh = await sibling.load();
      expect(fresh.spaces.single.name, 'Existing');
      expect(fresh.spaceIdForSession('chat'), space.id);
    },
  );

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
