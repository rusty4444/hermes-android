import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/operational_activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fifo_shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final racing in [false, true]) {
    for (final latest in ['newest explicit text', '']) {
      test(
        'real presentation close/remount/alias with Activity reload: racing=$racing latest="$latest"',
        () async {
          SharedPreferences.setMockInitialValues({});
          final registry = ChatPresentationRegistry('connection');
          addTearDown(registry.close);
          final writer = registry.chatFor('local').openWriter()
            ..edit('obsolete instruction');
          await writer.flush();
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
            read = OperationalActivityStore().load('other-chat-scope');
            await platform.readEntered.future;
          }
          writer.edit(latest);
          final closing = writer.close();
          await platform.writeQueued.future;
          if (racing) {
            platform.releaseRead.complete();
            await read;
          }
          await closing;
          expect(
            (await platform.disk())[draftPreferenceKey('local')],
            latest.isEmpty ? null : latest,
          );
          final replacement = registry.chatFor('local').openWriter();
          final remounted = await replacement.read();
          registry.bind('local', 'stored');
          for (var i = 0; i < 8; i++) {
            await ComposerDraftStore.read(
              connectionId: 'connection',
              sessionId: 'stored',
            );
          }
          await replacement.close();
          final disk = await platform.disk();
          final observed = {
            'remounted': remounted,
            'physicalCanonical': disk[draftPreferenceKey('stored')],
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
            'remounted': latest,
            'physicalCanonical': latest.isEmpty ? null : latest,
          });
        },
      );
    }
  }
}
