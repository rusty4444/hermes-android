import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session session(String id, {double startedAt = 1}) => Session(
  id: id,
  title: 'Session $id',
  model: 'test',
  source: 'api',
  messageCount: 1,
  isActive: false,
  preview: '',
  startedAt: startedAt,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('spaces and assignments stay scoped to their connection', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = ChatSpaceStore(prefs, connectionId: 'gateway-a');
    final second = ChatSpaceStore(prefs, connectionId: 'gateway-b');

    final project = await first.createSpace('Hermes Android');
    await first.assignSession('session-1', project.id);

    expect((await first.load()).spaces.single.name, 'Hermes Android');
    expect((await first.load()).spaceIdForSession('session-1'), project.id);
    expect((await second.load()).spaces, isEmpty);
    expect((await second.load()).spaceIdForSession('session-1'), isNull);
  });

  test('space names are trimmed and unique without regard to case', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');

    final created = await store.createSpace('  ScriptHive  ');

    expect(created.name, 'ScriptHive');
    expect(() => store.createSpace('scripthive'), throwsFormatException);
    expect(() => store.createSpace('   '), throwsFormatException);
  });

  test('session scopes return all, unassigned, or one space', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');
    final android = await store.createSpace('Android');
    final sessions = [session('one'), session('two'), session('three')];
    await store.assignSession('one', android.id);

    final state = await store.load();

    expect(
      state.sessionsFor(sessions, const ChatSpaceScope.all()).map((s) => s.id),
      ['one', 'two', 'three'],
    );
    expect(
      state
          .sessionsFor(sessions, const ChatSpaceScope.unassigned())
          .map((s) => s.id),
      ['two', 'three'],
    );
    expect(
      state
          .sessionsFor(sessions, ChatSpaceScope.space(android.id))
          .map((s) => s.id),
      ['one'],
    );
    expect(state.latestActivityFor(sessions, android.id), 1);
  });

  test('moving to unassigned removes the previous assignment', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');
    final android = await store.createSpace('Android');
    await store.assignSession('one', android.id);

    await store.assignSession('one', null);

    expect((await store.load()).spaceIdForSession('one'), isNull);
  });

  test('renameSpace preserves identity and assignments', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');
    final android = await store.createSpace('Android');
    await store.assignSession('one', android.id);

    await store.renameSpace(android.id, 'Hermes Android');

    final state = await store.load();
    expect(state.spaces.single.id, android.id);
    expect(state.spaces.single.name, 'Hermes Android');
    expect(state.spaceIdForSession('one'), android.id);
  });

  test('assignment to an unknown space is rejected', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(prefs, connectionId: 'gateway');

    expect(
      () => store.assignSession('one', 'missing-space'),
      throwsArgumentError,
    );
  });
}
