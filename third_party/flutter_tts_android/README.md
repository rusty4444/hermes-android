# Audited Android patch: flutter_tts 4.2.5

Source: https://pub.dev/packages/flutter_tts/versions/4.2.5
Upstream: https://github.com/dlutton/flutter_tts (MIT; original LICENSE retained).
This is a local Hermes patch, **not an upstream fix** or a version upgrade.

Only `android/src/main/kotlin/com/eyedeadevelopment/fluttertts/FlutterTtsPlugin.kt`
is copied. `manifest.json` pins both original and patched SHA-256. Pubspec/lock,
all hosted Dart and non-Android bytes, plugin registration/channel, existing
FlutterTts instance, selected voice/rate and public Dart API remain unchanged.

`android/flutter-tts-patch.gradle` replaces the actual `:flutter_tts` KGP main
source set for every production variant. The task-backed guard checks upstream
content, the complete upstream main native source inventory, patched content,
and the compiler's exact single-source input. It fails closed on drift; never
edit the pub cache. Debug/release/profile compile the same patched source.

The patch confines native callback delivery to the main Handler, checks exact
utterance UUID/epoch/owner identity after that boundary, retains each Result in
its owner and settles it once. Stop/pause revoke before native stop and cancel
queued initialization/retry speaks; a later explicit speak uses a fresh epoch.
Registration precedes native start. Engine initialization is separately fenced;
speech/file/silence callbacks cannot borrow another owner's completion or focus.

Native regression command: `gradle -p android :flutter_tts:testDebugUnitTest`.
The committed Robolectric tests instantiate the actual shipping plugin and invoke
real MethodCalls and provider listener callbacks, not a copied completion model.
They reproduce the upstream failure and control both queued-before-Stop and
late-after-new-speak orders. Dart speaker/controller tests hold B pending beyond
the echo guard and permit capture only after its own reply plus the full guard.
These are deterministic platform-boundary tests, not physical audio evidence.

The Android Dart speaker also ignores uncorrelated global cancellation/error
events: Stop's legacy onCancel notification can follow its reply and must not
cancel a replacement operation. Native cancellation/error still settles its own
awaited result as non-success. Non-Android legacy callback handling is retained.

The pre-existing upstream service-connection inspection is retained unchanged;
this patch adds no runtime-reflection adapter or replacement TTS instance.
