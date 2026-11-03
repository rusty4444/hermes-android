import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/draft_read_outage_preferences.dart';
import 'support/fifo_shared_preferences.dart' show draftPreferenceKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DraftReadOutagePreferences> install() async {
    final original = SharedPreferencesStorePlatform.instance;
    final platform = DraftReadOutagePreferences(await original.getAll());
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() async {
      if (!platform.releaseRead.isCompleted) platform.releaseRead.complete();
      await platform.tail;
      SharedPreferencesStorePlatform.instance = original;
    });
    return platform;
  }

  for (final saved in ['saved explicit text', '']) {
    test(
      'failed hydration stays unknown to save/flush/close: saved="$saved"',
      () async {
        final registry = ChatPresentationRegistry('connection');
        addTearDown(registry.close);
        final first = registry.chatFor('local').openWriter()..edit(saved);
        await first.close();
        final platform = await install();
        final before = await platform.disk();
        final next = registry.chatFor('local').openWriter();
        platform.failNextRead = true;
        expect(await next.read(), isNull);
        await next.save('');
        await next.flush();
        await next.close();
        expect(platform.failures, 1);
        expect(platform.draftMutations, isEmpty);
        expect(await platform.disk(), before);
        final recovered = registry.chatFor('local').openWriter();
        expect(await recovered.read(), saved);
        await recovered.close();
        expect(
          (await platform.disk())[draftPreferenceKey('local')],
          saved.isEmpty ? null : saved,
        );
        platform.expectDrainedFifo();
      },
    );
  }

  test(
    'same live writer can retry a real failed read without caching absence',
    () async {
      final registry = ChatPresentationRegistry('connection');
      addTearDown(registry.close);
      await (registry.chatFor('local').openWriter()..edit('saved text'))
          .close();
      final platform = await install();
      final writer = registry.chatFor('local').openWriter();
      platform.failNextRead = true;
      expect(await writer.read(), isNull);
      expect(platform.draftMutations, isEmpty);
      expect(await writer.read(), 'saved text');
      expect(await writer.read(), 'saved text');
      await writer.close();
      expect(
        (await platform.disk())[draftPreferenceKey('local')],
        'saved text',
      );
      platform.expectDrainedFifo();
    },
  );

  test(
    'public physical reader reports sanitized unavailable rather than absent',
    () async {
      await ComposerDraftStore.save(
        connectionId: 'connection',
        sessionId: 'local',
        text: 'saved text',
      );
      final platform = await install();
      final before = await platform.disk();
      platform.failNextRead = true;
      await expectLater(
        ComposerDraftStore.read(connectionId: 'connection', sessionId: 'local'),
        throwsA(
          isA<ComposerDraftReadException>().having(
            (error) => error.toString(),
            'sanitized public message',
            'Composer draft is unavailable.',
          ),
        ),
      );
      expect(await platform.disk(), before);
      expect(platform.draftMutations, isEmpty);
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'local',
        ),
        'saved text',
      );
      expect(
        await ComposerDraftStore.read(
          connectionId: 'connection',
          sessionId: 'absent',
        ),
        isNull,
      );
      platform.expectDrainedFifo();
    },
  );

  for (final latest in ['edited during failed read', '']) {
    test(
      'a held failure cannot replace a new explicit value: "$latest"',
      () async {
        final registry = ChatPresentationRegistry('connection');
        addTearDown(registry.close);
        await (registry.chatFor('local').openWriter()..edit('old text'))
            .close();
        final platform = await install();
        platform
          ..holdNextRead = true
          ..failNextRead = true;
        final writer = registry.chatFor('local').openWriter();
        final read = writer.read();
        await platform.readEntered.future;
        writer.edit(latest);
        final save = writer.flush();
        platform.releaseRead.complete();
        expect(await read, latest);
        await save;
        expect(await writer.read(), latest);
        await writer.close();
        expect(
          (await platform.disk())[draftPreferenceKey('local')],
          latest.isEmpty ? null : latest,
        );
        platform.expectDrainedFifo();
      },
    );
  }
}
