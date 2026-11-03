/// The Hermes Android navigation shell.
///
/// Replaces drawer-hidden navigation with the validated top-level structure
/// Chats / Crons / Projects / Activity / More.
/// Adapts to a bottom bar on phones and a side rail on tablets/foldables.
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

import '../theme/hermes_theme.dart';

/// A top-level destination of the Hermes app.
enum HermesDestination {
  /// Human conversations, with attention, filters, and search.
  chats,

  /// Conversations produced by scheduled jobs, separate from human chats.
  crons,

  /// Server-owned Projects and their chats, files, assets, and activity.
  projects,

  /// Global operational timeline: running, blocked, completed, failed.
  activity,

  /// Everything else: files, assets, search, cron, skills, settings.
  more;

  String label(AppLocalizations l10n) {
    return switch (this) {
      HermesDestination.chats => l10n.chats,
      HermesDestination.crons => l10n.crons,
      HermesDestination.projects => l10n.nav_projects,
      HermesDestination.activity => l10n.nav_activity,
      HermesDestination.more => l10n.nav_more,
    };
  }

  IconData get icon {
    switch (this) {
      case HermesDestination.chats:
        return Icons.chat_bubble_outline;
      case HermesDestination.crons:
        return Icons.schedule_outlined;
      case HermesDestination.projects:
        return Icons.folder_outlined;
      case HermesDestination.activity:
        return Icons.bolt_outlined;
      case HermesDestination.more:
        return Icons.more_horiz;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case HermesDestination.chats:
        return Icons.chat_bubble_rounded;
      case HermesDestination.crons:
        return Icons.schedule_rounded;
      case HermesDestination.projects:
        return Icons.folder_rounded;
      case HermesDestination.activity:
        return Icons.bolt_rounded;
      case HermesDestination.more:
        return Icons.more_horiz_rounded;
    }
  }
}

/// Builds the pane for one destination.
typedef HermesPaneBuilder =
    Widget Function(BuildContext context, HermesDestination destination);

/// Exposes whether the pane it wraps is the visible destination.
///
/// Panes live in an [IndexedStack] and stay mounted when another tab is
/// selected, so widgets that poll (e.g. the session-list refresh) need this
/// to stop while hidden. Standalone hosts without a shell see `true`.
class HermesPaneVisibility extends InheritedWidget {
  const HermesPaneVisibility({
    required this.active,
    required super.child,
    super.key,
  });

  /// Whether this pane is the selected destination.
  final bool active;

  /// True when the calling pane is the selected destination.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<HermesPaneVisibility>()
          ?.active ??
      true;

  @override
  bool updateShouldNotify(HermesPaneVisibility oldWidget) =>
      oldWidget.active != active;
}

/// The adaptive navigation shell.
///
/// [badges] drives attention counts (for example pending approvals on
/// Activity); a zero or negative count renders nothing so the bar stays calm
/// when there is nothing to report.
class HermesShell extends StatefulWidget {
  /// Below this width the shell uses a bottom bar; at or above it, a rail.
  static const double railBreakpoint = 720;

  static const int maxBadgeCount = 99;

  final HermesPaneBuilder builder;
  final HermesDestination initialDestination;
  final Map<HermesDestination, int> badges;
  final ValueChanged<HermesDestination>? onDestinationChanged;

  /// The shell's floating action button.
  ///
  /// Owned here rather than by a host Scaffold: the shell draws the bottom
  /// bar, so a FAB placed above it would float over the last destination and
  /// swallow its taps.
  final Widget? floatingActionButton;

  const HermesShell({
    required this.builder,
    this.initialDestination = HermesDestination.chats,
    this.badges = const {},
    this.onDestinationChanged,
    this.floatingActionButton,
    super.key,
  });

  @override
  State<HermesShell> createState() => _HermesShellState();
}

class _HermesShellState extends State<HermesShell> {
  late HermesDestination _current = widget.initialDestination;
  late final Set<HermesDestination> _visitedDestinations = {
    widget.initialDestination,
  };

  void _select(HermesDestination destination) {
    // Re-tapping the active destination is a no-op rather than a rebuild or a
    // duplicate notification: callers use the callback for analytics/state.
    if (destination == _current) return;
    setState(() {
      _current = destination;
      _visitedDestinations.add(destination);
    });
    widget.onDestinationChanged?.call(destination);
  }

  Widget? _badge(HermesDestination destination) {
    final count = widget.badges[destination] ?? 0;
    if (count <= 0) return null;
    final text = count > HermesShell.maxBadgeCount
        ? '${HermesShell.maxBadgeCount}+'
        : '$count';
    return Badge(label: Text(text));
  }

  Widget _icon(HermesDestination destination, {required bool selected}) {
    final tokens = HermesTokens.of(context);
    final icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      color: selected ? tokens.onAccentContainer : tokens.muted,
    );
    final badge = _badge(destination);
    if (badge == null) return icon;
    return Badge(label: (badge as Badge).label, child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final useRail =
        MediaQuery.sizeOf(context).width >= HermesShell.railBreakpoint;

    // Keep every visited destination mounted so local UI state (search text,
    // selected filters, scroll position) survives switching away and back.
    // Unvisited panes stay as inert placeholders: building all destinations
    // eagerly would start their network reads before the user opens them.
    final pane = IndexedStack(
      index: _current.index,
      children: [
        for (final destination in HermesDestination.values)
          if (_visitedDestinations.contains(destination))
            KeyedSubtree(
              key: ValueKey(destination),
              child: HermesPaneVisibility(
                active: destination == _current,
                child: widget.builder(context, destination),
              ),
            )
          else
            const SizedBox.shrink(),
      ],
    );

    if (useRail) {
      return Scaffold(
        backgroundColor: tokens.surface,
        floatingActionButton: widget.floatingActionButton,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: tokens.surface,
              selectedIndex: _current.index,
              onDestinationSelected: (index) =>
                  _select(HermesDestination.values[index]),
              labelType: NavigationRailLabelType.all,
              indicatorColor: tokens.accentContainer,
              destinations: [
                for (final destination in HermesDestination.values)
                  NavigationRailDestination(
                    icon: _icon(destination, selected: false),
                    selectedIcon: _icon(destination, selected: true),
                    label: Text(destination.label(context.l10n)),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: tokens.border),
            Expanded(child: pane),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: tokens.surface,
      body: pane,
      floatingActionButton: widget.floatingActionButton,
      // Label sizes are the worst-case bases: the NavigationBar clamps its
      // label text scaling at 1.3x internally (Flutter keeps the visual
      // hierarchy), so 9sp fits every shipped label on a 320dp phone even at
      // the clamp, and 10sp covers 360dp and wider. The app's 1.15x/1.30x
      // text-size preference still scales the labels within that clamp.
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final base = Theme.of(
              context,
            ).navigationBarTheme.labelTextStyle?.resolve(states);
            return (base ?? const TextStyle()).copyWith(
              fontSize: MediaQuery.sizeOf(context).width < 360 ? 9 : 10,
            );
          }),
        ),
        child: NavigationBar(
          backgroundColor: tokens.raised,
          indicatorColor: tokens.accentContainer,
          selectedIndex: _current.index,
          onDestinationSelected: (index) =>
              _select(HermesDestination.values[index]),
          destinations: [
            for (final destination in HermesDestination.values)
              NavigationDestination(
                icon: _icon(destination, selected: false),
                selectedIcon: _icon(destination, selected: true),
                label: destination.label(context.l10n),
              ),
          ],
        ),
      ),
    );
  }
}
