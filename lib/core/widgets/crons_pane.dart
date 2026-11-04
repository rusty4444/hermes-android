/// The Crons destination: **Upcoming** schedules beside run **History**.
///
/// Issue #259: the destination used to be history-only, so a job an agent had
/// just scheduled was invisible until it first ran. The two views are selected
/// with the same `ChoiceChip` row the Chats browser uses, so the control is
/// the established one rather than a new invention.
///
/// Both views stay mounted, which keeps loaded history (and the host's
/// `GlobalKey` handle on the history browser, used for archive/rename
/// reconciliation) alive across a view switch.
///
/// **Only the Upcoming view is visibility-gated here.** The history browser
/// keeps the destination's own refresh authority exactly as it had before the
/// split: issue #149 scoped its periodic tick to the authority its selected
/// filter renders (archive-free unless Archived is selected), and the Crons
/// destination being open is what licenses that tick. Narrowing it to "only
/// while the History chip is selected" would silently drop the cadence
/// `periodic_refresh_scope_test` pins, and switching to History would then
/// show rows as stale as the last time it was looked at. Upcoming, which is a
/// new reader on a different endpoint, gets its own gate so it polls only
/// while it is the view on screen. The host also disables history's archive
/// authority behind Upcoming, even if its retained filter is Archived;
/// returning to History catches that authority up through `_ensureArchives`.
library;

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';
import 'hermes_shell.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Which half of the Crons destination is showing.
enum CronsView { upcoming, history }

const Key kCronsUpcomingChipKey = Key('crons-view-upcoming');
const Key kCronsHistoryChipKey = Key('crons-view-history');

class CronsPane extends StatefulWidget {
  /// Scheduled job definitions — what will run.
  final Widget upcoming;

  /// Cron run conversations — what already ran.
  final Widget history;

  /// Which view opens first. Upcoming by default: the whole point of the
  /// split is that a scheduled job is visible before it has ever run.
  final CronsView initialView;

  /// Reports the selected view so a host can scope its own actions.
  final ValueChanged<CronsView>? onViewChanged;

  const CronsPane({
    required this.upcoming,
    required this.history,
    this.initialView = CronsView.upcoming,
    this.onViewChanged,
    super.key,
  });

  @override
  State<CronsPane> createState() => CronsPaneState();
}

class CronsPaneState extends State<CronsPane> {
  late CronsView _view = widget.initialView;

  CronsView get view => _view;

  void select(CronsView view) {
    if (_view == view) return;
    setState(() => _view = view);
    widget.onViewChanged?.call(view);
  }

  String _label(CronsView view) => switch (view) {
    CronsView.upcoming => context.l10n.crons_upcoming,
    CronsView.history => context.l10n.crons_history,
  };

  Key _key(CronsView view) => switch (view) {
    CronsView.upcoming => kCronsUpcomingChipKey,
    CronsView.history => kCronsHistoryChipKey,
  };

  @override
  Widget build(BuildContext context) {
    // The destination's own visibility still gates both views: a hidden
    // destination must not poll, whichever view is selected inside it.
    final destinationVisible = HermesPaneVisibility.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            HermesSpacing.md,
            HermesSpacing.lg,
            0,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final view in CronsView.values)
                  Padding(
                    padding: const EdgeInsets.only(right: HermesSpacing.sm),
                    child: ChoiceChip(
                      key: _key(view),
                      label: Text(_label(view)),
                      selected: _view == view,
                      onSelected: (_) => select(view),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view.index,
            sizing: StackFit.expand,
            children: [
              HermesPaneVisibility(
                active: destinationVisible && _view == CronsView.upcoming,
                child: widget.upcoming,
              ),
              // Deliberately NOT re-scoped: the history browser keeps the
              // destination's visibility and therefore the archive-free
              // periodic tick issue #149 established for it.
              widget.history,
            ],
          ),
        ),
      ],
    );
  }
}
