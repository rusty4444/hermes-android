/// Public display fields only. Never retain token previews or auth-store data.
library;

enum OAuthProviderDisabledReason { hostCliRequired }

enum OAuthTransportUnavailableReason { httpsRequired, authenticationRequired }

class OAuthProvider {
  final String id;
  final String name;
  final String flow;
  final bool loggedIn;
  final bool statusKnown;
  const OAuthProvider({
    required this.id,
    required this.name,
    required this.flow,
    this.loggedIn = false,
    this.statusKnown = false,
  });

  static bool validId(String value) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value);

  factory OAuthProvider.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final flow = json['flow'];
    if (id is! String ||
        !validId(id) ||
        name is! String ||
        name.isEmpty ||
        flow is! String) {
      throw const FormatException('Invalid provider catalog');
    }
    final status = json['status'];
    return OAuthProvider(
      id: id,
      name: name,
      flow: flow,
      loggedIn: status is Map && status['logged_in'] == true,
      statusKnown: status is Map && status['logged_in'] is bool,
    );
  }

  OAuthProviderDisabledReason? get disabledReason => flow == 'device_code'
      ? null
      : OAuthProviderDisabledReason.hostCliRequired;
}

Uri? safeProviderOAuthUrl(String value) {
  // No whitespace/control-character normalization or non-HTTPS schemes.
  if (value.contains(RegExp(r'[\s\x00-\x1f\x7f\\]'))) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

class OAuthDeviceSession {
  final String id;
  final String userCode;
  final Uri verificationUrl;
  final Duration lifetime;
  final Duration pollInterval;
  const OAuthDeviceSession({
    required this.id,
    required this.userCode,
    required this.verificationUrl,
    required this.lifetime,
    required this.pollInterval,
  });

  factory OAuthDeviceSession.fromJson(Map<String, dynamic> json) {
    final id = json['session_id'];
    final code = json['user_code'];
    final url = json['verification_url'];
    final expires = json['expires_in'];
    final interval = json['poll_interval'];
    final uri = url is String ? safeProviderOAuthUrl(url) : null;
    if (id is! String ||
        !validSessionId(id) ||
        code is! String ||
        code.isEmpty ||
        code.length > 256 ||
        uri == null ||
        json['flow'] != 'device_code' ||
        expires is! num ||
        !expires.isFinite ||
        expires <= 0 ||
        interval is! num ||
        !interval.isFinite ||
        interval <= 0) {
      throw const FormatException('Unsupported OAuth session');
    }
    return OAuthDeviceSession(
      id: id,
      userCode: code,
      verificationUrl: uri,
      // Host sessions have a 15-minute TTL. Never outlive it locally.
      lifetime: Duration(milliseconds: (expires.clamp(0, 900) * 1000).ceil()),
      pollInterval: Duration(milliseconds: (interval * 1000).ceil()),
    );
  }

  static bool validSessionId(String id) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,256}$').hasMatch(id);
}

enum OAuthLoginStatus { pending, approved, denied, expired, cancelled, error }

/// Historical Nous session email, NOT proof of the current host account.
/// Repeated approved polls replay this value even after account replacement.
/// Catalog source labels, token previews and usage are not account identities.
String? oauthAccountEmail(String providerId, Map<String, dynamic> poll) {
  if (providerId != 'nous') return null;
  final value = poll['account_email'];
  if (value is! String ||
      value.isEmpty ||
      value.length > 320 ||
      value.trim() != value ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return null;
  }
  return value;
}

OAuthLoginStatus parseOAuthStatus(Map<String, dynamic> json, String sessionId) {
  if (json['session_id'] != sessionId) {
    throw const FormatException('OAuth session mismatch');
  }
  return switch (json['status']) {
    'pending' => OAuthLoginStatus.pending,
    'approved' => OAuthLoginStatus.approved,
    'denied' => OAuthLoginStatus.denied,
    'expired' => OAuthLoginStatus.expired,
    'cancelled' => OAuthLoginStatus.cancelled,
    'error' => OAuthLoginStatus.error,
    _ => throw const FormatException('Unknown OAuth status'),
  };
}
