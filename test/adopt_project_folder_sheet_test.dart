// The existing-folder adoption UI (issue #232).
//
// Enumeration is real: it rides the dashboard's `GET /api/fs/list` route. The
// sheet must list unregistered candidates, mark registered ones, adopt through
// the real contract, keep prior state on failure, and — on a connection that
// cannot list at all — say "not supported" rather than show an empty list.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/hermes_project.dart';
import 'package:hermes_android/core/services/project_folder_discovery.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/projects_root_resolver.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/adopt_project_folder_sheet.dart';
import 'package:hermes_android/core/widgets/projects_pane.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

HermesProject _project({
  required String id,
  required String name,
  String? primaryPath,
}) => HermesProject.fromJson({
  'id': id,
  'slug': name.toLowerCase(),
  'name': name,
  'primary_path': ?primaryPath,
  'folders': [
    if (primaryPath != null)
      {'path': primaryPath, 'is_primary': true, 'added_at': 1},
  ],
});

/// Discovery that answers from a fixed result, so the sheet can be driven
/// without an HTTP layer. The real `fs/list` wiring is covered in
/// test/project_folder_discovery_test.dart.
class _StubDiscovery extends ProjectFolderDiscovery {
  final ProjectFolderDiscoveryResult Function() build;
  final Completer<void>? gate;

  /// Registered sets the sheet passed in, so the real pane wiring can be
  /// checked without a gateway.
  final List<List<String>> scanned = [];
  int scans = 0;

  _StubDiscovery(this.build, {this.gate});

  @override
  Future<ProjectFolderDiscoveryResult> scan({
    required Iterable<HermesProject> registered,
  }) async {
    scans++;
    scanned.add([for (final project in registered) project.id]);
    final pending = gate;
    if (pending != null) await pending.future;
    return build();
  }
}

