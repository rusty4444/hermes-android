import 'dart:async';

import 'composer_draft_store.dart';
import 'tool_activity_group_pins.dart';

/// Null is observed absence; a failed read must throw, never manufacture empty
/// draft authority. Legacy reader seams share this availability boundary.
typedef ComposerDraftReader =
    Future<String?> Function({
      required String connectionId,
      required String sessionId,
    });

/// Connection-configuration lifetime, owned by the application, not a route.
/// No transcript, credentials, or pending-turn receipt is kept here.
class ChatPresentationRegistry {
  ChatPresentationRegistry(this.connectionId);

  final String connectionId;
  final Map<String, ChatPresentationState> _aliases = {};
  int _intent = 0;
  bool _closed = false;
  bool get isClosed => _closed;

  ChatPresentationState chatFor(String id) {
    if (_closed) throw StateError('Chat presentation registry is closed.');
    return (_aliases[id] ??= ChatPresentationState._(this, id))._root;
  }

  void bind(String local, String stored) {
    final source = chatFor(local);
    final target = _aliases[stored]?._root;
    final writers = [
      source._writer,
      target?._writer,
    ].whereType<ComposerDraftHandle>().toList();
    if (target != null && !identical(source, target)) {
      // Existing leases follow the redirect. The most recent explicit intent
      // wins, not whichever asynchronous migration/read happens to finish last.
      if (source._edit > target._edit) {
        target
          .._text = source._text ?? source._intentText
          .._intentText = source._intentText
          .._edit = source._edit;
      }
      if (source._authority > target._authority) {
        target
          .._writer = source._writer
          .._onBindingChanged = source._onBindingChanged
          .._authority = source._authority
          .._writerClosed = source._writerClosed
          .._writerEdited = source._writerEdited;
      }
      // A view keeps its token through convergence, never another view's value.
      target._reasoningVisits.addAll(source._reasoningVisits);
      source._reasoningVisits.clear();
      target._toolAliases.mergeMissingFrom(source._toolAliases);
      target._toolVisits.addAll(source._toolVisits);
      source._toolVisits.clear();
      for (final pins in target._toolVisits) {
        // Share learned identity, never another route's manual choices.
        pins.inheritAliasesFrom(target._toolAliases);
      }
      source._redirect = target;
    }
    final state = target ?? source;
    final changed = state._sessionId != stored;
    state._sessionId = stored;
    _aliases[local] = state;
    _aliases[stored] = state;
    if (changed || !identical(source, state)) {
      state._binding++;
      if (state._edit == 0) state._text = null;
      state._pendingWrites++;
      unawaited(
        ComposerDraftStore.bind(
              connectionId: connectionId,
              localSessionId: local,
              storedSessionId: stored,
              isCurrent: () => !_closed,
            )
            .then((_) async {
              final root = state._root;
              final writer = root._writer;
              if (writer != null) {
                // Move an existing lease, not a new edit. A separate newer
                // storage writer must not be reclaimed by this migration.
                await writer.handoffFrom(
                  writers,
                  canonicalSessionId: stored,
                  isCurrent: () => !_closed && identical(root._writer, writer),
                );
              }
              await state._persist();
              if (!_closed && !root._writerEdited) {
                // The canonical composer may already have read an empty key.
                // Invalidate that read, then offer migration to its live lease.
                if (root._edit == 0) root._text = null;
                root._binding++;
                root._onBindingChanged?.call();
              }
            })
            .whenComplete(() => state._pendingWrites--),
      );
    }
  }

  /// Rejection uses the admitted lease, never a new edit or mount. Keep the
  /// cached projection and the queued physical write in the same transition.
  Future<void> restoreRejectedDraft({
    required ComposerDraftHandle handle,
    required String text,
    required bool Function() isCurrent,
  }) {
    final state = _aliases[handle.sessionId]?._root;
    if (_closed ||
        state == null ||
        !identical(state._writer, handle) ||
        !isCurrent()) {
      return Future.value();
    }
    final edit = state._edit;
    state
      .._text = text
      .._intentText = text;
    return handle.save(
      text,
      isCurrent: () =>
          !_closed &&
          isCurrent() &&
          identical(state._root._writer, handle) &&
          state._root._edit == edit &&
          state._root._text == text,
    );
  }

  void close() {
    _closed = true; // Fences leases, held reads and queued migrations together.
    for (final state in _aliases.values.map((s) => s._root).toSet()) {
      for (final pins in state._reasoningVisits) {
        pins.clear();
      }
      state._reasoningVisits.clear();
      for (final pins in state._toolVisits) {
        pins.clear();
      }
      state._toolVisits.clear();
    }
    _aliases.clear();
  }
}

class ChatPresentationState {
  ChatPresentationState._(this._registry, this._sessionId);

  final ChatPresentationRegistry _registry;
  String _sessionId;
  ChatPresentationState? _redirect;
  ChatPresentationState get _root => _redirect?._root ?? this;
  final Set<ToolActivityGroupPins> _reasoningVisits = {};
  // The application retains identity aliases, not cross-visit tool choices.
  final ToolActivityGroupPins _toolAliases = ToolActivityGroupPins();
  final Set<ToolActivityGroupPins> _toolVisits = {};

  /// Reasoning run IDs are scope-stable from first render. Only this mounted
  /// view owns manual choices; aliases transfer tokens, not their values.
  ToolActivityGroupPins openReasoningVisit() {
    if (_registry._closed) {
      throw StateError('Chat presentation registry is closed.');
    }
    final pins = ToolActivityGroupPins();
    _root._reasoningVisits.add(pins);
    return pins;
  }

  void closeReasoningVisit(ToolActivityGroupPins pins) {
    _root._reasoningVisits.remove(pins);
    pins.clear();
  }

