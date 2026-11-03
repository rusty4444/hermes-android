# Foreground hands-free voice (Android)

Hands-free is **off by default**. It is not remembered as a running session.
It does not change the gateway, model, credentials or normal chat permissions.
Manual **Start voice input** still produces an editable draft and never sends it.

## Setup and use

1. Open the chat you want to use. Finish any running/uncertain turn, clear or save
   the manual draft, and remove pending attachments. Enable **Spoken replies**.
2. Press the **Start hands-free** composer icon to open setup and read the
   disclosures. Choose **Listen up to N seconds**, from 0 to 30; the default is
   10. Zero requires the wake phrase for every prompt. Only this timeout is saved,
   not permission to run the microphone. The active mode also has an information
   button; opening its setup stops listening and requires another explicit Start.
3. Confirm **Start hands-free** while this chat is visible. Grant microphone
   permission if asked. If the permission dialog backgrounds the app, setup may
   finish but capture stays off: press Start again after returning.
4. When the screen says **Say Hey Hermes**, say **“Hey Hermes”**. Wait for
   **“Ready — speak now”**, then say your prompt. The ready status is an accessible
   live region; it is not a promise of an audible earcon on every device.
5. Partial recognition appears in a separate voice preview, never the manual
   composer. Only a genuine Android final result followed by recognizer teardown
   can submit one prompt through the ordinary chat admission/reservation path.
6. Only that exact admitted turn's successful public final reply is read aloud,
   once, with the existing selected voice and rate. The microphone stays off
   during playback. After completion and a 300 ms echo guard, a positive timeout
   permits one bounded follow-up without the wake phrase. Silence or an early
   provider end returns to local wake listening. There is no STT restart loop.
7. **Stop hands-free** is available throughout setup, capture, waiting, playback,
   follow-up and errors, including a fixed composer Stop icon. Stopping voice
   does not cancel an already submitted chat turn. **Stop response** retains its
   existing explicit server/transport interruption behaviour.

Typing/editing the composer, adding attachments, starting manual dictation or
Read aloud, disabling spoken replies, opening a modal/Settings/another route,
changing chat/tab/account, locking/backgrounding the app, or closing the screen
revokes voice consent. Returning to the chat or resuming **never restarts it**.
Failures, uncertain delivery and requests for approval/input stop hands-free;
it never resends automatically or approves a request for you. Check setup and
connection, then explicitly Stop/Start to try again.

## Privacy, network and limits

- Wake detection is local CPU inference using the bundled English sherpa-onnx
  GigaSpeech 3.3M int8 keyword model. No account, wake API key, enrollment,
  training or runtime model download is needed.
- **Offline wake does not mean offline conversation.** The normal Android
  SpeechRecognizer provider, selected reply voice and gateway may use networks.
  This feature does not force on-device/offline STT or change the speech service.
- No wake PCM is persisted, uploaded, or passed to Dart. Diagnostics do not log
  transcripts or credentials. The sent prompt remains normal gateway chat data.
- Say the wake phrase, **wait for ready**, then speak: there is no same-breath
  guarantee or audio pre-roll from wake detection into Android recognition.
- Follow-up time is a **maximum**, not a guaranteed minimum. Android providers
  may ignore requested silence settings and terminate earlier. Startup is bounded
  to 5 seconds, each spoken utterance to 30 seconds, with a 2-second final-result
  grace. A timeout cannot manufacture a final result from partial text.
- Playback uses completion acknowledgement, queue replacement and provider-sized
  chunks, with a five-minute overall deadline. Cancellation, missing completion,
  unavailable voices and errors cannot start a follow-up microphone session.
- This is foreground/current-chat only, not an always-on/low-power hardware
  hotword, background microphone service, lock-screen assistant, boot action,
  Android Auto integration or guaranteed car/Bluetooth audio route. Continuous
  CPU wake capture consumes battery; false activations and misses are possible.
- English wake detection does not imply every STT language/accent is supported.
  Recognition uses the existing selected locale and default Android provider.

## Implementation and verification boundaries

