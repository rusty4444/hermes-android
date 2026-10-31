import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/client_certificate.dart';
import '../models/session_search_hit.dart';
import 'tls_client_factory.dart';

/// Raised when a server-side session search cannot be completed.
///
/// Carries a human-readable reason so the session list can explain the failure
/// and offer local search instead of silently returning nothing.
class SessionSearchException implements Exception {
  final String message;

  const SessionSearchException(this.message);

  @override
  String toString() => message;
}

/// Queries the dashboard's full-text session search.
///
/// The Hermes dashboard exposes `GET /api/sessions/search`, which runs an FTS5
/// query across stored message content, applies prefix wildcards so partial
/// words match, and de-duplicates results by compression lineage. That is
/// strictly more capable than filtering the loaded list on device, which only
/// sees titles, previews, and model names.
///
/// This client owns HTTP only. Deciding *whether* to use it belongs to
/// [SessionSearchPreferences]; rendering belongs to the session list.
class SessionSearchClient {
  /// Upper bound accepted by the dashboard endpoint. Larger values are clamped
  /// server-side; clamping here keeps the request honest and the UI bounded.
  static const int maxLimit = 100;

  final http.Client _http;
  final String _baseUrl;
  final Future<Map<String, String>> Function() _authHeaders;

  SessionSearchClient({
    required String baseUrl,
    required Future<Map<String, String>> Function() headers,
    ClientCertificateConfig? clientCertificate,
    TlsClientFactory tlsClientFactory = const TlsClientFactory(),
    http.Client? httpClient,
  }) : // Trailing slashes would produce `//api/...` once joined below.
       _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _authHeaders = headers,
       // Reuse the connection's mTLS identity. Passing only the dashboard's
       // auth headers would send a cookie over a transport that cannot present
       // the client certificate, so a proxy enforcing mTLS would reject search
       // even though the session list loaded.
       _http =
           httpClient ?? tlsClientFactory.createRestClient(clientCertificate);

  /// Runs a full-text search and returns the matching sessions.
  ///
  /// Returns an empty list for a blank query rather than asking the server for
  /// everything. Throws [SessionSearchException] when the dashboard is
  /// unreachable, rejects the credentials, or answers with an unexpected shape
  /// — the caller surfaces that instead of showing an empty result set that
  /// would read as "no matches".
  Future<List<SessionSearchHit>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final safeLimit = limit.clamp(1, maxLimit);
    final uri = Uri.parse(
      '$_baseUrl/api/sessions/search',
    ).replace(queryParameters: {'q': trimmed, 'limit': '$safeLimit'});

    final http.Response response;
    try {
      response = await _http.get(uri, headers: await _authHeaders());
    } catch (error) {
      throw SessionSearchException('Could not reach the dashboard: $error');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SessionSearchException(
        'The dashboard rejected the saved credentials. Check the dashboard '
        'username and password for this connection.',
      );
    }
    if (response.statusCode == 404) {
      throw const SessionSearchException(
        'This dashboard does not expose session search. Update Hermes on the '
        'host, or switch back to on-device search.',
      );
    }
    if (response.statusCode != 200) {
      throw SessionSearchException(
        'Session search failed with HTTP ${response.statusCode}.',
      );
    }

    return _decodeHits(response.body);
  }

  List<SessionSearchHit> _decodeHits(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const SessionSearchException(
        'The dashboard returned a malformed search response.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const SessionSearchException(
        'The dashboard returned an unexpected search response.',
      );
    }

    final results = decoded['results'];
    if (results is! List) return const [];

    return results
        .whereType<Map<String, dynamic>>()
        .map(SessionSearchHit.fromJson)
        .toList(growable: false);
  }

  void close() => _http.close();
}
