import 'dart:convert';
import 'dart:io';

/// Real backend producers persisted in disposable SQLite and API-projected.
Map<String, Map<String, dynamic>> internalBackgroundMessageFixtures() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/internal_background_messages.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (fixture['cases'] as Map<String, dynamic>).map(
    (name, value) => MapEntry(name, Map<String, dynamic>.from(value as Map)),
  );
}

/// Actual backend consecutive-user repairs, persisted and publicly projected.
Map<String, Map<String, dynamic>> mergedInternalBackgroundMessageFixtures() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/merged_internal_background_messages.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (fixture['cases'] as Map<String, dynamic>).map(
    (name, value) => MapEntry(name, Map<String, dynamic>.from(value as Map)),
  );
}
