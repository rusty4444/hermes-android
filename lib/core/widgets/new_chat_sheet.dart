/// The sheet behind Home's global **New** button.
///
/// Presentation only: every decision about which modes exist, which are
/// runnable, and what a drafted chat looks like lives in the pure
/// `lib/core/utils/new_chat_options.dart` helper.
///
/// The one rule this file owns is the roadmap's capability-discovery rule made
/// visible: a mode that cannot run is drawn *disabled with its reason*, never
/// removed from the sheet. A user who cannot start a Project chat should learn
/// why, not wonder where the option went.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'package:flutter/material.dart';

import '../models/hermes_project.dart';
import '../theme/hermes_theme.dart';
import '../utils/new_chat_options.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Asks which chat to start. Pops the chosen mode, or null when dismissed.
class NewChatSheet extends StatelessWidget {
  final List<NewChatOption> options;

  const NewChatSheet({required this.options, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.sm,
            ),
            child: Text(
              context.l10n.start_something_new,
              style: tokens.typography.title.copyWith(color: tokens.onSurface),
            ),
          ),
          for (final option in options)
            ListTile(
              enabled: option.enabled,
              // A disabled row still explains itself, so the reason replaces
              // the description rather than hiding beside it.
              title: Text(option.label(context.l10n)),
              subtitle: Text(
                option.disabledReason ?? option.description(context.l10n),
              ),
              leading: Icon(
                option.mode == NewChatMode.quickChat
                    ? Icons.bolt_outlined
                    : Icons.folder_outlined,
              ),
              onTap: option.enabled
                  ? () => Navigator.of(context).pop(option.mode)
                  : null,
            ),
          const SizedBox(height: HermesSpacing.md),
        ],
      ),
    );
  }
}

/// Asks which project a new Project chat belongs to.
///
/// Creation may skip a single choice. Moves always ask for an explicit target.
class ProjectPickerSheet extends StatelessWidget {
  final List<HermesProject> projects;
  final bool requireFolder;

  const ProjectPickerSheet({
    required this.projects,
    this.requireFolder = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.sm,
            ),
            child: Text(
              context.l10n.which_project,
              style: tokens.typography.title.copyWith(color: tokens.onSurface),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final project in projects)
                  ListTile(
                    enabled:
                        !requireFolder ||
                        (project.workingDirectory?.trim().isNotEmpty ?? false),
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(project.name),
                    subtitle:
                        requireFolder &&
                            (project.workingDirectory?.trim().isEmpty ?? true)
                        ? Text(
                            context
                                .l10n
                                .this_project_has_no_folder_to_open_the_chat_in,
                          )
                        : project.workingDirectory == null
                        ? null
                        : Text(
                            project.workingDirectory!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => Navigator.of(context).pop(project),
                  ),
              ],
            ),
          ),
          const SizedBox(height: HermesSpacing.md),
        ],
      ),
    );
  }
}
