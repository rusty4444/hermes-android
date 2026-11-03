import 'package:flutter/material.dart';

import '../controllers/voice_composer_controller.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class VoiceComposerIndicator extends StatelessWidget {
  static const indicatorKey = Key('voice-listening-indicator');
  static const stopKey = Key('voice-stop');
  static const cancelKey = Key('voice-cancel');

  final VoiceComposerController controller;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const VoiceComposerIndicator({
    required this.controller,
    required this.onStop,
    required this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final elapsed = _formatElapsed(controller.elapsed);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: context.l10n.listening_elapsed(elapsed),
      child: Container(
        key: indicatorKey,
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(4, 2, 4, 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 420 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final status = Row(
              mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    context.l10n.listening(elapsed),
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            );
            final actions = Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                Semantics(
                  label: context.l10n.stop_voice_input,
                  button: true,
                  excludeSemantics: true,
                  child: TextButton.icon(
                    key: stopKey,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                    ),
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(context.l10n.stop),
                  ),
                ),
                Semantics(
                  label: context.l10n.cancel_voice_input,
                  button: true,
                  excludeSemantics: true,
                  child: TextButton.icon(
                    key: cancelKey,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                    ),
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: Text(context.l10n.cancel),
                  ),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class VoiceComposerStartButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const VoiceComposerStartButton({
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.start_voice_input,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      child: IconButton.filledTonal(
        icon: const Icon(Icons.mic),
        onPressed: enabled ? onPressed : null,
        tooltip: context.l10n.speak_to_hermes,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}
