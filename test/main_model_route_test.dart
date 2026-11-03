import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/main_model_route.dart';

void main() {
  test('only exact reviewed provider endpoint pairs are standard', () {
    expect(
      mainModelUsesCustomEndpoint('openai-api', 'https://api.openai.com/v1'),
      isFalse,
    );
    expect(
      mainModelUsesCustomEndpoint('openai-api', 'https://api.openai.com/v1/'),
      isFalse,
    );
    for (final endpoint in [
      'https://api.openai.com/v2',
      'https://api.openai.com/v1?route=private',
      'https://api.openai.com/v1#private',
      'https://user@api.openai.com/v1',
      'https://api.openai.com.evil.test/v1',
      'http://api.openai.com/v1',
      'https://api.openai.com/v1/tenant',
      ' https://api.openai.com/v1',
    ]) {
      expect(
        mainModelUsesCustomEndpoint('openai-api', endpoint),
        isTrue,
        reason: endpoint,
      );
    }
    for (final provider in [
      'custom',
      'local',
      'custom:openai-api',
      'unknown',
      'anthropic',
      'openai',
    ]) {
      expect(
        mainModelUsesCustomEndpoint(provider, 'https://api.openai.com/v1'),
        isTrue,
        reason: provider,
      );
    }
    expect(mainModelUsesCustomEndpoint('openai-api', ''), isFalse);
    expect(mainModelUsesCustomEndpoint('custom', ''), isTrue);
  });
}
