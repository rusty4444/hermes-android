import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/hands_free_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handsFreeEnabled.value = true;
  });

  test('defaults to enabled when nothing is stored', () async {
    await HandsFreePreferenceStore.load();
    expect(handsFreeEnabled.value, isTrue);
  });

  test('load restores a persisted disable', () async {
    SharedPreferences.setMockInitialValues({
      HandsFreePreferenceStore.storageKey: false,
    });
    await HandsFreePreferenceStore.load();
    expect(handsFreeEnabled.value, isFalse);
  });

  test('setEnabled updates the live value and persists it', () async {
    await HandsFreePreferenceStore.setEnabled(false);
    expect(handsFreeEnabled.value, isFalse);
    final store = await SharedPreferences.getInstance();
    expect(store.getBool(HandsFreePreferenceStore.storageKey), isFalse);

    await HandsFreePreferenceStore.setEnabled(true);
    expect(handsFreeEnabled.value, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        HandsFreePreferenceStore.storageKey,
      ),
      isTrue,
    );
  });
}
