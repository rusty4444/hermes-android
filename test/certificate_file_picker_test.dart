import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the connection dialog asks `file_picker` for.
class _FakeFilePicker extends FilePicker {
  final files = <PlatformFile>[];
  Completer<FilePickerResult?>? held;
  final List<
    ({FileType type, List<String>? allowedExtensions, bool allowMultiple})
  >
  calls =
      <
        ({FileType type, List<String>? allowedExtensions, bool allowMultiple})
      >[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('allowCompression is deprecated and has no effect.')
    bool? allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool? withData = false,
    bool? withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls.add((
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    ));
    if (held != null) return held!.future;
    if (files.isEmpty) return null;
    final picked = List<PlatformFile>.of(files);
    files.clear();
    return FilePickerResult(picked);
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.support);
  final Directory support;
  @override
  Future<String?> getApplicationSupportPath() async => support.path;
}

class _HeldFile extends Fake implements File {
  final entered = Completer<void>();
  final release = Completer<Uint8List>();

  void _enter() {
    if (!entered.isCompleted) entered.complete();
  }

  @override
  Future<Uint8List> readAsBytes() async {
    _enter();
    return release.future;
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    _enter();
    yield await release.future;
  }
}

Future<_FakeFilePicker> _openClientCertificateSection(
  WidgetTester tester,
) async {
  final picker = _FakeFilePicker();
  FilePicker.platform = picker;
  addTearDown(() => FilePicker.platform = _FakeFilePicker());

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Add Connection'));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Host',
    ),
    'https://gateway.example',
  );
  await tester.pumpAndSettle();

  final scrollable = find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      )
      .first;
  final toggle = find.byKey(const Key('connection_client_certificate_toggle'));
  await tester.scrollUntilVisible(toggle, 200, scrollable: scrollable);
  await tester.tap(toggle);
  await tester.pumpAndSettle();

  // The dialog offers one picker for every certificate format — PKCS#12,
  // a lone PEM, or the certificate and key as separate files.
  expect(
    find.byKey(const Key('connection_client_certificate_pick')),
    findsOneWidget,
  );
  expect(
    find.byKey(const Key('connection_client_certificate_pick_p12')),
    findsNothing,
  );
  expect(
    find.byKey(const Key('connection_client_certificate_pick_cert_pem')),
    findsNothing,
  );
  expect(
    find.byKey(const Key('connection_client_certificate_pick_key_pem')),
    findsNothing,
  );
  // The password field must not appear until a chosen file actually asks for
  // one: showing it up front implied a password was required before picking.
  expect(
    find.byKey(const Key('connection_client_certificate_password')),
    findsNothing,
  );
  return picker;
}

Future<void> _tapPickerButton(WidgetTester tester) async {
  final button = find.byKey(const Key('connection_client_certificate_pick'));
  final scrollable = find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(button, 200, scrollable: scrollable);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Let real filesystem work and the password debounce complete between frames.
Future<void> _waitForImport(
  WidgetTester tester,
  bool Function() settled,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    try {
      if (settled()) return;
    } on PathNotFoundException {
      // A collector can remove a directory during a recursive listing. Retry
      // the observation; the terminal assertion still requires no files.
    }
  }
  fail('Certificate import did not reach its expected terminal state.');
}

