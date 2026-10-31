import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'independent_push_quality_edit_race_test.dart' as race;
import 'support/mtls_fixture.dart' show loopbackIdentity;

class _FixtureCertificateFiles implements ClientCertificateFileStore {
  @override
  Future<void> deleteUnreferenced(
    Iterable<String> referencedDirectoryPaths,
  ) async {}
}

class _Push extends MobilePushService {
  _Push() : super(supported: false);
  final queue = <MobilePushRoute>[];
  bool current = true;
  Completer<bool>? heldCheck;
  final checkEntered = Completer<void>();
  @override
  Future<void> initialize(ConnectionManager manager) async => notifyListeners();
  @override
  bool get hasPendingTap => queue.isNotEmpty;
  void tap(SavedConnection c, String id) {
    queue.add(MobilePushRoute(c, id, 'event-$id', const {}));
    notifyListeners();
  }

  @override
  Future<MobilePushRoute?> takePendingNotificationRoute() async =>
      queue.isEmpty ? null : queue.removeAt(0);
  @override
  Future<bool> isRouteCurrent(MobilePushRoute route) async {
    final held = heldCheck;
    if (held != null) {
      heldCheck = null;
      checkEntered.complete();
      return held.future;
    }
    return current;
  }
}

// Only dart:io transport is replaced: root constructs the production ApiClient,
// IOClient, authenticated requests and session pagination, not the lookup seam.
class _Wire extends HttpOverrides {
  _Wire({this.canonicalRoot = false});
  final bool canonicalRoot;
  final contexts = <SecurityContext?>[];
  final requests = <(Uri, Map<String, String>)>[];
  final firstPage = Completer<HttpClientResponse>();
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    contexts.add(context);
    return _Client(this);
  }

  Future<HttpClientResponse> respond(Uri uri, _Headers headers) async {
    requests.add((uri, Map.of(headers.values)));
    if (uri.path == '/api/sessions' && uri.queryParameters['offset'] == '0') {
      return firstPage.future;
    }
    return _Response({
      'data': [
        {
          'id': canonicalRoot ? 'current-tip' : 'exact',
          if (canonicalRoot) '_lineage_root_id': 'exact',
          'title': 'Target',
          'source': 'mobile',
        },
      ],
      'has_more': false,
    });
  }

  void releaseFirst() => firstPage.complete(
    _Response({
      'data': [
        {
          'id': 'not-the-target',
          '_lineage_root_id': 'other-root',
          'title': 'Other',
          'source': 'mobile',
        },
      ],
      'has_more': true,
    }),
  );
}

