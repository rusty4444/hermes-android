import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/chat_activity_bar.dart';

/// These mock-only composer fixtures never invoke the native image picker.
/// Yielding root-zone work also drains the startup lost-image lookup.
void mockChatImageRecovery() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/image_picker');
  messenger.setMockMethodCallHandler(channel, (_) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// Drain joined StreamSubscription cancellation across fake/root zones, then
/// finish ordinary route animations. Active turns intentionally animate forever;
/// waiting for global idle is not evidence that their composer work completed.
Future<void> pumpChatUpdates(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  if (tester
      .widgetList<ChatActivityBar>(find.byType(ChatActivityBar))
      .any((bar) => !bar.isTerminalNotice)) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}
