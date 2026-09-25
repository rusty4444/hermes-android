import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/chat_detail_visibility.dart';

/// Settings card choosing how tool activity and reasoning cards appear in chat.
class ChatDetailVisibilityCard extends StatefulWidget {
  const ChatDetailVisibilityCard({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<ChatDetailVisibilityCard> createState() =>
      _ChatDetailVisibilityCardState();
}

class _ChatDetailVisibilityCardState extends State<ChatDetailVisibilityCard> {
  late final ChatDetailVisibilityStore _store;
  late ChatDetailVisibility _toolActivity;
  late ChatDetailVisibility _reasoning;

  @override
  void initState() {
    super.initState();
    _store = ChatDetailVisibilityStore(widget.preferences);
    _toolActivity = _store.readToolActivity();
    _reasoning = _store.readReasoning();
  }

  Future<void> _setToolActivity(ChatDetailVisibility value) async {
    await _store.saveToolActivity(value);
    if (mounted) setState(() => _toolActivity = value);
  }

  Future<void> _setReasoning(ChatDetailVisibility value) async {
    await _store.saveReasoning(value);
    if (mounted) setState(() => _reasoning = value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat detail cards',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Auto opens cards while work runs or in verbose mode. '
              'Collapsed keeps them closed until tapped. Hidden removes them '
              'from the chat display only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _VisibilityRow(
              key: const Key('chat-tool-activity-visibility'),
              icon: Icons.build_outlined,
              title: 'Tool activity',
              value: _toolActivity,
              onChanged: _setToolActivity,
            ),
            const SizedBox(height: 12),
            _VisibilityRow(
              key: const Key('chat-reasoning-visibility'),
              icon: Icons.psychology_outlined,
              title: 'Reasoning',
              value: _reasoning,
              onChanged: _setReasoning,
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final ChatDetailVisibility value;
  final ValueChanged<ChatDetailVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ChatDetailVisibility>(
            showSelectedIcon: false,
            segments: [
              for (final visibility in ChatDetailVisibility.values)
                ButtonSegment<ChatDetailVisibility>(
                  value: visibility,
                  label: Text(visibility.label),
                ),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.single),
          ),
        ),
      ],
    );
  }
}
