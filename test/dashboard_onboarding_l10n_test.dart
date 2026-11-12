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
    'auth labels describe no manual sign-in, explicit proxy and safe failures',
    () async {
      final en = await loadTestL10n(const Locale('en'));
      expect(en.dashboard_auth_none, 'None (no manual sign-in)');
      expect(en.dashboard_auth_basic, 'Basic');
      expect(en.dashboard_auth_oidc, 'OIDC');
      expect(
        en.dashboard_native_onboarding,
        'Choose Dashboard authentication below. None means no manual sign-in; '
        'the Dashboard may still use its built-in session token (SPA). '
        'Proxy-injected authentication is a separate advanced option that must '
        'be enabled explicitly. Authentication failures do not fall back to '
        'unauthenticated requests. Basic requires both username and password '
        'and disables proxy authentication. OIDC saves your connection and '
        'opens browser sign-in. The API key is independent; Hermes profile '
        'selects the Dashboard profile.',
      );
      expect(en.leave_blank_for_default_9119, contains('HTTPS'));
      expect(en.leave_blank_for_default_9119, contains('HTTP'));
      expect(en.leave_blank_for_default_9119, contains('URL'));
      for (final locale in [const Locale('zh'), const Locale('zh', 'Hans')]) {
        final zh = await loadTestL10n(locale);
        expect(zh.dashboard_auth_none, '无（无需手动登录）');
        expect(zh.dashboard_auth_basic, '基本认证（Basic）');
        expect(zh.dashboard_auth_oidc, 'OIDC（浏览器登录）');
        expect(
          zh.dashboard_native_onboarding,
          '选择 Dashboard 身份验证。“无”表示无需手动登录，Dashboard 仍可能使用内置会话令牌（SPA）认证。'
          '代理注入认证是独立的高级选项，必须显式启用；认证失败不会自动回退为无凭据请求。'
          '基本认证需要同时填写用户名和密码，并禁用代理认证。OIDC 会先保存连接，再打开浏览器登录。'
          'API 密钥独立；Hermes 配置选择 Dashboard 配置。',
        );
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
      expect(find.text('无（无需手动登录）'), findsOneWidget);
      final selector = find.byKey(const Key('dashboard_auth_mode'));
      await tester.scrollUntilVisible(
        selector.hitTestable(),
        80,
        scrollable: find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(selector.hitTestable(), findsOneWidget);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text('基本认证（Basic）').last, findsOneWidget);
      await tester.tap(find.text('OIDC（浏览器登录）').last);
      await tester.pumpAndSettle();
      expect(find.text('保存并在浏览器中登录'), findsOneWidget);
      expect(
        find.byKey(const Key('dashboard_resolved_destination')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dashboard_resolved_destination')),
            )
            .data,
        startsWith('Dashboard 地址／受信任来源\n'),
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存并在浏览器中登录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('浏览器登录需要 HTTPS'), findsOneWidget);
      expect(manager.getConnections(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