  /// One actual ChatScreen State is one visit, even while covered by a route.
  /// Distinct prebinding routes keep independent choices after convergence.
  ToolActivityGroupPins openToolVisit() {
    if (_registry._closed) {
      throw StateError('Chat presentation registry is closed.');
    }
    final pins = ToolActivityGroupPins()
      ..inheritAliasesFrom(_root._toolAliases);
    _root._toolVisits.add(pins);
    return pins;
  }

  void closeToolVisit(ToolActivityGroupPins pins) {
    _root._toolVisits.remove(pins);
    pins.clear();
  }

  /// Ingress may learn an ID while a route is covered or no route is mounted.
  /// Only visits already holding a pin propagate a manual choice to that ID.
  void aliasTool(String groupId, String durableId) {
    final state = _root;
    if (_registry._closed) return;
    state._toolAliases.alias(groupId, durableId);
    for (final pins in state._toolVisits) {
      pins.alias(groupId, durableId);
    }
  }

  String? _text;
  // The last explicitly owned value survives a cold read on remount. An alias
  // may arrive before that read, so its chronology must retain a value too.
  String? _intentText;
  int _edit = 0;
  int _authority = 0;
  int _binding = 0;
  ComposerDraftHandle? _writer;
  void Function()? _onBindingChanged;
  bool _writerClosed = true;
  bool _writerEdited = false;
  int _pendingWrites = 0;

  ComposerDraftWriter openWriter({void Function()? onBindingChanged}) {
    final state = _root;
    // Once a detached writer's checkpoint drains, re-read durable state on
    // the next mount, including writes made by another application embedder.
    if (state._writerClosed && state._pendingWrites == 0) {
      state._text = null;
      // Hydration invalidates the cached value, not the chronology of the
      // user's last edit/clear. A late alias still compares that intent.
    }
    final token = ComposerDraftStore.open(
      connectionId: _registry.connectionId,
      sessionId: state._sessionId,
    );
    state._writer = token;
    state._onBindingChanged = onBindingChanged;
    state._writerClosed = false;
    state._writerEdited = false;
    state._authority = ++_registry._intent;
    return ComposerDraftWriter._(this, token, onBindingChanged);
  }

  Future<void> _persist() {
    final state = _root;
    final text = state._text;
    if (text == null || state._edit == 0 || _registry._closed) {
      return Future.value();
    }
    final edit = state._edit;
    final binding = state._binding;
    state._pendingWrites++;
    return state._writer!
        .save(
          text,
          isCurrent: () =>
              !_registry._closed &&
              identical(state, _root) &&
              edit == state._edit &&
              text == state._text &&
              binding == state._binding,
        )
        .whenComplete(() => state._pendingWrites--);
  }
}

/// Mounting admits a writer; only a subsequent explicit edit can reclaim it.
/// Checkpoints/disposal/restoration never acquire authority from a newer route.
class ComposerDraftWriter {
  ComposerDraftWriter._(this._state, this._token, this._onBindingChanged);

  final ChatPresentationState _state;
  final ComposerDraftHandle _token;
  ComposerDraftHandle get draftHandle => _token;
  final void Function()? _onBindingChanged;
  bool _closed = false;
  ChatPresentationState get _root => _state._root;
  bool get isCurrent =>
      !_closed && !_state._registry._closed && identical(_root._writer, _token);

  Future<String?> read({ComposerDraftReader? reader}) async {
    while (isCurrent) {
      final state = _root;
      if (state._text != null) return state._text;
      final binding = state._binding;
      final edit = state._edit;
      final String? text;
      try {
        // Follow this lease's durable alias, not a logical destination whose
        // migration may have failed. Otherwise a successful read of that
        // still-absent destination could erase the untouched source on close.
        // Legacy projection readers continue to receive the logical identity.
        text = reader == null
            ? await ComposerDraftStore.read(
                connectionId: _token.connectionId,
                sessionId: _token.sessionId,
              )
            : await reader(
                connectionId: state._registry.connectionId,
                sessionId: state._sessionId,
              );
      } catch (_) {
        if (!isCurrent) return null;
        if (!identical(state, _root) || binding != state._binding) continue;
        // Leave unavailable hydration unknown. Retained edit chronology alone
        // cannot authorize an empty checkpoint/close; a newer explicit edit
        // may already have supplied its own value while the read was pending.
        return state._text;
      }
      if (!isCurrent) return null;
      if (!identical(state, _root) || binding != state._binding) continue;
      if (edit == state._edit) state._text = text ?? '';
      return state._text;
    }
    return null;
  }

  void edit(String text) {
    if (_closed || _state._registry._closed) return;
    final state = _root;
    _token.edited();
    state
      .._writer = _token
      .._onBindingChanged = _onBindingChanged
      .._writerClosed = false
      .._writerEdited = true
      .._edit = ++state._registry._intent
      .._authority = state._registry._intent
      .._intentText = text
      .._text = text;
  }

  Future<void> save(String text) {
    if (!isCurrent) return Future.value();
    final state = _root;
    // An untouched route leaving before hydration is not an explicit clear.
    if (state._text == null) return Future.value();
    if (state._text != text) {
      // Checkpoint/submit-clear/rejection restoration changes the value of
      // this existing lease, not the chronology of explicit user edits.
      state._text = text;
      if (state._edit != 0) state._intentText = text;
    }
    return state._persist();
  }

  Future<void> flush() => isCurrent ? _root._persist() : Future.value();

  Future<void> close() {
    final saved = flush();
    if (isCurrent) {
      _root._writerClosed = true;
      _root._onBindingChanged = null;
    }
    _closed = true;
    return saved;
  }
}