Dart uses `com.hermesagent.hermes_android/voice` and `voice/events` with protocol
version 1, typed string-keyed StandardMessageCodec maps and owner/generation/
sequence/operation fences. Android manual dictation and hands-free use the same
joinable native capture owner; non-Android manual dictation retains
`speech_to_text`. TTS reuses the chat's existing `FlutterTts` instance. Android
builds apply a [content-pinned local 4.2.5 native patch](../third_party/flutter_tts_android/README.md)
for utterance/result/epoch correlation and Stop-versus-queued-start fencing.
This is not an upstream fix claim; Dart/non-Android plugin sources are unchanged.

A stopped generation cannot restart. Native release acknowledgement is required
before another capture/playback action; waiting for a timer or `notListening`
from the old Flutter speech plugin is not substituted for release. Root navigation,
ModalRoute visibility, destination activity, foreground epochs and
`ConnectionMutationBarrier` account epochs independently fence continuations.

Voice turns have an exact local terminal Future across REST/SSE, stock app-owned
Gateway and recovery-v2 paths. History hydration, old same-text messages, sibling
snapshots, tool/interim output and unrelated terminals do not acquire voice reply
rights. Local revocation is also checked after connection/write-ahead awaits and
immediately before physical transport admission. Once sent, a turn remains owned
by normal chat/recovery; losing voice consent never resends it.

Deterministic Dart/platform-channel/widget fixtures exercise adverse completion
orders, manual selection/Stop/Cancel, all three submission paths, permission and
navigation/account revocation, TTS chunk/deadline/cancel/error barriers and stale
or malformed events. These fixtures are **not physical microphone/acoustic proof**.

Independent native CPU inference of the frozen 2.0.1 runtime/model detected all
six labelled synthetic “Hey Hermes” positives (Samantha, Daniel and Karen voices
at two rates) and rejected all seven negatives (including “Hey Henry”, “Hello
Hermes”, silence and noise). Fresh-engine replays reproduced all thirteen outcomes.
A separate **Android ARM64 AAR/JNI probe on an API 35 emulator** reproduced the
same keywords, tokens, timestamps and feed positions, with verified model, keyword,
native-library and executable hashes. Every native stream and engine was released.
The parent independently replayed both host and Android probes without tuning.

These are **synthetic engine tests**, not a microphone-to-reply demonstration,
human/accent/noise accuracy estimate, field false-accept rate, battery, thermal,
latency or microphone-routing measurement. The emulator used 4096-byte pages;
it is not 16 KB runtime proof. Android 14–16 physical permission/privacy-switch/
provider/network/TTS loss, actual wake/STT/TTS and background/lock behaviour remain
explicit device acceptance gates. Exact-candidate APK/R8 packaging, all distributed
ABIs, bundled hashes/notices and real 16 KB launch are separate checks; no performance
or reliability claim is made here. Runtime and model licensing/provenance are in
[the bundled voice notice](../third_party/voice/NOTICE.md).

## Primary sources

- [Android SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer):
  short recognition sessions, provider/network behaviour and wait-for-terminal rules.
- [Android audio-input sharing](https://developer.android.com/media/platform/sharing-audio-input):
  concurrent recorder/privacy silencing is not microphone ownership.
- [Android foreground-service restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start):
  while-in-use permission restrictions; this feature does not add a microphone FGS.
- [sherpa-onnx keyword spotting](https://k2-fsa.github.io/sherpa/onnx/kws/index.html)
  and [English model](https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html).
- [Pinned sherpa source](https://github.com/k2-fsa/sherpa-onnx/tree/af2d8d81dbfa61c4cea4c568da78f3982edca005)
  and [runtime 2.0.1](https://github.com/k2-fsa/sherpa-onnx/releases/tag/v2.0.1).
- [FlutterTts 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5):
  `awaitSpeakCompletion(true)`, queue mode and speech input limits.
- [speech_to_text 7.4.0](https://pub.dev/packages/speech_to_text/versions/7.4.0):
  short intermittent dictation, not continuous hotword listening.

Thanks to @mannok for the feature proposal in #142. Hermes Agent assisted with
research, implementation, documentation and regression testing.
