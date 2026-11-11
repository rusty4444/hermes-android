import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_native_auth_security_test.dart' show MemoryStore;
import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

void main() {
  test(
    'auth labels describe legacy fallback and effective default ports',
    () async {
      final en = await loadTestL10n(const Locale('en'));
      expect(en.dashboard_auth_none, 'Legacy / proxy');
      expect(en.dashboard_native_onboarding, contains('SPA'));
      expect(en.dashboard_native_onboarding, contains('both'));
      expect(en.leave_blank_for_default_9119, contains('HTTPS'));
      expect(en.leave_blank_for_default_9119, contains('HTTP'));
      expect(en.leave_blank_for_default_9119, contains('URL'));
      for (final locale in [const Locale('zh'), const Locale('zh', 'Hans')]) {
        final zh = await loadTestL10n(locale);
        expect(zh.dashboard_auth_none, '兼容模式／代理');
        expect(zh.dashboard_native_onboarding, contains('SPA'));
        expect(zh.leave_blank_for_default_9119, contains('HTTPS'));
        expect(zh.leave_blank_for_default_9119, contains('HTTP'));
        expect(zh.leave_blank_for_default_9119, contains('URL'));
      }
    },
  );
  for (final locale in [const Locale('zh'), const Locale('zh', 'Hans')]) {
    test(
      '$locale translates browser sign-in actions and recovery states',
      () async {
        final l10n = await loadTestL10n(locale);
        expect(l10n.dashboard_authentication, 'Dashboard 身份验证');
        expect(l10n.dashboard_auth_done, '完成');
        expect(l10n.dashboard_native_save_and_sign_in, '保存并在浏览器中登录');
        expect(l10n.dashboard_native_sign_in, '在浏览器中登录');
        expect(l10n.dashboard_native_sign_in_again, '重新登录');
        expect(l10n.dashboard_native_sign_out, '退出登录');
        expect(l10n.dashboard_native_waiting, contains('浏览器中完成登录'));
        expect(l10n.dashboard_native_browser_failed, contains('无法打开外部浏览器'));
        expect(l10n.dashboard_native_failed, contains('未尝试使用其他凭据'));
        expect(l10n.dashboard_native_storage_failed, contains('无法安全地'));
        expect(l10n.dashboard_native_expired, contains('已过期'));
        expect(l10n.dashboard_native_cancelled, contains('已取消'));
        expect(l10n.dashboard_native_timeout, contains('超时'));
        expect(l10n.dashboard_native_changed, contains('连接已更改'));
        expect(l10n.dashboard_native_signed_in, contains('已在此设备上登录'));
        expect(l10n.dashboard_native_signed_out, contains('尚未登录'));
        expect(l10n.dashboard_native_intro, contains('凭据不会发送到浏览器'));
        expect(l10n.dashboard_native_setup_notice, contains('不会测试登录'));
      },
    );
    testWidgets('$locale onboarding uses Chinese authentication copy', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: MemoryStore(),
        nativePushSupported: false,
      );
      final turns = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(turns.close);
      await tester.pumpWidget(
        testAppWithL10n(
          HomeScreen(connManager: manager, turnApplicationController: turns),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      final l10n = await loadTestL10n(locale);
      await tester.enterText(
        find.widgetWithText(TextField, l10n.host),
        '127.0.0.1',
      );
      expect(find.text('Dashboard 身份验证'), findsOneWidget);
      expect(find.textContaining('OIDC 会先保存连接'), findsOneWidget);
      expect(find.text('兼容模式／代理'), findsOneWidget);
      final selector = find.byKey(const Key('dashboard_auth_mode'));
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('基本认证（Basic）').last, findsOneWidget);
      await tester.tap(find.text('OIDC（浏览器登录）').last);
      await tester.pumpAndSettle();
      expect(find.text('保存并在浏览器中登录'), findsOneWidget);
      expect(find.text('Dashboard 地址／受信任来源'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '保存并在浏览器中登录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('浏览器登录需要 HTTPS'), findsOneWidget);
      expect(manager.getConnections(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
