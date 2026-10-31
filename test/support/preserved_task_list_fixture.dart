import 'dart:convert';
import 'dart:io';

/// Captured from Hermes todo compaction through real SQLite/API projection.
Map<String, Map<String, dynamic>> preservedTaskListFixtures() {
  final fixture =
      jsonDecode(
            File('test/fixtures/preserved_task_lists.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (fixture['cases'] as Map<String, dynamic>).map(
    (name, row) => MapEntry(name, Map<String, dynamic>.from(row as Map)),
  );
}
