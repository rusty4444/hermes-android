# Android background smoke fixture

This developer-only fixture exercises the real Android application against a controllable local stock-style Gateway. It performs **no model inference and no real tools**. Every response is labelled `Fixture` and the fixed credential is a public test value. It is not a substitute for testing a production Gateway or a manufacturer's battery management.

## Start an isolated emulator

Use a disposable Android API 35+ ARM64 emulator, not your personal phone/profile. Record its serial (the examples use `emulator-5580`). Start the fixture bound to host loopback:

```sh
export TMPDIR="$HOME/.hermes/cache/scratch"
python3 tools/background_smoke_gateway.py --port 18643 --log "$TMPDIR/background-smoke-wire.jsonl"
```

In another terminal:

```sh
adb -s emulator-5580 reverse tcp:18643 tcp:18643
flutter build apk --debug --target tool/background_smoke_main.dart
adb -s emulator-5580 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5580 shell am start -n com.hermesagent.hermes_android.dev/com.hermesagent.hermes_android.MainActivity
adb -s emulator-5580 shell pm grant com.hermesagent.hermes_android.dev android.permission.POST_NOTIFICATIONS
```

The debug-only entry point adds one clearly labelled connection to `127.0.0.1:18643`; it never touches a real connection. Do not distribute that APK. Ordinary builds still use `lib/main.dart` and do not seed any fixture.

## Controlled test sequence

1. Open **Background fixture A** and send any text. The fixture emits commentary A and a running first tool, then waits indefinitely for a control request. Inspect `/test/status`: `submit_count` must be exactly 1.
2. Press Android Home, then switch the display off. Inspect `dumpsys activity services com.hermesagent.hermes_android.dev` for the one active foreground service, and `dumpsys notification --noredact` for its disclosure plus the quiet chat-specific entry.
3. Advance the fixture while backgrounded:

   ```sh
   curl -fsS -H 'Authorization: Bearer background-smoke-fixture-key' \
     -H 'Content-Type: application/json' -d '{"session_id":"smoke-chat-a"}' \
     http://127.0.0.1:18643/test/advance
   ```

   This completes tool one, emits commentary B, explicit fixture reasoning, and starts tool two. The wire log records how many live sockets each event reached.
4. Return to the app, navigate back to Chats, reopen A. It must attach to the same running turn, not submit again. The UI order must be commentary A, first tool batch, commentary B, reasoning, second tool batch. A later completion updates the original tool group; it must not move the group past later text.
5. Advance once more using the same command. The final durable assistant row is `Fixture final answer C.`. The chat must settle and its ongoing entry disappear. `/test/status` must still report exactly one submission.
6. Repeat with A and B active concurrently; settling A must not stop protection or erase notifications for B.
7. To check recovery, interrupt the forwarded port or kill the app process **without Force stop**, then restore/reopen. A submitted request must never be sent twice. Process-death completion without reopening requires the separately configured push path; this fixture does not pretend to provide a distributor.
8. Test forced Doze separately, recording whether the app is battery-exempt:

   ```sh
   adb -s emulator-5580 shell dumpsys battery unplug
   adb -s emulator-5580 shell dumpsys deviceidle force-idle
   # Observe honest disconnect/recovery; uninterrupted networking is not guaranteed.
   adb -s emulator-5580 shell dumpsys deviceidle unforce
   adb -s emulator-5580 shell dumpsys battery reset
   ```

Read fixture state without exposing any real credentials:

```sh
curl -fsS -H 'Authorization: Bearer background-smoke-fixture-key' \
  http://127.0.0.1:18643/test/status
```

The fixture's own real-HTTP/WebSocket contract tests verify that it retains a running turn after a socket drops and resumes without another prompt:

```sh
python3 -m unittest discover -s tools -p test_background_smoke_gateway.py
```

## Cleanup

Stop the fixture and the disposable emulator. Remove only its `adb reverse` mapping and test APK/AVD, never a user's production app or unrelated emulator. Keep wire logs with the exact source commit and APK hash when recording results; manual instructions above are not evidence that a test passed.
