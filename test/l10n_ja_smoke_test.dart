// Reviewer-requested smoke coverage: the ja locale must render both a normal
// message and a placeholder message.
//
// Covers https://github.com/rusty4444/hermes-android/pull/115 review findings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

import 'support/l10n_test_utils.dart';

void main() {
  group('ja locale', () {
    test('renders a normal message in Japanese', () async {
      final ja = await loadTestL10n(const Locale('ja'));
      expect(ja.cancel, 'キャンセル');
      expect(ja.connect, '接続');
      expect(ja.deny, '拒否');
      expect(ja.reasoning_off, 'オフ');
    });

    test('renders placeholder messages with substituted values', () async {
      final ja = await loadTestL10n(const Locale('ja'));
      expect(
        ja.connection_address_key('10.0.2.2:8642', '✓'),
        '10.0.2.2:8642  •  キー: ✓',
      );
      expect(ja.version_label('2.1.8'), 'バージョン 2.1.8');
      expect(
        ja.model_via_provider('deepseek-v4.1-flash', 'opencode-go'),
        'deepseek-v4.1-flash  \n`opencode-go` 経由',
      );
    });

    testWidgets('pumps widgets under Locale(ja) with the app delegates', (
      tester,
    ) async {
      await tester.pumpWidget(
        testAppWithL10n(
          Builder(
            builder: (context) => Column(
              children: [
                Text(context.l10n.cancel),
                Text(context.l10n.connection_address_key('10.0.2.2:8642', '✓')),
              ],
            ),
          ),
          locale: const Locale('ja'),
        ),
      );

      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('10.0.2.2:8642  •  キー: ✓'), findsOneWidget);
    });
  });
}
