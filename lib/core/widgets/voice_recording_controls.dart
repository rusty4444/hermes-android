import 'package:flutter/material.dart';

import '../controllers/voice_recording_controller.dart';
import '../l10n/l10n.dart';

/// Local recording controls. Server recognition begins only when Send is tapped.
class VoiceRecordingControls extends StatelessWidget {
  final VoiceRecordingController controller;
  final VoidCallback onSend;
  final bool canSend;

  const VoiceRecordingControls({
    required this.controller,
    required this.onSend,
    this.canSend = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final l10n = context.l10n;
      final time =
          '${controller.elapsed.inMinutes}:${(controller.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
      final actions = Wrap(
        alignment: WrapAlignment.end,
        children: [
          if (controller.recording)
            IconButton(
              key: const Key('voice-recording-stop'),
              tooltip: l10n.voice_recording_pause,
              onPressed: controller.busy ? null : controller.stop,
              icon: const Icon(Icons.pause),
            ),
          if (controller.hasDraft && !controller.recording) ...[
            IconButton(
              key: const Key('voice-recording-play'),
              tooltip: controller.playing
                  ? l10n.voice_recording_pause_playback
                  : l10n.voice_recording_preview,
              onPressed: controller.busy ? null : controller.togglePlayback,
              icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              key: const Key('voice-recording-resume'),
              tooltip: l10n.voice_recording_resume,
              onPressed: controller.busy ? null : controller.resumeRecording,
              icon: const Icon(Icons.mic),
            ),
            IconButton(
              key: const Key('voice-recording-send'),
              tooltip: l10n.voice_recording_send,
              onPressed: controller.busy || !canSend ? null : onSend,
              icon: const Icon(Icons.send),
            ),
          ],
          if (!controller.hasDraft && !controller.recording && !controller.busy)
            IconButton(
              tooltip: l10n.voice_recording_start,
              onPressed: controller.start,
              icon: const Icon(Icons.mic),
            ),
          IconButton(
            key: const Key('voice-recording-discard'),
            tooltip: l10n.voice_recording_discard,
            onPressed: controller.busy ? null : controller.discard,
            icon: const Icon(Icons.close),
          ),
        ],
      );
      final status = Row(
        children: [
          if (controller.busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(controller.recording ? Icons.mic : Icons.audio_file_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.busy
                  ? l10n.voice_recording_processing
                  : controller.recording
                  ? l10n.voice_recording_elapsed(time)
                  : l10n.voice_recording_draft(time),
              maxLines: 2,
            ),
          ),
        ],
      );
      return Container(
        key: const Key('voice-recording-controls'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth < 420 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.4
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [status, actions],
                    )
                  : Row(
                      children: [
                        Expanded(child: status),
                        actions,
                      ],
                    ),
            ),
            if (controller.error != null)
              Text(
                _failure(context, controller.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    },
  );

  String _failure(BuildContext context, VoiceRecordingFailure failure) {
    final l10n = context.l10n;
    return switch (failure) {
      VoiceRecordingFailure.microphonePermission =>
        l10n.voice_recording_permission,
      VoiceRecordingFailure.durationLimit => l10n.voice_recording_limit,
      VoiceRecordingFailure.empty => l10n.voice_recording_empty,
      VoiceRecordingFailure.submissionUnconfirmed =>
        l10n.voice_recording_unconfirmed,
      VoiceRecordingFailure.submission => l10n.voice_recording_submit_failed,
      _ => l10n.voice_recording_failed,
    };
  }
}
