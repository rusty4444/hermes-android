import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/slash_command.dart';

/// Returns the command token when [text] is a single leading slash token.
///
/// This is the dropdown trigger: a trailing space, a newline, an argument or a
/// slash anywhere else is a normal message, so the dropdown never intercepts
/// prose or URLs and only shows while the first token is being typed.
String? slashCommandQuery(String text) {
  if (!text.startsWith('/')) return null;
  if (text.length > 1 && text.contains(RegExp(r'\s'))) return null;
  return text.substring(1);
}

/// Returns the command name at the start of [text], arguments included.
///
/// This is the send gate: the gateway parses the whole line itself
/// (`/title My chat`, `/yolo on`), so only the leading whitespace-delimited
/// token decides whether the line is a command. A lone `/` is not one.
String? slashCommandName(String text) {
  if (!text.startsWith('/')) return null;
  final token = text.split(RegExp(r'\s')).first;
  final name = token.substring(1);
  return name.isEmpty ? null : name;
}

/// Owns slash-command trigger detection, the per-connection catalogue cache
/// and the local per-keystroke filter.
///
/// It never submits a prompt and never edits the composer: execution stays on
/// the chat screen's existing send path so the busy-steer contract from #191
/// keeps exactly one owner.
class SlashCommandController extends ChangeNotifier {
  SlashCommandController({
    required this.loadCatalog,
    String cacheScope = '',
    this.limit = 8,
  }) : _scope = cacheScope;

  final Future<SlashCommandCatalog> Function() loadCatalog;
  final int limit;

  String _scope;
  SlashCommandCatalog? _catalog;
  Object? _catalogError;
  Future<bool>? _flight;
  int _generation = 0;
  bool _open = false;
  String _query = '';
  bool _disposed = false;

  /// Whether the dropdown should be visible for the current draft.
  bool get isOpen => _open && _catalogError == null;

  bool get catalogLoaded => _catalog != null;

  /// A failed catalogue fetch disables the feature without touching the
  /// composer; it never rethrows into the text field's listener.
  bool get catalogUnavailable => _catalogError != null;

  String get query => _query;

  List<SlashCommand> get matches {
    final catalog = _catalog;
    if (catalog == null) return const [];
    final query = _query.toLowerCase();
    if (query.isEmpty) {
      return List<SlashCommand>.unmodifiable(catalog.commands.take(limit));
    }
    final prefix = <SlashCommand>[];
    final contains = <SlashCommand>[];
    for (final command in catalog.commands) {
      final name = command.name.toLowerCase();
      if (name.startsWith(query)) {
        prefix.add(command);
      } else if (name.contains(query)) {
        contains.add(command);
      }
    }
    return List<SlashCommand>.unmodifiable(
      [...prefix, ...contains].take(limit),
    );
  }

  /// Feeds composer text changes into the dropdown. Returns whether [text]
  /// keeps the dropdown open.
  bool updateText(String text) {
    final query = slashCommandQuery(text);
    if (query == null) {
      close();
      return false;
    }
    final opening = !_open || _query != query;
    _open = true;
    _query = query;
    if (opening || _catalog == null) {
      unawaited(ensureCatalog());
    }
    _notify();
    return isOpen;
  }

  /// Loads the catalogue once per scope. Catalogues are read-only, so a
  /// successful response is cached until [invalidate]; a failure is sticky
  /// until the next explicit invalidation (connection change) and never
  /// retried per keystroke.
  Future<bool> ensureCatalog() {
    if (_catalog != null) return Future<bool>.value(true);
    if (_catalogError != null) return Future<bool>.value(false);
    final flight = _flight;
    if (flight != null) return flight;
    final generation = _generation;
    final started = _load(generation);
    _flight = started;
    return started;
  }

  Future<bool> _load(int generation) async {
    try {
      final catalog = await loadCatalog();
      if (_disposed || generation != _generation) return false;
      _catalog = catalog;
      _catalogError = null;
      _notify();
      return true;
    } catch (error) {
      if (_disposed || generation != _generation) return false;
      _catalogError = error;
      _open = false;
      _notify();
      return false;
    } finally {
      if (!_disposed && generation == _generation) _flight = null;
    }
  }

  /// Whether the gateway dispatches [name] through `slash.exec`.
  ///
  /// A loaded catalogue is authoritative. Without one, the reviewed
  /// [kSlashExecutableCommands] set is only a last-resort hint: the dispatch
  /// path still attempts a `/`-line and the server's `unsupported_command`
  /// reply falls back to a plain send.
  bool isExecutable(String name) {
    final catalog = _catalog;
    if (catalog != null) return catalog.canExecute(name);
    final bare = name.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase();
    return bare.isNotEmpty && kSlashExecutableCommands.contains(bare);
  }

  /// Drops the cache. Called on connection changes and scope switches.
  void invalidate() {
    _generation++;
    _catalog = null;
    _catalogError = null;
    _flight = null;
    _open = false;
    _query = '';
    _notify();
  }

  /// Invalidates only when the cache scope (connection/session) changed.
  void updateScope(String scope) {
    if (scope == _scope) return;
    _scope = scope;
    invalidate();
  }

  void close() {
    if (!_open && _query.isEmpty) return;
    _open = false;
    _query = '';
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
