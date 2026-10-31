import 'dart:convert';

import 'connection_manager.dart';

/// All requests use the existing dashboard login/cookie/proxy/token ladder.
/// Subscriber keys come exclusively from the native connector, never VAPID.
class MobilePushApi {
  MobilePushApi(this.client);
  final DashboardClient client;
  static const prefix = 'plugins/mobile-push';

  static bool validIdentifier(Object? value, {int maxLength = 200}) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= maxLength &&
      RegExp(r'[A-Za-z0-9_.:@-]+').stringMatch(value) == value;

  /// Missing scope is the legacy exact allowlist, never an implicit upgrade.
  static String sessionScope(Map<String, dynamic> state) {
    final scope = state['session_scope'] ?? 'explicit';
    final ids = state['sessions'];
    final valid =
        ids is List &&
        switch (scope) {
          'authorized' => ids.isEmpty,
          'explicit' =>
            ids.isNotEmpty && ids.length <= 128 && ids.every(validIdentifier),
          _ => false,
        };
    if (!valid) {
      throw const FormatException('Invalid sealed push session scope.');
    }
    return scope as String;
  }

  // Explicit on EVERY operation, including retries/revokes/event reads. Merely
  // constructing DashboardClient(gatewayProfile: ...) does not scope generic HTTP.
  Map<String, String> _query([Map<String, String> extra = const {}]) => {
    'profile': ?client.gatewayProfile,
    ...extra,
  };

  /// Validate every supplied token before deduplication; never trim/drop one.
  static List<String> validateSessionIds(List<String> sessions) {
    if (sessions.isEmpty ||
        sessions.length > 128 ||
        sessions.any((id) => !validIdentifier(id))) {
      throw StateError(
        'Select 1–128 durable session IDs, each 1–200 ASCII characters using '
        'only letters, digits, _ . : @ or -. Remove blank IDs and whitespace.',
      );
    }
    return sessions.toSet().toList();
  }

  Future<Map<String, dynamic>> capabilities({bool authorized = false}) async {
    final result = await client.apiGet(
      '$prefix/capabilities',
      queryParameters: _query(),
    );
    final key = result['vapid_public_key'];
    if (result['schema'] != 1 ||
        result['registration_fence'] != 1 ||
        result['enabled'] != true ||
        result['transports'] is! List ||
        !(result['transports'] as List).contains('webpush') ||
        key is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{87}$').hasMatch(key)) {
      throw const FormatException('Mobile push is unavailable on this server.');
    }
    final bytes = base64Url.decode(base64Url.normalize(key));
    if (bytes.length != 65 || bytes.first != 4) {
      throw const FormatException('Invalid server VAPID public key.');
    }
    if (authorized &&
        (result['session_scope_modes'] is! List ||
            !(result['session_scope_modes'] as List).contains('authorized'))) {
      throw const FormatException(
        'This server needs an updated mobile-push plugin for automatic subscriptions.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> state) async {
    final scope = sessionScope(state);
    return client.apiPut(
      '$prefix/registrations/${Uri.encodeComponent(state['installation'] as String)}',
      queryParameters: _query(),
      body: {
        'endpoint': state['endpoint'],
        'keys': state['keys'],
        'registration_nonce': state['nonce'],
        'registration_revision': state['revision'],
        'event_kinds': const [
          'turn_done',
          'turn_error',
          'input',
          'input_resolved',
        ],
        if (scope == 'authorized')
          'session_scope': 'authorized'
        else
          'session_ids': state['sessions'],
      },
    );
  }

  Future<Map<String, dynamic>> confirm(
    String installation,
    int generation,
    String challenge,
  ) => client.apiPost(
    '$prefix/registrations/${Uri.encodeComponent(installation)}/confirm',
    queryParameters: _query(),
    body: {'generation': generation, 'challenge': challenge},
  );
  Future<void> revoke(String installation) => client.apiDelete(
    '$prefix/registrations/${Uri.encodeComponent(installation)}',
    queryParameters: _query(),
  );

  Future<Map<String, dynamic>> events(
    String cursor, {
    Map<String, dynamic>? state,
  }) async {
    final authorized = state != null && sessionScope(state) == 'authorized';
    final installation = state?['installation'];
    final generation = state?['generation'];
    if (authorized &&
        (installation is! String || generation is! int || generation <= 0)) {
      throw const FormatException('Invalid push event authority.');
    }
    final response = await client.apiGet(
      '$prefix/events',
      queryParameters: _query({
        'after': cursor,
        'limit': '100',
        if (authorized) ...{
          'installation_id': installation as String,
          'generation': '$generation',
        },
      }),
    );
    // Every page is checked before accepting its first event.
    if (authorized &&
        (response['installation_id'] != installation ||
            response['generation'] is! int ||
            response['generation'] != generation ||
            response['session_scope'] != 'authorized')) {
      throw const FormatException('Push event authority mismatch.');
    }
    return response;
  }
}
