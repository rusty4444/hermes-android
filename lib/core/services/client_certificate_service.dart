import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pkcs12_parser/pkcs12_parser.dart';
import 'package:uuid/uuid.dart';

import '../models/client_certificate.dart';
import 'tls_client_factory.dart';

/// A certificate import failure with a message that is safe to show to the
/// user. Parser internals stay out of the UI; the actionable distinction is
/// "wrong password" versus "this file cannot be read".
class ClientCertificateImportException implements Exception {
  final String message;

  /// True when the failure may be resolved by supplying (or correcting) the
  /// container/key password. The dialog keeps the picked bytes in that case so
  /// the user never has to re-pick the file, and re-runs the import when the
  /// password field changes.
  final bool passwordRelated;

  const ClientCertificateImportException(
    this.message, {
    this.passwordRelated = false,
  });

  @override
  String toString() => message;
}

/// Owns selected or newly materialized files until an editor/import settles.
///
/// Only directory paths are shared across service instances. Registration occurs
/// before filesystem creation/rename, so a collector cannot observe an unleased
/// half-written identity. Closing joins admitted work before releasing paths.
class ClientCertificateFileLease {
  static final _zoneKey = Object();
  static final _references = <String, int>{};

  final _directories = <String>{};
  int _operations = 0;
  bool _closed = false;
  Completer<void>? _closing;

  Future<T> run<T>(Future<T> Function() action) async {
    if (_closed) throw StateError('Certificate file owner is closed.');
    _operations++;
    try {
      return await runZoned(action, zoneValues: {_zoneKey: this});
    } finally {
      _operations--;
      _releaseIfClosed();
    }
  }

  /// Completes after close and all admitted work have released their paths.
  Future<void> get whenClosed => _closed && _operations == 0
      ? Future<void>.value()
      : (_closing ??= Completer<void>()).future;

  /// Idempotent; disposal cannot release files beneath an admitted save/import.
  Future<void> close() {
    _closed = true;
    _releaseIfClosed();
    if (_operations == 0) return Future<void>.value();
    return (_closing ??= Completer<void>()).future;
  }

  void _retain(String directory) {
    if (_closed && _operations == 0) {
      throw StateError('Certificate file owner is closed.');
    }
    final path = ClientCertificateService._normalize(directory);
    if (_directories.add(path)) {
      _references[path] = (_references[path] ?? 0) + 1;
    }
  }

  /// Pins an existing selection synchronously, before validation can suspend.
  /// Repeated retention by this owner does not accumulate references.
  void retainIdentity(ClientCertificateConfig config) {
    if (_closed) throw StateError('Certificate file owner is closed.');
    _retain(config.directoryPath);
  }

  /// Drops a replaced pick without retaining every abandoned path for the
  /// lifetime of a long-lived editor. This does not delete any files.
  void releaseIdentity(ClientCertificateConfig config) =>
      _releaseDirectory(config.directoryPath);

  void _releaseDirectory(String directory) {
    final path = ClientCertificateService._normalize(directory);
    if (_directories.remove(path)) {
      final remaining = _references[path]! - 1;
      if (remaining == 0) {
        _references.remove(path);
      } else {
        _references[path] = remaining;
      }
    }
  }

  void _releaseIfClosed() {
    if (!_closed || _operations != 0) return;
    for (final path in _directories.toList()) {
      _releaseDirectory(path);
    }
    final closing = _closing;
    _closing = null;
    closing?.complete();
  }

  static ClientCertificateFileLease? get _current =>
      Zone.current[_zoneKey] as ClientCertificateFileLease?;

  static void _retainMaterializedDirectory(String path) =>
      _current?._retain(path);

  static bool _isLeased(String path) =>
      _references.containsKey(ClientCertificateService._normalize(path));
}

/// Removes certificate/key files that no saved connection references.
///
/// Kept as a narrow interface so [ConnectionManager] can garbage-collect
/// identities after a successful save without depending on `path_provider` in
/// unit tests.
abstract interface class ClientCertificateFileStore {
  /// Deletes every stored identity whose directory is not in
  /// [referencedDirectoryPaths] and no live file lease owns. Best-effort:
  /// abandoned staged imports are also cleared.
  Future<void> deleteUnreferenced(Iterable<String> referencedDirectoryPaths);
}

