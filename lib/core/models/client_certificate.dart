import 'dart:io';

/// A client certificate/key pair used for HTTP mutual TLS.
///
/// The paths point into app-private storage. Key material itself is never
/// copied into this model or into preferences; only the on-disk paths are
/// stored there.
///
/// [privateKeyPassword] is intentionally **not** serialized by [toJson]: it is
/// a runtime-only value that [ConnectionManager] keeps in the platform secure
/// store. [fromJson] still accepts a legacy `private_key_password` field so an
/// existing install can migrate it out of plain preferences.
class ClientCertificateConfig {
  /// Human-readable name shown in the connection editor (usually the imported
  /// file name or the certificate's subject CN).
  final String label;

  /// PEM chain for `SecurityContext.useCertificateChain`: the leaf certificate
  /// first, followed by any intermediates/root supplied with it.
  final String certificatePemPath;

  /// PEM private key for `SecurityContext.usePrivateKey`.
  final String privateKeyPemPath;

  /// Password protecting the PEM private key, when it is encrypted.
  ///
  /// Runtime-only: persisted in [CredentialStore], never in preferences.
  final String? privateKeyPassword;

  const ClientCertificateConfig({
    required this.label,
    required this.certificatePemPath,
    required this.privateKeyPemPath,
    this.privateKeyPassword,
  });

  /// Directory holding this identity's PEM files.
  String get directoryPath => File(certificatePemPath).parent.path;

  ClientCertificateConfig copyWith({
    String? label,
    String? certificatePemPath,
    String? privateKeyPemPath,
    String? privateKeyPassword,
    bool clearPrivateKeyPassword = false,
  }) {
    return ClientCertificateConfig(
      label: label ?? this.label,
      certificatePemPath: certificatePemPath ?? this.certificatePemPath,
      privateKeyPemPath: privateKeyPemPath ?? this.privateKeyPemPath,
      privateKeyPassword: clearPrivateKeyPassword
          ? null
          : (privateKeyPassword ?? this.privateKeyPassword),
    );
  }

  /// Non-secret metadata only. The key password lives in the credential store.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'certificate_pem_path': certificatePemPath,
    'private_key_pem_path': privateKeyPemPath,
  };

  factory ClientCertificateConfig.fromJson(Map<String, dynamic> json) {
    // A legacy build wrote `private_key_password` here. Accept it so the
    // migration in ConnectionManager can move it to the secure store; it is
    // never written back by toJson.
    final password = json['private_key_password'] as String?;
    return ClientCertificateConfig(
      label: json['label'] as String,
      certificatePemPath: json['certificate_pem_path'] as String,
      privateKeyPemPath: json['private_key_pem_path'] as String,
      privateKeyPassword: password == null || password.isEmpty
          ? null
          : password,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClientCertificateConfig &&
        other.label == label &&
        other.certificatePemPath == certificatePemPath &&
        other.privateKeyPemPath == privateKeyPemPath &&
        other.privateKeyPassword == privateKeyPassword;
  }

  @override
  int get hashCode => Object.hash(
    label,
    certificatePemPath,
    privateKeyPemPath,
    privateKeyPassword,
  );
}
