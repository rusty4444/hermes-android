import 'package:hermes_android/l10n/app_localizations.dart';

enum GatewaySensitivePromptKind { sudo, secret }

/// A request-ID keyed password or secret prompt emitted by Hermes.
///
/// Values entered by the user are intentionally not part of this model so they
/// cannot be retained alongside chat or connection state.
class GatewaySensitivePromptRequest {
  final GatewaySensitivePromptKind kind;
  final String requestId;
  final String title;
  final String description;
  final String fieldLabel;

  const GatewaySensitivePromptRequest({
    required this.kind,
    required this.requestId,
    required this.title,
    required this.description,
    required this.fieldLabel,
  });

  static GatewaySensitivePromptRequest? fromEventData({
    required GatewaySensitivePromptKind kind,
    required Map<String, dynamic> data,
    AppLocalizations? l10n,
  }) {
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) return null;

    if (kind == GatewaySensitivePromptKind.sudo) {
      return GatewaySensitivePromptRequest(
        kind: kind,
        requestId: requestId,
        title: l10n?.admin_password_needed ?? 'Administrator password needed',
        description:
            l10n?.hermes_needs_a_sudo_password_for_the_pending_terminal_command ??
            'Hermes needs a sudo password for the pending terminal command.',
        fieldLabel: l10n?.sudo_password ?? 'Sudo password',
      );
    }

    final envVar = data['env_var']?.toString().trim() ?? '';
    final prompt = data['prompt']?.toString().trim() ?? '';
    return GatewaySensitivePromptRequest(
      kind: kind,
      requestId: requestId,
      title: envVar.isEmpty ? (l10n?.secret_needed ?? 'Secret needed') : envVar,
      description: prompt.isEmpty
          ? (l10n?.hermes_needs_a_secret_for_the_pending_skill ??
                'Hermes needs a secret for the pending skill.')
          : prompt,
      fieldLabel: envVar.isEmpty
          ? (l10n?.secret_value ?? 'Secret value')
          : envVar,
    );
  }
}
