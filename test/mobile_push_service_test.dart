import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:hermes_android/core/widgets/mobile_push_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/mobile_push_api.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySecrets implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// Controlled native boundary; cryptographic/decrypted gates are separately
/// tested by the real Kotlin policy. HTTP below is an authenticated API fixture,
/// not evidence of a live server subscription or physical device delivery.
class Fixture {
  final native = <String, dynamic>{'enabled': false};
  final methods = <String>[];
  final requests = <http.Request>[];
  final MethodChannel channel = const MethodChannel(
    MobilePushService.channelName,
  );
  late MobilePushService service;
  late DashboardClient Function(SavedConnection) clientFactory;
  String? failNativeOnce;
  late final ConnectionManager manager;
  late final SavedConnection connection;
  int capsStatus = 200;
  int? registrationFence = 1;
  bool capsEnabled = true;
  List<String>? scopeModes = ['explicit', 'authorized'];
  bool permission = true;
  String? enableFailureCode;
  List<Map<String, String>> options = [
    {'id': 'test.distributor', 'label': 'Test distributor'},
  ];
  bool failRevoke = false;
  String? failCommand;
  final connectionFences = <String, String>{};
  final connectionChanges = <String, Set<String>>{};
  int fenceSequence = 0;
  Future<void> Function(String, Map<String, dynamic>)? afterCommand;
  Future<http.Response> Function(http.Request)? onPut;
  Future<http.Response> Function(http.Request)? onCapabilities;
  Future<http.Response> Function(http.Request)? onConfirm;
  Future<http.Response> Function(http.Request)? onEvents;
  List<Map<String, dynamic>> feed = [];
  int eventPageSize = 100;
  final int expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  Map<String, dynamic> clone(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);
  Future<void> setup() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    manager = ConnectionManager(prefs, credentialStore: MemorySecrets());
    await manager.saveConnection(
      'Fixture',
      'https://fixture.invalid',
      443,
      'gateway-test-key',
      dashboardPrefix: '/dash',
      dashboardUsername: 'fixture-user',
      dashboardPassword: 'fixture-password',
      gatewayProfile: 'selected-work-profile',
    );
    connection = manager.getConnections().single;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          if (failNativeOnce == call.method) {
            failNativeOnce = null;
            throw PlatformException(code: 'process-died-before-persist');
          }
          final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
          if (call.method == failCommand) {
            failCommand = null;
            throw PlatformException(
              code: 'fixture-process-died-before-persist',
            );
          }
          switch (call.method) {
            case 'connectionFence':
              final id = args['connection'] as String;
              if (connectionChanges.values.any((ids) => ids.contains(id))) {
                throw PlatformException(code: 'account-change-pending');
              }
              return {
                'connection_fence': connectionFences.putIfAbsent(
                  id,
                  () => 'fence-${++fenceSequence}',
                ),
              };
            case 'beginConnectionChange':
              final ids = Set<String>.from(args['connections'] as List);
              connectionChanges[args['mutation'] as String] = ids;
              for (final id in ids) {
                connectionFences.remove(id);
              }
              if (ids.contains(native['connection'])) disableNative();
              await afterCommand?.call(call.method, args);
              return clone(native);
            case 'endConnectionChange':
              connectionChanges.remove(args['mutation']);
              await afterCommand?.call(call.method, args);
              return clone(native);
            case 'permission':
              return permission;
            case 'distributors':
              return ['test.distributor'];
            case 'transportOptions':
              return options;
            case 'snapshot':
              return clone(native);
            case 'preferences':
              native.addAll(args);
              return clone(native);
            case 'enable':
              if (enableFailureCode != null) {
                throw PlatformException(code: enableFailureCode!);
              }
              final id = args['connection'] as String;
              if (connectionChanges.values.any((ids) => ids.contains(id)) ||
                  connectionFences[id] == null ||
                  args['connection_fence'] != connectionFences[id]) {
                throw PlatformException(code: 'stale-account-consent');
              }
              connectionFences.remove(id);
              native.addAll({
                ...args,
                'enabled': true,
                'active': false,
                'installation': 'fixture-installation',
                'nonce': 'fixture-nonce',
                'registration_fence': 1,
                'revision': 1,
                'generation': 0,
              });
              final enabledState = clone(native);
              await afterCommand?.call(call.method, args);
              return enabledState;
            case 'recoverRegistration':
            case 'beginRegistration':
            case 'beginConfirmation':
              if (args['nonce'] != native['nonce'] ||
                  args['revision'] != native['revision'] ||
                  args['generation'] != native['generation'] ||
                  native['active'] == true ||
                  native['enabled'] != true) {
                throw PlatformException(code: 'stale');
              }
              if (call.method == 'recoverRegistration') {
                native.addAll({
                  'nonce': 'recovered-nonce-${native['revision']}',
                  'revision': (native['revision'] as int) + 1,
                  'generation': 0,
                  'active': false,
                });
                for (final key in [
                  'registration_attempt',
                  'confirmation_attempt',
                  'pending_until',
                  'challenges',
                  'tap',
                  'seen',
                  'issued',
                ]) {
                  native.remove(key);
                }
              } else if (call.method == 'beginRegistration') {
                native['registration_attempt'] = true;
                native['pending_until'] = expiry - 3300;
              } else {
                native['confirmation_attempt'] = true;
              }
              return clone(native);
            case 'generation':
              if (args['nonce'] != native['nonce'] ||
                  args['revision'] != native['revision'] ||
                  native['enabled'] != true) {
                throw PlatformException(code: 'stale');
              }
              native['generation'] = args['generation'];
              native.remove('registration_attempt');
              return clone(native);
            case 'activate':
              if (args['nonce'] != native['nonce'] ||
                  native['enabled'] != true) {
                throw PlatformException(code: 'stale');
              }
              native['active'] = true;
              native.remove('challenges');
              native.remove('confirmation_attempt');
              native.remove('pending_until');
              return clone(native);
            case 'disable':
              disableNative();
              return clone(native);
            case 'revoked':
              native['revocations'] = (native['revocations'] as List)
                  .where(
                    (e) => e['installation'] != args['revokedInstallation'],
                  )
                  .toList();
              return clone(native);
            case 'takeTap':
              return native.remove('tap');
            case 'retryDistributor':
              return clone(native);
            default:
              throw StateError(call.method);
          }
        });
    clientFactory = (c) => DashboardClient(
      host: c.host,
      port: c.dashboardPort,
      useHttps: c.useHttps,
      pathPrefix: c.dashboardPrefix!,
      username: c.dashboardUsername,
      password: c.dashboardPassword,
      gatewayProfile: c.gatewayProfile,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/dash/auth/password-login') {
          expect(jsonDecode(request.body)['username'], 'fixture-user');
          return http.Response(
            '{}',
            200,
            headers: {
              'set-cookie': 'hermes_session_at=fixture-cookie; HttpOnly',
            },
          );
        }
        expect(request.url.host, 'fixture.invalid');
        expect(
          request.url.path.startsWith('/dash/api/plugins/mobile-push/'),
          isTrue,
        );
        expect(request.headers['Cookie'], 'hermes_session_at=fixture-cookie');
        expect(request.url.queryParameters['profile'], c.gatewayProfile);
        expect(request.headers.containsKey('Authorization'), isFalse);
        if (request.url.path.endsWith('/capabilities')) {
          if (onCapabilities != null) return onCapabilities!(request);
          return http.Response(
            jsonEncode({
              'schema': 1,
              'registration_fence': registrationFence,
              'session_scope_modes': scopeModes,
              'enabled': capsEnabled,
              'transports': ['webpush'],
              'vapid_public_key': base64Url
                  .encode([4, ...List<int>.filled(64, 1)])
                  .replaceAll('=', ''),
            }),
            capsStatus,
          );
        }
        if (request.method == 'PUT') {
          if (onPut != null) return onPut!(request);
          return pending();
        }
        if (request.url.path.endsWith('/confirm')) {
          if (onConfirm != null) return onConfirm!(request);
          return http.Response('{"status":"active","generation":7}', 200);
        }
        if (request.method == 'DELETE') {
          return http.Response('{}', failRevoke ? 503 : 200);
        }
        if (request.url.path.endsWith('/events')) {
          if (onEvents != null) return onEvents!(request);
          final after = int.parse(request.url.queryParameters['after']!);
          final page = feed.skip(after).take(eventPageSize).toList();
          final next = after + page.length;
          return http.Response(
            jsonEncode({
              'events': page,
              'next_cursor': next,
              'has_more': next < feed.length,
              if (native['session_scope'] == 'authorized') ...{
                'installation_id': native['installation'],
                'generation': native['generation'],
                'session_scope': 'authorized',
              },
            }),
            200,
          );
        }
        throw StateError('Unexpected fixture request');
      }),
    );
    createService();
  }

  void restart() {
    service.dispose();
    // Recreate the Dart controller, retaining only the native durable snapshot.
    createService();
  }

  void disableNative() {
    final revokes = native['revocations'] as List? ?? [];
    if (native['enabled'] == true) {
      revokes.add({
        'connection': native['connection'],
        'installation': native['installation'],
        'binding': native['binding'],
      });
    }
    native.addAll({
      'enabled': false,
      'active': false,
      'nonce': '',
      'generation': 0,
      'revocations': revokes,
    });
    for (final key in [
      'challenges',
      'tap',
      'keys',
      'endpoint',
      'issued',
      'seen',
    ]) {
      native.remove(key);
    }
  }

  void createService() {
    service = MobilePushService(
      supported: true,
      channel: channel,
      clientFactory: clientFactory,
    );
  }

  http.Response pending({String status = 'pending'}) => http.Response(
    jsonEncode({
      'generation': 7,
      'status': status,
      'registration_nonce': native['nonce'],
      'registration_revision': native['revision'],
    }),
    200,
  );
  void seed({bool active = false}) {
    native.addAll({
      'enabled': true,
      'active': active,
      'connection': connection.id,
      'binding': MobilePushService.binding(connection),
      'installation': 'fixture-installation',
      'nonce': 'fixture-nonce',
      'registration_fence': 1,
      'revision': 1,
      'generation': active ? 7 : 0,
      'sessions': ['durable-session'],
      'endpoint': 'https://distributor.invalid/test',
      'keys': {'p256dh': 'test-fixture-only', 'auth': 'test-fixture-only'},
    });
  }

  void challenge({int generation = 7}) {
    native['challenges'] = [
      {
        'schema': 1,
        'kind': 'challenge',
        'event_id': 'challenge-event',
        'generation': generation,
        'registration_nonce': native['nonce'],
        'expires_at': expiry,
        'challenge': 'fixture-encrypted-proof',
      },
    ];
  }

  Map<String, dynamic> event(
    String id, {
    String session = 'durable-session',
    String kind = 'turn_done',
    int? expires,
  }) => {
    'cursor': 1,
    'event_id': id,
    'kind': kind,
    'session_id': session,
    'created_at': expiry - 3600,
    'expires_at': expires ?? expiry,
  };
  void tap(String id) {
    native['tap'] = {
      'event_id': id,
      'connection': connection.id,
      'installation': native['installation'],
      'nonce': native['nonce'],
      'revision': native['revision'],
      'generation': native['generation'],
      'expires_at': expiry,
    };
  }

  Future<void> changed() {
    final result = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          MobilePushService.channelName,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('changed'),
          ),
          (_) => result.complete(),
        );
    return result.future;
  }

  void close() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture f;
  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = Fixture();
    await f.setup();
  });
  tearDown(() {
    f.close();
  });
  test(
    'off by default; startup performs no permission, connector or network registration',
    () async {
      await f.service.initialize(f.manager);
      expect(f.service.enabled, isFalse);
      expect(f.requests, isEmpty);
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
    },
  );
  testWidgets(
    'settings one toggle explicitly enables authorized hints without manual IDs',
    (tester) async {
      await tester.runAsync(() => f.service.initialize(f.manager));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobilePushSettings(
                connection: f.connection,
                connectionManager: f.manager,
                service: f.service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await f.service.initialize(f.manager);
        await f.service.distributors();
      });
      await tester.pumpAndSettle();
      expect(find.text('Background notifications'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      final enable = find.byType(Switch);
      expect(f.methods, isNot(contains('permission')));
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(f.methods, contains('permission'));
      expect(f.native['sessions'], isEmpty);
      expect(f.native['session_scope'], 'authorized');
      expect(f.native['distributor'], 'automatic');
      expect(find.text('Disable and revoke'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'startup hydrates disabled notification preferences before native sync',
    () async {
      await f.manager.prefs.setString(
        NotificationPrefsStore.storageKey,
        jsonEncode(
          NotificationPrefs.defaults.copyWith(enabled: false).toJson(),
        ),
      );
      await f.service.initialize(f.manager);
      expect(f.native['master'], isFalse);
      expect(
        f.methods.where((method) => method == 'preferences'),
        hasLength(1),
      );
    },
  );
  test('empty allowlist fails before permission or HTTP', () async {
    await f.service.initialize(f.manager);
    await expectLater(
      f.service.enable(f.connection, 'test.distributor', []),
      throwsStateError,
    );
    expect(f.requests, isEmpty);
  });
  test(
    'missing plugin and forbidden principal are honest and never opt in',
    () async {
      await f.service.initialize(f.manager);
      f.capsStatus = 404;
      await expectLater(
        f.service.enable(f.connection, 'test.distributor', ['durable-session']),
        throwsA(isA<DashboardHttpException>()),
      );
      expect(f.service.error, contains('may be missing or disabled'));
      f.capsStatus = 403;
      await expectLater(
        f.service.enable(f.connection, 'test.distributor', ['durable-session']),
        throwsA(isA<DashboardHttpException>()),
      );
      expect(f.service.error, contains('denied'));
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
    },
  );
  test(
    'unfenced legacy server rejected before permission or native consent',
    () async {
      await f.service.initialize(f.manager);
      f.registrationFence = null;
      await expectLater(
        f.service.enable(f.connection, 'test.distributor', ['durable-session']),
        throwsFormatException,
      );
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
      expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
    },
  );
  test('disabled selected profile gates permission and registration', () async {
    await f.service.initialize(f.manager);
    f.capsEnabled = false;
    await expectLater(
      f.service.enable(f.connection, 'test.distributor', ['durable-session']),
      throwsFormatException,
    );
    expect(f.methods, isNot(contains('permission')));
    expect(f.methods, isNot(contains('enable')));
    expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
  });
  for (final boundary in ['capabilities', 'PUT']) {
    test('profile edit invalidates held $boundary authority', () async {
      final entered = Completer<void>();
      final released = Completer<http.Response>();
      if (boundary == 'capabilities') {
        await f.service.initialize(f.manager);
        f.onCapabilities = (_) {
          entered.complete();
          return released.future;
        };
      } else {
        f.seed();
        f.onPut = (_) {
          entered.complete();
          return released.future;
        };
      }
      final flight = boundary == 'capabilities'
          ? f.service.enable(f.connection, 'test.distributor', [
              'durable-session',
            ])
          : f.service.initialize(f.manager);
      await entered.future;
      await f.manager.updateConnection(
        f.connection.id,
        f.connection.label,
        'https://fixture.invalid',
        443,
        f.connection.apiKey,
        gatewayProfile: 'different-selected-profile',
      );
      released.complete(
        boundary == 'capabilities'
            ? http.Response(
                jsonEncode({
                  'schema': 1,
                  'registration_fence': 1,
                  'enabled': true,
                  'transports': ['webpush'],
                  'vapid_public_key': base64Url
                      .encode([4, ...List<int>.filled(64, 1)])
                      .replaceAll('=', ''),
                }),
                200,
              )
            : f.pending(),
      );
      await flight;
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
      expect(f.methods, isNot(contains('generation')));
      expect(f.methods, isNot(contains('activate')));
      expect(f.service.active, isFalse);
      expect(f.requests.where((r) => r.url.path.endsWith('/events')), isEmpty);
    });
  }
  test(
    'registration must echo exact durable revision before accepting generation',
    () async {
      f.seed();
      f.onPut = (_) async => http.Response(
        jsonEncode({
          'generation': 7,
          'status': 'pending',
          'registration_nonce': f.native['nonce'],
          'registration_revision': 999,
        }),
        200,
      );
      await f.service.initialize(f.manager);
      expect(f.service.active, isFalse);
      expect(f.native['registration_attempt'], isTrue);
      expect(f.methods, isNot(contains('generation')));
    },
  );
  test('permission denial never grants native consent', () async {
    await f.service.initialize(f.manager);
    f.permission = false;
    await expectLater(
      f.service.enable(f.connection, 'test.distributor', ['durable-session']),
      throwsStateError,
    );
    expect(f.methods, isNot(contains('enable')));
  });
  test(
    'explicit opt in binds one connection and only selected durable IDs',
    () async {
      await f.service.initialize(f.manager);
      await f.service.enable(f.connection, 'test.distributor', [
        'durable-session',
        'durable-session',
      ]);
      expect(f.native['sessions'], ['durable-session']);
      expect(f.native['connection'], f.connection.id);
      expect(f.service.active, isFalse);
      expect(f.service.status, contains('Pending distributor'));
    },
  );
  test(
    'challenge delivered during PUT is queued and confirmed after generation response',
    () async {
      f.seed();
      f.onPut = (request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['session_ids'], ['durable-session']);
        expect(body['keys'], f.native['keys']);
        expect(body.containsKey('vapid_public_key'), isFalse);
        f.challenge(); // native received and persisted BEFORE PUT completed
        return f.pending();
      };
      await f.service.initialize(f.manager);
      expect(f.service.active, isTrue);
      expect(
        f.methods.indexOf('generation'),
        lessThan(f.methods.indexOf('activate')),
      );
      final confirm = f.requests.singleWhere(
        (r) => r.url.path.endsWith('/confirm'),
      );
      expect(jsonDecode(confirm.body), {
        'generation': 7,
        'challenge': 'fixture-encrypted-proof',
      });
    },
  );
  test(
    'every push operation forwards named profile and event cursor',
    () async {
      final requests = <http.Request>[];
      final client = DashboardClient(
        host: 'fixture.invalid',
        port: 443,
        useHttps: true,
        pathPrefix: '/dash',
        proxied: true,
        gatewayProfile: 'other-profile',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'schema': 1,
              'registration_fence': 1,
              'enabled': true,
              'transports': ['webpush'],
              'vapid_public_key': base64Url
                  .encode([4, ...List<int>.filled(64, 1)])
                  .replaceAll('=', ''),
            }),
            200,
          );
        }),
      );
      final api = MobilePushApi(client);
      f.seed();
      await api.capabilities();
      await api.register(f.native);
      await api.confirm('phone', 7, 'proof');
      await api.events('123');
      await api.revoke('phone');
      expect(requests, hasLength(5));
      for (final request in requests) {
        expect(request.url.queryParameters['profile'], 'other-profile');
        expect(request.url.path, startsWith('/dash/api/plugins/mobile-push/'));
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
      expect(requests[3].url.queryParameters['after'], '123');
      expect(requests[3].url.queryParameters['limit'], '100');
      client.close();
    },
  );
  test(
    'lost PUT acknowledgement rotates fenced authority and recovers same scope',
    () async {
      f.seed();
      var attempts = 0;
      f.onPut = (_) async {
        attempts++;
        f.challenge();
        if (attempts == 1) throw http.ClientException('response lost');
        return f.pending();
      };
      await f.service.initialize(f.manager);
      expect(f.native['generation'], 0);
      expect(f.service.active, isFalse);
      await f.service.retry();
      expect(f.service.active, isTrue);
      final puts = f.requests.where((r) => r.method == 'PUT').toList();
      expect(puts, hasLength(2));
      final before = jsonDecode(puts[0].body) as Map;
      final after = jsonDecode(puts[1].body) as Map;
      expect(
        after['registration_revision'],
        (before['registration_revision'] as int) + 1,
      );
      expect(after['registration_nonce'], isNot(before['registration_nonce']));
      expect(after['session_ids'], before['session_ids']);
      expect(after['endpoint'], before['endpoint']);
      expect(f.methods.where((m) => m == 'enable'), isEmpty);
    },
  );
  for (final method in ['generation', 'activate']) {
    test(
      'process death after server reply before native $method persists recovers',
      () async {
        f.seed();
        f.challenge();
        var serverActive = false;
        f.onPut = (_) async {
          f.challenge(); // New native nonce needs a fresh encrypted proof.
          return f.pending();
        };
        f.onConfirm = (_) async {
          serverActive = true;
          return http.Response('{"status":"active","generation":7}', 200);
        };
        f.failNativeOnce = method;
        await f.service.initialize(f.manager);
        expect(f.native['active'], isFalse);
        f.service.dispose();
        f.createService();
        await f.service.initialize(f.manager);
        expect(f.service.active, isTrue);
        expect(serverActive, isTrue);
      },
    );
  }
  test(
    'lost confirmation ACK recovers after challenge expiry without push authority',
    () async {
      f.seed();
      f.challenge();
      var attempts = 0;
      var serverActive = false;
      f.onPut = (_) async {
        f.challenge();
        return f.pending();
      };
      f.onConfirm = (_) async {
        serverActive = true;
        if (++attempts == 1) throw http.ClientException('reply lost');
        return http.Response('{"status":"active","generation":7}', 200);
      };
      await f.service.initialize(f.manager);
      expect(f.service.active, isFalse);
      (f.native['challenges'] as List).single['expires_at'] = 1;
      await f.service.retry();
      expect(f.service.active, isTrue);
      expect(attempts, 2);
      expect(serverActive, isTrue);
    },
  );
  test(
    'expired pending challenge retry requests fresh encrypted proof for renewed authority',
    () async {
      f.seed();
      f.native['generation'] = 7;
      f.challenge();
      (f.native['challenges'] as List).single['expires_at'] = 1;
      f.onPut = (_) async {
        f.challenge(); // server reissues only an expired pending challenge
        return f.pending();
      };
      await f.service.initialize(f.manager);
      expect(f.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(f.service.active, isTrue);
    },
  );
  test('active PUT recovery alone never grants native authority', () async {
    f.seed();
    f.onPut = (_) async => f.pending(status: 'active');
    await f.service.initialize(f.manager);
    expect(f.native['generation'], 0);
    expect(f.service.active, isFalse);
    expect(f.methods, isNot(contains('activate')));
  });
  test(
    'disable during lost-confirmation recovery fences the late active ACK',
    () async {
      f.seed();
      f.challenge();
      var attempts = 0;
      final started = Completer<void>();
      final response = Completer<http.Response>();
      f.onPut = (_) async {
        f.challenge();
        return f.pending();
      };
      f.onConfirm = (_) async {
        if (++attempts == 1) throw http.ClientException('reply lost');
        started.complete();
        return response.future;
      };
      await f.service.initialize(f.manager);
      final retry = f.service.retry();
      await started.future;
      final disable = f.service.disable();
      await Future<void>.delayed(Duration.zero);
      expect(f.native['enabled'], isFalse);
      response.complete(
        http.Response('{"status":"active","generation":7}', 200),
      );
      await retry;
      await disable;
      expect(f.native['active'], isFalse);
      expect(f.methods, isNot(contains('activate')));
    },
  );
  test(
    'confirmation response for a different generation cannot activate',
    () async {
      f.seed();
      f.challenge();
      f.onConfirm = (_) async =>
          http.Response('{"status":"active","generation":8}', 200);
      await f.service.initialize(f.manager);
      expect(f.service.active, isFalse);
      expect(f.methods, isNot(contains('activate')));
    },
  );
  test('old challenge cannot activate a new generation', () async {
    f.seed();
    f.challenge(generation: 6);
    await f.service.initialize(f.manager);
    expect(f.service.active, isFalse);
    expect(f.methods, isNot(contains('activate')));
  });
  test(
    'disable while PUT is in flight clears local authority before network revoke',
    () async {
      f.seed();
      final put = Completer<http.Response>();
      final started = Completer<void>();
      f.onPut = (_) {
        started.complete();
        return put.future;
      };
      final initialization = f.service.initialize(f.manager);
      await started.future;
      final disabled = f.service.disable();
      // Let the MethodChannel persist disable without completing the held PUT.
      await Future<void>.delayed(Duration.zero);
      expect(f.native['enabled'], isFalse);
      put.complete(
        http.Response(
          '{"generation":7,"status":"pending","registration_nonce":"fixture-nonce"}',
          200,
        ),
      );
      await initialization;
      await disabled;
      expect(f.methods, isNot(contains('generation')));
      expect(f.methods, isNot(contains('activate')));
    },
  );
  test(
    'renewal during confirmation makes late confirmation powerless',
    () async {
      f.seed();
      f.challenge();
      f.onConfirm = (_) async {
        f.native.addAll({
          'nonce': 'renewed-nonce',
          'revision': 2,
          'generation': 0,
          'active': false,
        });
        return http.Response('{"status":"active","generation":7}', 200);
      };
      await f.service.initialize(f.manager);
      expect(f.native['active'], isFalse);
      expect(f.methods, isNot(contains('activate')));
    },
  );
  test(
    'failed server revoke remains durable and is retried on next foreground refresh',
    () async {
      f.seed(active: true);
      await f.service.initialize(f.manager);
      f.failRevoke = true;
      await f.service.disable();
      expect(f.native['enabled'], isFalse);
      expect(f.service.pendingRevocations, 1);
      f.failRevoke = false;
      await f.service.refresh();
      expect(f.service.pendingRevocations, 0);
    },
  );
  test(
    'native changed callback reconciles all pages and routes only authorized live events',
    () async {
      f.seed(active: true);
      await f.service.initialize(f.manager);
      f.eventPageSize = 1;
      f.feed = [
        f.event('old', expires: 1),
        f.event('other', session: 'not-selected'),
        f.event('valid'),
      ];
      f.tap('valid');
      await f.changed();
      expect(f.service.events.map((e) => e['event_id']), ['valid']);
      final route = await f.service.takePendingNotificationRoute();
      expect(route?.sessionId, 'durable-session');
      expect(await f.service.isRouteCurrent(route!), isTrue);
      await f.service.disable();
      expect(await f.service.isRouteCurrent(route), isFalse);
    },
  );
  test(
    'notification master and kind preferences sync to native and reject stale taps',
    () async {
      f.seed(active: true);
      f.feed = [f.event('valid')];
      await f.service.initialize(f.manager);
      final prefs = NotificationPrefs.defaults.copyWith(
        kind: HermesNotificationKind.turnDone,
        kindValue: false,
      );
      notificationPrefs.value = prefs;
      await f.service.syncPreferences(prefs);
      expect(f.native['kinds'], isNot(contains('turn_done')));
      f.tap('valid');
      await f.changed();
      expect(await f.service.takePendingNotificationRoute(), isNull);
      await f.service.syncPreferences(prefs.copyWith(enabled: false));
      expect(f.native['master'], isFalse);
    },
  );
  test(
    'edited saved login invalidates native authority instead of reusing old credentials',
    () async {
      f.seed(active: true);
      await f.service.initialize(f.manager);
      await f.manager.updateApiKey(f.connection.id, 'changed-login');
      await f.service.refresh();
      expect(f.native['enabled'], isFalse);
      expect(f.service.status, contains('changed'));
    },
  );
}
