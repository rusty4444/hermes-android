# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Release notes for
versions prior to 1.0.7 are in the **What's new** sections of the [README](README.md).

## [Unreleased]

### Added

- Settings → Appearance → *Chat detail cards* lets Tool activity and
  Reasoning cards each stay **Auto** (previous behavior), start
  **Collapsed** even while a tool is running or verbose mode is on, or be
  **Hidden** from the chat display. The choices are included in
  configuration backups and never alter the stored conversation.

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
