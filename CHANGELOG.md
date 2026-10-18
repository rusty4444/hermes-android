# Changelog

All notable changes since v1.0.7 are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The [README](README.md)
shows only the three latest releases.

## [2.1.22] - 2026-10-19

### Added

- Settings → Appearance now offers a Compact chat density that reduces bubble
  spacing and hides visual sender labels while preserving screen-reader speaker
  announcements. The choice updates open chats immediately, survives backup
  restore and remains available when the dashboard is offline (PR #147).

### Fixed

- Tool activity cards now respect a user's collapsed or expanded choice while
  more tools run, even when the card moves in the chat list or history pages
  change (PR #148).
- Answering one question in a batch clarification no longer closes the chat or
  the next question; cancellation and overlapping approval dialogs also leave
  the correct route open (PR #145).

### Thanks

- [@igitur](https://github.com/igitur) (Francois Botha) for Compact chat
  density and persistent tool-card expansion, with widget regressions in PRs
  #147 and #148.
- [@dadofsambonzuki](https://github.com/dadofsambonzuki) (Nathan Day) for
  diagnosing and fixing batch clarification navigation in PR #145.
- Maintainer follow-up commits addressed additional accessibility, identity,
  and overlapping-dialog edge cases while preserving contributor commits.

## [2.1.21] - 2026-10-19 — Optimisation Release

### Changed

- The first Flutter frame no longer waits for saved preferences, Android
  Keystore reads, or initial intent probes. Secure credential migration and
  share/Quick Chat intents still complete before entering Home.
- Home displays its first five sessions with a progress bar while the full
  list loads. Chats shows a provisional human-chat list when opened early,
  fills it from the same background scan, and reuses Home's complete list when
  available instead of starting another full scan (PR #146).

### Fixed

- Incomplete or shifting session pages no longer prune device-local Quick Chat
  archive records. Older blocked work and local pins remain reachable after
  the full scan.

### Thanks

- [@rusty4444](https://github.com/rusty4444) for testing the prereleases on
  Android and identifying the early Chats transition. Implementation was
  assisted by Hermes Agent.

## [2.1.20] - 2026-10-18

### Added

- Ordinary launches check GitHub Releases for a newer Hermes Android APK no
  more than once every 12 hours after an answered check. Offline attempts may
  retry next launch. The advisory prompt opens the release in a browser;
  it does not download or install anything. Shares, Quick Chat shortcuts, and
  another screen opened before a slow check completes are not interrupted.
- Settings → About offers a manual update check and an opt-out for launch
  checks. **Later** prompts again on the next launch, while **Skip this
  version** waits until a newer release. Both preferences are included in app
  backups.

### Fixed

- A `304 Not Modified` response now compares the cached validated release
  against the installed version instead of incorrectly claiming the app is
  current. Update controls remain available when dashboard settings cannot
  load; remote images in release notes no longer fetch third-party URLs.

### Thanks

- [@igitur](https://github.com/igitur) (Francois Botha) for the update-check
  implementation, translations, and initial regressions in PR #143.

## [2.1.19] - 2026-10-12

### Added

- Android-only chat pins now keep chosen conversations above the Chats browser
  and classic session list. Pins are per connection, survive app restarts and
  compression continuations, and travel with app backups without changing the
  Gateway's server-side pinned flag or other clients. Filters and search still
  apply (PR #140).

### Thanks

- No external contributors in this patch.

## [2.1.18] - 2026-10-12

### Fixed

- Multiline captions, multiple attachment drafts, large text, gateway notices,
  and the on-screen keyboard no longer push the chat editor or Send button
  below the visible viewport. Composer extras scroll before the fixed controls,
  including in narrow landscape and unusually short layouts (PR #139).

### Thanks

- @simplaerai-sv for the responsive composer implementation and regression
  coverage across portrait, landscape, narrow-screen, and large-text layouts.

## [2.1.17] - 2026-10-11

### Fixed

- The model picker now works on API-server-only connections over port `8642`
  without requiring the Desktop Dashboard on port `9119`. The selected provider
  and model are applied to subsequent chat turns while preserving the current
  session and normal automatic chat titles (#129, PR #138).

### Thanks

- @HorCyChangGenitek for the detailed API-only reproduction that identified the
  model picker's unintended Dashboard dependency (#129).

## [2.1.16] - 2026-10-10

### Fixed

- Chat headers now resolve the authoritative server-side Project instead of
  remaining **Unassigned** when navigation context is missing. Project metadata
  refreshes after durable-session binding and reconnect without blocking turn
  recovery, and stale or disposed routes cannot overwrite a newer label (#132,
  PR #133).

### Thanks

- No external contributors in this patch.

## [2.1.15] - 2026-10-10

### Added

- Android notifications now match the Desktop experience for completed and
  failed turns, approvals, clarifications, plugin events, credit changes, and
  other background activity, with per-kind controls and safe routing back to
  the owning chat (PR #128).
- `MEDIA:` deliveries now render as authenticated, tappable file cards with
  safe streaming detection, complete gateway file-type support, and coalesced
  downloads (PR #137).
- Composer drafts now persist per saved connection and session, survive route
  changes and process restarts, and are removed when their chat or connection
  is deleted (PR #131).

### Changed

- Session status chips refresh while their pane is visible without overlapping
  requests or continuing to poll under another route (PR #131).

### Thanks

- @maebahesioru for the desktop-parity notification system, durable composer
  drafts, live session refresh, and extensive lifecycle regression coverage in
  PRs #128 and #131.
- @Thaeland for the secure inline `MEDIA:` delivery cards, complete extension
  contract, and streaming/download race coverage in PR #137.

## [2.1.14] - 2026-10-08

### Fixed

- Bottom navigation labels now stay on one line on narrow phones at every
  supported text size and across every shipped locale. Concise Russian bar
  labels preserve the full pane titles (PR #126).

### Thanks

- @maebahesioru for the responsive navigation-label implementation,
  localisation updates, accessibility handling, and focused regression
  coverage in PR #126.

## [2.1.13] - 2026-10-05

### Added

- Long-pressing a chat message now opens a selectable-text dialog so any part
  of the message can be copied, with readable light and dark themes and
  complete localisation across all shipped languages (PR #127).

### Thanks

- @maebahesioru for the selectable-message-text implementation, localisation,
  dark-theme handling, and focused regression coverage in PR #127.

## [2.1.12] - 2026-10-04

### Added

- Android 13 and newer now expose a per-app language picker for all nine shipped
  locales (PR #125).

### Fixed

- Unended sessions no longer appear permanently active when the Gateway omits
  an authoritative liveness flag. Recent activity keeps them active for five
  minutes, while fixed `is_active: false` placeholders in Projects responses
  are ignored (PR #123).

### Thanks

- @maebahesioru for the Android locale declaration, session-liveness fix, and
  focused regression coverage in PRs #125 and #123.

## [2.1.11] - 2026-10-04

### Added

- Added complete app localisation for Japanese, Simplified Chinese, Korean,
  Spanish, French, German, Brazilian Portuguese, and Russian, with English kept
  as the fallback for unsupported locales (PR #115).

### Changed

- App copy now uses generated Flutter localisation catalogues, including
  locale-aware Russian plurals and region-safe Chinese and Portuguese
  resolution.

### Thanks

- @maebahesioru for the localisation implementation, regression coverage,
  on-device Japanese QA, and thorough review follow-up in PR #115.

## [2.1.10] - 2026-10-02

### Fixed

- Sending from an existing server-side chat now targets that exact session
  instead of opening and submitting into a new sibling session (#120, PR #122).
- Local drafts no longer race legacy `session.create` against recovery v2
  `session.open`; explicit legacy fallback still establishes one session.

### Thanks

- No external contributors in this patch.

## [2.1.9] - 2026-10-02

### Fixed

- Gateway clarification, approval, sudo, and secret requests now reach the
  phone during a running turn, with safe socket ownership and reconnect replay
  (#116, PR #118).
- Large server-side chats open with a bounded recent transcript, keep the
  composer usable during hydration, and preserve authoritative history across
  failed, concurrent, completed, and stopped turns (#117, PR #119).
- Session activity now follows the Gateway's explicit `is_active` state while
  retaining compatibility with older gateways that omit it (PR #121).

### Thanks

- @maebahesioru for correcting session liveness handling and adding focused
  regression coverage in PR #121.

## [2.1.8] - 2026-09-30

### Fixed

- HTTPS connections now honour an explicit Port field value, including `8642`;
  scheme defaults are inferred only when the field is blank (#110, PR #111).
- Leaving a chat during a running turn no longer closes its SSE connection and
  interrupts the work server-side. Detached clients now remain open until the
  stream settles, with failure and timeout paths still releasing them (#112,
  PR #113).

### Thanks

- @igitur for diagnosing and fixing both connection-lifecycle issues and for
  the comprehensive regression coverage in PRs #111 and #113.

## [2.1.7] - 2026-09-28

### Added

- Safely provision folders for name-only Projects, while refusing to adopt a
  directory whose ownership cannot be established.
- Show complete project ownership and server-archived chat information in the
  workspace using stock Hermes gateway contracts.

### Fixed

- Detached replies now recover across long outages, app backgrounding, capped
  message-history rollover, temporary fetch failures, and retained terminal
  failures without restoring the composer too early or polling forever.
- Session pagination now handles repeated pinned backfills without skipping or
  duplicating rows, and no longer prunes assignments from a mutable OFFSET scan
  that cannot prove deletion.
- Project creation, rename, archive, delete, selection, refresh, and cache writes
  now reconcile concurrent optimistic changes without persisting placeholders,
  losing confirmed updates, or allowing a disposed repository to overwrite a
  newer one.
- Stock gateway session moves use `session.workspace.move`; the never-shipped
  `projects.assign_session` dependency has been removed.
- Archived reads are profile-scoped and paged completely; machine-generated
  sessions stay out of human chat lists and unknown project maps no longer label
  chats as unassigned.
- WebSocket creation, session resume, dashboard authentication, HTTP timeouts,
  SSE cancellation, and stale runtime-session recovery are hardened against
  duplicate sockets, leaked streams, zombie reconnects, and stale in-flight
  state.
- Android now declares speech-recognition service visibility, restoring voice
  dictation discovery on Android 11 and newer.

### Thanks

- @Thaeland for the extensive stock-Hermes compatibility implementation,
  diagnostics, and regression coverage in PR #106.

## [2.1.6] - 2026-09-26

### Fixed

- Android now trusts certificate authorities that the device user explicitly
  installed, allowing private Caddy and Tailscale reverse proxies to reach the
  Hermes Gateway while retaining normal system certificate validation (#108).

### Thanks

- @spsDrop for reporting the private-CA connection failure and confirming the
  affected Caddy/Tailscale setup (#108).

## [2.1.5] - 2026-09-24

### Changed

- Android release APKs and app bundles no longer embed dependency metadata,
  matching F-Droid's build requirements.

## [2.1.4] - 2026-09-23

### Fixed

- Long user and Hermes messages now wrap inside the capped tablet chat column
  instead of sizing from the full screen and being clipped (PR #105, #104).

### Thanks

- @kon1z for the precise tablet reproduction, measurements, and root-cause
  analysis in #104.

## [2.1.3] - 2026-09-17

### Fixed

- Chats over the Desktop Gateway transport could silently run under the
  server's *default* profile instead of the profile the connection was meant
  for. A machine-level `hermes dashboard`/`hermes serve` hosts every profile
  and scopes each `/api/ws` JSON-RPC call by a `profile` field in its params
  (`session.create` / `session.resume` store it on the session), which the app
  never sent. Connections now have an optional **Hermes profile** field (under
  *Custom proxy and dashboard details*) that is added to every JSON-RPC
  payload on that socket, the way Hermes Desktop does. Leave it blank for
  isolated per-profile dashboards.
- Chat models can be listed and applied without a Desktop Gateway configured (PR #97).
- The desktop gateway URL field no longer hard-codes a default, and optional connection fields can now be cleared (PR #86).
- The release pipeline pins the production APK signing certificate so a wrong keystore aborts the release instead of publishing a broken APK (PR #99).

### Thanks

- @AletheiaVox for the Hermes-profile plumbing on the Desktop Gateway socket (PR #98).
- @software-greg for the gateway-less chat model picker (PR #97).
- @realchrisolin for the desktop gateway URL field fixes (PR #86).

## [2.1.2] - 2026-09-17

### Fixed

- Project chats open on stock Hermes gateways. The commit-before-open path no
  longer depends on `projects.assign_session` (never shipped upstream): a
  missing sibling falls back to binding the chat through the session `cwd`
  that the stock gateway already honours for project grouping, and the
  `session.create` request now matches stock `SessionCreateParams` (no
  client-supplied `session_id`).
- Reconnects after a dropped socket now resume the gateway-minted stored
  session identity instead of creating a second session, and remember the
  Project working directory so a recreated session stays in its project.

### Thanks

- @Thaeland for the stock-gateway diagnosis in #100 and the cwd-fallback fix
  in PR #102.

## [2.1.1] - 2026-09-06

### Fixed

- Parse the batch `questions[]` clarify payload emitted by stock Hermes
  gateways, not just the custom desktop gateway shape (PR #95).

### Changed

- Release builds now fail when an APK lacks a valid signing block, so unsigned
  artefacts can no longer be tagged and published (PR #96).

## [2.1.0] - 2026-09-03

Community daily-driver workspace edition from
[@CarlosReyesPena](https://github.com/CarlosReyesPena) (PR #88).

### Added

- Workspace shell: Home attention digest, global New chat button, Activity
  operational timeline, More pane routing Cron/Skills/Memory/Settings/dashboard.
- Projects pane over the gateway `projects.*` RPC family: tree overview,
  per-project chats, Spaces→Projects migration preview and write path, chat
  moves between projects, per-project search, safe deletion, and legacy-gateway
  compatibility mode.
- Chats browser with All/Recent/Unassigned/Archived filters, date grouping,
  status and project labels.
- Session search with three per-connection modes: on-device, dashboard FTS5
  full-text with matching excerpts, and AI-assisted query rewriting.
- Encrypted configuration export/import (PBKDF2 + AES-256-GCM), with restore
  available from the empty-connection state.
- Quick chat lifecycle: app shortcut, share-target intents, share review
  sheets, 72-hour archive policy.
- Gateway capability discovery (CapabilityRegistry) so older gateways degrade
  gracefully instead of erroring.
- Runtime Android 13+ notification permission request.
- Chat UI: sticky context header, You/Hermes role labels, long-press action
  sheet, fenced code blocks with copy and wrap/scroll toggle, full tool output
  on expanded activity cards.

### Fixed

- Fresh TCP per request with a 20 s timeout fixes stale keep-alive hangs.
- FAB no longer swallows taps on the More destination.

### Validation

- `flutter analyze` clean; 941 Flutter tests pass (including release-identity
  gates), CI green on PR #88.
- Secret scan of the merged diff: no real credentials (test fixtures only).

## [1.0.14-hermesapk.14] - 2026-07-30

### Added

- Remote Gateway attachments now identify the mobile source channel and active
  ATLAS profile so the server can register them in the canonical document inbox.
- The attachment response carries the document-intake status without exposing
  credentials or raw user/session identifiers.

### Changed

- Chat upload remains available if document catalog registration is temporarily
  unavailable and shows a non-blocking pending notice to the operator.

### Validation

- Static analysis passes with `--fatal-infos`.
- 113 Flutter tests pass.
- The synthetic Desktop Gateway contract suite passes with the extended
  `atlas_intake` response.
- An ARM64 debug APK builds successfully. It remains a private test artifact
  signed with the Android debug certificate.

## [1.0.13-hermesapk.13] - 2026-07-30

Community Remote Gateway edition based on Hermes Android 1.0.13.

### Added

- A unified Desktop Gateway JSON-RPC chat transport with session resume/create,
  reconnect handling, streaming, interruption, and persistent chat mapping.
- Per-chat model and thinking-effort selection. Supported effort values follow
  the Hermes Desktop contract: `none`, `minimal`, `low`, `medium`, `high`,
  `xhigh`, `max`, and `ultra`.
- Up to 10 mixed attachments per message, 16 MiB each, uploaded through
  `file.attach`, with per-file progress, remove, failure, and retry states.
- Selectable Markdown, Copy, Read aloud, Edit and resend, Regenerate, Stop,
  conversation export, session search, Rename, Branch, and Delete.
- Native handling for approval, sudo, secret, clarification, notification,
  reasoning, interim message, tool activity, background result, review summary,
  and subagent events from Hermes Desktop Gateway.
- A local synthetic Desktop Gateway fixture and contract test suite under
  `tools/fake_gateway`.
- A separate debug application ID (`com.hermesagent.hermes_android.dev`) so the
  community test build can coexist with the upstream application.

### Changed

- Text, images, and files in Desktop Gateway profiles now share one session and
  one JSON-RPC transport instead of splitting new messages across REST and
  WebSocket paths.
- Model and thinking overrides are scoped to one conversation; the profile
  default remains controlled from Settings.
- Release signing no longer falls back to the Android debug key. A real release
  requires an explicitly configured private keystore.

### Fixed

- Branch actions no longer open a dialog while the popup route is being torn
  down, preventing the Flutter `_dependents.isEmpty` assertion.
- If Hermes creates a branch but returns a late JSON-RPC error, the app refreshes
  history and reconciles the successful result instead of showing a false
  failure.
- Dashboard dialogs no longer refresh their parent while an IME-dependent route
  is closing.
- Microphone permission is requested only after an explicit microphone action.
- Session identity, official terminal events, retry state, delayed events, and
  duplicate tool progress are handled defensively.

### Validation

- 110 Flutter tests pass.
- The synthetic gateway contract suite covers Dashboard authentication,
  session lifecycle, model/reasoning configuration, attachments, streaming,
  interruption, interactive requests, activity, notifications, and subagents.
- The ARM64 debug build was validated on a physical Android phone connected to a
  private Remote Gateway network.

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