void main() {
  Directory isolatedSupport() {
    final support = Directory.systemTemp.createTempSync('picker-review-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      if (support.existsSync()) support.deleteSync(recursive: true);
    });
    return support;
  }

  PlatformFile document(String name, List<int> bytes, {int? size}) =>
      PlatformFile(
        name: name,
        size: size ?? bytes.length,
        bytes: Uint8List.fromList(bytes),
      );

  Future<void> invokePicker(WidgetTester tester) async {
    final dynamic callback = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('connection_client_certificate_pick')),
        )
        .onPressed;
    await tester.runAsync(() async => await callback());
    await tester.pumpAndSettle();
  }

  List<int> combined() => [
    ...File('test/fixtures/mtls-client-cert.pem').readAsBytesSync(),
    10,
    ...File('test/fixtures/mtls-client-key.pem').readAsBytesSync(),
  ];

  testWidgets('picker read failure is sanitized and remains retryable', (
    tester,
  ) async {
    final support = isolatedSupport();
    final picker = await _openClientCertificateSection(tester);
    picker.files.add(
      PlatformFile(
        name: 'missing.pem',
        size: 0,
        path: '${support.path}/missing.pem',
      ),
    );
    await invokePicker(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('That certificate could not be loaded.'), findsOneWidget);
    expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
    picker.files.add(document('valid.pem', combined()));
    await invokePicker(tester);
    expect(find.textContaining('Loaded: valid.pem'), findsOneWidget);
    await tester.runAsync(() async => tester.tap(find.text('Cancel')));
    await _waitForImport(
      tester,
      () => support.listSync(recursive: true).whereType<File>().isEmpty,
    );
  });

  for (final cachedPath in [false, true]) {
    testWidgets(
      'actual oversized certificate is rejected with unknown size path=$cachedPath',
      (tester) async {
        final support = isolatedSupport();
        final picker = await _openClientCertificateSection(tester);
        final bytes = [...combined(), ...List<int>.filled(1024 * 1024, 32)];
        final source = File('${support.path}/oversized.pem');
        if (cachedPath) source.writeAsBytesSync(bytes);
        picker.files.add(
          cachedPath
              ? PlatformFile(name: 'large.pem', size: 0, path: source.path)
              : document('large.pem', bytes, size: 0),
        );
        await invokePicker(tester);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Loaded:'), findsNothing);
        expect(
          find.text('That certificate could not be loaded.'),
          findsOneWidget,
        );
        expect(
          support
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path != source.path),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {});
      },
    );
  }

  testWidgets('late picker result after disposal never imports or throws', (
    tester,
  ) async {
    final support = isolatedSupport();
    final picker = await _openClientCertificateSection(tester);
    late Future<void> picking;
    await tester.runAsync(() async {
      picker.held = Completer<FilePickerResult?>();
      final dynamic callback = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('connection_client_certificate_pick')),
          )
          .onPressed;
      picking = callback() as Future<void>;
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      picker.held!.complete(
        FilePickerResult([document('late.pem', combined())]),
      );
      await picking;
    });
    expect(tester.takeException(), isNull);
    expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  testWidgets('picker owns selection before waiting for the platform', (
    tester,
  ) async {
    isolatedSupport();
    final picker = await _openClientCertificateSection(tester);
    late Future<void> picking;
    await tester.runAsync(() async {
      picker.held = Completer<FilePickerResult?>();
      final dynamic callback = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('connection_client_certificate_pick')),
          )
          .onPressed;
      picking = callback() as Future<void>;
    });
    await tester.pump();
    // Release even if an assertion fails: do not poison following tests.
    try {
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('connection_client_certificate_toggle')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('connection_client_certificate_pick')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
    } finally {
      await tester.runAsync(() async {
        picker.held!.complete(null);
        await picking;
      });
    }
    await tester.pumpAndSettle();
  });

  testWidgets(
    'disposal during a held file read fences import and error delivery',
    (tester) async {
      final support = isolatedSupport();
      final picker = await _openClientCertificateSection(tester);
      final bytes = Uint8List.fromList(combined());
      picker.files.add(
        PlatformFile(
          name: 'held.pem',
          size: bytes.length,
          path: 'held-read.pem',
        ),
      );
      late _HeldFile held;
      late Future<void> picking;
      await tester.runAsync(() async {
        held = _HeldFile();
        final dynamic callback = tester
            .widget<OutlinedButton>(
              find.byKey(const Key('connection_client_certificate_pick')),
            )
            .onPressed;
        picking = IOOverrides.runZoned(
          () => callback() as Future<void>,
          createFile: (path) {
            expect(path, 'held-read.pem');
            return held;
          },
        );
        await held.entered.future;
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        held.release.complete(bytes);
        await picking;
      });
      expect(tester.takeException(), isNull);
      expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  testWidgets('new unprotected half retires an earlier password retry', (
    tester,
  ) async {
    isolatedSupport();
    final picker = await _openClientCertificateSection(tester);
    picker.files.add(
      document(
        'protected.p12',
        File('test/fixtures/client-test.p12').readAsBytesSync(),
      ),
    );
    await invokePicker(tester);
    expect(
      find.byKey(const Key('connection_client_certificate_password')),
      findsOneWidget,
    );
    // A scheduled password retry belongs to the old selection too.
    await tester.enterText(
      find.byKey(const Key('connection_client_certificate_password')),
      'test-password',
    );
    picker.files.add(
      document(
        'new-cert.pem',
        File('test/fixtures/mtls-client-cert.pem').readAsBytesSync(),
      ),
    );
    await invokePicker(tester);
    expect(
      find.byKey(const Key('connection_client_certificate_password')),
      findsNothing,
    );
    expect(find.text('new-cert.pem'), findsOneWidget);
  });

  testWidgets('protected PKCS12 retries without repicking', (tester) async {
    final support = isolatedSupport();
    final picker = await _openClientCertificateSection(tester);
    picker.files.add(
      document(
        'protected.p12',
        File('test/fixtures/client-test.p12').readAsBytesSync(),
      ),
    );
    await invokePicker(tester);
    final password = find.byKey(
      const Key('connection_client_certificate_password'),
    );
    expect(password, findsOneWidget);
    await tester.enterText(password, 'wrong');
    await _waitForImport(
      tester,
      () => find.textContaining('password is incorrect').evaluate().isNotEmpty,
    );
    expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
    await tester.enterText(password, 'test-password');
    await _waitForImport(tester, () => password.evaluate().isEmpty);
    expect(find.textContaining('Loaded: protected.p12'), findsOneWidget);
    expect(picker.calls, hasLength(1));
    await tester.runAsync(() async => tester.tap(find.text('Cancel')));
    await _waitForImport(
      tester,
      () => support.listSync(recursive: true).whereType<File>().isEmpty,
    );
  });

  for (final keyFormat in ['traditional', 'whitespace']) {
    for (final mode in ['combined', 'certificate-first', 'key-first']) {
      testWidgets(
        'encrypted PEM $keyFormat $mode prompts and retries without repicking',
        (tester) async {
          final support = Directory.systemTemp.createTempSync('pem-editor-');
          final oldPaths = PathProviderPlatform.instance;
          PathProviderPlatform.instance = _Paths(support);
          addTearDown(() {
            PathProviderPlatform.instance = oldPaths;
            if (support.existsSync()) support.deleteSync(recursive: true);
          });
          final picker = await _openClientCertificateSection(tester);
          final cert = File(
            'test/fixtures/mtls-client-cert.pem',
          ).readAsBytesSync();
          final key = File(
            'test/fixtures/mtls-client-key-$keyFormat.pem',
          ).readAsBytesSync();
          PlatformFile picked(String name, List<int> bytes) => PlatformFile(
            name: name,
            size: bytes.length,
            bytes: Uint8List.fromList(bytes),
          );
          if (mode == 'combined') {
            picker.files.add(picked('combined.pem', [...cert, 10, ...key]));
          } else {
            picker.files.addAll(
              mode == 'certificate-first'
                  ? [picked('cert.pem', cert), picked('key.pem', key)]
                  : [picked('key.pem', key), picked('cert.pem', cert)],
            );
          }
          await _tapPickerButton(tester);
          final password = find.byKey(
            const Key('connection_client_certificate_password'),
          );
          expect(password, findsOneWidget);
          expect(picker.calls, hasLength(1));
          expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
          await tester.runAsync(() async {
            await tester.enterText(password, 'wrong');
          });
          await _waitForImport(
            tester,
            () => find
                .textContaining('password is incorrect')
                .evaluate()
                .isNotEmpty,
          );
          expect(password, findsOneWidget);
          await tester.runAsync(() async {
            await tester.enterText(
              password,
              keyFormat == 'traditional'
                  ? ' exact fixture password\t '
                  : '  key password \t',
            );
          });
          await _waitForImport(tester, () => password.evaluate().isEmpty);
          expect(password, findsNothing);
          expect(picker.calls, hasLength(1));
          final stagedFiles = support
              .listSync(recursive: true)
              .whereType<File>()
              .toList();
          expect(stagedFiles, hasLength(2));
          final stagedDirectories = {
            for (final file in stagedFiles) file.parent.path,
          };
          expect(stagedDirectories, hasLength(1));
          final stagedDirectory = Directory(stagedDirectories.single);
          await tester.runAsync(() async {
            await tester.tap(find.text('Cancel'));
          });
          await _waitForImport(
            tester,
            // Recursive listing races the real asynchronous directory deletion:
            // a child can disappear after listSync has enumerated its parent.
            // Wait for this exact owned identity to be gone before traversing.
            () => !stagedDirectory.existsSync(),
          );
          await tester.pumpAndSettle();
          expect(stagedFiles.every((file) => !file.existsSync()), isTrue);
          expect(support.listSync(recursive: true).whereType<File>(), isEmpty);
        },
      );
    }
  }

  testWidgets(
    'Android picks certificate files unfiltered so PEM files are selectable',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final picker = await _openClientCertificateSection(tester);
      await _tapPickerButton(tester);

      expect(picker.calls, hasLength(1));
      expect(picker.calls.single.type, FileType.any);
      expect(picker.calls.single.allowedExtensions, isNull);
      expect(picker.calls.single.allowMultiple, isTrue);

      // Reset before the test body ends: flutter_test verifies foundation
      // debug variables are unset after every test.
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('desktop keeps the extension filter for certificate files', (
    tester,
  ) async {
    // flutter_test defaults to an Android target, so pin the desktop
    // platform explicitly for this case.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final picker = await _openClientCertificateSection(tester);
    await _tapPickerButton(tester);

    expect(picker.calls, hasLength(1));
    expect(picker.calls.single.type, FileType.custom);
    expect(picker.calls.single.allowedExtensions, [
      'pem',
      'crt',
      'cer',
      'key',
      'p12',
      'pfx',
    ]);
    expect(picker.calls.single.allowMultiple, isTrue);

    // Reset before the test body ends: flutter_test verifies foundation
    // debug variables are unset after every test.
    debugDefaultTargetPlatformOverride = null;
  });
}
