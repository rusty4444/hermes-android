import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/project_folder_provisioner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A dashboard stand-in: serves the managed-files routes the provisioner
/// uses and records every request so tests can assert what was created.
class _FakeDashboard {
  final List<String> _mkdirs = [];
  List<String> get mkdirs => _mkdirs;

  /// Paths that already exist on the host (GET /api/files answers 200).
  final Set<String> existing;

  /// Paths whose mkdir is refused with 403.
  final Set<String> forbiddenMkdirs;

  /// Directory paths where marker WRITES are refused (read-only mount).
  final Set<String> readOnlyDirs;

  /// When set, every fs/read-text returns this content instead of what
  /// was written — simulates a host whose read cannot be trusted to echo
  /// the claim back.
  String? corruptReadText;

  /// Marker files written via fs/write-text, keyed by path.
  final Map<String, String> writtenFiles = {};

  /// Locked-root value for GET /api/files (null = unlocked, browses home).
  final String? lockedRoot;

  /// The browsed-home path value for GET /api/files.
  final String homePath = '/home/tester';

  /// Hook fired AFTER the GET /api/files probe answers 404 for a path and
  /// BEFORE the mkdir for that path is handled — the exact probe→mkdir
  /// window a concurrent creator races through. Tests use it to plant a
  /// directory (or a marker) mid-race.
  void Function(String probedPath)? onProbeMissing;

  /// Number of leading existence probes answered 200 (present) regardless
  /// of [existing] — simulates taken candidate names when the real names
  /// are random and cannot be pre-listed.
  int probesAnsweredPresent = 0;

  _FakeDashboard({
    Set<String>? existing,
    Set<String>? forbiddenMkdirs,
    Set<String>? readOnlyDirs,
    this.lockedRoot,
  }) : existing = existing ?? {},
       forbiddenMkdirs = forbiddenMkdirs ?? {},
       readOnlyDirs = readOnlyDirs ?? {};

