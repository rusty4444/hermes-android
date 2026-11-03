import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/memory_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _graph({
  String profile = 'User prefers concise replies.',
  String notes = 'The workspace uses Dart.',
}) => {
  'memory': [
    {'source': 'memory', 'body': notes},
    {'source': 'profile', 'body': profile},
  ],
  'nodes': [
    {
      'kind': 'memory',
      'id': 'memory:memory:0:0123456789ab',
      'memorySource': 'memory',
    },
    {
      'kind': 'memory',
      'id': 'memory:profile:1:abcdef012345',
      'memorySource': 'profile',
    },
  ],
};

http.Response _json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

SavedConnection _connection({String profile = 'work'}) => SavedConnection(
  id: 'memory-screen',
  label: 'Test',
  host: 'fixture',
  port: 8642,
  apiKey: '',
  dashboardProxied: true,
  gatewayProfile: profile,
);

class _TrackingClient extends MockClient {
  _TrackingClient(super.handler);
  int closeCount = 0;
  @override
  void close() {
    closeCount++;
    super.close();
  }
}

Future<void> _mount(
  WidgetTester tester,
  http.Client client, {
  SavedConnection? connection,
  Locale locale = const Locale('en'),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MemoryScreen(
        key: const ValueKey('memory-screen'),
        connection: connection ?? _connection(),
        testHttpClient: client,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('opens on user facts and keeps agent notes in their own tab', (
    tester,
  ) async {
    final paths = <String>[];
    final client = _TrackingClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.queryParameters['profile'], 'work');
      paths.add(request.url.path);
      return _json(_graph());
    });
    await _mount(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('User prefers concise replies.'), findsOneWidget);
    expect(find.text('The workspace uses Dart.'), findsNothing);
    expect(find.text('Source: USER.md'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('MemPalace'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('memory_enabled'), findsNothing);
    expect(find.textContaining('config.yaml'), findsNothing);
    await tester.tap(find.text('Agent notes'));
    await tester.pumpAndSettle();
    expect(find.text('The workspace uses Dart.'), findsOneWidget);
    expect(find.text('Source: MEMORY.md'), findsOneWidget);
    expect(paths, ['/api/learning/graph']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(client.closeCount, 1);
  });

  testWidgets('an explicit empty list shows an honest empty state', (
    tester,
  ) async {
    var requests = 0;
    await _mount(
      tester,
      MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/learning/graph');
        return _json({'memory': [], 'nodes': []});
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('No memory entries'), findsOneWidget);
    expect(find.textContaining('after Hermes remembers them'), findsOneWidget);
    expect(find.textContaining('config.yaml'), findsNothing);
    expect(requests, 1);
    expect(
      tester.widget<ListView>(find.byType(ListView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
  });

  testWidgets(
    'unsupported and malformed responses are errors, not empty facts',
    (tester) async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/learning/graph');
        if (requests == 1) return http.Response('Not found', 404);
        if (requests == 2) {
          return _json({
            'memory': {'memory_enabled': true},
          });
        }
        return _json(_graph());
      });
      await _mount(tester, client);
      await tester.pumpAndSettle();
      expect(find.textContaining('Check the selected profile'), findsOneWidget);
      expect(find.text('No memory entries'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check the selected profile'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('User prefers concise replies.'), findsOneWidget);
      expect(requests, 3);
    },
  );

  testWidgets('server failures show a retry without leaking response bodies', (
    tester,
  ) async {
    await _mount(
      tester,
      MockClient((_) async => http.Response('private-debug-data', 500)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Check your dashboard connection'),
      findsOneWidget,
    );
    expect(find.textContaining('private-debug-data'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('refresh is single-flight and replaces stale saved facts', (
    tester,
  ) async {
    var requests = 0;
    final refreshed = Completer<http.Response>();
    await _mount(
      tester,
      MockClient((_) async {
        requests++;
        return requests == 1 ? _json(_graph()) : refreshed.future;
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Refresh',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(requests, 2);
    refreshed.complete(
      _json(_graph(profile: 'User prefers detailed replies.')),
    );
    await tester.pumpAndSettle();
    expect(find.text('User prefers detailed replies.'), findsOneWidget);
    expect(find.text('User prefers concise replies.'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'late ${fails ? 'error' : 'success'} after disposal is ignored',
      (tester) async {
        final response = Completer<http.Response>();
        final client = _TrackingClient((_) => response.future);
        await _mount(tester, client);
        await tester.pumpWidget(const SizedBox.shrink());
        if (fails) {
          response.completeError(StateError('late error'));
        } else {
          response.complete(_json(_graph()));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(client.closeCount, 1);
      },
    );

    testWidgets('profile change fences old ${fails ? 'error' : 'success'}', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final oldClient = _TrackingClient((_) => response.future);
      await _mount(tester, oldClient);
      await _mount(
        tester,
        MockClient((request) async {
          expect(request.url.queryParameters['profile'], 'other');
          return _json(_graph(profile: 'Facts from the other profile.'));
        }),
        connection: _connection(profile: 'other'),
      );
      await tester.pumpAndSettle();
      if (fails) {
        response.completeError(StateError('old profile error'));
      } else {
        response.complete(_json(_graph(profile: 'Old private profile fact.')));
      }
      await tester.pumpAndSettle();
      expect(find.text('Facts from the other profile.'), findsOneWidget);
      expect(find.text('Old private profile fact.'), findsNothing);
      expect(find.text('Failed to load memory'), findsNothing);
      expect(oldClient.closeCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a long fact loads its full text by exact server node ID', (
    tester,
  ) async {
    final preview = List.filled(1200, 'x').join();
    final full = '$preview THE END';
    var detailRequests = 0;
    await _mount(
      tester,
      MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/learning/node')) {
          detailRequests++;
          expect(request.url.queryParameters, {
            'id': 'memory:profile:1:abcdef012345',
            'profile': 'work',
          });
          return _json({
            'ok': true,
            'kind': 'memory',
            'id': 'memory:profile:1:abcdef012345',
            'content': full,
          });
        }
        return _json(_graph(profile: preview));
      }),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Read full fact'));
    await tester.pumpAndSettle();
    expect(find.text('Read full fact').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Read full fact'));
    await tester.pumpAndSettle();
    expect(find.text(full), findsOneWidget);
    expect(find.text('Preview truncated'), findsNothing);
    expect(detailRequests, 1);
  });

  testWidgets('a stale full-fact read preserves its labelled preview', (
    tester,
  ) async {
    final preview = List.filled(1200, 'x').join();
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/learning/node')) {
          return http.Response('stale', 404);
        }
        return _json(_graph(profile: preview));
      }),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Read full fact'));
    await tester.pumpAndSettle();
    expect(find.text('Read full fact').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Read full fact'));
    await tester.pumpAndSettle();
    expect(find.text(preview), findsOneWidget);
    expect(find.text('Preview truncated'), findsOneWidget);
    expect(find.textContaining('It may have changed'), findsOneWidget);
  });

  testWidgets('legacy long facts retain previews without unsafe expansion', (
    tester,
  ) async {
    final preview = List.filled(1200, 'x').join();
    final graph = _graph(profile: preview);
    for (final node in graph['nodes'] as List) {
      node['id'] = (node['id'] as String).split(':').take(3).join(':');
    }
    var requests = 0;
    await _mount(
      tester,
      MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/learning/graph');
        return _json(graph);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text(preview), findsOneWidget);
    expect(find.text('Preview truncated'), findsOneWidget);
    expect(find.text('Read full fact'), findsNothing);
    expect(
      find.textContaining('Full facts require a newer Hermes gateway'),
      findsOneWidget,
    );
    expect(requests, 1);
  });

  testWidgets('large text keeps title and profile within the toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      MockClient((_) async => _json(_graph())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    final toolbar = tester.getRect(find.byType(NavigationToolbar));
    final title = tester.getRect(find.text('Memory'));
    final profile = tester.getRect(find.text('work'));
    expect(title.top, greaterThanOrEqualTo(toolbar.top));
    expect(profile.bottom, lessThanOrEqualTo(toolbar.bottom));
  });

  testWidgets('all shipped locales fit narrow phones at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final locale in AppLocalizations.supportedLocales) {
      await _mount(
        tester,
        MockClient((_) async => _json(_graph())),
        locale: locale,
        textScale: 2,
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$locale');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
