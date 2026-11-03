import 'dart:convert';
import 'dart:io';

/// Synthetic DAG summaries assembled by real LCM and publicly projected after
/// disposable SessionDB persistence. No user conversation data is captured.
Map<String, Map<String, dynamic>> lcmSummaryFixtures() {
  final fixture =
      jsonDecode(
            File('test/fixtures/lcm_summary_messages.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return (fixture['cases'] as Map<String, dynamic>).map(
    (name, value) => MapEntry(name, Map<String, dynamic>.from(value as Map)),
  );
}
