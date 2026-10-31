/// The More destination pane.
///
/// The fifth top-level destination (Chats / Crons / Projects / Activity / More).
/// Groups Workspace, Agent and System capabilities, with a Dashboard fallback
/// for functionality that does not yet have a native screen. Roadmap-only
/// organisation placeholders are omitted from the menu.
///
/// Two rules drive this file:
///
/// 1. **Keep supported capabilities discoverable.** A surface the current
///    connection cannot serve stays disabled *with a precise reason*.
///    Capabilities exposed in other destinations need not be duplicated here.
/// 2. **Explain, do not crash.** Availability is data, so tests can assert it
///    without pumping a widget, and the pane simply renders it.
library;

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

const providerTitles = <String, String>{
  'openrouter': 'OpenRouter',
  'openai': 'OpenAI',
  'anthropic': 'Claude (Anthropic)',
  'deepseek': 'DeepSeek',
};

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

/// Builds the More menu for the current connection.
///
/// [dashboardReachable] gates the surfaces served by the Hermes Dashboard.
/// Local device settings stay reachable regardless, so the user can always
/// repair a broken connection from inside the app.
///
/// [providerIds] is a model-catalog hint, not an account-capability inventory.
/// Usage stays discoverable regardless of empty, partial or alias-only catalogs.
List<MoreSection> buildMoreSections({
  required bool dashboardReachable,
  required AppLocalizations l10n,
  Set<String> providerIds = const {},
}) {
  MoreEntryAvailability dashboardBacked() => dashboardReachable
      ? MoreEntryAvailability.available
      : MoreEntryAvailability.unavailable;
  String? dashboardReason() => dashboardReachable
      ? null
      : l10n.needs_a_reachable_hermes_dashboard_check_the_host_port_and;

  return [
    MoreSection(
      title: l10n.workspace,
      entries: [
        MoreEntry(
          id: 'unassigned',
          title: l10n.unassigned_chats,
          subtitle: l10n.chats_that_are_not_assigned_to_a_project,
          icon: Icons.inbox_outlined,
        ),
        MoreEntry(
          id: 'files',
          title: l10n.files,
          subtitle: l10n.browse_the_miniserver_folders_behind_your_projects,
          icon: Icons.folder_open_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'assets',
          title: l10n.assets,
          subtitle: l10n.assets_recent_subtitle,
          icon: Icons.image_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
      ],
    ),
    MoreSection(
      title: l10n.agent,
      entries: [
        MoreEntry(
          id: 'cron',
          title: l10n.cron,
          subtitle: l10n.scheduled_jobs_and_their_last_runs,
          icon: Icons.schedule_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'skills',
          title: l10n.skills_and_tools,
          subtitle: l10n.what_hermes_knows_how_to_do,
          icon: Icons.auto_awesome_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        MoreEntry(
          id: 'memory',
          title: l10n.memory,
          subtitle: l10n.durable_facts_hermes_keeps_about_you,
          icon: Icons.psychology_outlined,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
      ],
    ),
    MoreSection(
      title: l10n.usage,
      entries: [
        MoreEntry(
          id: 'nous-portal',
          title: l10n.nous_portal,
          subtitle: l10n.portal_menu_subtitle,
          icon: Icons.public,
          availability: dashboardBacked(),
          unavailableReason: dashboardReason(),
        ),
        // Account usage capability is independent of the current model catalog.
        // Keep a stable list even when discovery fails or only returns aliases
        // such as openai-codex; route OpenAI through the canonical openai ID.
        for (final provider in providerTitles.entries)
          MoreEntry(
            id: provider.key,
            title: provider.value,
            subtitle: l10n.provider_usage,
            icon: Icons.public,
            availability: dashboardBacked(),
            unavailableReason: dashboardReason(),
          ),
      ],
    ),
    MoreSection(
      title: l10n.system,
      entries: [
        MoreEntry(
          id: 'settings',
          title: l10n.settings,
          subtitle: l10n.connection_appearance_and_device_preferences,
          icon: Icons.settings_outlined,
        ),
        MoreEntry(
          id: 'dashboard',
          title: l10n.open_the_hermes_dashboard,
          subtitle:
              l10n.everything_not_yet_native_in_the_authenticated_web_dashboard,
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
                color: dimmed ? tokens.raised : tokens.accentContainer,
                borderRadius: BorderRadius.circular(HermesRadius.sm),
              ),
              child: Icon(
                entry.icon,
                size: 20,
                color: dimmed ? tokens.muted : tokens.onAccentContainer,
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
                        StatusChip(
                          status: HermesStatus.idle,
                          label: context.l10n.coming_next,
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
