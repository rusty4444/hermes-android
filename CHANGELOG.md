# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Release notes for
versions prior to 1.0.7 are in the **What's new** sections of the [README](README.md).

## [2.1.8+2157] — 2026-09-30 (lokale build, kooreman.local)

Android Auto-keten gerepareerd. In 2156 waren manifest en signing goed, maar de
app verscheen nog steeds niet in de auto en Settings gaf 401. Oorzaken gevonden
en gefixt:

### Fixed
- **Android Auto-keten was volledig dood**: de Kotlin-kant bestond wel
  (`HermesAutoNotifications`, `VoiceReplyReceiver`, `NewChatReceiver`,
  `HermesForegroundService`), maar er was géén `MethodChannel`-handler en
  `AutoMessagingService` werd nergens in Dart aangeroepen. Daardoor kon de app
  de auto-code nooit bereiken: geen icoon, geen berichten.
  - `MainActivity`: channel `com.hermesagent.hermes_android/auto` geregistreerd
    (`showNewChatEntry`, `showAssistantMessage`, `start/stopForegroundService`)
    en de engine in `HermesEngineHolder` gezet zodat receivers de app kunnen
    bereiken als de UI niet op de voorgrond is.
  - `main.dart`: `AutoMessagingService.initialize()` aangeroepen.
  - `chat_screen`: publiceert de persistente Android Auto-entry bij openen van
    een chat en spiegelt afgeronde achtergrondturns naar
    Android Auto-gespreksnotificaties.
- **Settings 401 definitief opgelost**: de gateway API key heeft nu **voorrang**
  boven password-login in `DashboardClient`. Server-side geverifieerd dat 9119
  de API key als Bearer accepteert op alle endpoints die de app gebruikt
  (`/api/model/options`, `/api/config`, `/api/skills`, `/api/cron/jobs`,
  `/api/memory` → 200; zonder auth → 401). Voorheen won password-login zodra er
  een username/password was ingevuld, en die faalde.

### Aantekeningen
- OTA-update via `http://192.168.22.50:8842/hermes-android-release.apk`
  — systemd user-service `hermes-android-ota.service` (enabled, lingering aan;
  start automatisch bij boot, overleeft sessie-einde). Bron:
  `/data/hermes-android-update/server.py`.
- Chat draait via REST API op poort 8642; dashboard (Settings) op poort 9119.
- Audio: `speech_to_text` + `flutter_tts` aanwezig, `RECORD_AUDIO` permissie.

## [2.1.8+2156] — 2026-09-30 (lokale build, kooreman.local)

Upgrade naar upstream v2.1.8 met lokale fixes teruggezet zodat de app werkt in
de kooreman.local LAN-setup (API-server op 8642, dashboard op 9119) én als
Android Auto app.

### Fixed
- **Android Auto manifest** volledig hersteld zoals de 1.0.x werkende build:
  `com.google.android.gms.car.application` metadata, `specialUse`
  foreground-service (met `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`), `BootReceiver`
  (BOOT_COMPLETED / MY_PACKAGE_REPLACED / QUICKBOOT / RESTART_FG),
  `VoiceReplyReceiver`, `NewChatReceiver`, leanback-launcher, automotive
  feature-flag, benodigde permissies.
  (Upstream v2.1.8 had de Kotlin-code, maar de manifest-declaraties ontbraken.)
- **Settings/Memory/Cron/Skills 401**: `DashboardClient` accepteert nu
  de gateway API key als Bearer-token wanneer geen dashboard
  username/password is ingevuld. Alle Dashboard-instanties krijgen
  `connection.apiKey` mee.
- **"Could not mint Desktop gateway websocket ticket" opgelost**: de desktop
  gateway wordt alleen gestart als er expliciet een Desktop gateway URL is
  ingesteld. LAN-only setups blijven op de REST API (8642) draaien.
- **Release-signing hersteld**: `key.properties` pad gecorrigeerd
  (`android/key.properties`), waardoor de APK weer met de release-key
  (`CN=Hermes Android`, SHA-1 `4f19:...:8c0b`) wordt ondertekend. Hierdoor
  blijven app-instellingen en iconen behouden bij upgrade.

### Archief
- Oude debug-build 2149 gearchiveerd in `/data/hermes-android-archief/`.


## [1.0.25]

### Fixed
- Server-side: dashboard op poort 9119 accepteert `API_SERVER_KEY` nu als geldig
  Bearer-token op de routes die de Android-app gebruikt
  (`/api/model/options`, `/api/config`, `/api/skills`, `/api/cron/jobs`,
  `/api/memory`). Hierdoor werken Settings/Cron/Skills/Memory weer met dezelfde
  gateway API key.
- Image picker in chat gebruikt nu `pickMultiImage`, zodat je meerdere foto's
  tegelijk kunt selecteren en uploaden.

## [1.0.24]

### Changed
- Foutmeldingen in Settings/Cron/Skills/Memory tonen nu de gebruikte auth-mode
  (Bearer/key-length/prefix) en de exacte URL, zodat diagnose in de app kan
  plaatsvinden zonder logcat.

## [1.0.23]

### Changed
- `DashboardClient` valt niet meer terug op vervallen cookie/password-auth. Als
  de API key leeg of ongeldig is, komt er een directe foutmelding.
- OTA-poort 8842 wordt expliciet in de host-firewall geopend voor VPN-clients.

## [1.0.22]

### Added
- Menu-schermen tonen een duidelijke melding wanneer de dashboard/gateway API
  key ontbreekt.

### Fixed
- `SavedConnection.fromMap` leest nu zowel `api_key` (snake_case) als `apiKey`
  (camelCase) voor backwards compatibility met oudere opgeslagen connecties.

## [1.0.21]