/// Imports PKCS#12 or PEM client certificates into app-private storage.
///
/// The certificate and key are written as separate PEM files because
/// `SecurityContext` loads them separately. Keys never leave the app sandbox.
///
/// Imports are **staged**: files are written under `client-certs/.staging/`
/// and only moved into their permanent `client-certs/<id>/` directory by
/// [commit], after connection validation. Editors/imports use a
/// [ClientCertificateFileLease] through save, rollback and native cleanup.
/// A failed save is not proof of rollback: collect permanent files only under
/// the saved-list owner after reading their physical references.
class ClientCertificateService implements ClientCertificateFileStore {
  static const String _directoryName = 'client-certs';
  static const String _stagingDirectoryName = '.staging';
  static const String _certificateFileName = 'certificate.pem';
  static const String _privateKeyFileName = 'private-key.pem';

  final Future<Directory> Function() _supportDirectory;

  ClientCertificateService({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  /// Extracts the leaf certificate, chain, and private key from a `.p12`/
  /// `.pfx` container.
  ///
  /// The container password is used only to decrypt the file. The extracted
  /// key is written unencrypted, so the password is deliberately **not**
  /// retained: storing it would add a secret with no remaining use.
  Future<ClientCertificateConfig> importPkcs12({
    required List<int> bytes,
    required String? password,
    required String label,
  }) async {
    final Pkcs12 parsed;
    try {
      parsed = Pkcs12.load(
        Uint8List.fromList(bytes),
        password == null || password.isEmpty ? null : password,
      );
    } on Pkcs12MacMismatchException {
      // The MAC covers the whole container, so a mismatch means either a
      // missing password or a wrong one. Only the first is worth prompting for.
      if (password == null || password.isEmpty) {
        throw const ClientCertificateImportException(
          'This certificate needs its password. Enter it below and it will open automatically.',
          passwordRelated: true,
        );
      }
      throw const ClientCertificateImportException(
        'The certificate password is incorrect, or the file is corrupted.',
        passwordRelated: true,
      );
    } on Pkcs12BadPasswordException {
      throw const ClientCertificateImportException(
        'The certificate password is incorrect.',
        passwordRelated: true,
      );
    } on Pkcs12UnsupportedException {
      throw const ClientCertificateImportException(
        'This certificate uses an encryption method the app cannot read.',
      );
    } on Pkcs12ParseException {
      throw const ClientCertificateImportException(
        'The selected file is not a readable PKCS#12 (.p12/.pfx) certificate.',
      );
    } on Pkcs12Exception {
      throw const ClientCertificateImportException(
        'The selected certificate could not be read.',
      );
    }

    // SecurityContext.useCertificateChain expects one PEM chain file, leaf
    // first, so concatenate the parser's issuer-ordered CA certificates.
    final certificatePem = [
      parsed.certificatePem,
      ...parsed.caChainPem,
    ].join('\n');
    return _writePair(
      certificatePem: certificatePem,
      privateKeyPem: parsed.privateKeyPem,
      // Pkcs12.load returns an unencrypted key, so no password is needed.
      password: null,
      label: _resolveLabel(label, parsed.certificatePem),
    );
  }

  /// Imports a client identity from a single user-picked file, sniffing its
  /// format from the content rather than the file name.
  ///
  /// Accepted inputs: a `.p12`/`.pfx` container; a lone PEM certificate; a
  /// lone PEM private key; or a single PEM document holding both. A lone
  /// half without its staged counterpart returns `null`, so the caller can
  /// stage it and prompt for the missing half. Throws
  /// [ClientCertificateImportException] when the bytes are none of these.
  Future<ClientCertificateConfig?> importIdentityDocument({
    required List<int> bytes,
    String? password,
    required String label,
    List<int>? stagedCertificateBytes,
    String? stagedCertificateName,
    List<int>? stagedPrivateKeyBytes,
  }) async {
    if (_looksLikePkcs12(bytes)) {
      return importPkcs12(bytes: bytes, password: password, label: label);
    }
    final text = _asPemText(bytes);
    final certificateBlocks = _pemBlocks(text, 'CERTIFICATE');
    String? privateKeyBlock = _firstPemBlock(text, [
      'PRIVATE KEY',
      'RSA PRIVATE KEY',
      'EC PRIVATE KEY',
      'ENCRYPTED PRIVATE KEY',
      'OPENSSH PRIVATE KEY',
    ]);
    // Encrypted traditional OpenSSL keys carry the encryption marker in a
    // header above the PEM block, not inside it — see _isEncryptedPrivateKey.
    final privateKeyPem = privateKeyBlock == null
        ? null
        : _slicePemDocument(text, privateKeyBlock);
    if (certificateBlocks.isNotEmpty && privateKeyPem != null) {
      return _importPemPair(
        certificatePem: certificateBlocks.join('\n'),
        privateKeyPem: privateKeyPem,
        password: _isEncryptedPrivateKey(privateKeyPem) ? password : null,
        label: _resolveLabel(label, certificateBlocks.first),
      );
    }
    final stagedCertificate = stagedCertificateBytes == null
        ? null
        : _asPemText(stagedCertificateBytes);
    final stagedCertBlocks = stagedCertificate == null
        ? <String>[]
        : _pemBlocks(stagedCertificate, 'CERTIFICATE');
    final stagedKey = stagedPrivateKeyBytes == null
        ? null
        : _asPemText(stagedPrivateKeyBytes);
    final stagedKeyBlock = stagedKey == null
        ? null
        : _firstPemBlock(stagedKey, [
            'PRIVATE KEY',
            'RSA PRIVATE KEY',
            'EC PRIVATE KEY',
            'ENCRYPTED PRIVATE KEY',
            'OPENSSH PRIVATE KEY',
          ]);
    final stagedKeyPem = stagedKey == null || stagedKeyBlock == null
        ? null
        : _slicePemDocument(stagedKey, stagedKeyBlock);
    if (certificateBlocks.isNotEmpty && stagedKeyPem != null) {
      return _importPemPair(
        certificatePem: certificateBlocks.join('\n'),
        privateKeyPem: stagedKeyPem,
        password: _isEncryptedPrivateKey(stagedKeyPem) ? password : null,
        label: _resolveLabel(label, certificateBlocks.first),
      );
    }
    if (privateKeyPem != null && stagedCertBlocks.isNotEmpty) {
      return _importPemPair(
        certificatePem: stagedCertBlocks.join('\n'),
        privateKeyPem: privateKeyPem,
        password: _isEncryptedPrivateKey(privateKeyPem) ? password : null,
        label: _resolveLabel(
          stagedCertificateName ?? label,
          stagedCertBlocks.first,
        ),
      );
    }
    if (certificateBlocks.isNotEmpty || privateKeyPem != null) {
      // A lone half: the caller stages it and waits for its counterpart.
      return null;
    }
    throw const ClientCertificateImportException(
      'That file is not a certificate: pick a .p12/.pfx container or PEM certificate and key files.',
    );
  }

  /// PKCS#12 is DER: an ASN.1 SEQUENCE at the front. PEM is base64 text, so a
  /// leading `0x30 0x82` reliably separates the container from PEM material.
  static bool _looksLikePkcs12(List<int> bytes) =>
      bytes.length > 2 && bytes[0] == 0x30 && bytes[1] == 0x82;

  /// Extracts the full text of every `BEGIN <label> ... END <label>` block,
  /// preserving any headers above the first block (e.g. traditional OpenSSL
  /// `Proc-Type`/`DEK-Info` encryption headers).
  static List<String> _pemBlocks(String text, String label) {
    final blocks = <String>[];
    final begin = '-----BEGIN $label-----';
    final end = '-----END $label-----';
    var searchFrom = 0;
    while (true) {
      final beginIndex = text.indexOf(begin, searchFrom);
      if (beginIndex < 0) return blocks;
      final endIndex = text.indexOf(end, beginIndex + begin.length);
      if (endIndex < 0) return blocks;
      var blockStart = beginIndex;
      // Keep encryption headers that precede the block: walk back over blank
      // lines and `Name: value` header lines.
      final headerBoundary = RegExp(
        r'\n\s*\n',
      ).allMatches(text.substring(0, beginIndex));
      if (headerBoundary.isNotEmpty) {
        final candidate = headerBoundary.last.end;
        final headerText = text.substring(candidate, beginIndex);
        if (headerText.trim().isNotEmpty &&
            RegExp(r'^(?:[A-Za-z0-9-]+:[^\n]*\n?)+$').hasMatch(headerText)) {
          blockStart = candidate;
        }
      }
      blocks.add(text.substring(blockStart, endIndex + end.length));
      searchFrom = endIndex + end.length;
    }
  }

  static String? _firstPemBlock(String text, List<String> labels) {
    String? earliest;
    var earliestIndex = -1;
    for (final label in labels) {
      final begin = '-----BEGIN $label-----';
      final index = text.indexOf(begin);
      if (index >= 0 && (earliestIndex < 0 || index < earliestIndex)) {
        earliestIndex = index;
        earliest = label;
      }
    }
    if (earliest == null) return null;
    final begin = '-----BEGIN $earliest-----';
    final end = '-----END $earliest-----';
    final endIndex = text.indexOf(end, earliestIndex + begin.length);
    if (endIndex < 0) return null;
    return text.substring(earliestIndex, endIndex + end.length);
  }

  /// Returns the private-key PEM including any traditional-OpenSSL headers
  /// above its block, mirroring [_pemBlocks].
  static String _slicePemDocument(String text, String block) {
    final blockIndex = text.indexOf(block);
    if (blockIndex < 0) return block;
    final headerBoundary = RegExp(
      r'\n\s*\n',
    ).allMatches(text.substring(0, blockIndex));
    if (headerBoundary.isEmpty) {
      final prefix = text.substring(0, blockIndex).trim();
      if (prefix.isEmpty) return block;
      // The block sits mid-document after other PEM blocks: slice from the
      // block itself so the certificate half is not duplicated into the key.
      return block;
    }
    final candidate = headerBoundary.last.end;
    final headerText = text.substring(candidate, blockIndex);
    if (headerText.trim().isNotEmpty &&
        RegExp(r'^(?:[A-Za-z0-9-]+:[^\n]*\n?)+$').hasMatch(headerText)) {
      return text.substring(candidate, blockIndex + block.length);
    }
    if (headerText.trim().isEmpty) return block;
    return block;
  }

  /// Stores an already-PEM certificate/key pair chosen by the user.
  Future<ClientCertificateConfig> importPemPair({
    required List<int> certificateBytes,
    required List<int> privateKeyBytes,
    String? password,
    required String label,
  }) async {
    final certificatePem = _asPemText(certificateBytes);
    final privateKeyPem = _asPemText(privateKeyBytes);
    if (!certificatePem.contains('-----BEGIN CERTIFICATE-----')) {
      throw const ClientCertificateImportException(
        'The selected certificate is not a PEM certificate.',
      );
    }
    if (!privateKeyPem.contains('-----BEGIN') ||
        !privateKeyPem.contains('PRIVATE KEY-----')) {
      throw const ClientCertificateImportException(
        'The selected private key is not a PEM private key.',
      );
    }
    return _importPemPair(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      // Only an encrypted PEM key needs (and therefore retains) a password.
      password: _isEncryptedPrivateKey(privateKeyPem) ? password : null,
      label: _resolveLabel(label, certificatePem),
    );
  }

  /// Do not announce an identity until the transport can actually open it.
  /// Password failures keep the editor's picked bytes available for retry.
  Future<ClientCertificateConfig> _importPemPair({
    required String certificatePem,
    required String privateKeyPem,
    required String? password,
    required String label,
  }) async {
    final encrypted = _isEncryptedPrivateKey(privateKeyPem);
    if (encrypted && (password == null || password.isEmpty)) {
      throw const ClientCertificateImportException(
        'This certificate needs its password. Enter it below and it will open automatically.',
        passwordRelated: true,
      );
    }
    final config = await _writePair(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      password: encrypted ? password : null,
      label: label,
    );
    try {
      try {
        const TlsClientFactory().securityContextFor(config);
      } on TlsClientConfigurationException {
        // dart:io can leave a failed PKCS#8 decrypt on its native error queue;
        // the next chain load consumes it even with the correct password.
        // Retry once with a fresh context, never bypassing parser validation.
        const TlsClientFactory().securityContextFor(config);
      }
    } on TlsClientConfigurationException {
      await discard(config);
      ClientCertificateFileLease._current?.releaseIdentity(config);
      throw ClientCertificateImportException(
        encrypted
            ? 'The certificate password is incorrect, or the file is corrupted.'
            : 'The selected certificate and private key could not be loaded.',
        passwordRelated: encrypted,
      );
    }
    return config;
  }

  /// Restores a key pair carried by an encrypted configuration backup.
  ///
  /// Run within a [ClientCertificateFileLease] until the account transaction
  /// settles: permanent files are not yet referenced while the import queues.
  Future<ClientCertificateConfig> restore({
    required String certificatePem,
    required String privateKeyPem,
    required String label,
    String? password,
  }) async {
    return _writePair(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      password: _isEncryptedPrivateKey(privateKeyPem) ? password : null,
      label: label,
      staged: false,
    );
  }

  /// Reads the PEM contents referenced by [config].
  ///
  /// Used by the encrypted backup export. Throws [ClientCertificateImportException]
  /// when a referenced file is missing so a backup never silently drops mTLS.
  Future<({String certificatePem, String privateKeyPem})> readPair(
    ClientCertificateConfig config,
  ) async {
    try {
      final certificatePem = await File(
        config.certificatePemPath,
      ).readAsString();
      final privateKeyPem = await File(config.privateKeyPemPath).readAsString();
      return (certificatePem: certificatePem, privateKeyPem: privateKeyPem);
    } catch (_) {
      throw const ClientCertificateImportException(
        'The saved client certificate files could not be read.',
      );
    }
  }

  /// Moves a staged import into permanent storage.
  ///
  /// Returns [config] unchanged when it is already permanent.
  Future<ClientCertificateConfig> commit(ClientCertificateConfig config) async {
    if (!await isStaged(config)) {
      ClientCertificateFileLease._retainMaterializedDirectory(
        config.directoryPath,
      );
      return config;
    }
    final directory = Directory(config.directoryPath);
    final root = await _rootDirectory();
    final destination = Directory(
      '${root.path}${Platform.pathSeparator}${const Uuid().v4()}',
    );
    ClientCertificateFileLease._retainMaterializedDirectory(destination.path);
    try {
      await destination.parent.create(recursive: true);
      await directory.rename(destination.path);
      ClientCertificateFileLease._current?._releaseDirectory(directory.path);
    } catch (_) {
      throw const ClientCertificateImportException(
        'The client certificate could not be stored securely on this device.',
      );
    }
    return ClientCertificateConfig(
      label: config.label,
      certificatePemPath:
          '${destination.path}${Platform.pathSeparator}$_certificateFileName',
      privateKeyPemPath:
          '${destination.path}${Platform.pathSeparator}$_privateKeyFileName',
      privateKeyPassword: config.privateKeyPassword,
    );
  }

  /// Whether [config] still points into the staging area.
  Future<bool> isStaged(ClientCertificateConfig config) async {
    final staging = await _stagingRoot();
    return _isWithin(config.directoryPath, staging.path);
  }

  /// Deletes a staged import that was never committed.
  ///
  /// Permanent identities are left alone: they may still be referenced by the
  /// saved connection.
  Future<void> discard(ClientCertificateConfig config) async {
    if (!await isStaged(config)) return;
    await _deleteDirectory(config.directoryPath);
  }

  /// Deletes a permanent identity. Only call once nothing references it.
  Future<void> delete(ClientCertificateConfig config) async {
    final root = await _rootDirectory();
    if (!_isWithin(config.directoryPath, root.path)) return;
    if (await isStaged(config)) return;
    await _deleteDirectory(config.directoryPath, unlessLeased: true);
  }

  /// Removes abandoned staged imports (app start, or after a failed save).
  Future<void> cleanupStaging() async {
    try {
      final staging = await _stagingRoot();
      if (!staging.existsSync()) return;
      await for (final entity in staging.list()) {
        if (entity is Directory) {
          await _deleteDirectory(entity.path, unlessLeased: true);
        }
      }
    } catch (_) {
      // Cleanup is best-effort; an unreadable staging directory must not stop
      // the app from starting.
    }
  }

  @override
  Future<void> deleteUnreferenced(
    Iterable<String> referencedDirectoryPaths,
  ) async {
    final root = await _rootDirectory();
    if (!root.existsSync()) return;
    final referenced = <String>{
      for (final path in referencedDirectoryPaths) _normalize(path),
    };
    // Staging is not saved metadata; a live editor still owns its staged files.
    await cleanupStaging();
    final stagingPath = (await _stagingRoot()).path;
    try {
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        if (_isWithin(entity.path, stagingPath)) continue;
        if (referenced.contains(_normalize(entity.path))) continue;
        await _deleteDirectory(entity.path, unlessLeased: true);
      }
    } catch (_) {
      // Garbage collection must never fail a connection save.
    }
  }

  Future<ClientCertificateConfig> _writePair({
    required String certificatePem,
    required String privateKeyPem,
    required String? password,
    required String label,
    bool staged = true,
  }) async {
    final directory = staged
        ? await _newStagingDirectory()
        : await _newPermanentDirectory();
    final certificateFile = File(
      '${directory.path}${Platform.pathSeparator}$_certificateFileName',
    );
    final privateKeyFile = File(
      '${directory.path}${Platform.pathSeparator}$_privateKeyFileName',
    );
    try {
      await certificateFile.writeAsString(certificatePem, flush: true);
      await privateKeyFile.writeAsString(privateKeyPem, flush: true);
    } catch (_) {
      // A partial import is unusable; remove it rather than leaving a config
      // that points at half-written PEM files.
      await _deleteDirectory(directory.path);
      throw const ClientCertificateImportException(
        'The certificate could not be stored securely on this device.',
      );
    }

    final keyPassword = password == null || password.isEmpty ? null : password;
    return ClientCertificateConfig(
      label: label,
      certificatePemPath: certificateFile.path,
      privateKeyPemPath: privateKeyFile.path,
      privateKeyPassword: keyPassword,
    );
  }

  Future<Directory> _rootDirectory() async {
    final support = await _supportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}$_directoryName');
  }