  DashboardClient client() => DashboardClient(
    host: 'localhost',
    port: 9119,
    proxied: true,
    httpClient: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    if (uri.path == '/api/files' && request.method == 'GET') {
      final path = uri.queryParameters['path'];
      if (path == null) {
        return http.Response(
          jsonEncode({
            'path': homePath,
            'parent': null,
            'entries': <dynamic>[],
            'locked_root': lockedRoot,
          }),
          200,
        );
      }
      if (probesAnsweredPresent > 0) {
        probesAnsweredPresent--;
        return http.Response(
          jsonEncode({'path': path, 'entries': <dynamic>[]}),
          200,
        );
      }
      if (existing.contains(path)) {
        // List whatever marker files were written directly inside this dir
        // (mirrors the stock scandir-backed listing the claim check reads).
        final entries = writtenFiles.entries
            .where((e) {
              final idx = e.key.lastIndexOf('/');
              return idx > 0 && e.key.substring(0, idx) == path;
            })
            .map((e) => {
              'name': e.key.substring(e.key.lastIndexOf('/') + 1),
              'is_directory': false,
            })
            .toList();
        return http.Response(
          jsonEncode({'path': path, 'entries': entries}),
          200,
        );
      }
      // The probe just proved absence — the race window opens here.
      onProbeMissing?.call(path);
      return http.Response('{"detail":"Path not found"}', 404);
    }
    if (uri.path == '/api/files/mkdir' && request.method == 'POST') {
      final path = (jsonDecode(request.body) as Map)['path'] as String;
      if (forbiddenMkdirs.contains(path)) {
        return http.Response('{"detail":"not writable"}', 403);
      }
      _mkdirs.add(path);
      existing.add(path);
      return http.Response(jsonEncode({'ok': true, 'path': path}), 200);
    }
    if (uri.path == '/api/fs/write-text' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map;
      final path = body['path'] as String;
      final content = body['content'] as String;
      // The stock route requires the parent dir to exist; a read-only
      // directory refuses the write like a mounted-ro folder would.
      final parent = path.substring(0, path.lastIndexOf('/'));
      if (!existing.contains(parent)) {
        return http.Response('{"detail":"Parent does not exist"}', 400);
      }
      if (readOnlyDirs.contains(parent)) {
        return http.Response('{"detail":"File is not writable"}', 403);
      }
      writtenFiles[path] = content;
      return http.Response(jsonEncode({'ok': true, 'path': path}), 200);
    }
    if (uri.path == '/api/fs/read-text' && request.method == 'GET') {
      final path = uri.queryParameters['path'];
      final content = writtenFiles[path];
      if (content == null) {
        return http.Response('{"detail":"File not found"}', 404);
      }
      return http.Response(
        jsonEncode({
          'binary': false,
          'text': corruptReadText ?? content,
          'path': path,
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  }
}

/// Marker files written directly inside [dir] (test helper).
List<String> _writtenUnder(_FakeDashboard dash, String dir) => dash
    .writtenFiles.keys
    .where((k) => k.substring(0, k.lastIndexOf('/')) == dir)
    .map((k) => k.substring(k.lastIndexOf('/') + 1))
    .toList();

/// The candidate name is `<slug>-<16-hex-nonce>[-<suffix>]`; tests match
/// the shape without pinning the random nonce.
final _candidatePattern = RegExp(
  r'^/home/tester/Projects/widget-lab-[0-9a-f]{16}(-\d+)?$',
);

void main() {
  group('provision', () {
    test('creates a fresh folder under <home>/Projects when unlocked', () async {
      final dash = _FakeDashboard();
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'widget-lab',
      );
      expect(folder, isNotNull);
      expect(folder!, matches(_candidatePattern));
      expect(dash.mkdirs, [folder]);
    });

    test('provisions inside the locked root when the dashboard is locked', () async {
      final dash = _FakeDashboard(lockedRoot: '/opt/data');
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'widget-lab',
      );
      expect(folder, isNotNull);
      expect(
        folder!,
        matches(RegExp(r'^/opt/data/widget-lab-[0-9a-f]{16}(-\d+)?$')),
      );
    });

    test('the candidate name carries per-call randomness (unguessable)', () async {
      // The probe→mkdir window cannot be closed by any check (stock mkdir
      // is exist_ok=True), so the NAME must be impossible to pre-create.
      // Two provisions of the same slug must never target the same path,
      // and the nonce must not be derived from the slug — an actor who
      // knows the slug cannot guess tomorrow's folder name.
      final dash = _FakeDashboard();
      final provisioner = DashboardFolderProvisioner(dash.client());
      final first = await provisioner.provision('widget-lab');
      final second = await provisioner.provision('widget-lab');
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, isNot(second));
      final dash2 = _FakeDashboard();
      final third = await DashboardFolderProvisioner(dash2.client()).provision(
        'widget-lab',
      );
      expect(third, isNot(first));
    });

    test('an empty-directory racer cannot win: it cannot name our path', () async {
      // The reviewer's race: after our 404 probe and before our mkdir, a
      // concurrent actor creates the SAME empty directory and we adopt it.
      // With a human-readable name the actor could guess it; with the
      // nonce it cannot. The racer here plants the GUESSABLE legacy name
      // the moment any probe reports absence — the old scheme's exact
      // failure mode — and our unguessable candidate must be untouched.
      final dash = _FakeDashboard();
      dash.onProbeMissing = (probed) {
        dash.existing.add('/home/tester/Projects/widget-lab');
        dash.writtenFiles['/home/tester/Projects/widget-lab/foreign.txt'] = 'x';
      };
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'widget-lab',
      );
      // We adopted OUR freshly created folder (nonce name), never the
      // racer's legacy-named one.
      expect(folder, isNotNull);
      expect(folder!, matches(_candidatePattern));
      expect(folder, isNot('/home/tester/Projects/widget-lab'));
      // And the racer's directory never received our marker.
      expect(
        _writtenUnder(dash, '/home/tester/Projects/widget-lab'),
        isNot(contains(startsWith('hermes-provision-'))),
      );
    });

    test('a racer that plants a marker in our path mid-race is NOT adopted', () async {
      // Defense-in-depth: even for an unguessable candidate, if something
      // (host bug, symlink farm) puts a foreign entry inside between the
      // probe and the claim check, the multi-entry listing must reject
      // adoption and move to the next suffix.
      final dash = _FakeDashboard();
      var raced = false;
      dash.onProbeMissing = (probed) {
        if (raced) return;
        raced = true;
        // Pre-create the exact candidate WITH a foreign marker — our
        // mkdir is exist_ok and succeeds, the claim check then sees two
        // entries (foreign + ours) and refuses.
        dash.existing.add(probed);
        dash.writtenFiles['$probed/hermes-provision-aaa.owner'] = 'aaa';
      };
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'widget-lab',
      );
      // Never adopted the contested path; a later suffix is clean.
      expect(folder, isNotNull);
      expect(folder, isNot(dash.mkdirs.first));
      expect(dash.mkdirs.length, greaterThan(1));
    });

    test('NEVER adopts an already-existing folder; takes the next suffix', () async {
      final dash = _FakeDashboard()..probesAnsweredPresent = 1;
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'widget-lab',
      );
      expect(folder, isNotNull);
      // First candidate probed present → the -1 suffix candidate adopted.
      expect(
        folder!,
        matches(RegExp(r'^/home/tester/Projects/widget-lab-[0-9a-f]{16}-1$')),
      );
      // Only the fresh path was ever created; the pre-existing one was
      // probed, never written into.
      expect(dash.mkdirs, [folder]);
    });

