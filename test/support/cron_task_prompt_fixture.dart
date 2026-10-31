import 'dart:convert';
import 'dart:io';

/// Synthetic cron producers persisted and passed through real backend projections.
Map<String, Map<String, dynamic>> cronTaskPromptFixtures() {
  final fixture =
      jsonDecode(
            File('test/fixtures/cron_task_prompts.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (fixture['cases'] as Map<String, dynamic>).map(
    (name, value) => MapEntry(name, Map<String, dynamic>.from(value as Map)),
  );
}