class _Client implements HttpClient {
  _Client(this.wire);
  final _Wire wire;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(wire, url);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value.toString();
  @override
  void forEach(void Function(String, List<String>) action) =>
      values.forEach((name, value) => action(name, [value]));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.wire, this.uri);
  final _Wire wire;
  @override
  final Uri uri;
  @override
  final _Headers headers = _Headers();
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<HttpClientResponse> close() => wire.respond(uri, headers);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(Map<String, Object> data) : bytes = utf8.encode(jsonEncode(data));
  final List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  HttpHeaders get headers => _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pendingNotificationApprovals.value = const [];
  });
  for (final boundary in [
    'revoke',
    'edit',
    'remove',
    'pending edit',
    'same-value edit',
    'dispose',
    'dispose during continuation',
    'edit during continuation',
    'newer tap',
    'newer tap during continuation',
    'unchanged authority',
    'canonical root',
    'mTLS identity',
  ]) {
    testWidgets(
      boundary == 'unchanged authority'
          ? 'unchanged authority pages to the exact session and opens it'
          : '$boundary after real page one sends no stale credentialed page two',
      (tester) async {
        final secrets = race.GatedSecrets();
        final manager = ConnectionManager(
          await SharedPreferences.getInstance(),
          credentialStore: secrets,
          certificateFiles: _FixtureCertificateFiles(),
        );
        await manager.saveConnection(
          'Fixture',
          'fixture.invalid',
          8642,
          'test-credential',
          gatewayProfile: 'selected-profile',
          clientCertificate: boundary == 'mTLS identity'
              ? loopbackIdentity
              : null,
        );
        final c = manager.getConnections().single;
        final push = _Push()..tap(c, 'exact');
        addTearDown(push.dispose);
        final wire = _Wire(canonicalRoot: boundary == 'canonical root');
        await HttpOverrides.runZoned(() async {
          await tester.pumpWidget(
            HermesApp(connManager: manager, mobilePush: push),
          );
          await _pump(tester);
          expect(wire.requests, hasLength(1));
          expect(wire.requests.single.$1.queryParameters['offset'], '0');
          expect(
            wire.requests.single.$2['authorization'],
            'Bearer test-credential',
          );
          Completer<bool>? continuation;
          if (boundary.contains('during continuation')) {
            continuation = Completer<bool>();
            push.heldCheck = continuation;
            wire.releaseFirst();
            await _pump(tester);
            expect(
              push.checkEntered.isCompleted,
              isTrue,
              reason: 'Production pagination must call the async route fence',
            );
          }
          Future<void>? editing;
          race.WriteGate? gate;
          if (boundary == 'revoke') push.current = false;
          if (boundary.startsWith('newer tap')) push.tap(c, 'not-the-target');
          if (boundary == 'remove') await manager.deleteConnection(c.id);
          if (boundary.contains('edit')) {
            if (boundary == 'pending edit') {
              gate = race.WriteGate();
              secrets.gates.add(gate);
            }
            editing = manager.updateApiKey(
              c.id,
              boundary == 'same-value edit'
                  ? c.apiKey
                  : 'replacement-credential',
            );
            await _pump(tester);
            if (gate != null) expect(gate.entered.isCompleted, isTrue);
            if (gate == null) await editing;
          }
          if (boundary.contains('dispose')) {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          if (continuation != null) {
            continuation.complete(
              true,
            ); // Old authority returned after lifetime loss.
          } else {
            wire.releaseFirst();
          }
          await _pump(tester);
          try {
            if (boundary.startsWith('newer tap') ||
                boundary == 'unchanged authority' ||
                boundary == 'canonical root' ||
                boundary == 'mTLS identity') {
              final pages = wire.requests.where(
                (r) => r.$1.path == '/api/sessions',
              );
              expect(pages.map((r) => r.$1.queryParameters['offset']), [
                '0',
                boundary.startsWith('newer tap') ? '0' : '50',
                if (boundary == 'unchanged authority' ||
                    boundary == 'mTLS identity')
                  '100', // Exact untagged row needs a client-side end probe.
              ]);
              final chats = tester.widgetList<ChatScreen>(
                find.byType(ChatScreen, skipOffstage: false),
              );
              expect(chats.map((c) => c.session.id), [
                boundary == 'canonical root'
                    ? 'current-tip'
                    : boundary.startsWith('newer tap')
                    ? 'not-the-target'
                    : 'exact',
              ]);
            } else {
              expect(
                wire.requests,
                hasLength(1),
                reason:
                    'No captured credentials may be sent after invalidation',
              );
              expect(
                find.byType(ChatScreen, skipOffstage: false),
                findsNothing,
              );
            }
            expect(
              find.byType(WorkspaceScreen, skipOffstage: false),
              findsNothing,
            );
            expect(pendingNotificationApprovals.value, isEmpty);
            if (boundary == 'mTLS identity') {
              expect(
                wire.contexts.any(
                  (context) =>
                      context != null &&
                      !identical(context, SecurityContext.defaultContext),
                ),
                isTrue,
                reason:
                    'The real root factory must load the saved TLS identity',
              );
            }
          } finally {
            if (gate != null) gate.release.complete();
            if (editing != null) await editing;
            await tester.pumpWidget(const SizedBox.shrink());
            await _pump(tester);
          }
        }, createHttpClient: wire.createHttpClient);
      },
    );
  }
}
