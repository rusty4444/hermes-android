# Hermes Android

Android client for [Hermes Agent](https://hermes-agent.nousresearch.com/) — chat with your Hermes sessions from a phone or tablet over local Wi-Fi or a private Tailscale network.

## Current release

- Version: **1.0.7**
- Package: `com.hermesagent.hermes_android`
- Recommended APK for most modern phones: `app-arm64-v8a-release.apk`
- Other APKs: `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`
- Download: [GitHub Releases](https://github.com/rusty4444/hermes-android/releases/latest)

## What's new in v1.0.7

- **Password-protected dashboards** — the Memory/Cron/Skills/Settings tabs now work against a dashboard secured with basic-auth, not just an open (`--insecure`) one. The app logs in via the dashboard's `/auth/password-login` flow and reuses the session cookie (the same mechanism the desktop client uses).
- **Configurable dashboard port** — set a custom dashboard port per connection when it isn't the default `9119`.
- **Dashboard details in the connection flow** — set the dashboard port/username/password while adding a connection (expand **Custom dashboard details**) or later via **⋮ → Dashboard Login**, with validation before saving.

## What's new in v1.0.6

- **Voice chat support** — tap the microphone in chat to dictate a message to Hermes, and Hermes can speak the response back.
- Spoken replies can be toggled from the chat input bar.
- Android/iOS microphone and speech-recognition permissions are included.

## Features

- **Hermes chat on Android** — browse sessions, create new chats, and send prompts to your Hermes Agent.
- **Streaming responses** — chat uses the Hermes Gateway OpenAI-compatible streaming endpoint: `POST /v1/chat/completions`. Tokens appear in real-time with smooth auto-scroll.
- **Messaging-style UI** — dark/light/system themes, gold Hermes accent color (`#D4AF37`), markdown rendering, relative timestamps, and responsive phone/tablet layouts.
- **Gold/black Hermes branding** — distinctive gold accent on black background, custom app icon with mipmap densities, agent messages use grey bubbles.
- **Gateway API integration** — sessions and chat run through the Hermes Gateway API Server, normally on port `8642`, with HTTP and HTTPS endpoints supported.
- **Dashboard integrations** — Memory, Cron Jobs, Skills, and Settings screens use the Hermes dashboard API (default port `9119`, configurable per connection) on the same host. Works with both open (`--insecure`) dashboards and **password-protected dashboards** via the built-in login.
- **Model settings** — view and change the configured Hermes model where the dashboard exposes model settings.
- **Cron management** — list, trigger, pause/resume, create, edit, and delete scheduled Hermes cron jobs.
- **Skills browser** — view available Hermes skills with descriptions and trigger conditions.
- **Memory viewer** — inspect conversation memory across sessions.
- **Verbose mode toggle** — show raw message metadata (role, tool calls, timestamps) in chat.
- **Three-way theme toggle** — Dark / Light / System default.
- **Keyboard handling** — auto-scroll on keyboard open, send action on Enter, FAB to scroll to bottom.
- **Voice chat** — microphone dictation sends recognised speech to Hermes, with optional text-to-speech replies.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-session-list.jpg" width="220" alt="Session list"><br><sub>Session list</sub></td>
    <td align="center"><img src="docs/screenshots/02-navigation-drawer.jpg" width="220" alt="Navigation drawer"><br><sub>Navigation drawer</sub></td>
    <td align="center"><img src="docs/screenshots/03-cron-jobs.jpg" width="220" alt="Cron jobs"><br><sub>Cron jobs</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/04-add-cron-job.jpg" width="220" alt="Add cron job"><br><sub>Add cron job</sub></td>
    <td align="center"><img src="docs/screenshots/05-memory.jpg" width="220" alt="Memory"><br><sub>Memory</sub></td>
    <td align="center"><img src="docs/screenshots/06-settings.jpg" width="220" alt="Settings"><br><sub>Settings</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/07-skills.jpg" width="220" alt="Skills"><br><sub>Skills</sub></td>
  </tr>
</table>

## Quick start

### Prerequisites

- Android device or emulator (Android 8+).
- Hermes Agent installed on the host machine.
- Hermes Gateway API Server reachable from the Android device.
- `API_SERVER_KEY` from the Hermes host environment (`~/.hermes/.env`).
- Optional: Hermes dashboard reachable for Memory/Cron/Skills/Settings screens.

Hermes Agent docs: <https://hermes-agent.nousresearch.com/docs>

### Install the APK

Download the latest APK from the [GitHub Releases](https://github.com/rusty4444/hermes-android/releases/latest) page.

For most Android phones, install the arm64 APK:

```bash
adb install app-arm64-v8a-release.apk
```

If sideloading directly on Android, enable **Install unknown apps** for your browser or file manager, then open the downloaded APK.

### 1. Start the Gateway API Server

The Android chat/session features connect to the Hermes Gateway API Server. It must bind to an address your phone can reach, not only `127.0.0.1`.

Use your normal Hermes gateway/API-server startup command and confirm:

- host/IP is reachable from Android
- port is usually `8642`
- `API_SERVER_KEY` is available in `~/.hermes/.env`

### 2. Optional: start the dashboard for drawer features

Memory, Cron Jobs, Skills, and Settings use the Hermes dashboard API (default port `9119`).

Open dashboard (no login):

```bash
hermes dashboard --insecure --host 0.0.0.0 --tui --port 9119
```

Password-protected dashboard (recommended on shared networks) — start it with a
basic-auth provider instead of `--insecure`, then enter the username/password in
the app's **Dashboard Login** dialog (see [Dashboard access](#4-optional-configure-dashboard-access)).

> `--host 0.0.0.0` is required when connecting from another device. A localhost-only dashboard cannot be reached from Android.

### 3. Connect the app

1. Put the Android device and Hermes host on the same Wi-Fi/LAN (or connect via Tailscale — see below).
2. Find the Hermes host IP:

   ```bash
   # macOS
   ipconfig getifaddr en0

   # Linux
   hostname -I | awk '{print $1}'
   ```

3. Open the Hermes Android app.
4. Tap **+** to add a connection.
5. Enter:
   - **Label:** any name, e.g. `Home`
   - **Host:** the host IP, e.g. `192.168.1.50`
   - **Port:** `8642`
   - **API Key:** `API_SERVER_KEY` from the Hermes machine
6. Tap the saved connection to browse sessions.
7. Tap a session to start chatting, or create a new one.

### 4. Optional: configure dashboard access

The drawer screens (Memory, Cron Jobs, Skills, Settings) talk to the Hermes
dashboard, which can run on a different port from the Gateway API Server and may
be password-protected. Configure it per connection — either while adding the
connection (expand **Custom dashboard details** in the Add Connection dialog) or
afterwards:

1. On the connections list, tap the **⋮** menu on a connection → **Dashboard Login**.
2. Fill in:
   - **Dashboard Port** — leave blank to use the default (`9119` for HTTP, or the
     same external port for HTTPS deployments), or set an explicit port if your
     dashboard is exposed elsewhere.
   - **Username / Password** — only for a password-protected dashboard. Leave
     both blank for an open (`--insecure`) dashboard.
3. Tap **Save**. The app validates the settings against the dashboard before
   storing them.

When credentials are set, the app authenticates via the dashboard's
`/auth/password-login` flow and reuses the returned session cookie — the same
mechanism the Hermes desktop client uses.

## Connect remotely with Tailscale

Tailscale gives your phone and Hermes machine a private encrypted network, so you do **not** need to expose Hermes directly to the public internet.

Tailscale website: <https://tailscale.com/>

### Install Tailscale on Android

1. Install Tailscale for Android: <https://tailscale.com/download/android>
2. Sign in with the same Tailscale account/tailnet used by your Hermes machine.
3. Leave Tailscale connected while using the Hermes app.

### Install Tailscale on the Hermes machine

Install Tailscale for your OS: <https://tailscale.com/download>

Examples:

```bash
# macOS with Homebrew
brew install --cask tailscale

# Debian/Ubuntu
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

After the Hermes machine is connected, get its Tailscale address:

```bash
tailscale ip -4
```

You can also enable MagicDNS and use the machine name instead of the `100.x.y.z` IP:

- MagicDNS docs: <https://tailscale.com/kb/1081/magicdns>

### Connect the app over Tailscale

In the Android app connection dialog:

- **Host:** the Hermes machine Tailscale IP, e.g. `100.64.12.34`, or its MagicDNS name
- **Port:** `8642`
- **API Key:** `API_SERVER_KEY`

If using Memory/Cron/Skills/Settings remotely, keep the dashboard reachable on the same Tailscale host at port `9119`.

## Connect over HTTPS

For hosted/reverse-proxy deployments (e.g., Hugging Face Spaces, VPS with nginx/Caddy), enter the full HTTPS URL in the **Host** field:

```text
https://your-hermes-host.example.com
```

If no port is included, the app uses port `443`. If your HTTPS service uses a custom port, either include it in the URL (`https://host.example.com:8443`) or set the Port field to that value before connecting.

For HTTPS connections, dashboard drawer screens use the same external HTTPS port. For local HTTP/LAN connections, chat uses port `8642` and dashboard screens use port `9119`.

### Security notes

- Prefer Tailscale/VPN for remote use.
- Do not port-forward the Gateway API Server or dashboard directly to the public internet.
- Rotate `API_SERVER_KEY` if it is shared or exposed.
- Local/Tailscale examples use HTTP, so the private network boundary matters. Use HTTPS for public or hosted endpoints.

## Architecture

```text
Android app (Flutter)
├─ Gateway API Server, port 8642
│  ├─ GET /api/sessions
│  ├─ GET /api/sessions/{id}/messages
│  └─ POST /v1/chat/completions  (SSE streaming)
└─ Hermes dashboard, port 9119
   ├─ /api/memory
   ├─ /api/cron/jobs
   ├─ /api/skills
   └─ /api/model/*
```

## Using the app

### Chat screen

- **Send messages** — Type in the input field and tap the send button or press Enter.
- **Streaming responses** — The agent's response appears token-by-token in real-time. The chat auto-scrolls to the bottom as new tokens arrive.
- **Tool progress** — When the agent uses tools, inline progress messages show the tool name, status, and progress.
- **Verbose mode** — Toggle in the app settings to show raw message metadata (role, tool call IDs, timestamps).
- **Markdown rendering** — Assistant messages render markdown (code blocks, tables, lists, links).
- **Relative timestamps** — Messages show "2m ago", "3h ago", etc.

### Voice chat

The chat input bar has two voice controls:

| Button | Icon | What it does |
|--------|------|-------------|
| **Mic** | 🎤 / 🎤🔴 | Tap to start voice dictation. Speak your message — it appears in the input field and sends automatically when you pause. Tap again (or the red stop icon) to cancel. |
| **Voice reply toggle** | 🔊 / 🔇 | Toggles whether Hermes reads its response aloud after a voice-input message. On = 🔊 (volume up), Off = 🔇 (volume off). |

**How voice replies work:**

1. Tap the mic, speak your question, and wait for the recognition to finish (the text appears and auto-sends).
2. Hermes streams its response as text in the chat as usual.
3. After the full response arrives, if the voice reply toggle is on (🔊), the app reads the response aloud using text-to-speech.

Voice replies **only** trigger when you send a message via the mic button. Typed messages produce text responses only.

#### Setting up text-to-speech (Android)

Spoken replies require Google Text-to-Speech to be installed and configured on your device. The app uses the device's built-in TTS engine — it does not bundle its own voices.

**Step-by-step:**

1. **Install Google Text-to-Speech** — If not already on your device, install from the Play Store: [Google Text-to-Speech](https://play.google.com/store/apps/details?id=com.google.android.tts)
2. **Set as default engine** — Settings → Accessibility → Text-to-speech output → Preferred engine → **Google Text-to-Speech**
3. **Download voice data** — In the same TTS settings screen, tap the gear icon ⚙️ next to Google Text-to-Speech → Install voice data → select **English (Australia)** or your preferred English voice → download
4. **Check media volume** — TTS uses the **media** audio stream, not the ringer. Turn up media volume and make sure your phone isn't in silent/vibrate-only mode.
5. **Test TTS** — In the TTS settings screen, tap "Play" to hear a test phrase. If you hear it, the app should work.

**Troubleshooting voice:**

- **Mic button does nothing** — Speech recognition may be unavailable on your device. Ensure Google app is installed and has microphone permission.
- **Voice reply toggle is on (🔊) but Hermes doesn't speak** — Google TTS is likely not installed or has no voice data downloaded. Follow the TTS setup steps above.
- **Hermes speaks quietly or too fast** — Adjust speech rate and volume in Settings → Accessibility → Text-to-speech output.
- **Recognition is inaccurate** — Speak clearly, reduce background noise, and check that the device's system language includes English.

### Session list

- Browse all Hermes sessions.
- Tap a session to open its chat.
- Pull to refresh the session list.
- Create a new session from the session list header.

### Navigation drawer (☰)

Access these dashboard-powered screens:

- **Memory** — View conversation memory across sessions. Shows stored facts, preferences, and project context.
- **Cron Jobs** — List all scheduled cron jobs. Trigger, pause/resume, create, edit, or delete jobs.
- **Skills** — Browse available Hermes skills with descriptions and trigger conditions.
- **Settings** — View and change the configured Hermes model, theme preference, and verbose mode.

### Theme

- Three-way toggle: **Dark** / **Light** / **System default**.
- Gold Hermes accent (`#D4AF37`) on dark mode; adapted for light mode.

### Cron job management

The Cron Jobs screen supports full CRUD:

- **List** — See all jobs with status (enabled/disabled), next run, and schedule.
- **Create** — Tap **+** to add a new job with schedule (cron expression or interval), prompt, and optional skills.
- **Edit** — Tap a job to modify its schedule, prompt, skills, or status.
- **Trigger** — Manually run a job immediately.
- **Pause/Resume** — Toggle job enabled state.
- **Delete** — Remove a job (with confirmation).

## Development

```bash
cd hermes-android
flutter pub get
flutter analyze
flutter test
flutter run -d android
```

## Build release APKs

```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
mkdir -p release-apks
cp build/app/outputs/flutter-apk/app-*-release.apk release-apks/
```

Output files:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
```

## Release checklist

Every release PR must complete [`CODE_QUALITY_CHECKLIST.md`](CODE_QUALITY_CHECKLIST.md) before tagging or publishing APKs. The checklist covers analysis, architecture, UX, security, release, and manual smoke-test checks.

Minimum release flow:

1. Update `pubspec.yaml` version.
2. Complete `CODE_QUALITY_CHECKLIST.md` and record any exceptions in the release PR.
3. Build split release APKs.
4. Tag the release, e.g. `v1.0.0`.
5. Create a GitHub Release with all APK assets.
6. Confirm the repository visibility and release assets on GitHub.

## Troubleshooting

### I can see sessions but dashboard drawer screens fail

Chat/session features use port `8642`. Memory, Cron Jobs, Skills, and Settings use the dashboard on port `9119`. Start the dashboard with `--host 0.0.0.0` and make sure port `9119` is reachable over Wi-Fi or Tailscale.

### Chat fails with an auth error

Check that the Android connection's API key matches `API_SERVER_KEY` from the Hermes machine (`~/.hermes/.env`).

### The app cannot find the host

- Verify phone and host are on the same Wi-Fi or same Tailscale tailnet.
- Try the raw IP before a hostname.
- Check local firewall rules for ports `8642` and `9119`.
- On Android, ensure the app has network permission (granted by default).

### Streaming stops or messages don't appear

- The SSE connection may have timed out. Pull to refresh the session list and re-enter the chat.
- Check that the Gateway API Server is running and responsive: `curl http://<host>:8642/api/sessions`.
- If using a reverse proxy, ensure it supports long-lived SSE connections (no aggressive timeouts).

### Dashboard screens show empty or error

- Verify the dashboard is running with `--host 0.0.0.0` (an open dashboard also needs `--insecure`).
- If the dashboard is password-protected, set the username/password under **⋮ → Dashboard Login** (or **Custom dashboard details** when adding the connection). A 401 here means the credentials are wrong.
- Check the dashboard port matches the connection (default `9119` for local/Tailscale, same HTTPS port for hosted; override it in Dashboard Login if needed).
- The dashboard must be on the same host as the Gateway API Server for the app's drawer to reach it.

### Voice dictation or spoken replies aren't working

- **Spoken replies not working** — Install Google Text-to-Speech, set it as the default engine, and download English voice data. See [Setting up text-to-speech](#setting-up-text-to-speech-android) above for step-by-step instructions.
- **Speech recognition not working** — Ensure the Google app is installed and has microphone permission (Settings → Apps → Hermes → Permissions → Microphone).
- **Voice reply toggle is off** — Check the speaker icon in the chat input bar: 🔊 = on, 🔇 = off. Tap it to enable spoken replies.
- **Media volume is zero** — TTS uses the media audio stream, not the ringer. Turn up media volume with the physical volume buttons while on the home screen.
- **Hermes speaks but audio is quiet or fast** — Adjust speech rate and volume in Settings → Accessibility → Text-to-speech output.

### Host field examples

The app accepts any of these forms and normalizes them when saving:

```text
192.168.1.50
192.168.1.50:8642
http://192.168.1.50:8642
100.64.12.34
hermes-machine.tailnet-name.ts.net
https://your-hermes-host.example.com
https://your-hermes-host.example.com:8443
```

## Project structure

```text
lib/
├── main.dart                          # App shell, saved connections, navigation drawer
├── core/
│   ├── models/
│   │   ├── connection.dart            # SavedConnection model and host normalization
│   │   └── session.dart               # Session model
│   ├── screens/
│   │   ├── session_list_screen.dart   # Session browser
│   │   ├── chat_screen.dart           # Chat with SSE streaming
│   │   ├── settings_screen.dart       # Model/theme/app settings
│   │   ├── memory_screen.dart         # Memory viewer
│   │   ├── skills_screen.dart         # Skills browser
│   │   └── cron_screen.dart           # Cron job manager
│   ├── services/
│   │   ├── connection_manager.dart    # Saved connections, Gateway API, Dashboard API
│   │   └── ws_client.dart             # JSON-RPC WebSocket client for future dashboard/TUI use
│   └── utils/
│       └── responsive.dart            # Phone/tablet breakpoints
└── assets/
    └── icon/
        └── icon.png                   # App icon source
```

## License

MIT
