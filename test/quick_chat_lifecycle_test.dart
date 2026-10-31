/// The Quick chat lifecycle, end to end.
///
/// `buildNewChatDraft` computed a 72 h deadline and `QuickChatStore` can now
/// hold it, but a stored deadline that nothing enforces is a comment. These
/// tests pin the two halves that make Quick chat real:
///
/// 1. **Enforcement** — [buildHomeDigest] drops an expired Quick chat from the
///    resumable sections, which is what "auto-archives after 72 hours" means
///    on screen. Blocked work is exempt: hiding a chat that is waiting on the
///    user would be a silent deletion of their attention, which the roadmap
///    forbids.
/// 2. **Wiring** — starting a Quick chat from Home's New button actually
///    records it, and starting a Project chat records nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_digest.dart';
import 'package:hermes_android/core/utils/new_chat_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

final _now = DateTime.utc(2026, 8, 29, 12);

double _secondsAgo(Duration ago) =>
    _now.subtract(ago).millisecondsSinceEpoch / 1000.0;

Session _session(
  String id, {
  Duration startedAgo = const Duration(hours: 1),
  Duration? endedAgo,
}) {
  return Session(
    id: id,
    title: 'Chat $id',
    model: 'claude-opus-5',
    source: 'mobile',
    messageCount: 2,
    isActive: endedAgo == null,
    preview: '',
    startedAt: _secondsAgo(startedAgo),
    endedAt: endedAgo == null ? null : _secondsAgo(endedAgo),
  );
}

List<String> _idsIn(HomeDigest digest, HomeSectionKind kind) {
  for (final section in digest.sections) {
    if (section.kind == kind) {
      return section.items.map((item) => item.session.id).toList();
    }
  }
  return const [];
}

SavedConnection _connection({String? desktopGatewayUrl}) => SavedConnection(
  id: 'conn-1',
  label: 'Miniserver',
  host: 'carlos-miniserver',
  port: 8642,
  apiKey: 'test-key',
  desktopGatewayUrl: desktopGatewayUrl,
);

Future<ProjectsRepository> _repository(
  List<Map<String, dynamic>> projects,
) async {
  return ProjectsRepository(
    client: ProjectsGatewayClient((method, params) async {
      if (method == 'projects.list') {
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'projects': projects, 'active_id': null},
        };
      }
      return {'jsonrpc': '2.0', 'id': 1, 'result': const {}};
    }),
    preferences: await SharedPreferences.getInstance(),
    connectionId: 'conn-1',
  );
}

Map<String, dynamic> _projectJson({
  required String id,
  required String name,
  String? primaryPath,
}) => {
  'id': id,
  'slug': name.toLowerCase(),
  'name': name,
  'archived': false,
  'created_at': 1750000000,
  'primary_path': ?primaryPath,
  'folders': const [],
};

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required SavedConnection connection,
  ProjectsRepository? repository,
  required ValueChanged<NewChatDraft> onNewChat,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: connection,
        repositoryFactory: repository == null ? null : (_) => repository,
        sessionsLoader: () async => const <Session>[],
        onNewChat: onNewChat,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('an expired quick chat leaves Home', () {
    test('it is dropped from Continue working', () {
      final digest = buildHomeDigest(
        sessions: [_session('quick'), _session('durable')],
        now: _now,
        archived: const {'quick'},
      );

      expect(_idsIn(digest, HomeSectionKind.continueWorking), ['durable']);
    });

    test('it is dropped from Recently completed too', () {
      final digest = buildHomeDigest(
        sessions: [
          _session('quick', endedAgo: const Duration(hours: 2)),
          _session('durable', endedAgo: const Duration(hours: 2)),
        ],
        now: _now,
        archived: const {'quick'},
      );

      expect(_idsIn(digest, HomeSectionKind.completedRecently), ['durable']);
    });

    test('but blocked work is never hidden by the archive', () {
      // Auto-archive is an organization rule. Applying it to a chat that is
      // waiting on the user would hide the one thing Home exists to show.
      final digest = buildHomeDigest(
        sessions: [_session('quick')],
        now: _now,
        attention: const {'quick': 'Approval requested'},
        archived: const {'quick'},
      );

      expect(_idsIn(digest, HomeSectionKind.needsYou), ['quick']);
      expect(digest.blockedCount, 1);
    });

    test('and running work is never hidden either', () {
      // A quick chat whose deadline passed mid-turn is still doing work.
      final digest = buildHomeDigest(
        sessions: [_session('quick')],
        now: _now,
        running: const {'quick'},
        archived: const {'quick'},
      );

      expect(_idsIn(digest, HomeSectionKind.running), ['quick']);
    });

    test('an archived id matching no session invents nothing', () {
      final digest = buildHomeDigest(
        sessions: [_session('durable')],
        now: _now,
        archived: const {'ghost'},
      );

      expect(_idsIn(digest, HomeSectionKind.continueWorking), ['durable']);
    });

    test('archiving every chat produces the calm empty digest', () {
      final digest = buildHomeDigest(
        sessions: [_session('quick')],
        now: _now,
        archived: const {'quick'},
      );

      expect(digest.isEmpty, isTrue);
      expect(digest.blockedCount, 0);
    });
  });

  group('the New button records the lifecycle', () {
    testWidgets('a quick chat is recorded with its 72 h deadline', (
      tester,
    ) async {
      final drafts = <NewChatDraft>[];
      await _pumpWorkspace(
        tester,
        connection: _connection(),
        onNewChat: drafts.add,
      );

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.quickChat.label(l10n)));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final state = await QuickChatStore(prefs, connectionId: 'conn-1').load();
      final id = drafts.single.session.id;

      expect(state.isQuick(id), isTrue);
      // The store round-trips through epoch millis, so it returns the same
      // instant normalised to UTC rather than the identical DateTime object.
      final expected = drafts.single.expiresAt!;
      expect(state.expiresAtFor(id)!.isUtc, isTrue);
      expect(
        state.expiresAtFor(id)!.millisecondsSinceEpoch,
        expected.millisecondsSinceEpoch,
      );
    });

    testWidgets('a project chat is never put on an archive timer', (
      tester,
    ) async {
      final drafts = <NewChatDraft>[];
      await _pumpWorkspace(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([
          _projectJson(
            id: 'p1',
            name: 'Hermes Android',
            primaryPath: '/srv/projects/hermes-android',
          ),
        ]),
        onNewChat: drafts.add,
      );

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.projectChat.label(l10n)));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final state = await QuickChatStore(prefs, connectionId: 'conn-1').load();

      expect(drafts.single.isQuick, isFalse);
      expect(state.isQuick(drafts.single.session.id), isFalse);
    });
  });
}
