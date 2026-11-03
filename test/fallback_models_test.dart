import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/model_management_screen.dart';
import 'package:hermes_android/core/widgets/fallback_models.dart';
import 'package:http/http.dart' as http;

import 'support/fallback_model_fixture.dart';
import 'support/l10n_test_utils.dart';

Finder control(String id) => find.byKey(ValueKey(id));
Finder row(int i) => control('fallback-row-$i');
Finder picker(int i, int which) => find
    .descendant(
      of: row(i),
      matching: find.byType(DropdownButtonFormField<String>),
    )
    .at(which);
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, int i, int which, String value) async {
  await tap(tester, picker(i, which));
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester,
  FallbackFixture fixture, {
  bool screen = false,
}) async {
  await tester.pumpWidget(
    testAppWithL10n(
      screen
          ? ModelManagementScreen(
              connection: fallbackConnection.copyWith(
                gatewayProfile: fixture.profile,
              ),
              dashboardClient: fixture.client,
            )
          : Scaffold(
              body: SingleChildScrollView(
                child: FallbackModels(client: fixture.client),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
}

bool saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(control('fallback-save')).onPressed != null;

void main() {
  testWidgets(
    'initial empty: add is draft-only and complete selections must be saved explicitly',
    (tester) async {
      final fixture = FallbackFixture();
      addTearDown(fixture.client.close);
      await mount(tester, fixture);
      expect(find.text('No entries in this fallback list.'), findsOneWidget);
      expect(fixture.writes, isEmpty);
      await tap(tester, control('fallback-add'));
      expect(saveEnabled(tester), isFalse);
      await choose(tester, 0, 0, 'other');
      expect(saveEnabled(tester), isFalse);
      await choose(tester, 0, 1, 'other-2');
      expect(fixture.writes, isEmpty);
      await tap(tester, control('fallback-save'));
      expect(fixture.writes.single, {
        'config': {
          'fallback_providers': [
            {'provider': 'other', 'model': 'other-2'},
          ],
        },
        'profile': 'research & development',
      });
      expect(fixture.configReads, 2);
      expect(find.text('Fallback list saved and verified.'), findsOneWidget);
      for (final request in fixture.requests.where((r) => r.method == 'GET')) {
        expect(request.url.path, startsWith('/proxy/api/'));
        expect(
          request.url.queryParameters['profile'],
          'research & development',
        );
        if (request.url.path.endsWith('/config')) {
          expect(request.url.queryParameters['include_defaults'], 'false');
        }
      }
    },
  );

  testWidgets(
    'populated: change model and provider, add, reorder both ways and delete final row',
    (tester) async {
      final fixture = FallbackFixture()
        ..config = {
          'fallback_providers': [
            {'provider': 'openai', 'model': 'old'},
          ],
        };
      addTearDown(fixture.client.close);
      await mount(tester, fixture);
      await choose(tester, 0, 1, 'new');
      await tap(tester, control('fallback-save'));
      expect(
        (fixture.config['fallback_providers'] as List).single['model'],
        'new',
      );
      await choose(tester, 0, 0, 'other');
      expect(saveEnabled(tester), isFalse);
      await choose(tester, 0, 1, 'other-1');
      await tap(tester, control('fallback-add'));
      await choose(tester, 1, 0, 'openai');
      await choose(tester, 1, 1, 'old');
      await tap(tester, control('fallback-up-1'));
      expect(
        find.descendant(of: row(0), matching: find.text('openai')),
        findsWidgets,
      );
      await tap(tester, control('fallback-down-0'));
      await tap(tester, control('fallback-save'));
      expect(fixture.config['fallback_providers'], [
        {'provider': 'other', 'model': 'other-1'},
        {'provider': 'openai', 'model': 'old'},
      ]);
      await tap(tester, control('fallback-delete-0'));
      await tap(tester, control('fallback-save'));
      expect(fixture.config['fallback_providers'], [
        {'provider': 'openai', 'model': 'old'},
      ]);
      await tap(tester, control('fallback-delete-0'));
      await tap(tester, control('fallback-save'));
      expect(fixture.config['fallback_providers'], isEmpty);
      expect(find.text('Fallback list saved and verified.'), findsOneWidget);
      expect(fixture.modelWrites, isEmpty);
    },
  );

  testWidgets(
    'unknown pair, custom/secret metadata and legacy are preserved, never displayed',
    (tester) async {
      final metadata = <String, dynamic>{
        'provider': 'openai',
        'model': 'private-model',
        'base_url': 'https://private.invalid/v1/',
        'api_key': r'${RAW_SECRET}',
        'key_env': 'FALLBACK_SECRET',
        'api_key_env': 'ALIAS_SECRET',
        'future': {
          'raw': [null, true, 3, 'preserve me'],
        },
      };
      final unknown = {
        'provider': 'retired-provider',
        'model': 'retired-model',
      };
      final legacy = {
        'provider': 'legacy',
        'model': 'legacy-model',
        'api_key': 'legacy-secret',
      };
      final fixture = FallbackFixture()
        ..config = {
          'fallback_providers': [
            metadata,
            unknown,
            {'provider': 'openai', 'model': 'unlisted-model'},
          ],
          'fallback_model': legacy,
          'unrelated': {'api_key': 'unrelated-secret'},
        };
      addTearDown(fixture.client.close);
      await mount(tester, fixture);
      expect(
        find.descendant(
          of: row(0),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
        findsNothing,
      );
      expect(find.text('retired-provider / retired-model'), findsOneWidget);
      expect(
        find.descendant(of: row(2), matching: find.text('unlisted-model')),
        findsWidgets,
      );
      for (final secret in [
        'private.invalid',
        r'${RAW_SECRET}',
        'FALLBACK_SECRET',
        'ALIAS_SECRET',
        'legacy-secret',
        'unrelated-secret',
      ]) {
        expect(find.textContaining(secret), findsNothing);
      }
      await tap(tester, control('fallback-up-1'));
      await tap(tester, control('fallback-save'));
      expect(fixture.config['fallback_providers'], [
        unknown,
        metadata,
        {'provider': 'openai', 'model': 'unlisted-model'},
      ]);
      expect(fixture.writes.single['config'], {
        'fallback_providers': fixture.config['fallback_providers'],
      });
      expect(fixture.config['fallback_model'], legacy);
      for (var i = 0; i < 3; i++) {
        await tap(tester, control('fallback-delete-0'));
      }
      await tap(tester, control('fallback-save'));
      expect(fixture.config['fallback_providers'], isEmpty);
      expect(fixture.config['fallback_model'], legacy);
      expect(find.text('Legacy fallbacks (read-only)'), findsOneWidget);
      expect(find.text('legacy / legacy-model'), findsOneWidget);
      expect(
        find.textContaining('even when the list above is empty'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [
    'rejected',
    'ignored',
    'metadata changed',
    'legacy changed',
  ]) {
    testWidgets(
      '$mode fails verification without losing draft or announcing success',
      (tester) async {
        final fixture = FallbackFixture()
          ..config = {
            'fallback_providers': [
              {'provider': 'openai', 'model': 'old'},
              {
                'provider': 'custom',
                'model': 'secret-model',
                'api_key': r'${KEY}',
              },
            ],
            'fallback_model': {'provider': 'legacy', 'model': 'legacy-model'},
          };
        if (mode == 'rejected') fixture.accepted = false;
        if (mode == 'ignored') fixture.persist = false;
        if (mode == 'metadata changed') {
          fixture.corrupt = (c) =>
              (c['fallback_providers'] as List)[1]['api_key'] = 'redacted';
        }
        if (mode == 'legacy changed') {
          fixture.corrupt = (c) => c['fallback_model'] = [];
        }
        addTearDown(fixture.client.close);
        await mount(tester, fixture);
        await choose(tester, 0, 0, 'other');
        await choose(tester, 0, 1, 'other-2');
        await tap(tester, control('fallback-save'));
        expect(find.text('Fallback list saved and verified.'), findsNothing);
        expect(find.textContaining('Your draft is preserved.'), findsOneWidget);
        expect(
          find.descendant(of: row(0), matching: find.text('other-2')),
          findsWidgets,
        );
        expect(saveEnabled(tester), isTrue);
        expect(fixture.configReads, mode == 'rejected' ? 1 : 2);
        expect(find.textContaining(r'${KEY}'), findsNothing);
      },
    );
  }

  for (final mode in ['malformed primary', 'malformed legacy', 'old host']) {
    testWidgets(
      '$mode fails closed independently of main and auxiliary, retry recovers',
      (tester) async {
        final fixture = FallbackFixture();
        if (mode == 'malformed primary') {
          fixture.config['fallback_providers'] = [
            {'provider': 'p'},
          ];
        }
        if (mode == 'malformed legacy') {
          fixture.config['fallback_model'] = [false];
        }
        if (mode == 'old host') fixture.configStatus = 404;
        addTearDown(fixture.client.close);
        await mount(tester, fixture, screen: true);
        expect(control('fallback-save'), findsNothing);
        expect(find.text('Set profile default'), findsOneWidget);
        expect(find.byKey(const ValueKey('vision')), findsOneWidget);
        expect(find.textContaining('never-show-server-secret'), findsNothing);
        fixture.configStatus = 200;
        fixture.config = {'fallback_providers': []};
        await tap(tester, control('fallback-retry'));
        expect(saveEnabled(tester), isTrue);
        expect(fixture.writes, isEmpty);
      },
    );
  }

  testWidgets(
    'discovery failure and retry keep unknown pairs and draft additions',
    (tester) async {
      final fixture = FallbackFixture()
        ..failDiscovery = true
        ..config = {
          'fallback_providers': [
            {'provider': 'unknown', 'model': 'unlisted'},
          ],
        };
      addTearDown(fixture.client.close);
      await mount(tester, fixture);
      expect(find.text('unknown / unlisted'), findsOneWidget);
      await tap(tester, control('fallback-add'));
      expect(saveEnabled(tester), isFalse);
      fixture.failDiscovery = false;
      await tap(tester, control('fallback-discovery-retry'));
      expect(row(1), findsOneWidget);
      await choose(tester, 1, 0, 'other');
      await choose(tester, 1, 1, 'other-1');
      await tap(tester, control('fallback-save'));
      expect(fixture.config['fallback_providers'], [
        {'provider': 'unknown', 'model': 'unlisted'},
        {'provider': 'other', 'model': 'other-1'},
      ]);
      expect(find.textContaining('never-show-server-secret'), findsNothing);
    },
  );

  for (final stage in ['initial', 'write', 'readback']) {
    for (final dispose in [false, true]) {
      for (final failure in [false, true]) {
        testWidgets(
          'held $stage ${failure ? 'failure' : 'success'} fenced on ${dispose ? 'dispose' : 'profile/client replacement'}',
          (tester) async {
            final old = FallbackFixture();
            final gate = Completer<http.Response>();
            if (stage == 'initial') old.heldInitial = gate;
            if (stage == 'write') old.heldWrite = gate;
            if (stage == 'readback') old.heldReadback = gate;
            addTearDown(old.client.close);
            final replacement = FallbackFixture(profile: 'different-profile')
              ..config = {
                'fallback_providers': [
                  {'provider': 'other', 'model': 'other-1'},
                ],
              };
            addTearDown(replacement.client.close);
            // Keep the same screen State across connection/client replacement.
            await tester.pumpWidget(
              testAppWithL10n(
                ModelManagementScreen(
                  connection: fallbackConnection,
                  dashboardClient: old.client,
                ),
              ),
            );
            for (var i = 0; i < 6; i++) {
              await tester.pump();
            }
            if (stage != 'initial') {
              await reveal(tester, control('fallback-save'));
              await tester.tap(control('fallback-save'));
              for (var i = 0; i < 6; i++) {
                await tester.pump();
              }
            }
            final reads = old.configReads;
            await tester.pumpWidget(
              dispose
                  ? const SizedBox()
                  : testAppWithL10n(
                      ModelManagementScreen(
                        connection: fallbackConnection.copyWith(
                          gatewayProfile: 'different-profile',
                        ),
                        dashboardClient: replacement.client,
                      ),
                    ),
            );
            await tester.pumpAndSettle();
            if (!dispose) {
              expect(find.textContaining('other-1'), findsWidgets);
              expect(saveEnabled(tester), isTrue);
            }
            if (failure) {
              gate.completeError(Exception('never-show-stale-secret'));
            } else {
              gate.complete(
                stage == 'write'
                    ? old.response({'ok': true})
                    : old.response({'fallback_providers': []}),
              );
            }
            await tester.pumpAndSettle();
            expect(old.configReads, reads);
            expect(replacement.writes, isEmpty);
            expect(
              find.text('Fallback list saved and verified.'),
              findsNothing,
            );
            expect(
              find.textContaining('Your draft is preserved.'),
              findsNothing,
            );
            expect(
              find.textContaining('never-show-stale-secret'),
              findsNothing,
            );
            if (!dispose) expect(saveEnabled(tester), isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final stage in ['initial', 'write', 'readback']) {
    testWidgets(
      'connection replacement fences held $stage even with the same injected client',
      (tester) async {
        final fixture = FallbackFixture();
        final gate = Completer<http.Response>();
        if (stage == 'initial') fixture.heldInitial = gate;
        if (stage == 'write') fixture.heldWrite = gate;
        if (stage == 'readback') fixture.heldReadback = gate;
        addTearDown(fixture.client.close);
        await tester.pumpWidget(
          testAppWithL10n(
            ModelManagementScreen(
              connection: fallbackConnection,
              dashboardClient: fixture.client,
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        if (stage != 'initial') {
          await reveal(tester, control('fallback-save'));
          await tester.tap(control('fallback-save'));
          for (var i = 0; i < 6; i++) {
            await tester.pump();
          }
        }
        fixture.heldInitial = null;
        fixture.heldReadback = null;
        fixture.config = {
          'fallback_providers': [
            {'provider': 'other', 'model': 'other-2'},
          ],
        };
        await tester.pumpWidget(
          testAppWithL10n(
            ModelManagementScreen(
              connection: fallbackConnection.copyWith(label: 'Replacement'),
              dashboardClient: fixture.client,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: row(0), matching: find.text('other-2')),
          findsWidgets,
        );
        final reads = fixture.configReads;
        gate.complete(
          stage == 'write'
              ? fixture.response({'ok': true})
              : fixture.response({'fallback_providers': []}),
        );
        await tester.pumpAndSettle();
        expect(fixture.configReads, reads);
        expect(
          find.descendant(of: row(0), matching: find.text('other-2')),
          findsWidgets,
        );
        expect(find.text('Fallback list saved and verified.'), findsNothing);
        expect(saveEnabled(tester), isTrue);
      },
    );
  }

  for (final stage in ['write', 'readback']) {
    testWidgets('late old $stage cannot release replacement screen save lock', (
      tester,
    ) async {
      final old = FallbackFixture();
      final oldGate = Completer<http.Response>();
      if (stage == 'write') old.heldWrite = oldGate;
      if (stage == 'readback') old.heldReadback = oldGate;
      final fresh = FallbackFixture(profile: 'new-profile')
        ..heldWrite = Completer<http.Response>();
      addTearDown(old.client.close);
      addTearDown(fresh.client.close);
      await mount(tester, old, screen: true);
      await reveal(tester, control('fallback-save'));
      await tester.tap(control('fallback-save'));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      await tester.pumpWidget(
        testAppWithL10n(
          ModelManagementScreen(
            connection: fallbackConnection.copyWith(
              gatewayProfile: 'new-profile',
            ),
            dashboardClient: fresh.client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, control('fallback-save'));
      await tester.tap(control('fallback-save'));
      await tester.pump();
      oldGate.complete(
        old.response(
          stage == 'write' ? {'ok': true} : {'fallback_providers': []},
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(saveEnabled(tester), isFalse);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Set profile default'),
            )
            .onPressed,
        isNull,
      );
      fresh.heldWrite!.complete(fresh.response({'ok': true}));
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      expect(find.text('Fallback list saved and verified.'), findsOneWidget);
    });
  }

  testWidgets('main status changes do not remount and lose fallback draft', (
    tester,
  ) async {
    final fixture = FallbackFixture();
    addTearDown(fixture.client.close);
    await mount(tester, fixture, screen: true);
    await tap(tester, control('fallback-add'));
    await choose(tester, 0, 0, 'other');
    await tap(tester, find.widgetWithText(FilledButton, 'Set profile default'));
    expect(
      find.descendant(of: row(0), matching: find.text('other')),
      findsWidgets,
    );
    expect(saveEnabled(tester), isFalse);
    expect(fixture.modelWrites, hasLength(1));
    expect(fixture.writes, isEmpty);
  });

  testWidgets(
    'fallback stays independently usable while main loading is held',
    (tester) async {
      final fixture = FallbackFixture()
        ..heldMainInfo = Completer<http.Response>();
      addTearDown(fixture.client.close);
      await tester.pumpWidget(
        testAppWithL10n(
          ModelManagementScreen(
            connection: fallbackConnection,
            dashboardClient: fixture.client,
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(saveEnabled(tester), isTrue);
      await tester.ensureVisible(control('fallback-save'));
      await tester.pump();
      await tester.tap(control('fallback-save'));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(find.text('Fallback list saved and verified.'), findsOneWidget);
      expect(fixture.writes, hasLength(1));
      fixture.heldMainInfo!.complete(
        fixture.response({'provider': 'openai', 'model': 'old'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fallback list saved and verified.'), findsOneWidget);
      expect(find.text('Set profile default'), findsOneWidget);
    },
  );

  testWidgets(
    'fallback write and readback lock main, auxiliary, refresh and all fallback edits',
    (tester) async {
      final fixture = FallbackFixture()
        ..heldWrite = Completer<http.Response>()
        ..heldReadback = Completer<http.Response>();
      addTearDown(fixture.client.close);
      await mount(tester, fixture, screen: true);
      await reveal(tester, control('fallback-save'));
      await tester.tap(control('fallback-save'));
      await tester.pump();
      void assertLocked() {
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Set profile default'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.refresh),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
              .onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(control('fallback-add')).onPressed,
          isNull,
        );
        expect(saveEnabled(tester), isFalse);
      }

      assertLocked();
      fixture.heldWrite!.complete(fixture.response({'ok': true}));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      assertLocked();
      expect(find.text('Fallback list saved and verified.'), findsNothing);
      fixture.heldReadback!.complete(fixture.response(fixture.config));
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Set profile default'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final scope in ['main', 'auxiliary']) {
    testWidgets(
      '$scope save locks fallback editing/retry and refresh until complete',
      (tester) async {
        final fixture = FallbackFixture()
          ..heldModelWrite = Completer<http.Response>();
        addTearDown(fixture.client.close);
        await mount(tester, fixture, screen: true);
        final target = scope == 'main'
            ? find.widgetWithText(FilledButton, 'Set profile default')
            : find.widgetWithText(FilledButton, 'Save');
        await reveal(tester, target);
        await tester.tap(target);
        await tester.pump();
        expect(saveEnabled(tester), isFalse);
        expect(
          tester.widget<OutlinedButton>(control('fallback-add')).onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.refresh),
              )
              .onPressed,
          isNull,
        );
        fixture.heldModelWrite!.complete(fixture.response({'ok': false}));
        await tester.pumpAndSettle();
        expect(saveEnabled(tester), isTrue);
        expect(fixture.writes, isEmpty);
      },
    );
  }

  testWidgets(
    'scrolling retains incomplete draft and refresh reloads every section',
    (tester) async {
      final fixture = FallbackFixture();
      addTearDown(fixture.client.close);
      await mount(tester, fixture, screen: true);
      await tap(tester, control('fallback-add'));
      await choose(tester, 0, 0, 'other');
      await reveal(tester, find.byKey(const ValueKey('vision')));
      await reveal(tester, find.text('Set profile default'));
      expect(row(0), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      final reads = fixture.configReads;
      final auxReads = fixture.requests
          .where((r) => r.url.path.endsWith('/auxiliary'))
          .length;
      await tap(tester, find.widgetWithIcon(IconButton, Icons.refresh));
      expect(fixture.configReads, reads + 1);
      expect(
        fixture.requests.where((r) => r.url.path.endsWith('/auxiliary')),
        hasLength(auxReads + 1),
      );
      expect(row(0), findsNothing);
    },
  );

  testWidgets(
    '320px, text scale 2 and keyboard inset have no layout overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = FallbackFixture()
        ..config = {
          'fallback_providers': [
            {
              'provider': 'openai',
              'model': 'unlisted-model-with-a-very-long-name',
            },
          ],
        };
      addTearDown(fixture.client.close);
      await tester.pumpWidget(
        testAppWithL10n(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: ModelManagementScreen(
                connection: fallbackConnection,
                dashboardClient: fixture.client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, control('fallback-save'));
      await tap(tester, control('fallback-add'));
      await choose(tester, 1, 0, 'other');
      await choose(tester, 1, 1, 'other-1');
      expect(tester.takeException(), isNull);
      expect(fixture.writes, isEmpty);
    },
  );
}
