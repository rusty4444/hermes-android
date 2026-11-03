/// The Hermes component kit.
///
/// Small, token-driven widgets shared by every screen so status, empty,
/// loading, and error situations look and behave the same everywhere. See
/// `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` ("Interface overhaul").
library;

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// A semantic notice must choose its text for the actual background, not the
/// app's default snackbar surface (which can have the opposite brightness).
SnackBar hermesStatusSnackBar(
  BuildContext context, {
  required String message,
  required HermesStatus status,
  Duration duration = const Duration(seconds: 4),
}) {
  final background = HermesTokens.of(context).colorForStatus(status);
  return SnackBar(
    backgroundColor: background,
    content: Text(message, style: TextStyle(color: foregroundFor(background))),
    duration: duration,
  );
}

/// Default wording for each semantic status, phrased for a person, not a state
/// machine: a blocked turn is something that "needs you".
String defaultStatusLabel(BuildContext context, HermesStatus status) {
  switch (status) {
    case HermesStatus.running:
      return context.l10n.status_running;
    case HermesStatus.blocked:
      return context.l10n.needs_you;
    case HermesStatus.failed:
      return context.l10n.status_failed;
    case HermesStatus.completed:
      return context.l10n.status_done;
    case HermesStatus.idle:
      return context.l10n.status_idle;
  }
}

/// A compact, color-coded state badge.
class StatusChip extends StatelessWidget {
  final HermesStatus status;
  final String? label;

  const StatusChip({required this.status, this.label, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final color = tokens.colorForStatus(status);
    final text = label ?? defaultStatusLabel(context, status);

    return Semantics(
      label: text,
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.sm,
            vertical: HermesSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(HermesRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            text,
            style: tokens.typography.label.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

/// A list-section title with an optional count and a single trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    required this.title,
    this.count,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final showAction = actionLabel != null && onAction != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.lg,
        HermesSpacing.sm,
        HermesSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: tokens.typography.section.copyWith(
                color: tokens.onSurface,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: HermesSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: HermesSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: tokens.raised,
                borderRadius: BorderRadius.circular(HermesRadius.sm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                '$count',
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ),
          ],
          const Spacer(),
          if (showAction)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: tokens.typography.label.copyWith(color: tokens.accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// The standard Hermes surface: a bordered, flat card.
///
/// Passing [status] tints the border and background so urgent work reads as
/// urgent without a second widget.
class HermesCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HermesStatus? status;
  final EdgeInsetsGeometry padding;

  const HermesCard({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.status,
    this.padding = const EdgeInsets.all(HermesSpacing.lg),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final accent = status == null ? null : tokens.colorForStatus(status!);

    final surface = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: padding,
      decoration: BoxDecoration(
        color: accent == null ? tokens.raised : accent.withValues(alpha: 0.08),
        borderRadius: HermesRadius.card,
        border: Border.all(
          color: accent == null ? tokens.border : accent.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );

    if (onTap == null && onLongPress == null) return surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: HermesRadius.card,
        child: surface,
      ),
    );
  }
}

/// A designed empty state: what is missing, why it matters, one way forward.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final showAction = actionLabel != null && onAction != null;

    return Padding(
      padding: const EdgeInsets.all(HermesSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: tokens.muted),
          const SizedBox(height: HermesSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: tokens.typography.section.copyWith(color: tokens.onSurface),
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: tokens.typography.body.copyWith(color: tokens.muted),
          ),
          if (showAction) ...[
            const SizedBox(height: HermesSpacing.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// A failure state, or — via [ErrorState.unsupported] — a calm compatibility
/// notice for a gateway that simply does not offer a capability yet.
class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final bool _informational;

  const ErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  }) : _informational = false;

  /// An older gateway missing a capability is not an error the user caused,
  /// so it must not be styled or worded like a crash.
  const ErrorState.unsupported({
    required this.title,
    required this.message,
    super.key,
  }) : onRetry = null,
       _informational = true;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final color = _informational ? tokens.muted : tokens.danger;

    return Padding(
      padding: const EdgeInsets.all(HermesSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _informational ? Icons.info_outline : Icons.error_outline_rounded,
            size: 40,
            color: color,
          ),
          const SizedBox(height: HermesSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: tokens.typography.section.copyWith(color: tokens.onSurface),
          ),
          const SizedBox(height: HermesSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: tokens.typography.body.copyWith(color: tokens.muted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: HermesSpacing.xl),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder rows shown while real content loads.
///
/// Preferred over a spinner: it preserves layout, so content does not jump
/// into place when it arrives.
class LoadingSkeleton extends StatefulWidget {
  final int rows;

  const LoadingSkeleton({this.rows = 3, super.key});

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Semantics(
      label: context.l10n.loading,
      container: true,
      child: Column(
        children: List.generate(widget.rows, (index) {
          return Padding(
            key: Key('skeleton-row-$index'),
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              HermesSpacing.sm,
              HermesSpacing.lg,
              HermesSpacing.sm,
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: tokens.raised.withValues(
                      alpha: 0.5 + _controller.value * 0.35,
                    ),
                    borderRadius: HermesRadius.card,
                    border: Border.all(color: tokens.border),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}