  Future<Directory> _stagingRoot() async {
    final root = await _rootDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}$_stagingDirectoryName',
    );
  }

  Future<Directory> _newStagingDirectory() async {
    final staging = await _stagingRoot();
    final directory = Directory(
      '${staging.path}${Platform.pathSeparator}${const Uuid().v4()}',
    );
    ClientCertificateFileLease._retainMaterializedDirectory(directory.path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _newPermanentDirectory() async {
    final root = await _rootDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}${const Uuid().v4()}',
    );
    ClientCertificateFileLease._retainMaterializedDirectory(directory.path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _deleteDirectory(
    String path, {
    bool unlessLeased = false,
  }) async {
    try {
      if (unlessLeased && ClientCertificateFileLease._isLeased(path)) return;
      final directory = Directory(path);
      if (directory.existsSync()) await directory.delete(recursive: true);
    } catch (_) {
      // A leftover directory is harmless; the original failure is actionable.
    }
  }

  static bool _isWithin(String candidate, String parent) {
    final normalizedCandidate = _normalize(candidate);
    final normalizedParent = _normalize(parent);
    return normalizedCandidate == normalizedParent ||
        normalizedCandidate.startsWith(
          '$normalizedParent${Platform.pathSeparator}',
        );
  }

  static String _normalize(String path) {
    var value = path;
    while (value.length > 1 && value.endsWith(Platform.pathSeparator)) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool _isEncryptedPrivateKey(String privateKeyPem) =>
      privateKeyPem.contains('ENCRYPTED PRIVATE KEY') ||
      // Traditional RSA/EC PEM uses an encryption header, not a PKCS#8 label.
      RegExp(
        r'^Proc-Type:[ \t]*4,[ \t]*ENCRYPTED[ \t]*\r?$',
        multiLine: true,
      ).hasMatch(privateKeyPem);

  /// Uses the caller-supplied label (usually the file name), falling back to
  /// the certificate CN when that label is blank.
  static String _resolveLabel(String label, String certificatePem) {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty) return trimmed;
    try {
      final certificate = X509CertificateDer(decodePem(certificatePem));
      final commonName = certificate.subject['CN']?.trim();
      if (commonName != null && commonName.isNotEmpty) return commonName;
    } catch (_) {
      // A readable label is cosmetic; the import itself has already succeeded.
    }
    return 'Client certificate';
  }

  static String _asPemText(List<int> bytes) {
    return String.fromCharCodes(bytes);
  }
}
