import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_project.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/utils/new_chat_options.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';


final _now = DateTime.utc(2026, 8, 28, 9, 30, 0);

HermesProject _project({
  String id = 'p1',
  String name = 'Hermes Android',
  bool archived = false,
  String? primaryPath,
}) {
  return HermesProject(
    id: id,
    slug: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    archived: archived,
    primaryPath: primaryPath,
  );
}

NewChatOption _option(List<NewChatOption> options, NewChatMode mode) {
  return options.firstWhere((option) => option.mode == mode);
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  group('NewChatMode', () {
    test('offers exactly the two validated creation modes', () {
      // The roadmap's global New button offers Project chat and Quick chat.
      // A third mode would be a product decision, not an implementation one.
      expect(NewChatMode.values, [
        NewChatMode.projectChat,
        NewChatMode.quickChat,
      ]);
    });

    test('each mode carries a distinct label and description', () {
      final labels = <String>{};
      final descriptions = <String>{};
      for (final mode in NewChatMode.values) {
        expect(mode.label(l10n), isNotEmpty);
        expect(mode.description(l10n), isNotEmpty);
        labels.add(mode.label(l10n));
        descriptions.add(mode.description(l10n));
      }
      expect(labels.length, NewChatMode.values.length);
      expect(descriptions.length, NewChatMode.values.length);
    });
  });

  group('buildNewChatOptions', () {
    test('always lists every mode so none is silently hidden', () {
      // Capability discovery rule: a mode that cannot run is disabled *with a
      // reason*, never dropped from the sheet.
      for (final support in ProjectsSupport.values) {
        final options = buildNewChatOptions(l10n: l10n, 
          support: support,
          projects: const [],
        );
        expect(
          options.map((option) => option.mode).toList(),
          NewChatMode.values,
          reason: 'support $support dropped a mode',
        );
      }
    });

    test('enables Project chat when the gateway hosts a project', () {
      final options = buildNewChatOptions(l10n: l10n, 
        support: ProjectsSupport.native,
        projects: [_project()],
      );

      final projectChat = _option(options, NewChatMode.projectChat);
      expect(projectChat.enabled, isTrue);
      expect(projectChat.disabledReason, isNull);
    });

    test('keeps Quick chat enabled on a gateway without Projects', () {
      // Quick chat needs no project and no `projects.*` family, so a legacy
      // gateway must still be able to start a chat from Home.
      final options = buildNewChatOptions(l10n: l10n, 
        support: ProjectsSupport.unsupported,
        projects: const [],
      );

      final quick = _option(options, NewChatMode.quickChat);
      expect(quick.enabled, isTrue);
      expect(quick.disabledReason, isNull);
    });

    test('disables Project chat on a gateway without Projects, with a reason '
        'naming the gateway rather than the user', () {
      final options = buildNewChatOptions(l10n: l10n, 
        support: ProjectsSupport.unsupported,
        projects: const [],
      );

      final projectChat = _option(options, NewChatMode.projectChat);
      expect(projectChat.enabled, isFalse);
      expect(projectChat.disabledReason, contains('gateway'));
    });

    test('a supported gateway with no project yet asks for one instead of '
        'blaming the gateway', () {
      final options = buildNewChatOptions(l10n: l10n, 
        support: ProjectsSupport.native,
        projects: const [],
      );

      final projectChat = _option(options, NewChatMode.projectChat);
      expect(projectChat.enabled, isFalse);
      expect(projectChat.disabledReason, isNotNull);
      expect(projectChat.disabledReason, isNot(contains('gateway')));
    });

    test(
      'an unprobed gateway is described as loading, never as unsupported',
      () {
        // The capability registry treats an absent advertisement as `unknown`;
        // telling the user Projects are missing before probing would be a lie.
        final options = buildNewChatOptions(l10n: l10n, 
          support: ProjectsSupport.unknown,
          projects: const [],
        );

        final projectChat = _option(options, NewChatMode.projectChat);
        expect(projectChat.enabled, isFalse);
        expect(projectChat.disabledReason, isNot(contains('gateway')));
        expect(projectChat.disabledReason?.toLowerCase(), contains('loading'));
      },
    );

    test('an archived project cannot enable Project chat', () {
      final options = buildNewChatOptions(l10n: l10n, 
        support: ProjectsSupport.native,
        projects: [_project(archived: true)],
      );

      expect(_option(options, NewChatMode.projectChat).enabled, isFalse);
    });

    test('a stale cached listing still enables Project chat', () {
      // Offline must degrade the freshness of the project list, not the
      // ability to start work in a project the user already knows about.
      final options = buildNewChatOptions(l10n: l10n, 
        support: ProjectsSupport.native,
        projects: [_project()],
        isStale: true,
      );

      expect(_option(options, NewChatMode.projectChat).enabled, isTrue);
    });

    test(
      'reads a ProjectsView directly so the caller cannot drift from it',
      () {
        final view = ProjectsView(
          projects: [_project()],
          archived: [_project(id: 'p2', name: 'Old', archived: true)],
          support: ProjectsSupport.native,
        );

        final options = buildNewChatOptionsFor(l10n, view);

        expect(_option(options, NewChatMode.projectChat).enabled, isTrue);
        expect(_option(options, NewChatMode.quickChat).enabled, isTrue);
      },
    );
  });

  group('buildNewChatDraft', () {
    test('a quick chat starts without a project', () {
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        sessionId: 'mob-1',
        now: _now,
      );

      expect(draft.isQuick, isTrue);
      expect(draft.projectId, isNull);
      expect(draft.projectName, isNull);
      expect(draft.projectWorkingDirectory, isNull);
      expect(draft.session.id, 'mob-1');
      expect(draft.session.isLocalDraft, isTrue);
    });

    test('a quick chat never inherits the active project', () {
      // Validated decision: Quick Chat starts without a Project even when one
      // is selected, otherwise it would quietly pollute a durable list.
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        project: _project(),
        sessionId: 'mob-1',
        now: _now,
      );

      expect(draft.projectId, isNull);
      expect(draft.session.title, isNot(contains('Hermes Android')));
    });

    test('a quick chat is marked Quick in its title', () {
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        sessionId: 'mob-1',
        now: _now,
      );

      expect(draft.session.title.toLowerCase(), contains('quick'));
    });

    test('a quick chat carries its 72 hour archive deadline', () {
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        sessionId: 'mob-1',
        now: _now,
      );

      expect(kQuickChatRetention, const Duration(hours: 72));
      expect(draft.expiresAt, _now.add(kQuickChatRetention));
    });

    test('a project chat carries the project and never expires', () {
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.projectChat,
        project: _project(primaryPath: '/srv/projects/hermes-android'),
        sessionId: 'mob-2',
        now: _now,
      );

      expect(draft.isQuick, isFalse);
      expect(draft.projectId, 'p1');
      expect(draft.projectName, 'Hermes Android');
      expect(draft.projectWorkingDirectory, '/srv/projects/hermes-android');
      expect(draft.session.title, contains('Hermes Android'));
      expect(draft.session.isLocalDraft, isTrue);
      expect(draft.expiresAt, isNull);
    });

    test('a project chat without a project is a programming error, not a '
        'silent quick chat', () {
      expect(
        () => buildNewChatDraft(l10n: l10n, 
          mode: NewChatMode.projectChat,
          sessionId: 'mob-3',
          now: _now,
        ),
        throwsArgumentError,
      );
    });

    test('a project whose name is blank still produces a usable title', () {
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.projectChat,
        project: const HermesProject(id: 'p9', slug: 'p9', name: '   '),
        sessionId: 'mob-4',
        now: _now,
      );

      expect(draft.session.title.trim(), isNotEmpty);
      expect(draft.projectId, 'p9');
    });

    test('an empty session id is rejected rather than sent to the gateway', () {
      expect(
        () => buildNewChatDraft(l10n: l10n, 
          mode: NewChatMode.quickChat,
          sessionId: '   ',
          now: _now,
        ),
        throwsArgumentError,
      );
    });

    test('the drafted session is shaped like one the gateway returns', () {
      final draft = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        sessionId: 'mob-5',
        now: _now,
      );
      final session = draft.session;

      // `started_at` is seconds since epoch in the REST contract, so the Home
      // digest ranks a brand new chat correctly instead of at 1970.
      expect(
        session.startedAt,
        closeTo(_now.millisecondsSinceEpoch / 1000.0, 0.001),
      );
      expect(session.endedAt, isNull);
      expect(session.isActive, isTrue);
      expect(session.messageCount, 0);
      expect(session.preview, isEmpty);
      expect(session.source, 'mobile');
    });

    test('the caller may pin the model, and otherwise gets the default', () {
      final drafted = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        sessionId: 'mob-6',
        now: _now,
        model: 'claude-opus-5',
      );
      final fallback = buildNewChatDraft(l10n: l10n, 
        mode: NewChatMode.quickChat,
        sessionId: 'mob-7',
        now: _now,
      );

      expect(drafted.session.model, 'claude-opus-5');
      expect(fallback.session.model, isNotEmpty);
    });
  });
}
