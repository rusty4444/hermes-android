import 'dart:async';
import 'dart:convert';

import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fallback_config_contract.dart';

final fallbackConnection = SavedConnection(
  id: 'fallback',
  label: 'Research',
  host: 'example.test',
  port: 8642,
  apiKey: 'unused-api-key',
  gatewayProfile: 'research & development',
  dashboardPrefix: '/proxy',
  dashboardProxied: true,
);

class FallbackFixture {
  Map<String, dynamic> config = {'fallback_providers': <dynamic>[]};
  final requests = <http.Request>[];
  final writes = <Map<String, dynamic>>[];
  final modelWrites = <Map<String, dynamic>>[];
  bool accepted = true;
  bool persist = true;
  bool failDiscovery = false;
  int configStatus = 200;
  Object schema = fallbackConfigSchema();
  int schemaStatus = 200;
  Completer<http.Response>? heldSchema;
  int schemaReads = 0;
  void Function(Map<String, dynamic>)? corrupt;
  Completer<http.Response>? heldInitial;
  Completer<http.Response>? heldWrite;
  Completer<http.Response>? heldReadback;
  Completer<http.Response>? heldModelWrite;
  Completer<http.Response>? heldMainInfo;
  int configReads = 0;
  final String profile;
  FallbackFixture({this.profile = 'research & development'});

  http.Response response(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  late final DashboardClient client = DashboardClient.fromConnection(
    fallbackConnection.copyWith(gatewayProfile: profile),
    httpClient: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/openapi.json')) {
        schemaReads++;
        if (heldSchema != null) return heldSchema!.future;
        return response(schema, schemaStatus);
      }
      if (path.endsWith('/config')) {
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(body);
          if (accepted && persist) {
            config = {...config, ...body['config'] as Map<String, dynamic>};
            corrupt?.call(config);
          }
          return heldWrite != null
              ? heldWrite!.future
              : response({'ok': accepted});
        }
        configReads++;
        if (heldInitial != null && writes.isEmpty) return heldInitial!.future;
        if (heldReadback != null && writes.isNotEmpty) {
          return heldReadback!.future;
        }
        return response(
          configStatus == 200 ? config : {'detail': 'never-show-server-secret'},
          configStatus,
        );
      }
      if (path.endsWith('/options')) {
        if (failDiscovery) {
          return response({'detail': 'never-show-server-secret'}, 500);
        }
        return response({
          'providers': [
            {
              'slug': 'openai',
              'models': ['old', 'new'],
            },
            {
              'slug': 'other',
              'models': ['other-1', 'other-2'],
            },
            {
              'slug': 'named-secret-route',
              'models': ['private'],
              'api_url': 'https://private.invalid/v1',
            },
            {
              'slug': 'user-defined',
              'models': ['private'],
              'is_user_defined': true,
            },
          ],
        });
      }
      if (path.endsWith('/set')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        modelWrites.add(body);
        return heldModelWrite != null
            ? heldModelWrite!.future
            : response({'ok': false});
      }
      if (path.endsWith('/info')) {
        if (heldMainInfo != null) return heldMainInfo!.future;
        return response({'provider': 'openai', 'model': 'old'});
      }
      if (path.endsWith('/custom-endpoints')) {
        return response({
          'current': {'provider': 'openai', 'model': 'old', 'base_url': ''},
          'endpoints': [],
        });
      }
      if (path.endsWith('/auxiliary')) {
        return response({
          'tasks': [
            {
              'task': 'vision',
              'label': 'Vision',
              'provider': 'auto',
              'model': '',
            },
          ],
        });
      }
      return response({}, 404);
    }),
  );
}
