import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/operational_activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fifo_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final readBeforeBinding in [true, false]) {
    for (final racing in [false, true]) {
      for (final latest in ['newer instruction', '']) {
        test('Activity reload vs durable draft alias: racing=$racing '
            'latest="$latest" readBeforeBinding=$readBeforeBinding', () async {
          SharedPreferences.setMockInitialValues({});
          await ComposerDraftStore.save(
            connectionId: 'connection',
            sessionId: 'local',
            text: 'obsolete instruction',
          );
          final original = SharedPreferencesStorePlatform.instance;
          final platform = FifoPreferences(await original.getAll());
          SharedPreferencesStorePlatform.instance = platform;
          addTearDown(() async {
            if (!platform.releaseRead.isCompleted) {
              platform.releaseRead.complete();
            }
            await platform.tail;
            SharedPreferencesStorePlatform.instance = original;
          });
          Future<List<OperationalActivityRecord>>? read;
          if (racing) {
            platform.holdRead = true;
            read = OperationalActivityStore().load('unrelated-scope');
            await platform.readEntered.future;
          }
          final saving = ComposerDraftStore.save(
            connectionId: 'connection',
            sessionId: 'local',
            text: latest,
          );
          await platform.writeQueued.future;
          if (racing) {
            platform.releaseRead.complete();
            await read;
          }
          await saving;
          expect(
            (await platform.disk())[draftPreferenceKey('local')],
            latest.isEmpty ? null : latest,
            reason: 'The source write physically succeeded before binding.',
          );
          // Binding needs its own fresh baseline: an earlier public read
          // must not be required to repair the cache for alias migration.
          final beforeAliasCache = readBeforeBinding
              ? await ComposerDraftStore.read(
                  connectionId: 'connection',
                  sessionId: 'local',
                )
              : null;
          await ComposerDraftStore.bind(
            connectionId: 'connection',
            localSessionId: 'local',
            storedSessionId: 'stored',
          );
          final afterAliasDisk = (await platform
              .disk())[draftPreferenceKey('stored')];
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final restarted = <String, Object>{
            for (final key in prefs.getKeys()) key: prefs.get(key)!,
          };
          SharedPreferences.setMockInitialValues(restarted);
          final reopened = await ComposerDraftStore.read(
            connectionId: 'connection',
            sessionId: 'local',
          );
          final observed = {
            if (readBeforeBinding) 'cacheBeforeAlias': beforeAliasCache,
            'physicalCanonical': afterAliasDisk,
            'reopenedThroughAlias': reopened,
          };
          platform.expectDrainedFifo();
          // Machine-readable FIFO evidence for the regression runner.
          // ignore: avoid_print
          print(
            jsonEncode({
              'racing': racing,
              'latest': latest,
              'observed': observed,
              'fifoTrace': platform.trace,
            }),
          );
          expect(observed, {
            if (readBeforeBinding)
              'cacheBeforeAlias': latest.isEmpty ? null : latest,
            'physicalCanonical': latest.isEmpty ? null : latest,
            'reopenedThroughAlias': latest.isEmpty ? null : latest,
          });
        });
      }
    }
  }

  for (final binding in [false, true]) {
    test('failed physical baseline is best effort and releases the queue: '
        'binding=$binding', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = ComposerDraftStore.open(
        connectionId: 'connection',
        sessionId: 'local',
      );
      await writer.save('current draft');
      final original = SharedPreferencesStorePlatform.instance;
      final before = await original.getAll();
      final platform = _FailingReadPreferences(before)..failRead = true;
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      if (binding) {
        await ComposerDraftStore.bind(
          connectionId: 'connection',
          localSessionId: 'local',
          storedSessionId: 'stored',
        );
      } else {
        await expectLater(
          ComposerDraftStore.read(
            connectionId: 'connection',
            sessionId: 'local',
          ),
          throwsA(isA<ComposerDraftReadException>()),
        );
      }
      expect(platform.failRead, isFalse);
      expect(await platform.getAll(), before);
      // A failed read must neither publish an alias nor revoke this writer.
      await writer.save('successor draft');
      expect(
        (await platform.getAll())[draftPreferenceKey('local')],
        'successor draft',
      );
      await ComposerDraftStore.bind(
        connectionId: 'connection',
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'stored',
        ),
        'successor draft',
      );
    });
  }

  test('revocation during the physical alias baseline fences the migration '
      'without stealing a queued writer lease', () async {
    SharedPreferences.setMockInitialValues({});
    final writer = ComposerDraftStore.open(
      connectionId: 'connection',
      sessionId: 'local',
    );
    await writer.save('current draft');
    final original = SharedPreferencesStorePlatform.instance;
    final platform = FifoPreferences(await original.getAll())..holdRead = true;
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() async {
      if (!platform.releaseRead.isCompleted) platform.releaseRead.complete();
      await platform.tail;
      SharedPreferencesStorePlatform.instance = original;
    });
    var current = true;
    final binding = ComposerDraftStore.bind(
      connectionId: 'connection',
      localSessionId: 'local',
      storedSessionId: 'stored',
      isCurrent: () => current,
    );
    await platform.readEntered.future;
    final successor = writer.save('queued successor');
    current = false;
    platform.releaseRead.complete();
    await Future.wait([binding, successor]);
    final disk = await platform.disk();
    expect(disk[draftPreferenceKey('local')], 'queued successor');
    expect(disk[draftPreferenceKey('stored')], isNull);
    expect(
      disk.keys.where((key) => key.contains('composer_draft_alias.')),
      isEmpty,
    );
    platform.expectDrainedFifo();
  });
}

class _FailingReadPreferences extends InMemorySharedPreferencesStore {
  _FailingReadPreferences(super.data) : super.withData();

  bool failRead = false;

  @override
  Future<Map<String, Object>> getAll() async {
    if (failRead) {
      failRead = false;
      throw StateError('Physical preference read failed.');
    }
    return super.getAll();
  }
}
