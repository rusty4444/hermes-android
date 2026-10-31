import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// One physical worker, including failures. Disk inspection does not repair the
/// legacy process cache; a failed/held read never permits native reordering.
class DraftReadOutagePreferences extends InMemorySharedPreferencesStore {
  DraftReadOutagePreferences(super.data) : super.withData();

  Future<void>? tail;
  bool failNextRead = false;
  final failingReads = <int>{};
  int reads = 0;
  bool holdNextRead = false;
  int failures = 0;
  final readEntered = Completer<void>();
  final releaseRead = Completer<void>();
  final trace = <String>[];

  Future<T> _enqueue<T>(String name, Future<T> Function() action) {
    trace.add('queued:$name');
    Future<T> perform() async {
      trace.add('start:$name');
      try {
        final value = await action();
        trace.add('finish:$name');
        return value;
      } catch (_) {
        trace.add('failed:$name');
        rethrow;
      }
    }

    final previous = tail;
    final result = previous == null
        ? perform()
        : previous.then((_) => perform());
    final pending = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    tail = pending;
    pending.whenComplete(() {
      if (identical(tail, pending)) tail = null;
    }).ignore();
    return result;
  }

  @override
  Future<Map<String, Object>> getAll() => _enqueue('getAll', () async {
    final fail = failingReads.remove(++reads) || failNextRead;
    failNextRead = false;
    final snapshot = Map<String, Object>.of(await super.getAll());
    if (holdNextRead) {
      holdNextRead = false;
      readEntered.complete();
      await releaseRead.future;
    }
    if (fail) {
      failures++;
      throw StateError('Fixture private provider detail: /private/draft-value');
    }
    return snapshot;
  });

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _enqueue('set:$key', () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) =>
      _enqueue('remove:$key', () => super.remove(key));

  Future<Map<String, Object>> disk() => super.getAll();

  Iterable<String> get draftMutations => trace.where(
    (event) =>
        event.startsWith('start:set:flutter.composer_draft') ||
        event.startsWith('start:remove:flutter.composer_draft'),
  );

  void expectDrainedFifo() {
    final queued = Queue<String>();
    String? active;
    for (final event in trace) {
      final separator = event.indexOf(':');
      final phase = event.substring(0, separator);
      final name = event.substring(separator + 1);
      switch (phase) {
        case 'queued':
          queued.add(name);
        case 'start':
          expect(active, isNull, reason: 'Physical operations cannot overlap.');
          expect(queued.removeFirst(), name);
          active = name;
        case 'finish':
        case 'failed':
          expect(active, name);
          active = null;
      }
    }
    expect(active, isNull);
    expect(queued, isEmpty);
    expect(tail, isNull);
  }
}
