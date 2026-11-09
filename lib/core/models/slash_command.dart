/// One slash command advertised by the gateway's `commands.catalog` RPC.
class SlashCommand {
  const SlashCommand({
    required this.name,
    this.description = '',
    this.category = '',
    this.argumentMode,
  });

  /// Canonical name without the leading slash, exactly as the gateway
  /// dispatches it.
  final String name;
  final String description;
  final String category;

  /// The gateway's argument hint for this command (`options`, `text` or
  /// `mixed`), when the catalogue carries one.
  final String? argumentMode;

  String get invocation => '/$name';
}

/// Last-resort execution hint used only while no catalogue has loaded.
///
/// The gateway owns the dispatchable set (its reviewed read/control/prompt
/// surfaces); a loaded catalogue is authoritative. This constant just keeps a
/// cold session from treating the first typed command as prose before
/// `commands.catalog` answers — the server's deterministic
/// `unsupported_command` reply still falls back to a plain send.
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

/// Parsed `commands.catalog` response (`CommandsCatalogResult`).
///
/// The real wire shape is a map of `pairs` (ordered `[/name, description]`
/// rows), `categories[]` (the same rows grouped for display), `skills` (keyed
/// usage metadata), `plugin_commands` (name without slash → description) and a
/// `commands` DICT of per-command metadata such as `argument_mode`. Aliases
/// live in `canon`, but `pairs` only carries canonical names; entries are
/// deduplicated by canonical (bare, case-insensitive) name.
class SlashCommandCatalog {
  SlashCommandCatalog({
    required List<SlashCommand> commands,
    required Set<String> executable,
  }) : commands = List<SlashCommand>.unmodifiable(commands),
       executable = Set<String>.unmodifiable(executable);

  final List<SlashCommand> commands;

  /// Canonical (bare, lowercase) names the gateway dispatches.
  final Set<String> executable;

  bool canExecute(String name) {
    final canonical = _canonicalName(name);
    return canonical != null && executable.contains(canonical);
  }

  static SlashCommandCatalog fromResult(Object? result) {
    final builder = _CatalogBuilder(
      _argumentModes(result is Map ? result['commands'] : null),
      _canonMap(result is Map ? result['canon'] : null),
    );
    if (result is List) {
      // Tolerant legacy shape: a bare list of `/name` strings or command maps.
      _addEntries(builder, result);
      return _build(builder, null);
    }
    if (result is! Map) return _build(builder, null);

    final categories = _categories(result['categories']);
    // Registry order first: `pairs` is every [key, description] row.
    _addPairs(builder, result['pairs'], categories.byKey);
    // A category row can add a pair the flat list omitted; keep its label.
    for (final category in categories.rows) {
      _addPairs(
        builder,
        category.pairs,
        categories.byKey,
        fallbackCategory: category.name,
      );
    }
    // Every plugin command, including one a display row hides from
    // `categories`. The keys carry no slash; the app always renders one.
    final pluginCommands = result['plugin_commands'];
    if (pluginCommands is Map) {
      for (final entry in pluginCommands.entries) {
        builder.add(
          entry.key,
          description: _text(entry.value),
          category: 'Plugin commands',
        );
      }
    }
    // Skills are usually in `pairs` already; `skills` also lists the ones whose
    // name collides with a built-in (no `/<name>` row). Those have no
    // description of their own.
    final skills = result['skills'];
    if (skills is Map) {
      for (final key in skills.keys) {
        builder.add(key, category: 'Skills');
      }
    }
    // Tolerant legacy envelopes: a list under `commands`, `entries` or `items`.
    for (final legacy in [result['commands'], result['entries'], result['items']]) {
      if (legacy is List) _addEntries(builder, legacy);
    }
    return _build(builder, result);
  }

  static SlashCommandCatalog _build(
    _CatalogBuilder builder,
    Object? result,
  ) {
    return SlashCommandCatalog(
      commands: builder.commands,
      // A gateway that advertises its own execution set wins; otherwise every
      // catalogued name is dispatchable and the server still refuses politely.
      executable: _advertisedExecutable(result) ?? builder.names,
    );
  }

  /// Legacy tolerance: an explicit dispatch set under one of these keys. The
  /// real contract has none — the catalogue itself is the set.
  static Set<String>? _advertisedExecutable(Object? result) {
    if (result is! Map) return null;
    final raw =
        result['executable'] ?? result['supported'] ?? result['slash_exec'];
    if (raw is! List) return null;
    final names = <String>{};
    for (final entry in raw) {
      final name = _canonicalName(entry is Map ? _entryName(entry) : entry);
      if (name != null) names.add(name);
    }
    return names.isEmpty ? null : names;
  }

  static void _addPairs(
    _CatalogBuilder builder,
    Object? raw,
    Map<String, String> categoryOf, {
    String fallbackCategory = '',
  }) {
    for (final pair in _pairs(raw)) {
      builder.add(
        pair.name,
        description: pair.description,
        category: categoryOf[_canonicalName(pair.name)] ?? fallbackCategory,
      );
    }
  }

