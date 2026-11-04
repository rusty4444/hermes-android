/// The Crons destination: **Upcoming** schedules beside run **History**.
///
/// Issue #259: the destination used to be history-only, so a job an agent had
/// just scheduled was invisible until it first ran. The two views are selected
/// with the same `ChoiceChip` row the Chats browser uses, so the control is
/// the established one rather than a new invention.
///
/// Both views stay mounted, which keeps loaded history (and the host's
/// `GlobalKey` handle on the history browser, used for archive/rename
/// reconciliation) alive across a view switch. The unselected view is wrapped
/// in a nested [HermesPaneVisibility] so its visibility-gated refresh stops:
/// the view you cannot see must not poll the gateway.
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
              HermesPaneVisibility(
                active: destinationVisible && _view == CronsView.history,
                child: widget.history,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
