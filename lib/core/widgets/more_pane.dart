/// The More destination pane.
///
/// The fourth top-level destination of the validated navigation
/// (Home / Projects / Activity / More). Phase 0 of
/// `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` requires the shell to expose every
/// capability instead of hiding it in a drawer, and requires an embedded
/// Dashboard fallback entry so no capability is blocked while the native UX
/// catches up.
///
/// Two rules drive this file:
///
/// 1. **Never hide a capability.** A surface that is not built yet is listed
///    as `Coming next`, and a surface the server cannot serve is listed as
///    disabled *with a precise reason* — never removed from the list.
/// 2. **Explain, do not crash.** Availability is data, so tests can assert it
///    without pumping a widget, and the pane simply renders it.
library;

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

/// Whether a More entry can be opened right now, and why not when it cannot.
enum MoreEntryAvailability {
  /// Usable now.
  available,

  /// Native surface not implemented yet; listed so it stays discoverable.
  comingSoon,

  /// The connected Hermes instance cannot serve it (for example: no
  /// reachable dashboard). Disabled with an explanation, never hidden.
  unavailable,
}

/// One row of the More pane.
@immutable
class MoreEntry {
  /// Stable identifier used for routing and tests. Never localized.
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final MoreEntryAvailability availability;

  /// Why the entry is disabled. Required for [MoreEntryAvailability.unavailable]
  /// so the UI can always tell the user what to fix.
  final String? unavailableReason;

  const MoreEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.availability = MoreEntryAvailability.available,
    this.unavailableReason,
  }) : assert(
         availability != MoreEntryAvailability.unavailable ||
             unavailableReason != null,
         'A disabled entry must explain itself',
       );

  bool get isSelectable => availability == MoreEntryAvailability.available;
}

/// A titled group of [MoreEntry] rows.
@immutable
class MoreSection {
  final String title;
  final List<MoreEntry> entries;

  const MoreSection({required this.title, required this.entries});
}

const _dashboardRequired =
    'Needs a reachable Hermes dashboard. Check the host, port, and '
    'credentials of this connection.';
const _gatewayAssetsRequired =
    'Needs a server-authoritative Assets index in the Hermes Gateway.';
const _gatewayOrganizationRequired =
    'Needs durable pin ordering, batch mutation, and undo contracts in the '
    'Hermes Gateway.';
const _gatewayAiFilingRequired =
    'Needs a correction-aware filing contract in the Hermes Gateway.';

