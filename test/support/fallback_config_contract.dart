import 'dart:convert';
import 'dart:io';

// Generated from actual FastAPI current/pinned-older config routes. Return a
// fresh object so adversarial mutations cannot poison sibling tests.
Map<String, dynamic> fallbackConfigContract() =>
    jsonDecode(
          File(
            'test/fixtures/fallback_config_contract.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> fallbackConfigSchema({bool older = false}) =>
    fallbackConfigContract()[older ? 'old_schema' : 'current_schema']
        as Map<String, dynamic>;
