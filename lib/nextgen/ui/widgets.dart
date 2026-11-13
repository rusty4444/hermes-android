// Small building blocks shared by the NextGen screens: cards, pills, section
// labels, the top glow and a segmented control, all drawn from [NgColors].
import 'package:flutter/material.dart';

import '../theme/nextgen_theme.dart';
import '../nextgen_l10n.dart';

/// A page scaffold with Kyllene's soft accent glow behind the top edge.
class NgPage extends StatelessWidget {
  const NgPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.leading,
    this.floating,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    // The glow sits behind the whole page, app bar included, so it never
    // shows a hard edge where the body starts.
    return ColoredBox(
      color: c.background,
      child: NgGlow(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: floating,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: leading,
            title: Text(title, style: NgType.heading.copyWith(color: c.text)),
            actions: actions,
          ),
          body: body,
        ),
      ),
    );
  }
}

/// Paints the optional accent glow behind [child].
class NgGlow extends StatelessWidget {
  const NgGlow({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    if (!c.glow) return child;
    return Stack(
      children: [
        Positioned(
          top: -220,
          left: -120,
          right: -120,
          height: 440,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    c.accent.withValues(alpha: 0.18),
                    c.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class NgCard extends StatelessWidget {
  const NgCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final radius = BorderRadius.circular(NgRadii.lg);
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borderColor ?? c.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Uppercase label above a group of rows.
class NgSectionLabel extends StatelessWidget {
  const NgSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: NgType.eyebrow.copyWith(color: c.text3),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A row inside a card: icon, title, optional subtitle and trailing widget.
class NgRow extends StatelessWidget {
  const NgRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final color = danger ? c.danger : c.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NgRadii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: danger ? c.danger : c.text2),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NgType.label.copyWith(color: color)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: NgType.caption.copyWith(color: c.text3),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (trailing == null && onTap != null)
              Icon(Icons.chevron_right, size: 18, color: c.text3),
          ],
        ),
      ),
    );
  }
}

/// A small rounded status pill.
class NgPill extends StatelessWidget {
  const NgPill(
    this.text, {
    super.key,
    this.tone = NgTone.neutral,
    this.icon,
    this.onTap,
  });

  final String text;
  final NgTone tone;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final (bg, fg) = switch (tone) {
      NgTone.neutral => (c.surface2, c.text2),
      NgTone.accent => (c.accentSoft, c.accentText),
      NgTone.success => (c.successSoft, c.success),
      NgTone.warning => (c.warningSoft, c.warning),
      NgTone.danger => (c.dangerSoft, c.danger),
    };
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: NgType.caption.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum NgTone { neutral, accent, success, warning, danger }

/// Primary full-width button.
class NgPrimaryButton extends StatelessWidget {
  const NgPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surface3,
          shape: const StadiumBorder(),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.text2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Secondary full-width button.
class NgSecondaryButton extends StatelessWidget {
  const NgSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.strokeStrong),
          shape: const StadiumBorder(),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// Text field styled like Kyllene's inputs.
class NgField extends StatelessWidget {
  const NgField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
    this.suffix,
    this.autofocus = false,
    this.autofillHints,
    this.textInputAction,
    this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final bool autofocus;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(NgRadii.md),
      borderSide: BorderSide(color: c.stroke),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label!, style: NgType.label.copyWith(color: c.text2)),
          ),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: !obscure,
          keyboardType: keyboardType,
          autofocus: autofocus,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          style: NgType.body.copyWith(color: c.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: NgType.body.copyWith(color: c.textMuted),
            filled: true,
            fillColor: c.input,
            suffixIcon: suffix,
            errorText: errorText,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Segmented choice control (Kyllene's theme and filter switchers).
class NgSegmented<T> extends StatelessWidget {
  const NgSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(NgRadii.full),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: v == selected ? c.thumb : Colors.transparent,
                    borderRadius: BorderRadius.circular(NgRadii.full),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labelOf(v),
                    style: NgType.label.copyWith(
                      color: v == selected ? c.text : c.text3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A centred message for empty and error states.
class NgEmpty extends StatelessWidget {
  const NgEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: c.text3),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: NgType.heading.copyWith(color: c.text),
            ),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// A rounded bottom sheet in NextGen colours.
Future<T?> showNgSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
}) {
  final c = NgColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: c.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(NgRadii.xl)),
    ),
    builder: builder,
  );
}

/// Short snackbar.
void ngToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

/// Asks for a line of text (rename etc.).
Future<String?> ngPromptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? confirm,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ngL.ng_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(confirm ?? ngL.ng_save),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Asks to confirm a destructive action.
Future<bool> ngConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String? confirm,
}) async {
  final c = NgColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(ngL.ng_cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm ?? ngL.ng_delete),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// "3m ago"-style relative time.
String ngAgo(DateTime? time) {
  if (time == null) return '';
  final d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 365) return '${(d.inDays / 7).floor()}w';
  return '${(d.inDays / 365).floor()}y';
}

String ngCompactNumber(num n) {
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}k';
  return n.toStringAsFixed(n is int ? 0 : 0);
}
