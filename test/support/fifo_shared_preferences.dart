import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// The plugin seam exercises physical storage separately from its Dart cache.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

String draftPreferenceKey(String id, {String connection = 'connection'}) =>
    'flutter.composer_draft.${base64Url.encode(utf8.encode('$connection\u0000$id')).replaceAll('=', '')}';

/// One native worker: the held getAll finishes before a queued write starts.
/// Legacy SharedPreferences can still replace its speculative Dart cache with
/// that old snapshot. No native response is delivered out of FIFO order.
class FifoPreferences extends InMemorySharedPreferencesStore {
  FifoPreferences(super.data) : super.withData();

  Future<void>? tail;
  bool holdRead = false;
  final readEntered = Completer<void>();
  final releaseRead = Completer<void>();
  final writeQueued = Completer<void>();
  final trace = <String>[];
  String watchedKey = draftPreferenceKey('local');

  Future<T> _enqueue<T>(String name, Future<T> Function() action) {
    trace.add('queued:$name');
    Future<T> perform() async {
      trace.add('start:$name');
      final value = await action();
      trace.add('finish:$name');
      return value;
    }

    final previous = tail;
    final result = previous == null
        ? perform()
        : previous.then((_) => perform());
    final pending = result.then<void>((_) {});
    tail = pending;
    pending.whenComplete(() {
      if (identical(tail, pending)) tail = null;
    }).ignore();
    return result;
  }

  @override
  Future<Map<String, Object>> getAll() => _enqueue('getAll', () async {
    final snapshot = Map<String, Object>.of(await super.getAll());
    if (holdRead) {
      holdRead = false;
      readEntered.complete();
      await releaseRead.future;
    }
    return snapshot;
  });

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key == watchedKey && !writeQueued.isCompleted) writeQueued.complete();
    return _enqueue('set:$key', () => super.setValue(valueType, key, value));
  }

  @override
  Future<bool> remove(String key) {
    if (key == watchedKey && !writeQueued.isCompleted) writeQueued.complete();
    return _enqueue('remove:$key', () => super.remove(key));
  }

  /// Inspect physical state without repairing the process-wide Dart cache.
  Future<Map<String, Object>> disk() => super.getAll();

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
          expect(active, isNull, reason: 'Native operations must not overlap.');
          expect(queued.removeFirst(), name);
          active = name;
        case 'finish':
          expect(active, name);
          active = null;
      }
    }
    expect(active, isNull);
    expect(queued, isEmpty);
  }
}
