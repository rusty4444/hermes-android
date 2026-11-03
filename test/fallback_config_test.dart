import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/fallback_config.dart';

void main() {
  for (final key in ['fallback_providers', 'fallback_model']) {
    for (final bad in <Object>[
      'not-a-chain',
      7,
      false,
      {},
      {'provider': 'p', 'model': ''},
      {'provider': ' ', 'model': 'm'},
      {'provider': 1, 'model': 'm'},
      [null],
      [7],
      [
        {'provider': 'p', 'model': 'm'},
        {'provider': 'p'},
      ],
    ]) {
      test(
        '$key rejects malformed persisted input ${bad.runtimeType} $bad',
        () {
          expect(
            () => FallbackConfig.fromConfig({key: bad}),
            throwsFormatException,
          );
        },
      );
    }
  }
  test('empty, absent, null and dictionary shapes retain safe semantics', () {
    final absent = FallbackConfig.fromConfig({});
    expect(absent.entries, isEmpty);
    expect(absent.confirms([], absent), isTrue);
    expect(
      FallbackConfig.fromConfig({'fallback_providers': null}).entries,
      isEmpty,
    );
    final legacy = {
      'provider': 'legacy',
      'model': 'legacy-model',
      'key_env': r'${OLD_KEY}',
    };
    final config = FallbackConfig.fromConfig({
      'fallback_providers': {'provider': 'openai', 'model': 'old'},
      'fallback_model': legacy,
      'unrelated-secret': 'must-not-retain',
    });
    expect(config.entries.single.model, 'old');
    expect(config.legacyEntries.single.toJson(), legacy);
    final saved = FallbackConfig.fromConfig({
      'fallback_providers': config.entries.map((e) => e.toJson()).toList(),
      'fallback_model': legacy,
    });
    expect(saved.confirms(config.entries, config), isTrue);
    expect(
      config.confirms(config.entries, config),
      isFalse,
    ); // dict was not replaced
    expect(FallbackConfig.fromConfig({}).confirms([], config), isFalse);
  });
  test('opaque JSON, raw env refs and exact strings remain immutable', () {
    final original = <String, dynamic>{
      'provider': ' openai ',
      'model': ' old ',
      'api_key': r'${FALLBACK_KEY}',
      'base_url': 'https://private.invalid/v1/',
      'future': {
        'nested': [null, true, 3, 2.5, 'é'],
      },
    };
    final entry = FallbackEntry(original);
    original['api_key'] = 'changed';
    expect(entry.toJson()['api_key'], r'${FALLBACK_KEY}');
    expect(entry.provider, ' openai ');
    expect(entry.hasMetadata, isTrue);
    expect(() => entry.toJson()['api_key'] = 'changed', throwsUnsupportedError);
    expect(
      () => (entry.toJson()['future'] as Map)['nested'] = [],
      throwsUnsupportedError,
    );
    expect(
      () => ((entry.toJson()['future'] as Map)['nested'] as List).clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'readback requires every field, value type, order and legacy representation',
    () {
      final entries = [
        {
          'provider': 'openai',
          'model': 'old',
          'future': [
            1,
            {'v': r'${KEY}'},
          ],
        },
        {'provider': 'other', 'model': 'other-1'},
      ];
      final legacy = {'provider': 'legacy', 'model': 'model'};
      final before = FallbackConfig.fromConfig({
        'fallback_providers': entries,
        'fallback_model': legacy,
      });
      expect(before.confirms(before.entries, before), isTrue);
      for (final altered in [
        {
          'fallback_providers': entries.reversed.toList(),
          'fallback_model': legacy,
        },
        {
          'fallback_providers': [
            {'provider': 'openai', 'model': 'old'},
            entries.last,
          ],
          'fallback_model': legacy,
        },
        {
          'fallback_providers': [
            {
              ...entries.first,
              'future': [
                1.0,
                {'v': r'${KEY}'},
              ],
            },
            entries.last,
          ],
          'fallback_model': legacy,
        },
        {
          'fallback_providers': entries,
          'fallback_model': [legacy],
        },
        {'fallback_providers': entries},
      ]) {
        expect(
          FallbackConfig.fromConfig(altered).confirms(before.entries, before),
          isFalse,
        );
      }
      final empty = FallbackConfig.fromConfig({
        'fallback_providers': [],
        'fallback_model': legacy,
      });
      expect(empty.confirms([], before), isTrue);
      expect(empty.legacyEntries, hasLength(1));
    },
  );
}
