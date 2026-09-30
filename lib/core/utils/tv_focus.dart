// TV / Android Auto focus helpers.
// Detects TV layout and wraps widgets with a D-pad focus ring + auto-scroll.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Returns true for wide screens typically used on TV or Android Auto displays.
bool isTvLayout(BuildContext context) {
  final mq = MediaQuery.of(context);
  final shortest = mq.size.width < mq.size.height
      ? mq.size.width
      : mq.size.height;
  return shortest >= 720 || mq.size.width >= 960;
}

/// Crash-safe focus wrapper for D-pad / remote navigation.
/// Uses a single [Focus] widget so it never collides with another focus node.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onLeft;
  final bool autoFocus;
  final FocusNode? focusNode;

  const TvFocusable({
    required this.child,
    this.onSelect,
    this.onLeft,
    this.autoFocus = false,
    this.focusNode,
    super.key,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node;
  bool _focused = false;
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final focused = _node.hasFocus;
    if (mounted) setState(() => _focused = focused);
    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: 0.5,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autoFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onSelect?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onLeft?.call();
            return widget.onLeft != null
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        key: _key,
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: _focused
              ? Border.all(color: const Color(0xFFD4AF37), width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Forces dark mode on TV so text stays readable against default light themes.
ThemeMode effectiveThemeMode(BuildContext context, ThemeMode userMode) {
  return isTvLayout(context) ? ThemeMode.dark : userMode;
}
