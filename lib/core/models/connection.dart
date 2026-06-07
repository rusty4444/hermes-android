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
      port: uri.hasPort
          ? uri.port
          : (detectedHttps || uri.scheme == 'https' ? 443 : fallbackPort),
      useHttps: detectedHttps || (uri.scheme == 'https'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'host': host,
    'port': port,
    'api_key': apiKey,
    'use_https': useHttps,
  };

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
