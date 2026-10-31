import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const connectionA = 'connection-a';
  const connectionB = 'connection-b';

  test('a saved draft round-trips per connection + session', () async {
    await ComposerDraftStore.save(
      connectionId: connectionA,
      sessionId: 's1',
      text: 'half typed',
    );

    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's1'),
      'half typed',
    );
    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's2'),
      isNull,
    );
  });

  test('identical session ids on different connections never leak', () async {
    await ComposerDraftStore.save(
      connectionId: connectionA,
      sessionId: 's1',
      text: 'from A',
    );
    await ComposerDraftStore.save(
      connectionId: connectionB,
      sessionId: 's1',
      text: 'from B',
    );

    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's1'),
      'from A',
    );
    expect(
      await ComposerDraftStore.read(connectionId: connectionB, sessionId: 's1'),
      'from B',
    );
  });

  test('empty text clears the draft instead of resurrecting it', () async {
    await ComposerDraftStore.save(
      connectionId: connectionA,
      sessionId: 's1',
      text: 'typed',
    );
    await ComposerDraftStore.save(
      connectionId: connectionA,
      sessionId: 's1',
      text: '',
    );

    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's1'),
      isNull,
    );
  });

  test('nonempty whitespace is literal draft content, not a clear', () async {
    for (final text in ['   ', '\r\n' * 1501]) {
      await ComposerDraftStore.save(
        connectionId: connectionA,
        sessionId: 's1',
        text: text,
      );
      expect(
        await ComposerDraftStore.read(
          connectionId: connectionA,
          sessionId: 's1',
        ),
        text,
      );
    }
  });

  test('remove drops one session, removeConnection drops the rest', () async {
    await ComposerDraftStore.save(
      connectionId: connectionA,
      sessionId: 's1',
      text: 'a1',
    );
    await ComposerDraftStore.save(
      connectionId: connectionA,
      sessionId: 's2',
      text: 'a2',
    );
    await ComposerDraftStore.save(
      connectionId: connectionB,
      sessionId: 's1',
      text: 'b1',
    );

    await ComposerDraftStore.remove(connectionId: connectionA, sessionId: 's1');
    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's1'),
      isNull,
    );
    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's2'),
      'a2',
    );

    await ComposerDraftStore.removeConnection(connectionA);
    expect(
      await ComposerDraftStore.read(connectionId: connectionA, sessionId: 's2'),
      isNull,
    );
    // Another connection's drafts survive the purge.
    expect(
      await ComposerDraftStore.read(connectionId: connectionB, sessionId: 's1'),
      'b1',
    );
  });
}