ProjectFolderDiscoveryResult _ready({
  String root = '/root/.hermes/projects',
  List<DiscoveredProjectFolder> folders = const [],
}) => ProjectFolderDiscoveryResult(
  status: ProjectFolderDiscoveryStatus.ready,
  root: root,
  rootSource: ProjectsRootSource.configured,
  folders: folders,
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required ProjectFolderDiscovery discovery,
  required ProjectFolderAdopter adopt,
  List<HermesProject> registered = const [],
}) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: Scaffold(
        body: AdoptProjectFolderSheet(
          discovery: discovery,
          registered: registered,
          adopt: adopt,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists unregistered candidates and marks registered folders', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final discovery = _StubDiscovery(
      () => _ready(
        folders: const [
          DiscoveredProjectFolder(
            name: 'already-known',
            path: '/root/.hermes/projects/already-known',
            registered: true,
            registeredProjectName: 'Already Known',
          ),
          DiscoveredProjectFolder(
            name: 'ledger',
            path: '/root/.hermes/projects/ledger',
          ),
        ],
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async =>
          fail('nothing was tapped'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.adopt_folder_description('/root/.hermes/projects')),
      findsOneWidget,
    );
    expect(find.text('ledger'), findsOneWidget);
    expect(find.text('/root/.hermes/projects/ledger'), findsOneWidget);
    expect(
      find.text(l10n.adopt_folder_registered('Already Known')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a candidate adopts it through the real contract', (
    tester,
  ) async {
    final adopted = <String, String>{};
    final discovery = _StubDiscovery(
      () => _ready(
        folders: const [
          DiscoveredProjectFolder(
            name: 'ledger',
            path: '/root/.hermes/projects/ledger',
          ),
        ],
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async {
        adopted[name] = path;
        return _project(id: 'srv-1', name: name, primaryPath: path);
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ledger'));
    await tester.pumpAndSettle();

    expect(adopted, {'ledger': '/root/.hermes/projects/ledger'});
  });

  testWidgets('a registered folder is not tappable', (tester) async {
    var adoptCalls = 0;
    final discovery = _StubDiscovery(
      () => _ready(
        folders: const [
          DiscoveredProjectFolder(
            name: 'already-known',
            path: '/root/.hermes/projects/already-known',
            registered: true,
            registeredProjectName: 'Already Known',
          ),
        ],
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async {
        adoptCalls++;
        return _project(id: 'srv-1', name: name, primaryPath: path);
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('already-known'));
    await tester.pumpAndSettle();

    expect(adoptCalls, 0);
  });

  testWidgets('a failing adoption shows the server error and keeps the sheet', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final error = JsonRpcError('projects.create', 'server said no');
    final discovery = _StubDiscovery(
      () => _ready(
        folders: const [
          DiscoveredProjectFolder(
            name: 'ledger',
            path: '/root/.hermes/projects/ledger',
          ),
        ],
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async =>
          throw error,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ledger'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adopt-folder-error')), findsOneWidget);
    expect(find.text(l10n.adopt_folder_error('$error')), findsOneWidget);
    // Still usable: the sheet stays open so the user can retry elsewhere.
    expect(find.text('ledger'), findsOneWidget);
  });

  testWidgets('a folderless destination is reported, never as success', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final discovery = _StubDiscovery(
      () => _ready(
        folders: const [
          DiscoveredProjectFolder(
            name: 'ledger',
            path: '/root/.hermes/projects/ledger',
          ),
        ],
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async =>
          throw ProjectFolderAdoptionException(
            _project(id: 'srv-1', name: name),
            path,
          ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ledger'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.adopt_folder_folderless('ledger')), findsOneWidget);
  });

  testWidgets('an unsupported connection says so and still allows a typed '
      'path', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final adopted = <String, String>{};
    final discovery = _StubDiscovery(
      () => const ProjectFolderDiscoveryResult(
        status: ProjectFolderDiscoveryStatus.unsupported,
        rootSource: ProjectsRootSource.unavailable,
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async {
        adopted[name] = path;
        return _project(id: 'srv-1', name: name, primaryPath: path);
      },
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adopt-folder-unsupported')), findsOneWidget);
    expect(find.text(l10n.adopt_folder_unsupported), findsOneWidget);
    expect(find.byKey(const Key('adopt-folder-none')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('adopt-folder-path')),
      '/root/.hermes/projects/ledger',
    );
    await tester.tap(find.byKey(const Key('adopt-folder-submit')));
    await tester.pumpAndSettle();

    // The folder name is the fallback Project name.
    expect(adopted, {'ledger': '/root/.hermes/projects/ledger'});
  });

  testWidgets('a failed listing is distinguished from unsupported', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final discovery = _StubDiscovery(
      () => const ProjectFolderDiscoveryResult(
        status: ProjectFolderDiscoveryStatus.failed,
        root: '/root/.hermes/projects',
        rootSource: ProjectsRootSource.configured,
        error: 'Permission denied',
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async =>
          fail('nothing was tapped'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('adopt-folder-failed')), findsOneWidget);
    expect(
      find.text(l10n.adopt_folder_failed('Permission denied')),
      findsOneWidget,
    );
  });

  testWidgets('a root with no adoptable folders says so explicitly', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final discovery = _StubDiscovery(
      () => _ready(
        folders: const [
          DiscoveredProjectFolder(
            name: 'already-known',
            path: '/root/.hermes/projects/already-known',
            registered: true,
            registeredProjectName: 'Already Known',
          ),
        ],
      ),
    );

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async =>
          fail('nothing was tapped'),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.adopt_folder_none), findsOneWidget);
  });

  testWidgets('a typed path must be absolute', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    var adoptCalls = 0;
    final discovery = _StubDiscovery(_ready);

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async {
        adoptCalls++;
        return _project(id: 'srv-1', name: name, primaryPath: path);
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adopt-folder-submit')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.projects_root_invalid_empty), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('adopt-folder-path')),
      'projects/ledger',
    );
    await tester.tap(find.byKey(const Key('adopt-folder-submit')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.projects_root_invalid_absolute), findsOneWidget);

    expect(adoptCalls, 0);
  });

  testWidgets('a typed Project name wins over the folder name', (tester) async {
    final adopted = <String, String>{};
    final discovery = _StubDiscovery(_ready);

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async {
        adopted[name] = path;
        return _project(id: 'srv-1', name: name, primaryPath: path);
      },
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('adopt-folder-path')),
      '/root/.hermes/projects/ledger',
    );
    await tester.enterText(
      find.byKey(const Key('adopt-folder-name')),
      'The Ledger',
    );
    await tester.tap(find.byKey(const Key('adopt-folder-submit')));
    await tester.pumpAndSettle();

    expect(adopted, {'The Ledger': '/root/.hermes/projects/ledger'});
  });

  testWidgets('a scan held from a disposed sheet never applies', (
    tester,
  ) async {
    final gate = Completer<void>();
    final discovery = _StubDiscovery(_ready, gate: gate);

    await _pumpSheet(
      tester,
      discovery: discovery,
      adopt: ({required String name, required String path}) async =>
          fail('nothing was tapped'),
    );
    await tester.pump();

    // Tear the sheet down while the scan is still in flight.
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();

    expect(discovery.scans, 1);
    expect(tester.takeException(), isNull);
  });

  group('pane affordance', () {
    testWidgets('an empty Projects list still offers adoption', (tester) async {
      // The reporter's exact situation in #232: no Projects in the app, real
      // folders already on the server.
      final repository = ProjectsRepository(
        client: ProjectsGatewayClient(
          (method, params) async => {
            'jsonrpc': '2.0',
            'id': 1,
            'result': const {'projects': [], 'active_id': null},
          },
        ),
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'gateway-a',
      );
      final discovery = _StubDiscovery(
        () => _ready(
          folders: const [
            DiscoveredProjectFolder(
              name: 'ledger',
              path: '/root/.hermes/projects/ledger',
            ),
          ],
        ),
      );

      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: HermesPaneVisibility(
            active: true,
            child: ProjectsPane(
              repository: repository,
              folderDiscovery: discovery,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.byKey(const Key('adopt-existing-folder')), findsOneWidget);

      await tester.tap(find.byKey(const Key('adopt-existing-folder')));
      await tester.pumpAndSettle();

      expect(find.byType(AdoptProjectFolderSheet), findsOneWidget);
      expect(find.text('ledger'), findsOneWidget);
    });

    testWidgets('adopting from the pane registers the folder and confirms it', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final created = <Map<String, dynamic>>[];
      // The gateway stays authoritative: the pane refreshes after adopting, so
      // the fake must really remember the registered Project.
      final registered = <Map<String, dynamic>>[];
      final repository = ProjectsRepository(
        client: ProjectsGatewayClient((method, params) async {
          switch (method) {
            case 'projects.list':
              return {
                'jsonrpc': '2.0',
                'id': 1,
                'result': {'projects': registered, 'active_id': null},
              };
            case 'projects.create':
              created.add(Map<String, dynamic>.from(params));
              final project = {
                'id': 'srv-1',
                'slug': 'ledger',
                'name': params['name'],
                'primary_path': params['primary_path'],
                'folders': [
                  {
                    'path': params['primary_path'],
                    'is_primary': true,
                    'added_at': 1,
                  },
                ],
              };
              registered.add(project);
              return {
                'jsonrpc': '2.0',
                'id': 1,
                'result': {'project': project},
              };
            default:
              return {'jsonrpc': '2.0', 'id': 1, 'result': const {}};
          }
        }),
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'gateway-adopt',
      );
      final discovery = _StubDiscovery(
        () => _ready(
          folders: const [
            DiscoveredProjectFolder(
              name: 'ledger',
              path: '/root/.hermes/projects/ledger',
            ),
          ],
        ),
      );

      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: HermesPaneVisibility(
            active: true,
            child: ProjectsPane(
              repository: repository,
              folderDiscovery: discovery,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('adopt-existing-folder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ledger'));
      await tester.pumpAndSettle();

      // Registered through the existing create contract, with the folder bound.
      expect(created.single['primary_path'], '/root/.hermes/projects/ledger');
      expect(
        find.text(
          l10n.adopt_folder_added('ledger', '/root/.hermes/projects/ledger'),
        ),
        findsOneWidget,
      );
      // The sheet closed and the Project is now in the list.
      expect(find.byType(AdoptProjectFolderSheet), findsNothing);
      expect(repository.current.projects.single.name, 'ledger');
    });

    testWidgets('a connection without discovery hides the affordance', (
      tester,
    ) async {
      final repository = ProjectsRepository(
        client: ProjectsGatewayClient(
          (method, params) async => {
            'jsonrpc': '2.0',
            'id': 1,
            'result': const {'projects': [], 'active_id': null},
          },
        ),
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'gateway-a',
      );

      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: HermesPaneVisibility(
            active: true,
            child: ProjectsPane(repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt-existing-folder')), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
