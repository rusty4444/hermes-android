// The per-connection Projects root (issue #232): defaults, round-trip,
// validation, and what a corrupt stored value does.
//
// The whole point of the default is that it changes nothing: an unconfigured
// connection must read back null so the provisioner keeps using the server's
// conventional `<home>/Projects`.

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/projects_root_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _connection({
  String id = 'c1',
  String host = 'gateway.test',
  int port = 8642,
  String? desktopGatewayUrl = 'https://gateway.test:9119',
}) => SavedConnection(
  id: id,
  label: 'Gateway',
  host: host,
  port: port,
  apiKey: 'k',
  desktopGatewayUrl: desktopGatewayUrl,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('default', () {
    test('an unconfigured connection reads back null', () async {
      final store = await ProjectsRootPreference.open();
      expect(store.read(connectionIdentity: 'any'), isNull);
    });

    test('one connection never sees another connection value', () async {
      final store = await ProjectsRootPreference.open();
      await store.save(connectionIdentity: 'a', path: '/root/.hermes/projects');
      expect(store.read(connectionIdentity: 'b'), isNull);
      expect(store.read(connectionIdentity: 'a'), '/root/.hermes/projects');
    });
  });

  group('round-trip', () {
    test('a saved absolute path survives a reopen', () async {
      final first = await ProjectsRootPreference.open();
      final saved = await first.save(
        connectionIdentity: 'gw',
        path: '/root/.hermes/projects',
      );
      expect(saved.isValid, isTrue);

      final second = await ProjectsRootPreference.open();
      expect(second.read(connectionIdentity: 'gw'), '/root/.hermes/projects');
    });

    test(
      'trailing and duplicate slashes are normalized on the way in',
      () async {
        final store = await ProjectsRootPreference.open();
        await store.save(
          connectionIdentity: 'gw',
          path: '  /root//.hermes/projects///  ',
        );
        expect(store.read(connectionIdentity: 'gw'), '/root/.hermes/projects');
      },
    );

    test('clear returns the connection to the server default', () async {
      final store = await ProjectsRootPreference.open();
      await store.save(connectionIdentity: 'gw', path: '/srv/projects');
      await store.clear(connectionIdentity: 'gw');
      expect(store.read(connectionIdentity: 'gw'), isNull);
    });
  });

  group('validation', () {
    test('empty and whitespace-only are rejected', () {
      for (final raw in ['', '   ', '\t\n']) {
        final result = ProjectsRootPreference.validate(raw);
        expect(result.isValid, isFalse, reason: raw);
        expect(result.issue, ProjectsRootIssue.empty, reason: raw);
      }
    });

    test('relative paths are rejected', () {
      for (final raw in ['Projects', './Projects', '../Projects', 'root/x']) {
        final result = ProjectsRootPreference.validate(raw);
        expect(result.isValid, isFalse, reason: raw);
        expect(result.issue, ProjectsRootIssue.notAbsolute, reason: raw);
      }
    });

    test('dot segments and control characters are rejected', () {
      for (final raw in [
        '/root/../etc',
        '/root/./projects',
        '/root/pro\u0000jects',
        '/root/pro\njects',
        r'/root\projects',
        '/',
        '///',
      ]) {
        final result = ProjectsRootPreference.validate(raw);
        expect(result.isValid, isFalse, reason: raw);
        expect(result.issue, ProjectsRootIssue.unsafeSegments, reason: raw);
      }
    });

    test('an absolute POSIX path is accepted and normalized', () {
      final result = ProjectsRootPreference.validate('/root/.hermes/projects/');
      expect(result.isValid, isTrue);
      expect(result.path, '/root/.hermes/projects');
      expect(result.issue, isNull);
    });

    test('a rejected path is never written', () async {
      final store = await ProjectsRootPreference.open();
      final result = await store.save(
        connectionIdentity: 'gw',
        path: 'Projects',
      );
      expect(result.isValid, isFalse);
      expect(store.read(connectionIdentity: 'gw'), isNull);
    });
  });

  group('corrupt storage', () {
    test('a relative stored value is ignored, not repaired', () async {
      final identity = 'gw';
      // Mirrors what a hand-edited preferences file or an older backup could
      // leave behind. The default must win rather than a relative root being
      // used as the folder new Projects are created under.
      SharedPreferences.setMockInitialValues({
        'projects_root.${Uri.encodeComponent(identity)}.path': 'Projects',
      });
      final store = await ProjectsRootPreference.open();
      expect(store.read(connectionIdentity: identity), isNull);
    });

    test(
      'a wrong-typed stored value keeps the default and never throws',
      () async {
        final identity = 'gw';
        SharedPreferences.setMockInitialValues({
          'projects_root.${Uri.encodeComponent(identity)}.path': 42,
        });
        final store = await ProjectsRootPreference.open();
        expect(() => store.read(connectionIdentity: identity), returnsNormally);
        expect(store.read(connectionIdentity: identity), isNull);
      },
    );
  });

  group('identity', () {
    test(
      'saved connections sharing an endpoint retain independent roots',
      () async {
        final store = await ProjectsRootPreference.open();
        final first = ProjectsRootPreference.identityOf(
          _connection(id: 'first'),
        );
        final second = ProjectsRootPreference.identityOf(
          _connection(id: 'second'),
        );
        expect(first, isNot(second));
        await store.save(connectionIdentity: first, path: '/srv/first');
        expect(store.read(connectionIdentity: second), isNull);
        await store.save(connectionIdentity: second, path: '/srv/second');
        expect(store.read(connectionIdentity: first), '/srv/first');
        expect(store.read(connectionIdentity: second), '/srv/second');
      },
    );

    test('editing the saved connection address retains its own preference', () {
      expect(
        ProjectsRootPreference.identityOf(_connection()),
        ProjectsRootPreference.identityOf(_connection(host: 'other.test')),
      );
      expect(
        ProjectsRootPreference.identityOf(_connection()),
        ProjectsRootPreference.identityOf(
          _connection(desktopGatewayUrl: 'https://elsewhere.test:9119'),
        ),
      );
    });
  });
}
