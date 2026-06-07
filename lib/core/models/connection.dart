/// Connection model for remote Hermes Gateway API Server.
class NormalizedConnectionHost {
  final String host;
  final int port;
  final bool useHttps;

  const NormalizedConnectionHost({
    required this.host,
    required this.port,
    this.useHttps = false,
  });
}

class SavedConnection {
  final String id;
  final String label;
  final String host;
  final int port;
  final String apiKey;
  final bool useHttps;

  SavedConnection({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.apiKey,
    this.useHttps = false,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// Parses [input] as a URI and extracts host, port, and HTTPS flag.
  ///
  /// When the user provides an explicit port inside the URL (e.g.
  /// `https://example.com:8443`) that port is always used.
  ///
  /// When the URL has no explicit port, the [fallbackPort] is used.
  /// Callers should set [fallbackPort] to the value typed by the user in the
  /// Port field, so custom HTTPS ports (e.g. 8443) are preserved.
  static NormalizedConnectionHost normalizeHostAndPort(
    String input,
    int fallbackPort,
  ) {
    var raw = input.trim();
    final bool detectedHttps = raw.toLowerCase().startsWith('https://');
    if (raw.isEmpty) {
      return NormalizedConnectionHost(
        host: raw,
        port: fallbackPort,
        useHttps: detectedHttps,
      );
    }

    if (!raw.contains('://')) raw = 'http://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return NormalizedConnectionHost(
        host: input.trim(),
        port: fallbackPort,
        useHttps: detectedHttps,
      );
    }

    return NormalizedConnectionHost(
      host: uri.host,
      port: uri.hasPort ? uri.port : fallbackPort,
      useHttps: detectedHttps || (uri.scheme == 'https'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'host': host,
      'port': port,
      'api_key': apiKey,
      'use_https': useHttps,
    };
  }

  factory SavedConnection.fromMap(Map<String, dynamic> map) {
    return SavedConnection(
      id: map['id'] as String,
      label: map['label'] as String,
      host: map['host'] as String,
      port: (map['port'] as int?) ?? 8642,
      apiKey: (map['api_key'] as String?) ?? '',
      useHttps: (map['use_https'] as bool?) ?? false,
    );
  }
}
