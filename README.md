# Hermes Android App

Mobile client for [Hermes Agent](https://hermes-agent.nousresearch.com) — connect to your dashboard from your Android phone over WiFi.

## Features

- **Gold/black Hermes branding** — Cinzel wordmark, gold accents, dark theme
- **Messaging-app style session list** — circular avatars, relative timestamps, message previews
- **Real-time WebSocket streaming** — token-by-token assistant responses
- **New chat creation** — name your session and start chatting
- **Full dashboard access** — Memory browser, Cron jobs, Settings, Skills
- **Media attachments** — photo library and camera picker
- **Responsive layout** — phone and tablet support

## Setup

### 1. Start the Hermes dashboard

The dashboard must bind to all interfaces so the Android app can reach it over WiFi:

```bash
hermes dashboard --insecure --host 0.0.0.0 --port 9119
```

> **Important:** `--host 0.0.0.0` is required. Without it the dashboard's WebSocket only accepts connections from localhost, and chat will fail with "Connection closed."

### 2. Find your server IP

On the machine running the dashboard:

```bash
# macOS / Linux
ipconfig getifaddr en0   # or: hostname -I | awk '{print $1}'
```

### 3. Connect from the app

1. Open the Hermes Android app
2. Tap **+** to add a connection
3. Enter a label, your server's IP, and port `9119`
4. Tap the connection to see your sessions

## Development

```bash
cd hermes-android
flutter pub get
flutter run -d android
```

### Build release APK

```bash
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-*-release.apk
```

## Architecture

```
┌──────────────┐     HTTP + WebSocket     ┌────────────────────┐
│  Android App  │ ───────────────────────> │  Hermes Dashboard   │
│  (Flutter)    │    REST API + WS         │  (port 9119)        │
└──────────────┘                           └────────────────────┘
```

- **REST API** — sessions, config, models, skills, memory, cron
- **WebSocket JSON-RPC** — real-time chat streaming via `/api/ws`
- **Session token** — auto-discovered from dashboard SPA page

## Tech Stack

- Flutter 3.44 / Dart 3.12
- Material 3 dark theme with gold accents
- `flutter_markdown` for message rendering
- `flutter_local_notifications` for push
- `google_fonts` (Cinzel) for branding
- `image_picker` for media attachments
- `web_socket_channel` for JSON-RPC streaming

## Project Structure

```
lib/
├── main.dart                          # Entry point + HomeScreen + HermesHeader
├── core/
│   ├── models/
│   │   ├── connection.dart            # SavedConnection model
│   │   └── session.dart               # Session model
│   ├── screens/
│   │   ├── session_list_screen.dart   # Messaging-style session browser
│   │   ├── chat_screen.dart           # Chat with WS streaming + media
│   │   ├── settings_screen.dart       # Model selection + skills
│   │   ├── memory_screen.dart         # Memory viewer
│   │   └── cron_screen.dart           # Cron job manager
│   ├── services/
│   │   ├── connection_manager.dart    # Connection persistence + ApiClient
│   │   ├── ws_client.dart             # JSON-RPC WebSocket client
│   │   └── notification_service.dart  # Push notification service
│   └── utils/
│       └── responsive.dart            # Phone/tablet breakpoints
└── assets/
    └── icon/
        └── icon.png                   # App icon source
```

## Troubleshooting

### "Connection closed" when sending messages

The dashboard WebSocket only accepts clients from private network IPs when bound to `0.0.0.0`. Ensure you're using:

```bash
hermes dashboard --insecure --bind 0.0.0.0
```

### "Session not found" for new sessions

New sessions show an empty chat until the first message is sent. The agent creates the session file on disk when you send your first prompt.

### Can't find the server

Make sure your phone and the dashboard host are on the same WiFi network. Check the firewall on the dashboard host isn't blocking port 9119.

## License

MIT
