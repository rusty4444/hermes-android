import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/connection.dart';

/// Raised for every backup failure. The message is intentionally generic and
/// never carries platform errors or secret material, so it can be surfaced
/// directly in the UI.
class ConfigBackupException implements Exception {
  final String message;

  const ConfigBackupException(this.message);

  @override
  String toString() => message;
}

/// A client identity carried inside an encrypted configuration backup.
///
/// The PEM contents live here (not in the connection metadata) so a backup can
/// restore mTLS on another device. This object is only ever serialized inside
/// [ConfigBackup], which [ConfigBackupCodec] encrypts.
class ClientCertificateBackup {
  final String label;
  final String certificatePem;
  final String privateKeyPem;

  /// Password for an encrypted PEM key, when the key itself is encrypted.
  final String? password;

  const ClientCertificateBackup({
    required this.label,
    required this.certificatePem,
    required this.privateKeyPem,
    this.password,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'certificate_pem': certificatePem,
    'private_key_pem': privateKeyPem,
    if (password != null) 'private_key_password': password,
  };

  factory ClientCertificateBackup.fromJson(Map<String, dynamic> json) {
    final password = json['private_key_password'] as String?;
    return ClientCertificateBackup(
      label: json['label'] as String,
      certificatePem: json['certificate_pem'] as String,
      privateKeyPem: json['private_key_pem'] as String,
      password: password,
    );
  }
}

/// A complete, portable snapshot of what the user configured on this device:
/// every saved connection (including its secrets) plus the non-secret app
/// preferences.
///
/// This object is only ever written to disk through [ConfigBackupCodec], which
/// encrypts it. It must never be serialized to an unprotected file.
class ConfigBackup {
  static const String format = 'hermes-android-config';

  /// v2 adds optional mTLS client identities ([clientCertificates]).
  static const int currentVersion = 2;

  final DateTime createdAt;
  final String appVersion;
  final List<SavedConnection> connections;
  final Map<String, Object> preferences;

  /// Client certificate/key PEM contents keyed by connection id.
  final Map<String, ClientCertificateBackup> clientCertificates;

  ConfigBackup({
    required this.createdAt,
    required this.appVersion,
    required this.connections,
    required this.preferences,
    this.clientCertificates = const <String, ClientCertificateBackup>{},
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'format': format,
      'version': currentVersion,
      'created_at': createdAt.toUtc().toIso8601String(),
      'app_version': appVersion,
      'connections': connections.map(_connectionToJson).toList(),
      if (clientCertificates.isNotEmpty)
        'client_certificates': clientCertificates.map(
          (id, certificate) => MapEntry(id, certificate.toJson()),
        ),
      'preferences': preferences.map(
        (key, value) => MapEntry(key, _preferenceToJson(value)),
      ),
    };
  }