/// Builds the More menu for the current connection.
///
/// [dashboardReachable] gates the surfaces served by the Hermes Dashboard.
/// Local device settings stay reachable regardless, so the user can always
/// repair a broken connection from inside the app.
///
/// [filingAvailable] is the gateway's proven answer for the `filing.*`
/// correction-aware contract (probed once via `filing.status`); without it
/// the entry stays disabled with its reason, never hidden.
///
/// [organizationAvailable] is the proven answer for the `organization.*`
/// batch pin/archive/undo contract (probed once via `organization.history`).
///
/// [assetsAvailable] is the proven answer for the `assets.*`
/// server-authoritative index (probed once via `assets.status`).
List<MoreSection> buildMoreSections({
  required bool dashboardReachable,
  bool filingAvailable = false,
  bool organizationAvailable = false,
  bool assetsAvailable = false,
}) {
  MoreEntryAvailability dashboardBacked() => dashboardReachable
      ? MoreEntryAvailability.available
      : MoreEntryAvailability.unavailable;
  String? dashboardReason() => dashboardReachable ? null : _dashboardRequired;

  return [
    MoreSection(
      title: 'Workspace',
      entries: [
        const MoreEntry(
          id: 'unassigned',
          title: 'Unassigned chats',
          subtitle: 'Chats that are not assigned to a Project',
          icon: Icons.inbox_outlined,
        ),
        const MoreEntry(
          id: 'archived-quick',
          title: 'Archived quick chats',
          subtitle: 'Review or promote quick chats past their retention period',
          icon: Icons.archive_outlined,
        ),
        MoreEntry(
          id: 'files',
          title: 'Files',
          subtitle: 'Browse the miniserver folders behind your projects',
          icon: Icons.folder_open_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'assets',
          title: 'Assets',
          subtitle: 'Artifacts, attachments, and generated media',
          icon: Icons.image_outlined,
          availability: assetsAvailable
              ? MoreEntryAvailability.available
              : MoreEntryAvailability.unavailable,
          unavailableReason:
              assetsAvailable ? null : _gatewayAssetsRequired,
        ),
      ],
    ),
    MoreSection(
      title: 'Organization',
      entries: [
        MoreEntry(
          id: 'pin-batch-undo',
          title: 'Pin, batch and undo',
          subtitle: 'Cross-device ordering and reversible bulk organization',
          icon: Icons.push_pin_outlined,
          availability: organizationAvailable
              ? MoreEntryAvailability.available
              : MoreEntryAvailability.unavailable,
          unavailableReason:
              organizationAvailable ? null : _gatewayOrganizationRequired,
        ),
        MoreEntry(
          id: 'ai-filing',
          title: 'AI-assisted filing',
          subtitle: 'Suggest Projects and learn from your corrections',
          icon: Icons.auto_fix_high_outlined,
          availability: filingAvailable
              ? MoreEntryAvailability.available
              : MoreEntryAvailability.unavailable,
          unavailableReason:
              filingAvailable ? null : _gatewayAiFilingRequired,
        ),
      ],
    ),
    MoreSection(
      title: 'Automation',
      entries: [
        MoreEntry(
          id: 'cron',
          title: 'Cron',
          subtitle: 'Scheduled jobs and their last runs',
          icon: Icons.schedule_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'skills',
          title: 'Skills and tools',
          subtitle: 'What Hermes knows how to do',
          icon: Icons.auto_awesome_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'memory',
          title: 'Memory',
          subtitle: 'Durable facts Hermes keeps about you',
          icon: Icons.psychology_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
      ],
    ),
    MoreSection(
      title: 'System',
      entries: [
        const MoreEntry(
          id: 'settings',
          title: 'Settings',
          subtitle: 'Connection, appearance, and device preferences',
          icon: Icons.settings_outlined,
        ),
        MoreEntry(
          id: 'dashboard',
          title: 'Open the Hermes dashboard',
          subtitle:
              'Everything not yet native, in the authenticated web dashboard',
          icon: Icons.open_in_new,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
      ],
    ),
  ];
}

/// Renders the More menu.
class MorePane extends StatelessWidget {
  final List<MoreSection> sections;
  final ValueChanged<MoreEntry> onSelect;

  const MorePane({required this.sections, required this.onSelect, super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
      children: [
        for (final section in sections) ...[
          SectionHeader(title: section.title),
          for (final entry in section.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HermesSpacing.lg,
                0,
                HermesSpacing.lg,
                HermesSpacing.md,
              ),
              child: _MoreEntryCard(entry: entry, onSelect: onSelect),
            ),
        ],
      ],
    );
  }
}

class _MoreEntryCard extends StatelessWidget {
  final MoreEntry entry;
  final ValueChanged<MoreEntry> onSelect;

  const _MoreEntryCard({required this.entry, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final dimmed = !entry.isSelectable;
    final titleColor = dimmed ? tokens.muted : tokens.onSurface;

    return Semantics(
      button: entry.isSelectable,
      enabled: entry.isSelectable,
      label: entry.title,
      child: HermesCard(
        onTap: entry.isSelectable ? () => onSelect(entry) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (dimmed ? tokens.muted : tokens.accent).withValues(
                  alpha: 0.14,
                ),
                borderRadius: BorderRadius.circular(HermesRadius.sm),
              ),
              child: Icon(
                entry.icon,
                size: 20,
                color: dimmed ? tokens.muted : tokens.accent,
              ),
            ),
            const SizedBox(width: HermesSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A Wrap rather than a Row: at a large text scale the badge
                  // moves to its own line instead of overflowing the card.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: HermesSpacing.sm,
                    runSpacing: HermesSpacing.xs,
                    children: [
                      Text(
                        entry.title,
                        style: tokens.typography.section.copyWith(
                          color: titleColor,
                        ),
                      ),
                      if (entry.availability ==
                          MoreEntryAvailability.comingSoon)
                        const StatusChip(
                          status: HermesStatus.idle,
                          label: 'Coming next',
                        ),
                    ],
                  ),
                  const SizedBox(height: HermesSpacing.xs),
                  Text(
                    entry.subtitle,
                    style: tokens.typography.body.copyWith(color: tokens.muted),
                  ),
                  if (entry.availability ==
                      MoreEntryAvailability.unavailable) ...[
                    const SizedBox(height: HermesSpacing.xs),
                    Text(
                      entry.unavailableReason!,
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
