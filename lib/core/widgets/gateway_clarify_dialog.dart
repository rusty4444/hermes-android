import 'package:flutter/material.dart';

import '../models/gateway_clarify.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

typedef ClarifyResponder = Future<void> Function(String answer);

/// Whether the card may still close the route it was opened in.
///
/// A gateway `request.cancel` closes the card itself while an answer is in
/// flight, and the screen that opened the card may have opened the next
/// question's card by the time [ClarifyResponder] completes. Popping then
/// closes whatever route is on top instead — the chat screen, or the next
/// question — so the card asks before it pops.
typedef ClarifyRouteOwner = bool Function();

class GatewayClarifyDialog extends StatefulWidget {
  final GatewayClarifyRequest request;
  final ClarifyResponder onRespond;

  /// Defaults to owning the route: a card mounted as a route of its own
  /// (tests, a single-question prompt) closes itself.
  final ClarifyRouteOwner? canCloseRoute;

  const GatewayClarifyDialog({
    required this.request,
    required this.onRespond,
    this.canCloseRoute,
    super.key,
  });

  @override
  State<GatewayClarifyDialog> createState() => _GatewayClarifyDialogState();
}

class _GatewayClarifyDialogState extends State<GatewayClarifyDialog> {
  final TextEditingController _otherController = TextEditingController();
  final Set<int> _selectedIndices = {};
  int? _selectedIndex;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String get _answer {
    final custom = _otherController.text.trim();
    if (!widget.request.multiSelect) {
      if (custom.isNotEmpty) return custom;
      final selectedIndex = _selectedIndex;
      return selectedIndex == null ? '' : widget.request.choices[selectedIndex];
    }

    final ordered = _selectedIndices.toList()..sort();
    final parts = [
      for (final index in ordered) widget.request.choices[index],
      if (custom.isNotEmpty) custom,
    ];
    return parts.join(', ');
  }

  void _selectChoice(int index) {
    if (_submitting) return;
    setState(() {
      _error = null;
      if (widget.request.multiSelect) {
        if (!_selectedIndices.add(index)) {
          _selectedIndices.remove(index);
        }
      } else {
        _selectedIndex = index;
        _otherController.clear();
      }
    });
  }

  Future<void> _respond(String answer) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onRespond(answer);
      // The answer may have been sent while the gateway cancelled the request:
      // the cancellation closes this card's route, and the screen may already
      // have opened the next question's card. Popping then would close a route
      // this card no longer owns.
      if (mounted && (widget.canCloseRoute?.call() ?? true)) {
        final route = ModalRoute.of<bool>(context)!;
        final navigator = Navigator.of(context);
        if (route.isCurrent) {
          navigator.pop(true);
        } else {
          // An approval can open above clarify while clarify.lock is pending.
          // A normal pop would close that approval, not this answered card.
          navigator.removeRoute(route, true);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            context.l10n.hermes_could_not_accept_the_answer_please_try_again;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final answer = _answer;

    return AlertDialog(
      icon: const Icon(Icons.help_outline_rounded),
      title: Text(context.l10n.hermes_needs_your_input),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                request.question,
                key: const Key('clarify-question'),
                style: theme.textTheme.titleMedium,
              ),
              if (request.hasChoices) ...[
                const SizedBox(height: 12),
                Text(
                  request.multiSelect
                      ? context.l10n.select_one_or_more_options_then_continue
                      : context.l10n.select_one_option_or_enter_another_answer,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                for (var index = 0; index < request.choices.length; index++)
                  Semantics(
                    selected: request.multiSelect
                        ? _selectedIndices.contains(index)
                        : _selectedIndex == index,
                    button: true,
                    child: ListTile(
                      key: Key('clarify-choice-$index'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        request.multiSelect
                            ? (_selectedIndices.contains(index)
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded)
                            : (_selectedIndex == index
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded),
                      ),
                      title: Text(request.choices[index]),
                      enabled: !_submitting,
                      onTap: () => _selectChoice(index),
                    ),
                  ),
              ],
              SizedBox(height: request.hasChoices ? 8 : 16),
              TextField(
                key: const Key('clarify-other-field'),
                controller: _otherController,
                autofocus: !request.hasChoices,
                enabled: !_submitting,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: request.hasChoices
                      ? context.l10n.other_answer
                      : context.l10n.your_answer,
                ),
                onChanged: (value) {
                  setState(() {
                    _error = null;
                    if (!request.multiSelect && value.trim().isNotEmpty) {
                      _selectedIndex = null;
                    }
                  });
                },
                onSubmitted: (_) {
                  final currentAnswer = _answer;
                  if (currentAnswer.isNotEmpty) _respond(currentAnswer);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('clarify-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('clarify-skip'),
          onPressed: _submitting ? null : () => _respond(''),
          child: Text(context.l10n.skip),
        ),
        FilledButton(
          key: const Key('clarify-continue'),
          onPressed: _submitting || answer.isEmpty
              ? null
              : () => _respond(answer),
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.continue_label),
        ),
      ],
    );
  }
}
