import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'config_backup.dart';
import 'config_backup_service.dart';
import 'connection_manager.dart';

/// Platform-facing half of the backup feature: picking files, writing the
/// export, and handing it to the share sheet.
///
/// Kept apart from [ConfigBackupService] so the pure logic stays testable, and
/// shared by both entry points — the connection list (needed on a fresh
/// install, where Settings is unreachable) and the Settings screen.
class ConfigBackupIo {
  final ConnectionManager connectionManager;

  ConfigBackupIo({required this.connectionManager});

  ConfigBackupService get _service => ConfigBackupService(
    connectionManager: connectionManager,
    preferences: connectionManager.prefs,
  );

  Future<String> exportEncrypted(String passphrase) async {
    String appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      appVersion = 'unknown';
    }
    final backup = await _service.export(appVersion: appVersion);
    return ConfigBackupCodec.encrypt(backup, passphrase: passphrase);
  }

  /// Writes the encrypted backup to a temp file and offers it to the share
  /// sheet. Returns the file name, or null when the user dismisses the sheet.
  Future<String?> deliverExport(String contents) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final directory = await getTemporaryDirectory();
    // Purge previous export files before writing a new one: the share
    // sheet gives no completion signal we can trust for deletion, so the
    // next export is the safe cleanup point. Without this, every export
    // left an encrypted copy of all secrets in the cache forever.
    try {
      for (final stale in directory.listSync()) {
        if (stale is File &&
            stale.path.contains('/hermes-config-') &&
            stale.path.endsWith('.json')) {
          try {
            stale.deleteSync();
          } catch (_) {
            // A file still held by the share sheet stays; next round gets it.
          }
        }
      }
    } catch (_) {
      // Cleanup is best-effort; the export itself must not fail on it.
    }
    final file = File('${directory.path}/hermes-config-$stamp.json');
    await file.writeAsString(contents, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        subject: 'Hermes configuration backup',
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
      ),
    );
    if (result.status == ShareResultStatus.dismissed) return null;
    return file.uri.pathSegments.last;
  }

  Future<String?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    final picked = result?.files.firstOrNull;
    if (picked == null) return null;

    final bytes = picked.bytes;
    if (bytes != null) return utf8.decode(bytes, allowMalformed: true);
    final path = picked.path;
    if (path == null) {
      throw const ConfigBackupException('That file could not be read.');
    }
    return File(path).readAsString();
  }

  Future<ConfigImportResult> importEncrypted(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  ) async {
    final backup = await ConfigBackupCodec.decrypt(
      contents,
      passphrase: passphrase,
    );
    return _service.import(backup, mode: mode);
  }
}