  factory ConfigBackup.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const ConfigBackupException(
        'This file is not a Hermes configuration backup.',
      );
    }
    final version = json['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      throw const ConfigBackupException(
        'This backup was made by a newer version of the app and cannot be '
        'imported.',
      );
    }

    try {
      final rawConnections = json['connections'] as List<dynamic>;
      final rawPreferences =
          (json['preferences'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final rawCertificates =
          (json['client_certificates'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final certificates = rawCertificates.map(
        (id, value) => MapEntry(
          id,
          ClientCertificateBackup.fromJson(value as Map<String, dynamic>),
        ),
      );
      final connections = rawConnections
          .map((entry) => _connectionFromJson(entry as Map<String, dynamic>))
          .toList();
      // Explicitly reject an unreadable restoration instead of claiming a
      // complete restore that silently dropped mTLS.
      for (final entry in rawConnections) {
        final map = entry as Map<String, dynamic>;
        if (map['requires_client_certificate'] == true &&
            !certificates.containsKey(map['id'])) {
          throw const ConfigBackupException(
            'This backup claims a client certificate for a connection but '
            'does not contain it, so a complete restore is not possible.',
          );
        }
      }

      return ConfigBackup(
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        appVersion: (json['app_version'] as String?) ?? 'unknown',
        connections: connections,
        clientCertificates: certificates,
        preferences: rawPreferences.map(
          (key, value) =>
              MapEntry(key, _preferenceFromJson(value as Map<String, dynamic>)),
        ),
      );
    } on ConfigBackupException {
      rethrow;
    } catch (_) {
      throw const ConfigBackupException(
        'This backup file is damaged and could not be read.',
      );
    }
  }

  static Map<String, dynamic> _connectionToJson(SavedConnection connection) {
    return <String, dynamic>{
      'id': connection.id,
      'label': connection.label,
      'host': connection.host,
      'port': connection.port,
      'api_key': connection.apiKey,
      'use_https': connection.useHttps,
      'gateway_prefix': connection.gatewayPrefix,
      'dashboard_prefix': connection.dashboardPrefix,
      'dashboard_proxied': connection.dashboardProxied,
      'desktop_gateway_url': connection.desktopGatewayUrl,
      'dashboard_port': connection.dashboardPortOverride,
      'dashboard_username': connection.dashboardUsername,
      'dashboard_password': connection.dashboardPassword,
      'gateway_profile': connection.gatewayProfile,
      // Paths are device-specific and meaningless on the target device; the
      // PEM contents travel in `client_certificates`. The marker lets a
      // hand-edited file fail closed instead of silently dropping mTLS.
      if (connection.clientCertificate != null)
        'requires_client_certificate': true,
    };
  }

  static SavedConnection _connectionFromJson(Map<String, dynamic> map) {
    String? nonEmpty(Object? value) {
      final text = (value as String?)?.trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    return SavedConnection(
      id: map['id'] as String,
      label: map['label'] as String,
      host: map['host'] as String,
      port: (map['port'] as int?) ?? 8642,
      apiKey: (map['api_key'] as String?) ?? '',
      useHttps: (map['use_https'] as bool?) ?? false,
      gatewayPrefix: nonEmpty(map['gateway_prefix']),
      dashboardPrefix: nonEmpty(map['dashboard_prefix']),
      dashboardProxied: (map['dashboard_proxied'] as bool?) ?? false,
      desktopGatewayUrl: nonEmpty(map['desktop_gateway_url']),
      dashboardPortOverride: map['dashboard_port'] as int?,
      dashboardUsername: nonEmpty(map['dashboard_username']),
      dashboardPassword: nonEmpty(map['dashboard_password']),
      gatewayProfile: nonEmpty(map['gateway_profile']),
    );
  }

  /// Preferences are tagged with their runtime type. Without the tag a Dart
  /// `int` would come back as a `double` (or vice versa) after the JSON round
  /// trip and `SharedPreferences` would then reject the write.
  static Map<String, dynamic> _preferenceToJson(Object value) {
    if (value is bool) {
      return <String, dynamic>{'type': 'bool', 'value': value};
    }
    if (value is int) {
      return <String, dynamic>{'type': 'int', 'value': value};
    }
    if (value is double) {
      return <String, dynamic>{'type': 'double', 'value': value};
    }
    if (value is String) {
      return <String, dynamic>{'type': 'string', 'value': value};
    }
    if (value is List<String>) {
      return <String, dynamic>{'type': 'string_list', 'value': value};
    }
    throw const ConfigBackupException(
      'A saved preference has an unsupported type and cannot be exported.',
    );
  }

  static Object _preferenceFromJson(Map<String, dynamic> entry) {
    final type = entry['type'];
    final value = entry['value'];
    switch (type) {
      case 'bool':
        if (value is bool) return value;
        break;
      case 'int':
        if (value is int) return value;
        break;
      case 'double':
        if (value is num) return value.toDouble();
        break;
      case 'string':
        if (value is String) return value;
        break;
      case 'string_list':
        if (value is List) {
          return value.map((item) => item as String).toList();
        }
        break;
    }
    throw const ConfigBackupException(
      'This backup file is damaged and could not be read.',
    );
  }
}

/// Encrypts and decrypts a [ConfigBackup] with a user-supplied passphrase.
///
/// The exported file holds API keys and dashboard passwords, so it is always
/// encrypted: PBKDF2-HMAC-SHA256 derives a key from the passphrase, and
/// AES-256-GCM provides confidentiality plus authentication. A tampered file
/// fails the MAC check and is rejected instead of being partially imported.
class ConfigBackupCodec {
  static const String envelopeFormat = 'hermes-android-config-encrypted';
  static const int envelopeVersion = 1;
  static const int defaultIterations = 210000;
  static const int _maxIterations = 2000000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;

  static final Random _random = Random.secure();

  static Future<String> encrypt(
    ConfigBackup backup, {
    required String passphrase,
    int iterations = defaultIterations,
  }) async {
    if (passphrase.trim().isEmpty) {
      throw const ConfigBackupException(
        'Choose a passphrase — the backup contains your API keys.',
      );
    }
    if (iterations < 1 || iterations > _maxIterations) {
      throw const ConfigBackupException(
        'The backup could not be protected safely.',
      );
    }

    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final secretKey = await _deriveKey(passphrase, salt, iterations);
    final plaintext = utf8.encode(jsonEncode(backup.toJson()));

    final SecretBox box;
    try {
      box = await AesGcm.with256bits().encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
      );
    } catch (_) {
      throw const ConfigBackupException(
        'The backup could not be protected safely.',
      );
    }

    return jsonEncode(<String, dynamic>{
      'format': envelopeFormat,
      'version': envelopeVersion,
      'kdf': <String, dynamic>{
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'cipher': <String, dynamic>{
        'algorithm': 'aes-256-gcm',
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      },
    });
  }

  static Future<ConfigBackup> decrypt(
    String armored, {
    required String passphrase,
  }) async {
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(armored) as Map<String, dynamic>;
    } catch (_) {
      throw const ConfigBackupException(
        'This file is not a Hermes configuration backup.',
      );
    }

    if (envelope['format'] != envelopeFormat) {
      throw const ConfigBackupException(
        'This file is not a Hermes configuration backup.',
      );
    }
    final version = envelope['version'];
    if (version is! int || version < 1 || version > envelopeVersion) {
      throw const ConfigBackupException(
        'This backup was made by a newer version of the app and cannot be '
        'imported.',
      );
    }

    final int iterations;
    final List<int> salt;
    final List<int> nonce;
    final List<int> ciphertext;
    final List<int> mac;
    try {
      final kdf = envelope['kdf'] as Map<String, dynamic>;
      final cipher = envelope['cipher'] as Map<String, dynamic>;
      if (kdf['algorithm'] != 'pbkdf2-hmac-sha256' ||
          cipher['algorithm'] != 'aes-256-gcm') {
        throw const ConfigBackupException(
          'This backup uses an unsupported encryption scheme.',
        );
      }
      iterations = kdf['iterations'] as int;
      salt = base64Decode(kdf['salt'] as String);
      nonce = base64Decode(cipher['nonce'] as String);
      ciphertext = base64Decode(cipher['ciphertext'] as String);
      mac = base64Decode(cipher['mac'] as String);
    } on ConfigBackupException {
      rethrow;
    } catch (_) {
      throw const ConfigBackupException(
        'This backup file is damaged and could not be read.',
      );
    }

    // An untrusted file must never be able to pin the UI thread by asking for
    // an unbounded amount of key-stretching work.
    if (iterations < 1 || iterations > _maxIterations) {
      throw const ConfigBackupException(
        'This backup file is damaged and could not be read.',
      );
    }

    final secretKey = await _deriveKey(passphrase, salt, iterations);

    final List<int> plaintext;
    try {
      plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
    } catch (_) {
      // Wrong passphrase and tampered ciphertext are indistinguishable here by
      // design — both fail the GCM authentication tag.
      throw const ConfigBackupException(
        'Wrong passphrase, or this backup file has been altered.',
      );
    }

    try {
      return ConfigBackup.fromJson(
        jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
      );
    } on ConfigBackupException {
      rethrow;
    } catch (_) {
      throw const ConfigBackupException(
        'This backup file is damaged and could not be read.',
      );
    }
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
    int iterations,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