### Changed
- Betere HTTP-foutmeldingen in `DashboardClient`: statuscode + body in plaats
  van generieke "Could not reach/authenticate".
- Debug logging toegevoegd in `_authHeaders()` zodat logcat toont welke auth
  mode wordt gebruikt.

## [1.0.20]

### Fixed
- Settings/Cron/Memory/Skills gebruiken nu de gateway API key als Bearer token
  voor dashboard endpoints.
- Image upload: afbeeldingen worden correct als OpenAI multimodal content array
  verstuurd (`text` + `image_url` parts).
- Conversation history in SSE-requests slaat de tijdelijke lokale rijen over.
- Verwijderde overgebleven `image_cropper` UCropActivity uit AndroidManifest.

### Changed
- Android Auto nieuw-gesprek notificatie is niet meer `ongoing`/`silent`, zodat
  Android Auto hem als ongelezen gesprek kan tonen.
- `DashboardClient` ondersteunt Bearer API-key auth naast password en insecure
  SPA-token modes.

## [1.0.19]

### Added
- Dedicated notification small icon `ic_stat_hermes` (wit op transparant).
- Android Auto notificatie actie krijgt microfoon icoon en label "Spreek in".
- `CarExtender.UnreadConversation` toegevoegd voor betere Android Auto
  compatibiliteit.

### Changed
- Persistent "Start nieuw gesprek" entry wordt herpost na tap of voice reply.

## [1.0.18]

### Fixed
- Debug logging toegevoegd voor gateway chat request body.
- Android Auto notificaties gebruiken `SEMANTIC_ACTION_REPLY` voor spraak.

## [1.0.17]

### Added
- Android Auto spraakknop via `RemoteInput` reply actie.
- `NewChatReceiver` en `VoiceReplyReceiver` met fallback als Flutter engine niet
  in cache staat.

### Fixed
- Buildfout door dubbele `subprojects` / `afterEvaluate` in root build.gradle.kts
  opgelost door het blok te verwijderen.
- Image upload zonder `image_cropper`: resize/compressie via `image_picker`.

## [1.0.16]

### Fixed
- Retry/logica in `connection_manager.dart` verbeterd; SSE retry bij
  verbindingsfouten.
- Assistant-antwoorden tijdens streaming worden bijgewerkt in Android Auto
  notificaties.

## [1.0.15]

### Added
- Attachment ondersteuning in chat: `_pickAttachment`, `_attachments` state,
  `_imageAttachmentDataUrls`, inline file summary en verwerking in `_sendMessage`.
- Dependencies `image_picker`, `file_selector`, `mime` toegevoegd.

### Removed
- `image_cropper` dependency verwijderd vanwege build-fouten.

## [1.0.14]

### Added
- Android Auto ondersteuning met persistente "Start nieuwe conversatie" entry en
  per-sessie berichtnotificaties.
- TV navigatie: `TvFocusable` vereenvoudigd, D-pad shortcuts, scroll-herstel.
- Lokale draft-sessies voor nieuwe chats totdat gateway bevestigt.
- Handmatige update-knop in Settings.
- "Automatische berichten" toggle vervangt "Only My Messages".
- Globale `ValueNotifier`-based settings (`AppSettings`).
- Android TV dwingt altijd `ThemeMode.dark` af.

### Fixed
- Chat UI overflow en scroll-vastlopen opgelost.
- Launcher icon aangepast naar dikke H op gouden cirkel voor betere zichtbaarheid
  in Android Auto/TV.

## [1.0.13]

### Changed
- Updated the Flutter package version to `1.0.13+113` so generated Android
  builds report the same version as the GitHub `v1.0.13` release.

## [1.0.12]

### Added
- **Session source filters** in Settings. Mobile users can now choose which
  Hermes session origins appear in the session list, including scheduled tasks,
  developer tool calls, CLI chats, desktop sessions, and messaging platforms.
- Filter preferences are scoped per saved connection so settings for one Hermes
  gateway do not affect another.

### Changed
- Session filtering is performed client-side against each session's recorded
  source, so it works without any Hermes Gateway API changes.

## [1.0.8]

### Added
- **Reverse-proxy path prefixes** for Gateway API and dashboard routes. Gateway
  prefixes are applied before `/api` and `/v1` routes; dashboard prefixes are
  applied before dashboard `/api` routes.
- **Proxied dashboard mode** for deployments where nginx/Caddy/another proxy
  injects dashboard authentication. In this mode the app sends clean dashboard
  requests without scraping the SPA token or using password login.
- **Dashboard / Proxy Settings** can edit gateway prefix, dashboard prefix,
  proxied-dashboard mode, dashboard port, and dashboard credentials after a
  connection is created.

### Fixed
- Existing chat history, streaming chat completions, session browsing, API-key
  validation, and dashboard validation now consistently use configured path
  prefixes.

## [1.0.7]

### Added
- Support for **password-protected dashboards**: the Memory, Cron Jobs, Skills,
  and Settings screens now authenticate against a basic-auth dashboard via the
  `/auth/password-login` flow and reuse the returned session cookie. Open
  (`--insecure`) dashboards continue to work via the existing token scrape.
- **Configurable dashboard port** per connection (`dashboardPortOverride`),
  defaulting to the previous behaviour (`9119` for HTTP, the external port for
  HTTPS) when unset.
- **Dashboard details in the Add Connection dialog** under a collapsible
  "Custom dashboard details" section, plus a **Dashboard Login** entry on each
  connection's overflow menu. Both validate the dashboard before saving.

### Changed
- `DashboardClient` accepts an optional `http.Client` for testability and
  de-duplicates concurrent login / token requests.

### Fixed
- Updating a connection's API key no longer clears its saved dashboard settings.
