// Client-certificate (mutual TLS) import for the NextGen connect screen.
//
// Reuses the classic [ClientCertificateService]: a `.p12`/`.pfx` container,
// one PEM holding both halves, or a certificate and its key picked one after
// the other. Imports are staged until the connection is saved; anything never
// saved is discarded.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/models/client_certificate.dart';
import '../../core/services/client_certificate_service.dart';
import '../theme/nextgen_theme.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

class NgCertificateController extends ChangeNotifier {
  NgCertificateController({
    ClientCertificateConfig? initial,
    ClientCertificateService? service,
  }) : _service = service ?? ClientCertificateService(),
       config = initial,
       _initial = initial {
    if (initial != null) _lease.retainIdentity(initial);
  }

  final ClientCertificateService _service;
  final _lease = ClientCertificateFileLease();
  final ClientCertificateConfig? _initial;

  /// The selected identity (staged or already saved), or null for none.
  ClientCertificateConfig? config;

  /// The user removed the saved certificate.
  bool get cleared => _initial != null && config == null;

  bool busy = false;
  String? error;

  /// A lone half waiting for its counterpart.
  String? waitingFor;

  /// The pick needs a password; [password] retries it.
  bool needsPassword = false;
  final password = TextEditingController();

  List<int>? _certBytes;
  String? _certName;
  List<int>? _keyBytes;
  List<int>? _pendingBytes;
  String? _pendingName;
  bool _committed = false;
  bool _disposed = false;

  static const _maxBytes = 1024 * 1024;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<List<int>?> _read(PlatformFile file) async {
    if (file.size > _maxBytes) return null;
    final path = file.path;
    if (path == null) return file.bytes;
    final f = File(path);
    if (await f.length() > _maxBytes) return null;
    return f.readAsBytes();
  }

  Future<void> pick() async {
    if (busy) return;
    busy = true;
    error = null;
    _changed();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      for (final file in result?.files ?? const <PlatformFile>[]) {
        final bytes = await _read(file);
        if (bytes == null) {
          error = ngL.ng_that_file_is_too_large_to;
          break;
        }
        await _import(bytes, file.name);
        if (config != null && waitingFor == null) break;
      }
    } catch (e) {
      error = ngL.ng_the_certificate_couldn_t_be_imported(e);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> retryWithPassword() async {
    final bytes = _pendingBytes;
    final name = _pendingName;
    if (bytes == null || name == null || password.text.isEmpty || busy) {
      return;
    }
    busy = true;
    _changed();
    try {
      await _import(bytes, name);
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _import(List<int> bytes, String name) async {
    try {
      final imported = await _lease.run(
        () => _service.importIdentityDocument(
          bytes: bytes,
          password: password.text,
          label: name,
          stagedCertificateBytes: _certBytes,
          stagedCertificateName: _certName,
          stagedPrivateKeyBytes: _keyBytes,
        ),
      );
      if (imported == null) {
        final text = String.fromCharCodes(bytes);
        if (text.contains('-----BEGIN CERTIFICATE-----')) {
          _certBytes = bytes;
          _certName = name;
          waitingFor = ngL.ng_now_pick_its_private_key;
        } else if (text.contains('PRIVATE KEY-----')) {
          _keyBytes = bytes;
          waitingFor = ngL.ng_now_pick_its_certificate;
        } else {
          error = ngL.ng_that_file_isn_t_a_certificate;
        }
        return;
      }
      await _replace(imported);
      _certBytes = null;
      _certName = null;
      _keyBytes = null;
      _pendingBytes = null;
      _pendingName = null;
      waitingFor = null;
      needsPassword = false;
      error = null;
    } on ClientCertificateImportException catch (e) {
      error = e.message;
      if (e.passwordRelated) {
        needsPassword = true;
        _pendingBytes = bytes;
        _pendingName = name;
      }
    }
  }

  Future<void> _replace(ClientCertificateConfig? next) async {
    final previous = config;
    config = next;
    if (next != null) _lease.retainIdentity(next);
    if (previous != null && previous != _initial) {
      _lease.releaseIdentity(previous);
      unawaited(_service.discard(previous));
    }
  }

  Future<void> clear() async {
    await _replace(null);
    _certBytes = null;
    _keyBytes = null;
    waitingFor = null;
    needsPassword = false;
    error = null;
    _changed();
  }

  /// Moves a staged import into permanent storage before it is saved.
  Future<ClientCertificateConfig?> commit() async {
    final current = config;
    if (current == null) return null;
    final saved = await _lease.run(() => _service.commit(current));
    config = saved;
    _committed = true;
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    final current = config;
    if (!_committed && current != null && current != _initial) {
      unawaited(_service.discard(current));
    }
    unawaited(_lease.close());
    password.dispose();
    super.dispose();
  }
}

/// The card shown under "Need a client certificate?".
class NgCertificateCard extends StatelessWidget {
  const NgCertificateCard({
    super.key,
    required this.controller,
    required this.isHttps,
  });

  final NgCertificateController controller;
  final bool isHttps;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final config = controller.config;
        return NgCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ngL.ng_if_a_proxy_in_front_of,
                style: NgType.bodySmall.copyWith(color: c.text2),
              ),
              if (!isHttps) ...[
                const SizedBox(height: 8),
                Text(
                  ngL.ng_client_certificates_are_only_used_with,
                  style: NgType.caption.copyWith(color: c.warning),
                ),
              ],
              const SizedBox(height: 12),
              if (config != null)
                Row(
                  children: [
                    Icon(Icons.verified_user, size: 18, color: c.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.label,
                        style: NgType.label.copyWith(color: c.text),
                      ),
                    ),
                    TextButton(
                      onPressed: controller.busy ? null : controller.clear,
                      child: Text(ngL.ng_remove),
                    ),
                  ],
                ),
              if (controller.waitingFor != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    controller.waitingFor!,
                    style: NgType.bodySmall.copyWith(color: c.accentText),
                  ),
                ),
              if (controller.needsPassword) ...[
                NgField(
                  controller: controller.password,
                  label: ngL.ng_certificate_password,
                  obscure: true,
                  onSubmitted: (_) => controller.retryWithPassword(),
                  suffix: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: controller.retryWithPassword,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    controller.error!,
                    style: NgType.bodySmall.copyWith(color: c.danger),
                  ),
                ),
              NgSecondaryButton(
                label: controller.busy
                    ? ngL.ng_importing
                    : config == null
                    ? ngL.ng_pick_certificate
                    : ngL.ng_pick_a_different_certificate,
                icon: Icons.badge_outlined,
                onPressed: controller.busy ? null : controller.pick,
              ),
              const SizedBox(height: 6),
              Text(
                ngL.ng_accepts_p12_pfx_or_pem_certificate,
                style: NgType.caption.copyWith(color: c.text3),
              ),
            ],
          ),
        );
      },
    );
  }
}
