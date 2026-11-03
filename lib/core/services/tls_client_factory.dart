import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/client_certificate.dart';

typedef HttpClientBuilder = HttpClient Function(SecurityContext context);

HttpClient _defaultHttpClientBuilder(SecurityContext context) =>
    HttpClient(context: context);

/// Builds the `dart:io` TLS layer used by every Hermes HTTP and WebSocket
/// transport.
///
/// Server trust deliberately stays at the platform default: there is no
/// `badCertificateCallback` here, so a proxy with an untrusted certificate is
/// still rejected. A configured client certificate must load successfully;
/// failures throw rather than retrying without it.
class TlsClientFactory {
  const TlsClientFactory({
    this.httpClientBuilder = _defaultHttpClientBuilder,
    this.trustedCertificatePaths = const <String>[],
  });

  final HttpClientBuilder httpClientBuilder;

  /// Extra PEM trust anchors (private CA certificates) to trust in addition to
  /// the platform roots. Empty by default: production server trust stays at
  /// the platform default.
  final List<String> trustedCertificatePaths;

  SecurityContext? securityContextFor(ClientCertificateConfig? config) {
    if (config == null) return null;
    try {
      final context = SecurityContext(withTrustedRoots: true);
      for (final path in trustedCertificatePaths) {
        context.setTrustedCertificates(path);
      }
      return context
        ..useCertificateChain(config.certificatePemPath)
        ..usePrivateKey(
          config.privateKeyPemPath,
          password: config.privateKeyPassword,
        );
    } catch (_) {
      // Do not include paths or key material in the user-visible error.
      throw const TlsClientConfigurationException(
        'The saved client certificate could not be loaded.',
      );
    }
  }

  HttpClient createHttpClient(ClientCertificateConfig? config) {
    final context = securityContextFor(config);
    // The app deliberately avoids pooled keep-alive sockets: dart:io can hold
    // a socket the server already closed and only notice on the next request,
    // which then hangs instead of reconnecting. Preserve that per-request
    // connection behaviour for both plain and mutually-authenticated TLS.
    return httpClientBuilder(context ?? SecurityContext.defaultContext)
      ..idleTimeout = Duration.zero;
  }

  http.Client createRestClient(ClientCertificateConfig? config) {
    return IOClient(createHttpClient(config));
  }
}

class TlsClientConfigurationException implements Exception {
  final String message;

  const TlsClientConfigurationException(this.message);

  @override
  String toString() => message;
}
