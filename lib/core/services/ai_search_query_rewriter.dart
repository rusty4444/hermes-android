import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/client_certificate.dart';
import 'tls_client_factory.dart';

/// Rewrites a natural-language question into a short lexical query through
/// Hermes' lightweight provider endpoint.
///
/// Provider credentials stay on the Hermes host. The endpoint does not create
/// an agent or session, load memories, or expose tools, so inexpensive models
/// receive only a tiny fixed prompt plus the user's query.
class AiSearchQueryRewriter {
  final http.Client _http;
  final String _baseUrl;
  final String _apiKey;

  AiSearchQueryRewriter({
    required String baseUrl,
    required String apiKey,
    String pathPrefix = '',
    ClientCertificateConfig? clientCertificate,
    TlsClientFactory tlsClientFactory = const TlsClientFactory(),
    http.Client? httpClient,
  }) : _baseUrl = _joinBaseUrl(baseUrl, pathPrefix),
       _apiKey = apiKey.trim(),
       // The rewrite endpoint sits behind the same reverse proxy as chat and
       // search; an mTLS-enforcing proxy must receive the client certificate
       // here too.
       _http =
           httpClient ?? tlsClientFactory.createRestClient(clientCertificate);

  Future<String> rewrite({
    required String query,
    required String provider,
    required String model,
  }) async {
    final original = query.trim();
    if (original.isEmpty) return '';
    if (provider.trim().isEmpty || model.trim().isEmpty) {
      throw const AiSearchRewriteException(
        'Choose an AI search model before using AI search.',
      );
    }

    late http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_baseUrl/v1/search/rewrite'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'query': original,
              'provider': provider.trim(),
              'model': model.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // AI-assisted rewriting is an enhancement, never a dependency of search.
      // A disconnected host, timeout, or provider outage degrades to the user's
      // original full-text query rather than turning Search into an error page.
      return original;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiSearchRewriteException(
        'The Hermes API rejected the saved API key.',
      );
    }
    if (response.statusCode == 404 ||
        response.statusCode == 429 ||
        response.statusCode >= 500) {
      return original;
    }
    if (response.statusCode != 200) {
      throw AiSearchRewriteException(
        _errorMessage(response.body) ??
            'AI query rewrite failed with HTTP ${response.statusCode}.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('response is not an object');
      }
      final rewritten = decoded['query']?.toString().trim() ?? '';
      if (rewritten.isEmpty) {
        throw const AiSearchRewriteException(
          'The selected model returned no usable search query.',
        );
      }
      return rewritten;
    } on AiSearchRewriteException {
      rethrow;
    } catch (_) {
      throw const AiSearchRewriteException(
        'Hermes returned a malformed AI rewrite response.',
      );
    }
  }

  static String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is! Map) return null;
      final message = error['message']?.toString().trim();
      return message == null || message.isEmpty ? null : message;
    } catch (_) {
      return null;
    }
  }

  static String _joinBaseUrl(String baseUrl, String prefix) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPrefix = prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return cleanPrefix.isEmpty ? base : '$base/$cleanPrefix';
  }

  void close() => _http.close();
}

class AiSearchRewriteException implements Exception {
  final String message;

  const AiSearchRewriteException(this.message);

  @override
  String toString() => message;
}
