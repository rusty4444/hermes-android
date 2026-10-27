import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/chat_space_store.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class SpacesScreen extends StatefulWidget {
  final ChatSpaceStore store;
  final List<Session> sessions;
  final ValueChanged<ChatSpaceScope> onScopeSelected;

  const SpacesScreen({
    required this.store,
    required this.sessions,
    required this.onScopeSelected,
    super.key,
  });

  @override
  State<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends State<SpacesScreen> {
  ChatSpaceState? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await widget.store.load();
    if (mounted) setState(() => _state = state);
  }

  Future<void> _createSpace() async {
    var draft = '';
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.new_space),
          content: TextField(
            key: const Key('space-name'),
            autofocus: true,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.name,
              errorText: error,
            ),
            onChanged: (value) => draft = value,
            onSubmitted: (value) {
              final normalized = value.trim();
              if (normalized.isEmpty) {
                setDialogState(() => error = context.l10n.enter_a_name);
              } else {
                Navigator.pop(dialogContext, normalized);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final normalized = draft.trim();
                if (normalized.isEmpty) {
                  setDialogState(() => error = context.l10n.enter_a_name);
                } else {
                  Navigator.pop(dialogContext, normalized);
                }
              },
              child: Text(context.l10n.create),
            ),
          ],
        ),
      ),
    );
    if (name == null || !mounted) return;
    try {
      await widget.store.createSpace(name);
      await _load();
    } on StateError {
      _showStorageFailure(_createSpace);
    } on FormatException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.message.toString())));
    }
  }

  Future<void> _renameSpace(ChatSpace space) async {
    var draft = space.name;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.rename_space),
        content: TextFormField(
          key: const Key('rename-space-name'),
          initialValue: space.name,
          autofocus: true,
          maxLength: 80,
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) =>
              Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await widget.store.renameSpace(space.id, name);
      await _load();
    } on StateError {
      _showStorageFailure(() => _renameSpace(space));
    } on FormatException catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.message.toString())));
    }
  }

  void _showStorageFailure(VoidCallback retry) {
    if (!mounted) return;
    // Localise the safe storage outcome without exposing provider payloads.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.could_not_save_chat_spaces),
        action: SnackBarAction(label: context.l10n.retry, onPressed: retry),
      ),
    );
  }

  String _countLabel(int count) => context.l10n.chats_count(count);

  String? _activityLabel(double? timestamp) {
    if (timestamp == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).toInt(),
    );
    return context.l10n.last_activity(date.day, date.month, date.year);
  }

  Widget _scopeTile({
    required Key key,
    required IconData icon,
    required String title,
    required int count,
    required ChatSpaceScope scope,
    Widget? trailing,
    String? detail,
  }) {
    return ListTile(
      key: key,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(_countLabel(count)), if (detail != null) Text(detail)],
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: () => widget.onScopeSelected(scope),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.spaces),
        actions: [
          IconButton(
            key: const Key('create-space'),
            tooltip: context.l10n.new_space,
            onPressed: _createSpace,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _scopeTile(
                  key: const Key('space-all'),
                  icon: Icons.forum_outlined,
                  title: context.l10n.all_chats,
                  count: widget.sessions.length,
                  scope: const ChatSpaceScope.all(),
                ),
                _scopeTile(
                  key: const Key('space-unassigned'),
                  icon: Icons.inbox_outlined,
                  title: context.l10n.unassigned,
                  count: state
                      .sessionsFor(
                        widget.sessions,
                        const ChatSpaceScope.unassigned(),
                      )
                      .length,
                  scope: const ChatSpaceScope.unassigned(),
                ),
                if (state.spaces.isNotEmpty) const Divider(),
                for (final space in state.spaces)
                  _scopeTile(
                    key: Key('space-${space.id}'),
                    icon: Icons.folder_outlined,
                    title: space.name,
                    count: state
                        .sessionsFor(
                          widget.sessions,
                          ChatSpaceScope.space(space.id),
                        )
                        .length,
                    scope: ChatSpaceScope.space(space.id),
                    detail: _activityLabel(
                      state.latestActivityFor(widget.sessions, space.id),
                    ),
                    trailing: PopupMenuButton<String>(
                      key: Key('space-menu-${space.id}'),
                      tooltip: context.l10n.space_actions,
                      onSelected: (action) {
                        if (action == 'rename') _renameSpace(space);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text(context.l10n.rename),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.spaces.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      context
                          .l10n
                          .create_a_space_to_separate_related_conversations,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}
