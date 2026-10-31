import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/widgets/config_backup_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Widget wrap(Widget child) {
  return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

const ConfigImportResult _noopResult = ConfigImportResult(
  connectionsAdded: 0,
  connectionsUpdated: 0,
  connectionsRemoved: 0,
  preferencesApplied: 0,
  preferencesSkipped: 0,
);

ConfigBackupCard buildCard({
  Future<String> Function(String)? onExport,
  Future<String?> Function(String)? onDeliverExport,
  Future<String?> Function()? onPickBackupFile,
  Future<ConfigImportResult> Function(String, String, ConfigImportMode)?
  onImport,
}) {
  return ConfigBackupCard(
    onExport: onExport ?? (_) async => 'encrypted',
    onDeliverExport: onDeliverExport ?? (_) async => 'shared',
    onPickBackupFile: onPickBackupFile ?? () async => 'encrypted',
    onImport: onImport ?? (_, _, _) async => _noopResult,
  );
}

Future<void> completeExportSheet(
  WidgetTester tester, {
  required String passphrase,
  String? confirm,
}) async {
  await tester.tap(find.byKey(const Key('config_export_button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('export_passphrase_field')),
    passphrase,
  );
  await tester.enterText(
    find.byKey(const Key('export_passphrase_confirm_field')),
    confirm ?? passphrase,
  );
  await tester.tap(find.byKey(const Key('export_confirm_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('export flow', () {
    testWidgets('passes the confirmed passphrase to the exporter', (
      tester,
    ) async {
      String? seen;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onExport: (passphrase) async {
              seen = passphrase;
              return 'encrypted-blob';
            },
          ),
        ),
      );

      await completeExportSheet(tester, passphrase: 'correct horse');

      expect(seen, 'correct horse');
    });

    testWidgets('refuses to export when the confirmation does not match', (
      tester,
    ) async {
      var exported = false;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onExport: (_) async {
              exported = true;
              return 'blob';
            },
          ),
        ),
      );

      await completeExportSheet(
        tester,
        passphrase: 'correct horse',
        confirm: 'wrong horse',
      );

      expect(exported, isFalse);
      expect(find.text('The two passphrases do not match.'), findsOneWidget);
    });

    testWidgets('refuses a passphrase that is too short to protect keys', (
      tester,
    ) async {
      var exported = false;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onExport: (_) async {
              exported = true;
              return 'blob';
            },
          ),
        ),
      );

      await completeExportSheet(tester, passphrase: 'short');

      expect(exported, isFalse);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
    });

    testWidgets('hands the encrypted blob to the delivery callback', (
      tester,
    ) async {
      String? delivered;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onExport: (_) async => 'encrypted-blob',
            onDeliverExport: (contents) async {
              delivered = contents;
              return 'Saved to Downloads';
            },
          ),
        ),
      );

      await completeExportSheet(tester, passphrase: 'correct horse');

      expect(delivered, 'encrypted-blob');
      expect(find.text('Backup exported — Saved to Downloads'), findsOneWidget);
    });

    testWidgets('surfaces an export failure instead of failing silently', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          buildCard(
            onExport: (_) async =>
                throw const ConfigBackupException('Keystore unavailable.'),
          ),
        ),
      );

      await completeExportSheet(tester, passphrase: 'correct horse');

      expect(find.byKey(const Key('config_backup_error')), findsOneWidget);
      expect(find.text('Keystore unavailable.'), findsOneWidget);
    });
  });

  group('import flow', () {
    testWidgets('does nothing when the user cancels the file picker', (
      tester,
    ) async {
      var imported = false;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onPickBackupFile: () async => null,
            onImport: (_, _, _) async {
              imported = true;
              return _noopResult;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('config_import_button')));
      await tester.pumpAndSettle();

      expect(imported, isFalse);
      expect(find.byKey(const Key('import_passphrase_field')), findsNothing);
    });

    testWidgets('imports with the chosen passphrase and merge mode', (
      tester,
    ) async {
      String? seenContents;
      String? seenPassphrase;
      ConfigImportMode? seenMode;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onPickBackupFile: () async => 'file-contents',
            onImport: (contents, passphrase, mode) async {
              seenContents = contents;
              seenPassphrase = passphrase;
              seenMode = mode;
              return const ConfigImportResult(
                connectionsAdded: 2,
                connectionsUpdated: 0,
                connectionsRemoved: 0,
                preferencesApplied: 5,
                preferencesSkipped: 0,
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('config_import_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import_passphrase_field')),
        'correct horse',
      );
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      expect(seenContents, 'file-contents');
      expect(seenPassphrase, 'correct horse');
      expect(seenMode, ConfigImportMode.merge);
      expect(
        find.text('Connections: 2 added · 5 settings restored'),
        findsOneWidget,
      );
    });

    testWidgets('passes replace mode when the user selects it', (tester) async {
      ConfigImportMode? seenMode;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onImport: (_, _, mode) async {
              seenMode = mode;
              return _noopResult;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('config_import_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import_passphrase_field')),
        'pass',
      );
      await tester.tap(find.byKey(const Key('import_mode_replace')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      expect(seenMode, ConfigImportMode.replace);
    });

    testWidgets('shows the wrong-passphrase failure to the user', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          buildCard(
            onImport: (_, _, _) async => throw const ConfigBackupException(
              'Wrong passphrase, or this backup file has been altered.',
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('config_import_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import_passphrase_field')),
        'nope',
      );
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('config_backup_error')), findsOneWidget);
      expect(
        find.text('Wrong passphrase, or this backup file has been altered.'),
        findsOneWidget,
      );
    });

    testWidgets('refuses to import without a passphrase', (tester) async {
      var imported = false;
      await tester.pumpWidget(
        wrap(
          buildCard(
            onImport: (_, _, _) async {
              imported = true;
              return _noopResult;
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('config_import_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_confirm_button')));
      await tester.pumpAndSettle();

      expect(imported, isFalse);
      expect(
        find.text('Enter the passphrase for this backup.'),
        findsOneWidget,
      );
    });
  });
}