  static void _addEntries(_CatalogBuilder builder, List<Object?> entries) {
    for (final entry in entries) {
      if (entry is String) {
        builder.add(entry);
        continue;
      }
      if (entry is! Map) continue;
      final name = _entryName(entry);
      if (name == null) continue;
      builder.add(
        name,
        description: _text(
          entry['description'] ?? entry['help'] ?? entry['summary'],
        ),
        category: _text(entry['category'] ?? entry['group'] ?? entry['source']),
      );
    }
  }

  static _CatalogCategories _categories(Object? raw) {
    final rows = <_CatalogCategory>[];
    final byKey = <String, String>{};
    if (raw is! List) return _CatalogCategories(rows, byKey);
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = _text(entry['name']);
      final pairs = _pairs(entry['pairs']);
      rows.add(_CatalogCategory(name, pairs));
      for (final pair in pairs) {
        final key = _canonicalName(pair.name);
        if (key != null) byKey.putIfAbsent(key, () => name);
      }
    }
    return _CatalogCategories(rows, byKey);
  }

  /// `canon` maps a lowercased alias key to its canonical name.
  static Map<String, String> _canonMap(Object? raw) {
    final canon = <String, String>{};
    if (raw is! Map) return canon;
    for (final entry in raw.entries) {
      final alias = _canonicalName(entry.key);
      final target = _bareName(entry.value);
      if (alias != null && target != null) canon[alias] = target;
    }
    return canon;
  }

  /// `commands` is a DICT of `{"/name": {argument_mode, desktop, ...}}`.
  static Map<String, String> _argumentModes(Object? raw) {
    final modes = <String, String>{};
    if (raw is! Map) return modes;
    for (final entry in raw.entries) {
      final key = _canonicalName(entry.key);
      if (key == null) continue;
      final value = entry.value;
      final mode = value is Map ? _text(value['argument_mode']) : '';
      if (const {'options', 'text', 'mixed'}.contains(mode)) {
        modes[key] = mode;
      }
    }
    return modes;
  }

  static List<_CatalogPair> _pairs(Object? raw) {
    if (raw is! List) return const [];
    final pairs = <_CatalogPair>[];
    for (final entry in raw) {
      if (entry is List && entry.isNotEmpty) {
        final name = _bareName(entry.first);
        if (name == null) continue;
        pairs.add(
          _CatalogPair(name, entry.length > 1 ? _text(entry[1]) : ''),
        );
        continue;
      }
      if (entry is String) {
        final name = _bareName(entry);
        if (name != null) pairs.add(_CatalogPair(name, ''));
        continue;
      }
      if (entry is Map) {
        final name = _bareName(_entryName(entry));
        if (name == null) continue;
        pairs.add(
          _CatalogPair(
            name,
            _text(entry['description'] ?? entry['help'] ?? entry['summary']),
          ),
        );
      }
    }
    return pairs;
  }

  static String? _entryName(Map entry) {
    final name = entry['name'] ?? entry['command'] ?? entry['slash'];
    return name is String ? name : null;
  }

  /// Canonical names are bare tokens. A gateway that echoes `/help` is
  /// normalised to `help`; anything with whitespace is not a command.
  static String? _bareName(Object? value) {
    if (value is! String) return null;
    var name = value.trim();
    while (name.startsWith('/')) {
      name = name.substring(1);
    }
    if (name.isEmpty || name.contains(RegExp(r'\s'))) return null;
    return name;
  }

  static String? _canonicalName(Object? value) => _bareName(value)?.toLowerCase();

  static String _text(Object? value) {
    if (value is! String) return '';
    return value.replaceAll('\u0000', '').trim();
  }
}

class _CatalogPair {
  const _CatalogPair(this.name, this.description);

  final String name;
  final String description;
}

class _CatalogCategory {
  const _CatalogCategory(this.name, this.pairs);

  final String name;
  final List<_CatalogPair> pairs;
}

class _CatalogCategories {
  const _CatalogCategories(this.rows, this.byKey);

  final List<_CatalogCategory> rows;
  final Map<String, String> byKey;
}

/// Accumulates catalogue rows in gateway order, filling gaps (description,
/// category, argument mode) from later passes instead of duplicating a name.
class _CatalogBuilder {
  _CatalogBuilder(this._argumentModes, this._canon);

  final Map<String, String> _argumentModes;
  final Map<String, String> _canon;
  final List<SlashCommand> _commands = [];
  final Map<String, int> _index = {};
  final Set<String> _accepted = {};

  List<SlashCommand> get commands => _commands;

  /// Canonical names plus every alias the gateway said it accepts.
  Set<String> get names => {..._index.keys, ..._accepted};

