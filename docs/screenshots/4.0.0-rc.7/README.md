# Ares 4.0.0-rc.7 screenshot captures

These are Android `screencap` PNGs from a disposable emulator. Classic and NextGen come from the same installed build. Each Classic image uses a different palette. Each NextGen image uses a different accent. Brightness is independent of colour.

- Device: disposable Pixel 6 profile, Android API 35 ARM64 emulator (`AresShowcase35`), 1080 × 2400 at 420 dpi.
- App: production-signed `4.0.0-rc.7`, version code **30432**, package `com.hermesagent.hermes_android`, from the published ARM64 APK on the [4.0.0-rc.7 release](https://github.com/rusty4444/hermes-android/releases/tag/v4.0.0-rc.7). Signer SHA-256 `475baf431b16d050c8f658ac838783b273f7c10bba06ed1d16bb0a4239f592fb`.
- Data: a loopback fixture on the host, reached from the emulator at `10.0.2.2:19119`. Conversations, scheduled jobs, insight figures and file names are illustrative fixture data. No production account, private chat, credential or live model call is in these images.
- Capture: Android `screencap`, saved as unedited PNG. Palette and brightness were written to app preferences, then the app was cold-started before each shot.
- Hashes, dimensions and the measured brightness of each file are in [manifest.json](manifest.json).
- The 3.0.0 gallery remains in `docs/screenshots/3.0.0/` for history. The README gallery links this directory.

## Classic

| Image | Screen | Palette | Brightness |
| --- | --- | --- | --- |
| [01](classic/01-chats-gold.png) | Chats | Gold | Dark |
| [02](classic/02-conversation-teal.png) | Conversation | Teal | Dark |
| [03](classic/03-crons-purple.png) | Crons | Purple | Dark |
| [04](classic/04-projects-orange.png) | Projects | Orange | Light |
| [05](classic/05-activity-green.png) | Activity | Green | Dark |
| [06](classic/06-more-blue.png) | More | Blue | Dark |
| [07](classic/07-settings-red.png) | Settings, with the NextGen switch | Red | Light |
| [08](classic/08-appearance-pink.png) | Appearance | Pink | Light |
| [09](classic/09-archived-indigo.png) | Archived chats | Indigo | Light |
| [10](classic/10-assets-cyan.png) | Assets | Cyan | Dark |

## NextGen

NextGen accents follow the Kyllene set: blue, violet, green, orange, pink and teal. They are separate from the Classic palettes.

| Image | Screen | Accent | Brightness |
| --- | --- | --- | --- |
| [01](nextgen/01-sidebar-blue.png) | Sidebar | Blue | Dark |
| [02](nextgen/02-live-violet.png) | Live chat, plan and subagents | Violet | Dark |
| [03](nextgen/03-approval-green.png) | Inline approval | Green | Light |
| [04](nextgen/04-insights-orange.png) | Insights | Orange | Light |
| [05](nextgen/05-scheduled-pink.png) | Scheduled jobs | Pink | Dark |
| [06](nextgen/06-settings-teal.png) | Settings | Teal | Dark |
