import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';
/// Transport state shown in the sticky chat context header.
enum ChatConnectionStatus {
  connecting('connecting'),
  connected('connected'),
  reconnecting('reconnecting'),
  offline('offline');

  final String label;
  const ChatConnectionStatus(this.label);
}

/// Sticky context row under the chat title.
///
/// Keeps the four decisions that affect a turn visible while messages scroll:
/// Project, effective model, reasoning effort, and connection state. It is
/// deliberately horizontally scrollable instead of wrapping into the chat,
/// so large text and narrow phones never clip or grow the AppBar unpredictably.
class ChatContextHeader extends StatelessWidget {
  final String? projectName;
  final String model;
  final String reasoningEffort;
  final String connectionLabel;
  final ChatConnectionStatus connectionStatus;

  const ChatContextHeader({
    required this.model,
    required this.reasoningEffort,
    required this.connectionLabel,
    required this.connectionStatus,
    this.projectName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final project = projectName?.trim();

    return Material(
      color: tokens.raised,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.md,
            vertical: HermesSpacing.xs,
          ),
          child: Row(
            children: [
              _ContextChip(
                icon: Icons.folder_outlined,
                label: project == null || project.isEmpty
                    ? context.l10n.unassigned
                    : project,
              ),
              const SizedBox(width: HermesSpacing.sm),
              _ContextChip(icon: Icons.smart_toy_outlined, label: model),
              const SizedBox(width: HermesSpacing.sm),
              _ContextChip(
                icon: Icons.psychology_outlined,
                label: _reasoningLabel(context, reasoningEffort),
              ),
              const SizedBox(width: HermesSpacing.sm),
              Semantics(
                label: context.l10n.connection_status_label(
                  connectionLabel,
                  connectionStatus.label,
                ),
                container: true,
                child: ExcludeSemantics(
                  child: _ContextChip(
                    icon: _connectionIcon(),
                    iconColor: _connectionColor(context),
                    label: connectionLabel,
                    trailingLabel:
                        connectionStatus == ChatConnectionStatus.connected
                        ? null
                        : '· ${connectionStatus.label}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _connectionIcon() {
    return switch (connectionStatus) {
      ChatConnectionStatus.connected => Icons.circle,
      ChatConnectionStatus.connecting ||
      ChatConnectionStatus.reconnecting => Icons.sync,
      ChatConnectionStatus.offline => Icons.cloud_off_outlined,
    };
  }

  Color _connectionColor(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return switch (connectionStatus) {
      ChatConnectionStatus.connected => tokens.success,
      ChatConnectionStatus.connecting ||
      ChatConnectionStatus.reconnecting => tokens.warning,
      ChatConnectionStatus.offline => tokens.danger,
    };
  }

  String _reasoningLabel(BuildContext context, String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      '' || 'none' => context.l10n.reasoning_off,
      'minimal' => context.l10n.reasoning_minimal,
      'low' => context.l10n.reasoning_low,
      'medium' => context.l10n.reasoning_medium,
      'high' => context.l10n.reasoning_high,
      'xhigh' => context.l10n.extra_high,
      'max' => context.l10n.reasoning_max,
      'ultra' => context.l10n.reasoning_ultra,
      _ => value,
    };
  }
}

class _ContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailingLabel;
  final Color? iconColor;

  const _ContextChip({
    required this.icon,
    required this.label,
    this.trailingLabel,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Container(
      constraints: trailingLabel == null
          ? const BoxConstraints(maxWidth: 220)
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: HermesSpacing.sm,
        vertical: HermesSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(HermesRadius.sm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? tokens.muted),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.label.copyWith(color: tokens.onSurface),
            ),
          ),
          if (trailingLabel != null) ...[
            const SizedBox(width: 4),
            Text(
              trailingLabel!,
              maxLines: 1,
              style: tokens.typography.label.copyWith(
                color: iconColor ?? tokens.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
