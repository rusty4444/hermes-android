import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/background_report.dart';
import '../models/received_scope_outcome.dart';
import '../services/remote_files_client.dart';
import '../services/tool_activity_group_pins.dart';
import '../utils/chat_display_items.dart';
import 'background_report_card.dart';
import 'gateway_activity_card.dart';
import 'gateway_insight_card.dart';
import 'media_artifact_card.dart';

typedef RecoveryMessageBuilder =
    Widget Function(
      Map<String, dynamic> message,
      bool expanded,
      ValueChanged<bool> onExpansionChanged,
    );

/// Frozen, read-only received output. It owns its own visit-local detail pins.
class ReceivedRecoveryInspector extends StatefulWidget {
  const ReceivedRecoveryInspector({
    required this.section,
    required this.verbose,
    required this.sourceIdentity,
    required this.filesClient,
    required this.messageBuilder,
    super.key,
  });

  final ChatDisplaySection section;
  final bool verbose;
  final Object sourceIdentity;
  final RemoteFilesDataSource Function() filesClient;
  final RecoveryMessageBuilder messageBuilder;

  @override
  State<ReceivedRecoveryInspector> createState() =>
      _ReceivedRecoveryInspectorState();
}

class _ReceivedRecoveryInspectorState extends State<ReceivedRecoveryInspector> {
  final _bucket = PageStorageBucket();
  final _scroll = ScrollController(keepScrollOffset: false);
  final _pins = <Object, bool>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _pin(Object identity, bool expanded) => setState(() {
    _pins.remove(identity);
    _pins[identity] = expanded;
    if (_pins.length > ToolActivityGroupPins.maxPins) {
      _pins.remove(_pins.keys.first);
    }
  });

  Widget _item(dynamic item) {
    final identity = chatDisplayItemIdentity(item);
    final expanded = _pins[identity] ?? false;
    void pin(bool value) => _pin(identity, value);
    Widget child;
    if (item is ChatToolActivityGroup) {
      child = GatewayActivityCard(
        activities: item.activities,
        verbose: widget.verbose,
        pinnedExpansion: expanded,
        onPinChanged: pin,
      );
    } else if (item is ChatReasoningItem) {
      child = GatewayReasoningCard(
        id: item.id,
        text: item.text,
        pinnedExpansion: expanded,
        onPinChanged: pin,
      );
    } else if (item is ChatAttachmentItem) {
      child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MediaArtifactCard(
          ref: item.ref,
          filesClient: widget.filesClient,
          sourceIdentity: widget.sourceIdentity,
        ),
      );
    } else {
      final message = item as Map<String, dynamic>;
      final report = BackgroundReport.fromMessage(message);
      child = report == null
          ? widget.messageBuilder(message, expanded, pin)
          : BackgroundReportCard(
              report: report,
              initiallyExpanded: expanded,
              onExpansionChanged: pin,
            );
    }
    final fact = widget.section.outcomes[identity];
    final localPrompt = item is Map<String, dynamic> && item['role'] == 'user';
    final provenance = localPrompt
        ? context.l10n.local_prompt_context
        : context.l10n.received_output_badge;
    final outcome = switch (fact?.outcome) {
      ReceivedLifecycleOutcome.completed => context.l10n.turn_completed,
      ReceivedLifecycleOutcome.failed => context.l10n.turn_failed,
      ReceivedLifecycleOutcome.unknown => context.l10n.received_outcome_unknown,
      null => null,
    };
    return KeyedSubtree(
      key: ValueKey(identity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.verbose)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                outcome == null ? provenance : '$outcome · $provenance',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .85,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.received_output_heading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const Key('chat-retained-received-close'),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(
            child: PageStorage(
              bucket: _bucket,
              child: ListView.builder(
                // A PageStorageKey here aliases ScrollPosition's double with every
                // unkeyed ExpansionTile's bool. Keep storage/pins explicit instead.
                key: const Key('retained-recovery-inspector'),
                controller: _scroll,
                itemCount: widget.section.items.length + 1,
                itemBuilder: (context, index) => index == 0
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            Text(context.l10n.received_output_explanation),
                            const SizedBox(height: 8),
                            Text(context.l10n.received_output_lifetime),
                          ],
                        ),
                      )
                    : _item(widget.section.items[index - 1]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
