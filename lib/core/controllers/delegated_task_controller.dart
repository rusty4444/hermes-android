import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/gateway_insight.dart';

import '../services/delegated_task_history.dart';

/// Owns only bounded, read-only history requests and its retry timer. The
/// parent owns activity events; neither side owns/controls a child runtime.
class DelegatedTaskController extends ChangeNotifier {
  DelegatedTaskController({
    required GatewaySubagentActivity task,
    required this.history,
    // Keep the public named argument separate from mutable controller state.
    // ignore: prefer_initializing_formals
  }) : _task = task;
  final TaskHistorySource history;
  final _TaskHistoryWindow _window = _TaskHistoryWindow();
  GatewaySubagentActivity _task;
  GatewaySubagentActivity get task => _task;
  List<Map<String, dynamic>> get rows => List.unmodifiable(_window.rows);
  int get olderOffset => _window.olderOffset;
  bool get hasOlder => _window.hasOlder;
  bool loading = false;
  bool loadingOlder = false;
  TaskHistoryProblem? error;
  TaskHistoryProblem? unavailable;
  TaskHistoryProblem? limitation;
  String? _canonicalSessionId;
  String? get canonicalSessionId => _canonicalSessionId;
  bool get hasRead => _hasRead;
  bool _hasRead = false;
  bool _closed = false;
  bool _foreground = true;
  bool _started = false;
  int _generation = 0;
  int _finalRetries = 0;
  bool _refreshQueued = false;
  Future<void>? _flight;
  Timer? _timer;

  void start() {
    if (_closed || _started) return;
    _started = true;
    unawaited(refresh());
  }

  void updateTask(GatewaySubagentActivity next) {
    if (_closed || !_task.matchesTask(next)) return;
    final wasComplete = _task.isComplete;
    final oldChild = _task.latestChildSessionId ?? _task.childSessionId;
    _task = _task.merge(next);
    if ((!wasComplete && _task.isComplete) ||
        oldChild != (_task.latestChildSessionId ?? _task.childSessionId)) {
      _generation++;
      _finalRetries = 0;
      _timer?.cancel();
      _queueRefresh();
    }
    if (!_closed) notifyListeners();
  }

  void setForeground(bool foreground) {
    if (_closed || _foreground == foreground) return;
    _foreground = foreground;
    _generation++;
    _timer?.cancel();
    if (foreground && _started) _queueRefresh();
  }

  void _queueRefresh() {
    if (!_foreground || _closed) return;
    if (_flight != null) {
      _refreshQueued = true;
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh() => _read(older: false);
  Future<void> loadOlder() => _read(older: true);

  Future<void> _read({required bool older}) {
    if (_closed || !_foreground) return Future.value();
    final flight = _flight;
    if (flight != null) return flight;
    if (older && !_window.hasOlder) return Future.value();
    final childId = GatewaySubagentActivity.opaqueId(_task.childSessionId);
    if (childId == null) {
      unavailable = TaskHistoryProblem.missingReference;
      notifyListeners();
      return Future.value();
    }
    // Reserve the flight synchronously, including notification re-entrancy.
    final completer = Completer<void>();
    _flight = completer.future;
    final generation = _generation;
    _refreshQueued = false;
    loading = !older;
    loadingOlder = older;
    error = null;
    unavailable = null;
    _timer?.cancel();
    notifyListeners();
    unawaited(
      _performRead(childId, older: older, generation: generation).whenComplete(
        () {
          _flight = null;
          if (!_closed) {
            loading = false;
            loadingOlder = false;
            notifyListeners();
            if (_refreshQueued && _foreground) {
              _refreshQueued = false;
              unawaited(refresh());
            } else {
              _schedule();
            }
          }
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<void> _performRead(
    String childId, {
    required bool older,
    required int generation,
  }) async {
    if (_closed || !_foreground || generation != _generation) return;
    try {
      final page = await history.fetch(
        childId,
        older ? _window.olderOffset : 0,
        latestChildId: _task.latestChildSessionId,
        currentSessionId: _canonicalSessionId,
      );
      if (_closed || !_foreground || generation != _generation) return;
      if (page.rows.any((row) => taskRowId(row) == null)) {
        throw const TaskHistoryUnavailable(
          TaskHistoryProblem.missingRowIdentity,
        );
      }
      if (_canonicalSessionId != page.sessionId) {
        // Commit identity, generation and coverage together, after proof. Keep
        // durable rows only when their previous segment is on this path.
        _window.resetSegment(
          retainRows:
              _canonicalSessionId == null ||
              page.lineage.contains(_canonicalSessionId),
        );
        _canonicalSessionId = page.sessionId;
        _generation++;
      }
      if (older && page.offset != 0) {
        _window.acceptOlder(page.rows);
      } else {
        _window.acceptRecent(page.rows);
      }
      limitation = page.limitation;
      _hasRead = true;
      _finalRetries = 0;
    } on TaskHistoryUnavailable catch (failure) {
      if (_closed || !_foreground || generation != _generation) return;
      unavailable = failure.reason;
    } catch (failure) {
      if (_closed || !_foreground || generation != _generation) return;
      error = failure is TaskHistoryReadFailure
          ? failure.reason
          : TaskHistoryProblem.refreshFailed;
      _finalRetries++;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_started ||
        !_foreground ||
        _closed ||
        unavailable != null ||
        limitation == TaskHistoryProblem.partialCompression) {
      return;
    }
    if (!_task.isComplete || (error != null && _finalRetries <= 3)) {
      _timer = Timer(const Duration(seconds: 2), () => unawaited(refresh()));
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _refreshQueued = false;
    _timer?.cancel();
    history.close();
    super.dispose();
  }
}

/// OFFSET pages can slide even during an explicit older read. Count unique
/// durable rows covered by this scan, not raw page sizes plus later head growth:
/// the latter double-counts a growth-induced overlap and skips older rows.
/// Retained rows beyond a disjoint latest-page gap are not scan coverage until
/// an explicit older read reaches them again.
class _TaskHistoryWindow {
  final _byId = <int, Map<String, dynamic>>{};
  Set<int> _coveredIds = {};
  bool hasOlder = false;
  int get olderOffset => _coveredIds.length;
  List<Map<String, dynamic>> get rows {
    final ids = _byId.keys.toList()..sort();
    return [for (final id in ids) _byId[id]!];
  }

  void resetSegment({required bool retainRows}) {
    if (!retainRows) _byId.clear();
    _coveredIds = {};
    hasOlder = false;
  }

  void acceptRecent(List<Map<String, dynamic>> page) {
    final ids = page.map((row) => taskRowId(row)!).toSet();
    if (ids.isNotEmpty && _coveredIds.intersection(ids).isEmpty) {
      _coveredIds = ids;
    } else {
      _coveredIds.addAll(ids);
    }
    if (page.length == 50) hasOlder = true;
    _merge(page);
  }

  void acceptOlder(List<Map<String, dynamic>> page) {
    _coveredIds.addAll(page.map((row) => taskRowId(row)!));
    hasOlder = page.length == 50;
    _merge(page);
  }

  void _merge(List<Map<String, dynamic>> page) {
    for (final row in page) {
      _byId[taskRowId(row)!] = row;
    }
  }
}
