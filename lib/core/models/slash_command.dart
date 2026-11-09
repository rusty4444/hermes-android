/// One slash command advertised by the gateway's `commands.catalog` RPC.
class SlashCommand {
  const SlashCommand({
    required this.name,
    this.description = '',
    this.category = '',
  });

  /// Canonical name without the leading slash, exactly as the gateway
  /// dispatches it.
  final String name;
  final String description;
  final String category;

  String get invocation => '/$name';
}

/// The commands the current gateway build dispatches through `slash.exec`.
///
/// A catalogue may advertise its own execution set; when it does not, this is
/// the reviewed fallback from the gateway contract. Everything outside the set
/// keeps the pre-existing send-as-text behaviour.
const Set<String> kSlashExecutableCommands = {
  'help',
  'commands',
  'status',
  'context',
  'version',
  'whoami',
  'usage',
  'insights',
  'profile',
  'diff',
  'memory',
  'kanban',
  'topup',
  'suggestions',
  'bundles',
  'skills',
  'title',
  'reasoning',
  'voice',
  'approvals',
  'codex-runtime',
  'footer',
  'busy',
  'verbose',
  'yolo',
  'fast',
  'personality',
  'goal',
  'subgoal',
  'loop',
  'heartbeat',
  'review',
  'refine',
  'debug',
  'curator',
  'autoprune',
  'approve',
  'deny',
  'plan',
  'learn',
  'init',
  'moa',
  'blueprint',
  'egress',
  'toolsets',
  'platforms',
  'cron',
};

/// Parsed `commands.catalog` response.
///
/// The wire format is tolerant by design: the gateway is free to ship a bare
/// list, a `commands` envelope, or string entries, and older builds omit the
/// execution set entirely.
class SlashCommandCatalog {
  const SlashCommandCatalog({required this.commands, required this.executable});

  final List<SlashCommand> commands;

  /// Canonical names the server will execute. Falls back to
  /// [kSlashExecutableCommands] when the response does not advertise a set.
  final Set<String> executable;

  bool canExecute(String name) => executable.contains(name);

  static SlashCommandCatalog fromResult(Object? result) {
    final rawCommands = result is Map
        ? (result['commands'] ?? result['entries'] ?? result['items'])
        : result;
    final commands = <String, SlashCommand>{};
    if (rawCommands is List) {
      for (final entry in rawCommands) {
        final command = _command(entry);
        if (command != null) commands[command.name] = command;
      }
    }
    return SlashCommandCatalog(
      commands: List<SlashCommand>.unmodifiable(commands.values),
      executable: _executableNames(result) ?? kSlashExecutableCommands,
    );
  }

  /// The gateway may advertise its execution set as a list of names or
  /// command maps under one of these keys. An absent key means "use the
  /// reviewed fallback", never "nothing is executable".
  static Set<String>? _executableNames(Object? result) {
    if (result is! Map) return null;
    final raw =
        result['executable'] ?? result['supported'] ?? result['slash_exec'];
    if (raw is! List) return null;
    final names = <String>{};
    for (final entry in raw) {
      final name = _entryName(entry);
      if (name != null) names.add(name);
    }
    return names.isEmpty ? null : Set<String>.unmodifiable(names);
  }

  static SlashCommand? _command(Object? entry) {
    if (entry is String) {
      final name = _normaliseName(entry);
      return name == null ? null : SlashCommand(name: name);
    }
    if (entry is! Map) return null;
    final name = _normaliseName(_entryName(entry));
    if (name == null) return null;
    return SlashCommand(
      name: name,
      description: _text(
        entry['description'] ?? entry['help'] ?? entry['summary'],
      ),
      category: _text(entry['category'] ?? entry['group'] ?? entry['source']),
    );
  }

  static String? _entryName(Object? entry) {
    if (entry is String) return _normaliseName(entry);
    if (entry is! Map) return null;
    return _normaliseName(entry['name'] ?? entry['command'] ?? entry['slash']);
  }

  /// Canonical names are bare tokens. A gateway that echoes `/help` is
  /// normalised to `help`; anything with whitespace is not a command.
  static String? _normaliseName(Object? value) {
    if (value is! String) return null;
    var name = value.trim();
    if (name.startsWith('/')) name = name.substring(1);
    if (name.isEmpty || name.contains(RegExp(r'\s'))) return null;
    return name;
  }

  static String _text(Object? value) {
    if (value is! String) return '';
    return value.replaceAll('\u0000', '').trim();
  }
}

/// What a `slash.exec` result asks the app to do.
enum SlashCommandResultKind { exec, prompt, unsupported }

class SlashCommandResult {
  const SlashCommandResult._(this.kind, this.text);

  const SlashCommandResult.exec(String output)
    : this._(SlashCommandResultKind.exec, output);

  const SlashCommandResult.prompt(String message)
    : this._(SlashCommandResultKind.prompt, message);

  const SlashCommandResult.unsupported()
    : this._(SlashCommandResultKind.unsupported, '');

  final SlashCommandResultKind kind;
  final String text;

  bool get isExecuted => kind == SlashCommandResultKind.exec;

  bool get isPrompt => kind == SlashCommandResultKind.prompt;

  static SlashCommandResult fromResult(Object? result) {
    if (result is! Map) return const SlashCommandResult.unsupported();
    final text = _resultText(
      result['output'] ?? result['message'] ?? result['text'],
    );
    return switch (result['type']) {
      'exec' => SlashCommandResult.exec(text),
      // `skill` and `send` both hand the app a message it must submit as an
      // ordinary prompt. An empty directive is not actionable.
      'skill' || 'send' when text.isNotEmpty => SlashCommandResult.prompt(text),
      _ => const SlashCommandResult.unsupported(),
    };
  }

  static String _resultText(Object? value) {
    if (value is! String) return '';
    return value.replaceAll('\u0000', '').trimRight();
  }
}
