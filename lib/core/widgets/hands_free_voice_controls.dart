import 'package:flutter/material.dart';

import '../controllers/hands_free_conversation_controller.dart';
import '../l10n/l10n.dart';

class HandsFreeVoiceControls extends StatelessWidget {
  const HandsFreeVoiceControls({
    super.key,
    required this.controller,
    required this.onStart,
    required this.onStop,
    required this.followupTimeout,
    required this.onFollowupChanged,
  });
  final HandsFreeConversationController controller;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final Duration followupTimeout;
  final ValueChanged<int> onFollowupChanged;

  String _status(BuildContext context) => switch (controller.state) {
    HandsFreeState.idle =>
      controller.permissionSetupComplete
          ? context.l10n.hands_free_setup_complete
          : context.l10n.hands_free_title,
    HandsFreeState.listening =>
      controller.ready
          ? context.l10n.hands_free_listening
          : context.l10n.hands_free_preparing,
    HandsFreeState.recording =>
      controller.ready
          ? context.l10n.hands_free_recording
          : context.l10n.hands_free_preparing,
    HandsFreeState.waiting => context.l10n.hands_free_waiting,
    HandsFreeState.speaking => context.l10n.hands_free_speaking,
    HandsFreeState.followup =>
      controller.ready
          ? context.l10n.hands_free_followup(followupTimeout.inSeconds)
          : context.l10n.hands_free_preparing,
    HandsFreeState.error => context.l10n.hands_free_error,
  };
  @override
  Widget build(BuildContext context) {
    final active =
        controller.active || controller.state == HandsFreeState.error;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(_status(context), key: const Key('hands-free-state')),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (active)
                TextButton.icon(
                  key: const Key('hands-free-stop'),
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  label: Text(context.l10n.hands_free_stop),
                )
              else
                TextButton(
                  key: const Key('hands-free-start'),
                  onPressed: controller.starting ? null : onStart,
                  child: Text(context.l10n.hands_free_start),
                ),
              IconButton(
                key: const Key('hands-free-info'),
                tooltip: context.l10n.hands_free_setup,
                onPressed: () => _settings(context),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          if (controller.preview.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: Text(
                context.l10n.hands_free_preview(controller.preview),
                key: const Key('hands-free-preview'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (!active)
            Text(
              context.l10n.hands_free_short_disclosure,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (controller.state == HandsFreeState.error)
            Text(
              context.l10n.hands_free_error_action,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Future<void> _settings(BuildContext context) async {
    final selected = await showHandsFreeSetup(
      context,
      followupTimeout: followupTimeout,
      confirmStart: false,
    );
    if (selected != null) onFollowupChanged(selected);
  }
}

/// A setup modal cannot start capture. It returns only the user's explicit
/// preference/Start intent to the still-current owning chat.
Future<int?> showHandsFreeSetup(
  BuildContext context, {
  required Duration followupTimeout,
  bool confirmStart = true,
}) {
  var seconds = followupTimeout.inSeconds;
  return showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.l10n.hands_free_setup),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.hands_free_disclosure),
              const SizedBox(height: 12),
              Text(context.l10n.hands_free_ready_cue),
              const SizedBox(height: 12),
              Text(context.l10n.hands_free_timing_limit),
              const SizedBox(height: 12),
              Text(
                seconds == 0
                    ? context.l10n.hands_free_followup_off
                    : context.l10n.hands_free_followup(seconds),
              ),
              Slider(
                value: seconds.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: context.l10n.hands_free_followup(seconds),
                onChanged: (value) => setState(() => seconds = value.round()),
              ),
            ],
          ),
        ),
        actions: [
          if (confirmStart)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
          TextButton(
            key: const Key('hands-free-confirm-start'),
            onPressed: () => Navigator.pop(context, seconds),
            child: Text(
              confirmStart ? context.l10n.hands_free_start : context.l10n.save,
            ),
          ),
        ],
      ),
    ),
  );
}