    test('skips every taken name until a free one is found', () async {
      final dash = _FakeDashboard()..probesAnsweredPresent = 3;
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'app',
      );
      expect(folder, isNotNull);
      expect(
        folder!,
        matches(RegExp(r'^/home/tester/Projects/app-[0-9a-f]{16}-3$')),
      );
    });

    test('a refused mkdir (403) stops the loop instead of suffix-spamming', () async {
      final dash = _FakeDashboard();
      // The candidate name is random, so forbid mkdir on whatever the
      // first probe reports free — the guard must stop the whole loop.
      dash.onProbeMissing = (probed) {
        dash.forbiddenMkdirs.add(probed);
      };
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'pairing',
      );
      expect(folder, isNull);
      expect(dash.mkdirs, isEmpty);
    });

    test('an unreadable projects root yields null, never a guess', () async {
      final failing = DashboardClient(
        host: 'localhost',
        port: 9119,
        proxied: true,
        httpClient: MockClient((_) async => http.Response('boom', 500)),
      );
      final folder = await DashboardFolderProvisioner(failing).provision('thing');
      expect(folder, isNull);
    });

    test('an empty or unsanitizable slug provisions nothing', () async {
      final dash = _FakeDashboard();
      final provisioner = DashboardFolderProvisioner(dash.client());
      expect(await provisioner.provision(''), isNull);
      expect(await provisioner.provision('  .  '), isNull);
      expect(await provisioner.provision('---'), isNull);
      expect(dash.mkdirs, isEmpty);
    });

    test('sanitizes separators and traversal out of the slug', () async {
      final dash = _FakeDashboard();
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        '../../evil Name',
      );
      expect(folder, isNotNull);
      expect(
        folder!,
        matches(
          RegExp(r'^/home/tester/Projects/evil-name-[0-9a-f]{16}(-\d+)?$'),
        ),
      );
      expect(folder.contains('..'), isFalse);
    });

    test('a read-only candidate directory is abandoned, never adopted', () async {
      final dash = _FakeDashboard();
      // Refuse marker writes in the FIRST candidate only.
      String? readOnly;
      dash.onProbeMissing = (probed) {
        readOnly ??= probed;
        dash.readOnlyDirs.add(readOnly!);
      };
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'locked-thing',
      );
      // Marker write refused → claim fails → a later suffix succeeds.
      expect(folder, isNotNull);
      expect(folder, isNot(readOnly));
    });

    test('a corrupt marker read (token mismatch) never adopts', () async {
      final dash = _FakeDashboard()..corruptReadText = 'not-what-we-wrote';
      final folder = await DashboardFolderProvisioner(dash.client()).provision(
        'weird-host',
      );
      // Every candidate fails verification; the loop exhausts and
      // degrades to folderless rather than adopting on a bad proof.
      expect(folder, isNull);
    });
  });
}