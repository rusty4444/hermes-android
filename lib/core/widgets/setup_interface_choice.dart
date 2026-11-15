import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Lets a new user choose the interface before connecting to a gateway.
class SetupInterfaceChoice extends StatelessWidget {
  const SetupInterfaceChoice({
    super.key,
    required this.nextGen,
    required this.onSelected,
  });

  final bool nextGen;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      key: const Key('setup-interface-choice'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.setup_interface_title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(
                      l10n.setup_interface_classic,
                      key: const Key('setup-interface-classic'),
                    ),
                    icon: const Icon(Icons.grid_view_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(
                      l10n.setup_interface_nextgen,
                      key: const Key('setup-interface-nextgen'),
                    ),
                    icon: const Icon(Icons.auto_awesome),
                  ),
                ],
                selected: {nextGen},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => onSelected(selection.single),
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '${l10n.setup_interface_classic}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: l10n.setup_interface_classic_description),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '${l10n.setup_interface_nextgen}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: l10n.setup_interface_nextgen_description),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.setup_interface_switch_later,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