  void add(
    Object? raw, {
    String description = '',
    String category = '',
  }) {
    final bare = SlashCommandCatalog._bareName(raw);
    final unaliased = SlashCommandCatalog._canonicalName(raw);
    if (bare == null || unaliased == null) return;
    // An alias row is the same command: resolve through `canon` and dedupe on
    // the canonical key.
    final name = _canon[unaliased] ?? bare;
    final key = name.toLowerCase();
    _accepted.add(unaliased);
    final mode = _argumentModes[key] ?? _argumentModes[unaliased];
    final index = _index[key];
    if (index == null) {
      _index[key] = _commands.length;
      _commands.add(
        SlashCommand(
          name: name,
          description: description,
          category: category,
          argumentMode: mode,
        ),
      );
      return;
    }
    final current = _commands[index];
    _commands[index] = SlashCommand(
      name: current.name,
      description: current.description.isNotEmpty
          ? current.description
          : description,
      category: current.category.isNotEmpty ? current.category : category,
      argumentMode: current.argumentMode ?? mode,
    );
  }
}

/// What a `slash.exec` result asks the app to do.
enum SlashCommandResultKind { exec, prompt, prefill }

/// Parsed `SlashExecResult`.
///
/// The plain worker/plugin form is `{"output": ..., "warning": ...}` with NO
/// `type`; `type` is only set when the gateway rerouted the command to
/// `command.dispatch` (`exec`, `alias`, `plugin`, `send`, `skill`, `prefill`).
class SlashCommandResult {
  const SlashCommandResult._(this.kind, this.text);

  const SlashCommandResult.exec(String output)
    : this._(SlashCommandResultKind.exec, output);

  const SlashCommandResult.prompt(String message)
    : this._(SlashCommandResultKind.prompt, message);

  const SlashCommandResult.prefill(String message)
    : this._(SlashCommandResultKind.prefill, message);

  final SlashCommandResultKind kind;
  final String text;

  bool get isExecuted => kind == SlashCommandResultKind.exec;

  bool get isPrompt => kind == SlashCommandResultKind.prompt;

  bool get isPrefill => kind == SlashCommandResultKind.prefill;

  static SlashCommandResult fromResult(Object? result) {
    if (result is! Map) return const SlashCommandResult.exec('');
    final output = _resultText(result['output']);
    final warning = _resultText(result['warning']);
    final type = _resultText(result['type']).toLowerCase();
    // Output is authoritative whatever `type` says (or omits).
    if (output.isNotEmpty) {
      return SlashCommandResult.exec(_withWarning(output, warning));
    }
    switch (type) {
      case 'skill':
      case 'send':
        final message = _resultText(result['message']);
        return message.isEmpty
            ? const SlashCommandResult.exec('')
            : SlashCommandResult.prompt(message);
      case 'prefill':
        final message = _resultText(result['message']);
        return message.isEmpty
            ? const SlashCommandResult.exec('')
            : SlashCommandResult.prefill(message);
      case 'alias':
        // An alias reply names `target`; UIs render `display`. The app does not
        // re-dispatch, so surface what the gateway told us and never re-send.
        return SlashCommandResult.exec(
          _withWarning(_directiveText(result, slashTarget: true), warning),
        );
      case 'exec':
      case 'plugin':
        return SlashCommandResult.exec(
          _withWarning(_directiveText(result), warning),
        );
    }
    // Neither output nor a recognised directive: the command completed here.
    return SlashCommandResult.exec(
      _withWarning(_directiveText(result), warning),
    );
  }

  /// `display`/`notice` are the renderable fields of a dispatch directive.
  static String _directiveText(Map result, {bool slashTarget = false}) {
    final display = _resultText(result['display']);
    if (display.isNotEmpty) return display;
    final notice = _resultText(result['notice']);
    if (notice.isNotEmpty) return notice;
    if (!slashTarget) return '';
    final target = _resultText(result['target']);
    if (target.isEmpty) return '';
    return target.startsWith('/') ? target : '/$target';
  }

  static String _withWarning(String text, String warning) {
    if (warning.isEmpty) return text;
    if (text.isEmpty) return warning;
    return '$text\n\n$warning';
  }

  static String _resultText(Object? value) {
    if (value is! String) return '';
    return value.replaceAll('\u0000', '').trimRight();
  }
}

/// Payload of a local slash-command output card.
///
/// Command output is local transcript context, never an assistant turn:
/// identity is per observation so repeated `/status` runs each keep a card.
class SlashCommandNotice {
  const SlashCommandNotice({
    required this.command,
    required this.output,
    required this.observedAt,
  });

  final String command;
  final String output;
  final int observedAt;

  String get identity => '$command|$observedAt';
}

/// The narrow gateway surface the slash-command feature needs.
///
/// [DesktopGatewayClient] implements it; tests provide a double without a
/// socket. `onSent` fires after the request is written to the transport, which
/// separates "never sent, safe to fall back" from "delivery unknown".
abstract interface class SlashCommandGateway {
  bool get slashCommandsSupported;

  Future<SlashCommandCatalog> fetchSlashCommands({String? sessionId});

  Future<SlashCommandResult> runSlashCommand({
    required String sessionId,
    required String command,
    void Function()? onSent,
  });
}
