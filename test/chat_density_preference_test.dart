import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';

void main() {
  setUp(() {
    chatDensitySelection.value = ChatDensity.comfortable;
  });

  test('unrecognised storage values fall back to comfortable', () {
    expect(ChatDensity.fromStorage(null), ChatDensity.comfortable);
    expect(ChatDensity.fromStorage('tiny'), ChatDensity.comfortable);
    expect(ChatDensity.fromStorage('compact'), ChatDensity.compact);
  });

  test('compact drops the sender label', () {
    expect(ChatDensity.comfortable.showsSenderLabel, isTrue);
    expect(ChatDensity.compact.showsSenderLabel, isFalse);
  });

  test('compact is tighter in every inset it owns', () {
    const comfortable = ChatDensity.comfortable;
    const compact = ChatDensity.compact;

    expect(
      compact.bubblePadding.vertical,
      lessThan(comfortable.bubblePadding.vertical),
    );
    expect(
      compact.bubblePadding.horizontal,
      lessThan(comfortable.bubblePadding.horizontal),
    );
    expect(
      compact.bubbleMargin.vertical,
      lessThan(comfortable.bubbleMargin.vertical),
    );
    expect(
      compact.bubbleMargin.horizontal,
      lessThan(comfortable.bubbleMargin.horizontal),
    );
    expect(compact.bubbleRadius, lessThan(comfortable.bubbleRadius));
    expect(compact.maxWidthInset, lessThan(comfortable.maxWidthInset));
    expect(compact.senderLabelGap, lessThan(comfortable.senderLabelGap));
    expect(compact.bodyBottomGap, lessThan(comfortable.bodyBottomGap));
    expect(compact.listEndPadding, lessThan(comfortable.listEndPadding));
  });

  test('store round-trips the selection and broadcasts it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = ChatDensityStore(prefs);

    expect(store.read(), ChatDensity.comfortable);

    final seen = <ChatDensity>[];
    void listener() => seen.add(chatDensitySelection.value);
    chatDensitySelection.addListener(listener);
    await store.save(ChatDensity.compact);
    chatDensitySelection.removeListener(listener);

    expect(prefs.getString(ChatDensity.preferenceKey), 'compact');
    expect(ChatDensityStore(prefs).read(), ChatDensity.compact);
    expect(seen, [ChatDensity.compact]);
  });
}
