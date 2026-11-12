import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/main.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_native_auth_security_test.dart' show MemoryStore;
import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _selectMode(WidgetTester tester, String label) async {
  final selector = find.byKey(const Key('dashboard_auth_mode'));
  await _reveal(tester, selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<ConnectionManager> _openAdd(
  WidgetTester tester, {
  double textScale = 1,
  String route = 'Add',
}) async {
  // A 1080 x 2412 phone at 3x, not a desktop-sized logical test surface.
  tester.view.physicalSize = const Size(1080, 2412);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final manager = ConnectionManager(
    await SharedPreferences.getInstance(),
    credentialStore: MemoryStore(),
    nativePushSupported: false,
  );
  if (route != 'Add') {
    await manager.saveConnection(
      'Existing',
      'https://api.example.test',
      443,
      'api-only',
      desktopGatewayUrl: 'https://dashboard.example.test:9443/proxy',
      dashboardPort: 9222,
      dashboardPrefix: '/legacy',
      dashboardUsername: 'legacy-user',
      dashboardPassword: '  exact password  ',
      gatewayProfile: 'research',
    );
  }
  final turns = GatewayTurnApplicationController(
    sessionFactory: (_) => InertTurnApplicationSession(),
  );
  addTearDown(turns.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: preferredSupportedLocales(),
      theme: hermesTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeScreen(connManager: manager, turnApplicationController: turns),
    ),
  );
  await tester.pumpAndSettle();
  if (route == 'Add') {
    await tester.tap(find.byIcon(Icons.add).first);
  } else {
    final l10n = await loadTestL10n(const Locale('zh'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        route == 'Edit' ? l10n.edit_connection : l10n.dashboard_proxy_settings,
      ),
    );
  }
  await tester.pumpAndSettle();
  return manager;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('dashboard-layout-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(support.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await support.delete(recursive: true);
  });

  testWidgets('phone onboarding asks for Dashboard address before auth mode', (
    tester,
  ) async {
    await _openAdd(tester);
    final l10n = await loadTestL10n(const Locale('zh'));
    final address = find.widgetWithText(
      TextField,
      l10n.desktop_gateway_url_optional,
    );
    final profile = find.widgetWithText(
      TextField,
      l10n.hermes_profile_optional,
    );
    final auth = find.byKey(const Key('dashboard_auth_mode'));
    final dashboardHeading = find.text(l10n.dashboard_native_origin);
    expect(dashboardHeading, findsOneWidget);
    expect(
      tester.getTopLeft(dashboardHeading).dy,
      greaterThan(
        tester.getBottomLeft(find.widgetWithText(TextField, l10n.api_key)).dy,
      ),
    );
    expect(
      tester.getTopLeft(dashboardHeading).dy,
      lessThan(tester.getTopLeft(address).dy),
    );
    for (final mode in [
      l10n.dashboard_auth_none,
      l10n.dashboard_auth_basic,
      l10n.dashboard_auth_oidc,
    ]) {
      await _selectMode(tester, mode);
      expect(
        address,
        findsOneWidget,
        reason: 'Dashboard address must not be conditional or advanced-only',
      );
      expect(
        tester.getTopLeft(address).dy,
        lessThan(tester.getTopLeft(auth).dy),
        reason: 'the destination must be entered before choosing its auth',
      );
      expect(profile, findsOneWidget);
      expect(find.widgetWithText(TextField, l10n.api_key), findsOneWidget);
      expect(find.widgetWithText(TextField, l10n.host), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone Basic fields keep floating labels clear with keyboard', (
    tester,
  ) async {
    await _openAdd(tester);
    final l10n = await loadTestL10n(const Locale('zh'));
    await _selectMode(tester, l10n.dashboard_auth_basic);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final profile = find.widgetWithText(
      TextField,
      l10n.hermes_profile_optional,
    );
    final user = find.widgetWithText(
      TextField,
      l10n.dashboard_username_optional,
    );
    final password = find.widgetWithText(
      TextField,
      l10n.dashboard_password_optional,
    );
    await _reveal(tester, profile);
    await tester.enterText(profile, 'research');
    await _reveal(tester, user);
    await tester.enterText(user, 'legacy-user');
    await tester.pumpAndSettle();
    final userToPassword =
        tester.getTopLeft(password).dy - tester.getBottomLeft(user).dy;
    final passwordToProfile =
        tester.getTopLeft(profile).dy - tester.getBottomLeft(password).dy;
    // Floating outline labels paint above their field's top edge. Adjacent
    // fields with no gap collide even though RenderFlex reports no overflow.
    expect(userToPassword, greaterThanOrEqualTo(16));
    expect(
      passwordToProfile,
      greaterThanOrEqualTo(16),
      reason: 'conditional credentials belong directly after authentication',
    );
    final guidance = find.text(
      l10n.profile_this_connection_chats_as_when_the_dashboard_serves_several,
    );
    expect(guidance, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(guidance);
    expect(paragraph.didExceedMaxLines, isFalse);
    await _reveal(tester, password);
    await tester.enterText(password, '  exact password  ');
    expect(tester.widget<TextField>(profile).controller!.text, 'research');
    expect(
      tester.widget<TextField>(password).controller!.text,
      '  exact password  ',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long OIDC destination has its own space before authentication', (
    tester,
  ) async {
    await _openAdd(tester, textScale: 1.3);
    final l10n = await loadTestL10n(const Locale('zh'));
    await _selectMode(tester, l10n.dashboard_auth_oidc);
    final address = find.widgetWithText(
      TextField,
      l10n.desktop_gateway_url_optional,
    );
    const url =
        'https://dashboard.department.example.test:9443/remote/teams/research/dashboard';
    await _reveal(tester, address);
    await tester.enterText(address, url);
    await tester.pumpAndSettle();
    final preview = find.byKey(const Key('dashboard_resolved_destination'));
    final auth = find.byKey(const Key('dashboard_auth_mode'));
    expect(tester.widget<Text>(preview).data, contains(url));
    expect(
      tester.getTopLeft(preview).dy - tester.getBottomLeft(address).dy,
      greaterThanOrEqualTo(12),
    );
    expect(
      tester.getTopLeft(auth).dy - tester.getBottomLeft(preview).dy,
      greaterThanOrEqualTo(16),
      reason: 'read the exact destination before choosing authentication',
    );
    final paragraph = tester.renderObject<RenderParagraph>(preview);
    expect(paragraph.didExceedMaxLines, isFalse);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await _reveal(tester, address);
    await _reveal(tester, auth);
    final profile = find.widgetWithText(
      TextField,
      l10n.hermes_profile_optional,
    );
    await _reveal(tester, profile);
    await tester.enterText(profile, 'research');
    await _reveal(tester, find.text(l10n.custom_proxy_and_dashboard_details));
    await tester.tap(find.text(l10n.custom_proxy_and_dashboard_details));
    await tester.pumpAndSettle();
    await _reveal(tester, find.widgetWithText(TextField, l10n.dashboard_port));
    await _reveal(tester, address);
    expect(tester.widget<TextField>(address).controller!.text, url);
    expect(tester.widget<TextField>(profile).controller!.text, 'research');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final route in ['Edit', 'Settings']) {
    testWidgets('$route keeps destination and auth separated on phone', (
      tester,
    ) async {
      final manager = await _openAdd(tester, route: route);
      final before = manager.getConnections().single;
      final l10n = await loadTestL10n(const Locale('zh'));
      final address = find.widgetWithText(
        TextField,
        route == 'Edit'
            ? l10n.desktop_gateway_url_optional
            : l10n.dashboard_native_origin,
      );
      final profile = find.widgetWithText(
        TextField,
        l10n.hermes_profile_optional,
      );
      final auth = find.byKey(const Key('dashboard_auth_mode'));
      final username = find.widgetWithText(
        TextField,
        l10n.dashboard_username_optional,
      );
      final password = find.widgetWithText(
        TextField,
        l10n.dashboard_password_optional,
      );
      expect(
        tester.getTopLeft(username).dy,
        greaterThan(tester.getBottomLeft(auth).dy),
      );
      expect(
        tester.getTopLeft(profile).dy - tester.getBottomLeft(password).dy,
        greaterThanOrEqualTo(16),
      );
      expect(
        tester.widget<TextField>(username).controller!.text,
        'legacy-user',
      );
      expect(
        tester.widget<TextField>(password).controller!.text,
        '  exact password  ',
      );
      await _selectMode(tester, l10n.dashboard_auth_oidc);
      final preview = find.byKey(const Key('dashboard_resolved_destination'));
      expect(
        tester.getTopLeft(preview).dy - tester.getBottomLeft(address).dy,
        greaterThanOrEqualTo(12),
      );
      expect(
        tester.getTopLeft(auth).dy - tester.getBottomLeft(preview).dy,
        greaterThanOrEqualTo(16),
      );
      if (route == 'Settings') {
        expect(
          tester.getTopLeft(find.text(l10n.dashboard_native_sign_in)).dy,
          greaterThan(tester.getBottomLeft(auth).dy),
        );
      }
      await _selectMode(tester, l10n.dashboard_auth_none);
      expect(profile, findsOneWidget);
      await _selectMode(tester, l10n.dashboard_auth_basic);
      expect(
        tester.widget<TextField>(username).controller!.text,
        'legacy-user',
      );
      expect(
        tester.widget<TextField>(password).controller!.text,
        '  exact password  ',
      );
      expect(tester.widget<TextField>(profile).controller!.text, 'research');
      expect(
        tester.widget<TextField>(address).controller!.text,
        'https://dashboard.example.test:9443/proxy',
      );
      expect(manager.getConnections().single.toMap(), before.toMap());
      expect(
        manager.getConnections().single.dashboardPassword,
        before.dashboardPassword,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Dashboard capability guidance wraps outside input decoration', (
    tester,
  ) async {
    await _openAdd(tester, textScale: 1.3);
    final l10n = await loadTestL10n(const Locale('zh'));
    final guidance = find.text(
      l10n.enables_file_attachments_through_the_desktop_remote_gateway,
    );
    expect(guidance, findsOneWidget);
    expect(
      find.ancestor(of: guidance, matching: find.byType(InputDecorator)),
      findsNothing,
    );
    expect(
      tester.renderObject<RenderParagraph>(guidance).didExceedMaxLines,
      isFalse,
    );
    await _reveal(tester, guidance);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
