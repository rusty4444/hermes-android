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

  /// Explicit dashboard port. When null, [dashboardPort] falls back to the
  /// default topology (see below). Set this when the dashboard is exposed on a
  /// non-default port.
  final int? dashboardPortOverride;

  /// Optional dashboard credentials for a basic-auth (password-protected)
  /// dashboard. When both are set, [DashboardClient] performs the
  /// `/auth/password-login` flow and authenticates with the resulting session
  /// cookie (same as hermes-desktop). When empty, it falls back to scraping the
  /// SPA session token, which only works on an insecure (open) dashboard.
  final String? dashboardUsername;
  final String? dashboardPassword;

  SavedConnection({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.apiKey,
    this.useHttps = false,
    this.dashboardPortOverride,
    this.dashboardUsername,
    this.dashboardPassword,
  });

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// Dashboard/API-server topology differs between local LAN and HTTPS proxy
  /// setups. Local Gateway chat connections normally use 8642 while the
  /// dashboard lives on 9119. HTTPS reverse-proxy deployments usually expose
  /// both API surfaces on the same external HTTPS port. An explicit
  /// [dashboardPortOverride] always wins.
  int get dashboardPort =>
      dashboardPortOverride ?? (useHttps ? port : 9119);

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

    final normalizedPort = uri.hasPort
        ? uri.port
        : detectedHttps && fallbackPort == 8642
        ? 443
        : fallbackPort;

    return NormalizedConnectionHost(
      host: uri.host,
      port: normalizedPort,
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
      'dashboard_port': dashboardPortOverride,
      'dashboard_username': dashboardUsername,
      'dashboard_password': dashboardPassword,
    };
  }

  factory SavedConnection.fromMap(Map<String, dynamic> map) {
    String? nonEmpty(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return SavedConnection(
      id: map['id'] as String,
      label: map['label'] as String,
      host: map['host'] as String,
      port: (map['port'] as int?) ?? 8642,
      apiKey: (map['api_key'] as String?) ?? '',
      useHttps: (map['use_https'] as bool?) ?? false,
      dashboardPortOverride: map['dashboard_port'] as int?,
      dashboardUsername: nonEmpty(map['dashboard_username']),
      dashboardPassword: nonEmpty(map['dashboard_password']),
    );
  }

  /// Returns a copy with the given fields replaced. Pass `clearDashboard*`
  /// flags to explicitly null out optional fields (since null args can't
  /// distinguish "leave unchanged" from "clear").
  SavedConnection copyWith({
    String? label,
    String? host,
    int? port,
    String? apiKey,
    bool? useHttps,
    int? dashboardPortOverride,
    String? dashboardUsername,
    String? dashboardPassword,
    bool clearDashboardPort = false,
    bool clearDashboardUsername = false,
    bool clearDashboardPassword = false,
  }) {
    return SavedConnection(
      id: id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      apiKey: apiKey ?? this.apiKey,
      useHttps: useHttps ?? this.useHttps,
      dashboardPortOverride: clearDashboardPort
          ? null
          : (dashboardPortOverride ?? this.dashboardPortOverride),
      dashboardUsername: clearDashboardUsername
          ? null
          : (dashboardUsername ?? this.dashboardUsername),
      dashboardPassword: clearDashboardPassword
          ? null
          : (dashboardPassword ?? this.dashboardPassword),
    );
  }
}
