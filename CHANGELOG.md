# Changelog

All notable changes since v1.0.7 are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The [README](README.md)
shows only the three latest stable-version changelog entries (including
source-only preparations), with prerelease preparation documented separately.

Publication correction: tags 3.1.1–3.1.6 have no published APK assets. Their
historical entries below describe source preparations, not downloadable releases;
production-code and verification statements do not establish publication.
The latest verified published stable is 3.1.7.

## [3.2.0-rc.1] - Unreleased

Release preparation only: `3.2.0-rc.1+3021`, with planned APK codes `30211`,
`30212` and `30213`, each above the published 3.1.7 maximum (`30203`).
Keep 3.1.7 as the current stable; the later stable must use a higher base
(at least `3022` if no intervening release consumes it).

### Planned — pending integration and validation

- Nous Portal support (#235).
- OpenRouter support (#237).
- Provider and auxiliary-model settings (#238).
- Command-palette and composer fixes (#239).
- Filter empty cron shells (#240).

These items are integration targets, not shipped features of this docs commit.
The release owner must reconcile them against the final integrated tree and
record its validation before publication. No RC APKs have been built, signed,
published or phone-tested by this preparation. See
[RC preparation notes](docs/releases/3.2.0-rc.1.md).

## [3.1.7] - 2026-10-31

Stable release for the LAN discovery feature. Release identity is
`3.1.7+3020`; production APK codes are `30201`, `30202` and `30203`, above
every 3.1.6 split. The production package and signing identity remain
unchanged. Install over the existing app without uninstalling.

### Added

- Find Hermes on LAN discovery (IPv4 and IPv6 subnet probing, HTTPS-aware,
  bounded concurrency).

### Fixed

- Test file cleanup in lan_discovery_service_test.dart (removed dead mock
  scaffolding and unused imports).


## [3.1.6] - 2026-10-29

Stable patch for the v3.1.5 release window README. Release identity is
`3.1.6+3019`; production APK codes are `30191`, `30192` and `30193`, above
every 3.1.5 and 3.1.4 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.5] - 2026-10-29

Stable patch for the v3.1.4 release window README. Release identity is
`3.1.5+3018`; production APK codes are `30181`, `30182` and `30183`, above
every 3.1.4 and 3.1.3 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.4] - 2026-10-29

Stable patch for the v3.1.4 release window README. Release identity is
`3.1.5+3018`; production APK codes are `30181`, `30182` and `30183`, above
every 3.1.4 and 3.1.3 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.4] - 2026-10-29

Stable patch for the v3.1.3 release window README. Release identity is
`3.1.4+3017`; production APK codes are `30171`, `30172` and `30173`, above
every 3.1.3 and 3.1.2 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.3] - 2026-10-29

Stable patch for the v3.1.3 release window README. Release identity is
`3.1.4+3017`; production APK codes are `30171`, `30172` and `30173`, above
every 3.1.3 and 3.1.2 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.3] - 2026-10-29

Stable patch for the v3.1.2 release window README. Release identity is
`3.1.3+3016`; production APK codes are `30161`, `30162` and `30163`, above
every 3.1.2 and 3.1.1 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.2] - 2026-10-29

Stable patch for the v3.1.2 release window README. Release identity is
`3.1.3+3016`; production APK codes are `30161`, `30162` and `30163`, above
every 3.1.2 and 3.1.1 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows exactly the three latest changelog releases,
  matching the release validation script.

## [3.1.2] - 2026-10-29

Stable patch for the v3.1.1 release window README. Release identity is
`3.1.2+3015`; production APK codes are `30151`, `30152` and `30153`, above
every 3.1.1 and 3.1.0 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows the three latest changelog releases, matching
  the release validation script.

## [3.1.1] - 2026-10-29

Stable patch for the v3.1.1 release window README. Release identity is
`3.1.2+3015`; production APK codes are `30151`, `30152` and `30153`, above
every 3.1.1 and 3.1.0 split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- README release window now shows the three latest changelog releases, matching
  the release validation script.

## [3.1.1] - 2026-10-29

Stable patch for the REST/API-server approval path. Release identity is
`3.1.1+3014`; production APK codes are `30141`, `30142` and `30143`, above
every 3.1.0 and 3.1 RC split. The production package and signing identity
remain unchanged. Install over the existing app without uninstalling.

### Fixed

- REST/API-server transport now handles `event: approval.request` frames
  instead of crashing on the non-object `choices` list. Approval frames are
  forwarded into the existing approval dialog, and the responder falls back to
  `POST /v1/runs/{run_id}/approval` when no Desktop Gateway session is
  available (#229).

### Thanks

- Thanks to @igitur for the detailed bug report and server-side frame evidence
  for #229.

## [3.1.0] - 2026-10-29

Stable promotion of RC2's application code. This entry covers **all changes
since 3.0.6**, including RC1 and RC2. Release identity is `3.1.0+3013`;
production APK codes are `30131`, `30132` and `30133`, above every 3.1 RC and
every 3.0.x split. The production package, `com.hermesagent.hermes_android`,
and signing identity remain unchanged. Export an encrypted configuration
backup, then install over the existing app without uninstalling or clearing
data. See the [detailed release notes](docs/releases/3.1.0.md).

### Added

- Opt-in foreground Android hands-free voice: local English “Hey Hermes” wake
  detection, one recognised prompt through normal chat admission, that turn's
  spoken reply, and a configurable 0–30 second follow-up window. The mode is off
  by default and stops on navigation, backgrounding, account changes or errors;
  returning never restarts the microphone. Wake detection is offline, but the
  Android speech provider, selected voice and gateway may use networks.
- A Settings → Voice switch turns the hands-free feature off entirely: the
  “Hey Hermes” start/stop control and in-chat voice controls disappear, and a
  running session stops immediately. Re-enabling restores the control surface
  without restarting capture (#227, #228).
- A shared, joinable native capture owner for Android manual dictation and
  hands-free input. Manual dictation remains draft-only. Bundled runtime/model
  provenance and licences accompany reproducible, hash-checked build inputs.
- Long pastes over 3,000 UTF-16 code units now attach as collision-safe
  `paste.txt` files in Remote Gateway chats, matching the Desktop threshold.
  Short pastes and legacy REST stay inline (#212).

### Fixed

- Stock idle turns settle only on owned successful completion receipts. A
  rejected foreign completion can no longer manufacture the next completion's
  evidence, and an owned receipt without a durable response-row floor releases
  admission as unknown instead of leaving the chat busy indefinitely (#221).

### Thanks

- Thanks to @mannok for the hands-free voice proposal (#142) and to
  @mordekai-lab for the stock-idle receipt policy work and regression tests
  in #221. Original commit histories are preserved.

Hermes Agent assisted with research, implementation, independent review,
documentation and tests. Automated checks do not establish physical-phone
acceptance: microphone → STT → gateway → TTS behaviour, Android 14–16
permission/privacy/lock scenarios, accents, noise, Bluetooth/car mode,
battery/thermal measurements, clipboard-paste behaviour and physical 16 KB-page
launch remain unverified limits, not promises.

## [3.0.6] - 2026-10-29

Release identity is `3.0.6+3010`, with production APK codes `30101`, `30102` and
`30103`, above every 3.0.5 split. The production package and signing identity
remain unchanged. Export an encrypted configuration backup, then install over
the existing app without uninstalling or clearing data. See the
[release notes](docs/releases/3.0.6.md).

### Fixed

- API-server (REST SSE) sends now register as app-wide turn activity, so
  backgrounding the phone mid-turn no longer freezes the process and destroys
  the turn (#225, #226).
- Approval and input notifications use generic body text — command details no
  longer reach the lock screen — with clearer connection attribution and state,
  controls placed next to the settings they affect, accessible switch labelling
  and honest disable messaging (#224).

### Thanks

- Thanks to @mordekai-lab for the notification clarity and privacy work and
  regression tests in #224. Their original commit history is preserved.

Hermes Agent assisted with review, integration, documentation and tests.
Automated checks do not establish physical-phone acceptance. The long-paste and
stock-idle settlement PRs shipped in 3.1.0-rc.1; uncertain delivery is not
automatically resent.

## [3.0.5] - 2026-10-28

Release identity is `3.0.5+3009`, with production APK codes `30091`, `30092` and
`30093`, above every 3.0.4 split. The production package and signing identity
remain unchanged. Export an encrypted configuration backup, then install over
the existing app without uninstalling or clearing data. See the
[release notes](docs/releases/3.0.5.md).

### Fixed

- Recognised scheduled-job setup, including embedded skill instructions, uses
  read-only Background task cards: collapsed in Verbose Mode and hidden in
  conversation-only mode. Ordinary human skill invocations, raw saved history
  and prompt ownership retain their existing behaviour (#218).
- An approval response dismisses only the dialog that submitted it. A removed
  dialog cannot pop the underlying chat, and a covered dialog cannot dismiss a
  newer prompt (#220).

### Thanks

- Thanks to @mordekai-lab for the approval-dialog route-ownership fix and
  regression tests in #220. Their original commit history is preserved.

Hermes Agent assisted with review, integration, documentation and tests.
Automated checks do not establish physical-phone acceptance. Stock-turn receipt
and long-paste changes from blocked PRs are not included; uncertain delivery is
not automatically resent.

## [3.0.4] - 2026-10-28

Release identity is `3.0.4+3008`, with production APK codes `30081`, `30082` and
`30083`, above every 3.0.3 split. Package and production signing identity remain
unchanged. Install over the existing production app without uninstalling or
clearing data; export an encrypted configuration backup first. See the
[release notes](docs/releases/3.0.4.md).

### Licence evidence and notices

- Document the MIT declaration that predates the community contributions,
  including all 56 PR #88 commits, and the applicable GitHub contribution terms.
  The application continues under its existing MIT terms; no contributor's
  silence is treated as permission or a new copyright assignment.
- Retain scoped upstream notices for the Graphify viewer, copied Hermes backend
  fixture templates, Gradle wrapper build materials and Flutter scaffolding.
  Preserve the unchanged embedded Library archive, its LGPL source/relink rights,
  Cinzel OFL and all existing third-party exceptions.
- Make the additional notice material available through the existing offline
  Licences page and corresponding source distribution, with regression gates.

No chat, authentication, notification-consent or gateway behaviour is changed.
Thanks to the original contributors and F-Droid reviewers for the evidence and
notice findings. Hermes Agent assisted with audit, implementation and tests.

## [3.0.3] - 2026-10-28

Release identity is `3.0.3+3007`, with production APK codes `30071`, `30072` and
`30073`, above every 3.0.2 split. Package and production signing identity remain
unchanged. Export an encrypted configuration backup, then install the matching
APK without uninstalling or clearing app data. See the
[release notes](docs/releases/3.0.3.md).

### Fixed

- Complete LCM context summaries render as read-only Background task reports,
  collapsed in Verbose Mode and hidden in conversation-only mode. Ordinary
  messages, genuine human input and saved history remain unchanged (#211).
- Recovery-v2 Stop preserves the admitted turn's observer through wind-down and
  handles Stop before its first state callback; attachment-only mid-turn Send
  now explains its unsupported action without losing staged files (#207).
- Stalled SSE bodies have an activity-renewed timeout, session paging does not
  truncate on misleading metadata, and message IDs stay within one URL segment.
- Connection reset verifies credential removal and rollback; rejected local
  space writes fail honestly. Closed Desktop clients cannot revive callbacks or
  send forgotten local clarification handles.
- Optional Android share-bridge failures no longer strand startup. Unsupported
  Projects metadata remains unknown instead of claiming every chat is Unassigned.
- Video staging uses process-held ownership locks for safe later reclamation,
  preserves original opening errors, and shares file classification with previews.
  Parser mutation and lifecycle regressions cover the independently validated
  audit gaps; see the [complete #207 dispositions](docs/audit-207/README.md).

### Thanks

- Thanks to @Thaeland for the explicitly AI-labelled #207 audits and follow-up
  evidence. Maintainer regression tests distinguish confirmed defects from
  disproved premises, intentional bounded behaviour and an unreproduced flake.

Hermes Agent assisted with validation, implementation, documentation and tests.
Automated checks do not certify physical-device codecs, memory use or every
gateway contract. Unknown outcomes remain unknown; prompts are not resent
automatically. The historical timing report remains not reproduced.

## [3.0.2] - 2026-10-27

Release identity is `3.0.2+3006`, with production APK codes `30061`, `30062` and
`30063`, above all 3.0.1 and 3.0.2-recovery.1 splits. The production package and
signing identity stay the same. Install over the existing production app without
uninstalling or clearing data. Export an encrypted configuration backup before
updating. See the [detailed release notes](docs/releases/3.0.2.md).

### Fixed

- Existing chats could appear frozen at an older unconfirmed reply even after
  newer saved messages arrived. Refreshed saved history now has its own end;
  retained unknown output stays available through a separate read-only inspector.
- The recovery inspector isolates its scroll and detail state, avoiding a
  scroll-offset/expansion-state type collision. Tool and reasoning expansion
  choices survive lazy scrolling within the visit.
- Delayed history reads, refresh and inspection respect newer reading and
  navigation intent. Failed or empty history reads do not hide retained output.

### Behaviour and limits

- Saved history and received output keep independent provenance. An unknown
  outcome remains unknown; idle state and matching text do not prove success or
  establish a saved-message match. The app does not resend missing requests.
- Quiet mode keeps its completed-reply filtering. Verbose Mode exposes retained
  public detail. Received output remains session-local and subject to existing
  retention limits; it is not a durable archive.
- You do not need a backend patch, gateway restart or app-data reset. Existing
  preview, backup, authentication and background-notification limits remain.

Sam confirmed the recovery testing build on his phone and approved stable
promotion. Hermes Agent assisted with implementation, review, documentation and
regression tests. Existing contributor credits and release history remain below.

## [3.0.1] - 2026-10-26

Release identity is `3.0.1+3004`, with production APK codes `30041`, `30042` and
`30043`, above all 3.0.0 splits. The production package and signing identity stay
the same. Export an encrypted configuration backup before updating. See the
[detailed release notes](docs/releases/3.0.1.md).

### Added

- In-app video attachment playback with play/pause, seeking and mute controls,
  using downloaded bytes rather than exposing gateway credentials to a player.
- Offline DOCX, XLSX and PPTX text previews in the shared chat/Assets viewer.
  Original formatting and images are not rendered; legacy binary Office formats
  and unsupported codecs retain Download/Share. PDF and plain-text previews remain.

### Behaviour and limits

- Videos start paused and offer replay after completion. Backgrounding the app
  or covering the preview pauses playback; returning does not resume it without
  a Play tap. The player reads an app-private local copy of cached original bytes.
- XLSX text includes sheet names and cell coordinates with raw stored values;
  the app does not evaluate formulas. DOCX tables and PPTX slides are text previews,
  without original layout, charts, images or formatting.
- Chat cards, inline file links and More → Assets share previews and cached
  original-byte Download/Share. Existing 25 MiB transfer and bounded-preview
  limits apply. Android/device codecs determine which videos can play; legacy
  Office and OpenDocument files retain the download/share fallback.
- These previews use existing gateway routes, with no backend patch or new
  server configuration. Background push and its separate companion requirements
  are unchanged. Automated checks do not establish physical-phone acceptance.

Hermes Agent assisted with implementation, review, documentation and regression
tests. Existing community credits and release history remain below.

## [3.0.0] - 2026-10-25

Stable promotion of RC3's application code. This entry covers **all changes since 2.1.33**, including RC1 and RC2, not only the final candidate. Release identity is `3.0.0+3003`; production APK codes are `30031`, `30032` and `30033`, above all 3.0 RCs. Package and production signer remain unchanged. Back up settings before updating. See [the detailed release notes](docs/releases/3.0.0.md) for the full behaviour inventory and compatibility limits.

### Added

- Ten complete colour palettes with independent light/dark/system appearance, live route updates, persisted preferences and encrypted backup/restore. Connection-screen appearance works before connecting; Android system chrome follows the app theme.
- A dedicated Crons conversation browser, with search, All/Recent/Archived filters and local pins. Scheduled conversations no longer appear in human Chats, including legacy job IDs and compressed roots.
- Verified Archive/Unarchive actions for stored chats, including durable restoration of expired Quick Chats and retryable incomplete archive reads.
- A current-work responding bar in quiet and Verbose modes, covering tools, exposed reasoning, delegated work and gateway status when emitted by the server.
- Local-time footers for human messages and completed Hermes replies, with server/device provenance, full-date tooltips and device locale/12-hour/24-hour formatting. Missing history times remain absent.
- Separate Stop and Send controls during active work. Remote Gateway Send provides text guidance through `session.steer`; REST/non-steering connections offer explicit Stop and send. Pending acknowledgements preserve newer edits and never trigger an automatic retry or interruption fallback.
- More → Assets with source-chat/filename search, type filters, incremental scans, source navigation and partial/retry reporting. Timeline and Assets recognise explicit MEDIA/filesystem deliveries and successful image-generation results, including outputs omitted from final prose.
- Zoomable image, Android PDF-page and selectable inert-text previews; direct native save/download from cards and popups, separately from Share. Other binaries retain metadata/download fallback. Transfers share a streaming 25 MiB per-file limit and resource/cancellation ownership.
- Tap-triggered HTTPS image downloads through a separate credential-free client, and external HTTP/HTTPS web-link opening in replies, selectable text and delegated-task transcripts. Code/unsupported schemes stay inert.
- Optional imported per-connection PEM/P12 client-certificate authentication, including encrypted PEM/password retries, bounded content-sniffed mobile picking, TLS validation and certificate-chain handling.
- Encrypted backup format v2 with portable imported identities, required passphrases and palette preferences; older supported backups remain readable.
- Simplified automatic background notifications with one opt-in plus Android permission, a built-in Google-backed transport on supported phones and optional external UnifiedPush. Authorised current/future-chat scope follows live server policy; old narrow consent is not expanded without a new choice.
- A bounded, metadata-only operational Activity index for stock Gateway turns, surviving restart and retaining compressed-chat lineage.
- Offline application/font/embedded-library/dependency licence notices in Settings → About → Licences, plus exact-source/relink release materials and checksums.

### Changed

- Navigation is Chats → Crons → Projects → Activity → More, with Chats replacing Home as the default. Relevant Needs you/Running now summaries sit above Chats.
- More groups Cron, Skills and Memory under Agent; duplicate archive navigation and unimplemented Organisation/batch/AI-filing placeholders are removed.
- Quiet mode shows human input and positively completed replies while keeping current work in the responding bar. Verbose Mode exposes retained detail with every expandable section initially collapsed; choices survive updates/lazy scrolling within a visit, not a true close/reopen.
- Recognised internal notices and preserved task reports use neutral, read-only background cards rather than editable human bubbles. Genuine steering, skill invocations, merged human follow-ups and public/hidden/model-only boundaries remain intact, including task history.
- Saved and received chat output retain independent provenance. Covered live copies yield to saved history only with a complete committed-turn receipt and fresh physical rows. The received-output explanation moves out of the transcript into Chat actions.
- Activity includes app-observed stock turns and gateway chats updated within seven days, including REST/other-client updates. Updated metadata is not inferred success/running; partial/stale coverage and uncertain outcomes remain explicit. Refresh pauses while hidden/backgrounded.
- Progressive, shared session scans replace the old 2,000-row ceiling. Active, archived and Project/Quick metadata complete independently and preserve known rows on failures.
- Android supplies file-delivery guidance through existing chat protocols, including reused TUI sessions, without a backend patch. Raw history retains ordinary app-added context; Android's public display/export hides recognised framing while preserving literal commands and voice-stop phrases.
- Release creation is immutable and create-only, bound to the peeled remote tag. Publication verifies every actual APK's identity, ABI code, production signer and licence/source bytes; early PR CI runs publisher/verifier/native-config regressions.

### Fixed

- Open chats at their latest visible message without pulling readers away during refresh, streaming, late history failure or task inspection.
- Preserve the previous completed REST reply when stopping a new response before its first text. Stale history cannot erase retained received output without its own proof.
- Keep canonical/local draft ownership, deliberate clears, reasoning/tool choices and child observers across identity binding, preference reloads, hydration failure, route reopen and delayed saves/rejections.
- Fence submission/recovery/history by request-start and observation authority so stale idle/terminal events cannot settle a newer turn, release Send early or resubmit uncertainty. Share proven receipt replacement across retained routes; retry superseded context without corrupting paging.
- Preserve newer external titles, confirmed archive/move results and late local pins through older aggregate reads and independent scope refreshes. Failed Quick Chat restoration remains retryable rather than claiming success.
- Preserve public-only export replacements, suppress hidden/model-only physical rows and image-only empty placeholders, and retain received unknown-outcome provenance.
- Keep appearance/device settings usable when server-model reads fail. Serialised saves and dismissed-picker rollback update the surviving app.
- Carry the saved TLS identity through independent REST/SSE, WSS, history/recovery, search, task, Memory, push and file clients, without lending it to GitHub updates or external images. Keep private-key passphrases in secure credential storage.
- Own staged/committed certificate files across queued account transactions and backup rollback. Preserve existing identities after cancellation/lost acknowledgements; report incomplete restoration under persistent storage failure.
- Serialise saved-account list transactions across managers, sanitise prerequisite-storage failures and isolate optional mutation observers.
- Retain notification taps across pause/resume and validate current credentials/profile/consent after asynchronous lookups. Coalesce canonical routes and reject stale/unscoped sensitive approval actions without preventing safe chat navigation.
- Start foreground protection only from confirmed policy; refresh notification permission without repeating startup prompts and clean up only the affected chat's entries.
- Recover fenced push registration/challenge state without widening consent. Old delayed writes/revocations/account changes cannot resurrect stale registration; native storage/leases belong to the Flutter engine across Activity detach/reattach.
- Explain missing/disabled/outdated/unauthorised push companions, link installation steps and scope off-state probes to Settings without enabling push. Companion dependency bounds admit current supported Hermes cryptography versions; guides distinguish mounted APIs from active hooks/workers and supported launch-profile hosting.
- Accept observed hosted `V2 Signer:` output while retaining strict production pinning and malformed/extra-signer rejection. Clean native CI provisions its pinned Gradle and actual Flutter version identity.

### Compatibility and limits

Quiet saved history needs completion metadata; duplicate handover needs optional `persisted_turn` receipts. Assets is partial discovery, not a filesystem catalogue. Imported identities are app-private files, not Android KeyChain keys. Push needs a separately installed/enabled/operator-authorised companion and supported phone transport; Force stop, Doze and OEM restrictions still apply. No host service is installed by the APK, and no private-CA, killed-process delivery, legal clearance or F-Droid approval is implied by automated checks. Some new strings retain English fallback in existing locales.

### Thanks

- @smhc contributed imported client certificates (#166), mobile picking/password/layout improvements (#187) and a physical Android mTLS report. Maintainer follow-ups preserve their commits and add encrypted-PEM, chain, ownership and transport coverage.
- Hermes Agent assisted with implementation, review, documentation and regression tests. Existing community credits remain in README/NOTICE. Historical RC entries below describe their status at publication, not the current stable version.

## [3.0.0-rc.3] - 2026-10-25

Testing candidate only. **2.1.33 remains latest stable.** Back up settings before
installing; stable 3.0 and GitLab/F-Droid updates remain on hold until phone
testing is approved. Base code **3002** produces **30021**, **30022** and
**30023**, above RC2's **30011–30013**, with the existing production signer.

### Fixed

- Show current tool, reasoning and delegated work in the responding bar even
  with Verbose Mode off, without adding partial replies to quiet chat (#200).
- Present recognised internal notices as neutral background tasks, preserving
  genuine human input, hidden/model-only exclusions and retry ownership (#201).
  Human follow-ups merged into a notice remain editable human messages and
  retain the reply's retry target, including delegated-task history.
- Replace saved/live duplicate presentation only when an exact committed-turn
  receipt and fresh complete history prove the handover. Share replacement
  context with retained chat routes and retry superseded context reads (#202).
  A held refresh cannot revive an answer vetoed by a newer alias observation;
  lagging history and uncertain outcomes never become inferred completion.
- Explain the separate mobile-push server prerequisite, link its installation
  guide and make off-state availability checks read-only and Settings-scoped
  without enabling notifications or clearing consent errors (#203).

### Changed

- Run the actual-APK verifier regressions during PR quality checks as well as
  tagged releases; publication still verifies all three signed splits and the
  corresponding source/relink materials before creating a release.

### Added

- Message-level local-time footers for user messages and completed Hermes
  replies in quiet/Verbose Mode and both chat densities (#198). Prefer recorded
  server times; label one-time device send/receipt observations in the tooltip.
  Missing or invalid history times remain absent rather than using fetch or
  rebuild time. Keep each completed message's footer when an earlier preview
  completes after later interim commentary. Preserve existing completion,
  source ownership and release gates.

## [3.0.0-rc.2] - 2026-10-24

Testing candidate only. The latest stable release remains **2.1.33**. Back up
settings before installing; phone acceptance is required before stable 3.0
promotion or GitLab/F-Droid updates. Base code **3001** produces split codes
**30011**, **30012** and **30013**, above RC1's **30001–30003**.

### Changed

- Keep quiet conversation presentation separate from Verbose Mode details.
  Quiet mode requires source-local reply-completion evidence; expandable
  verbose details start collapsed and preserve manual choices during a visit.
- Remove the unused Organisation section and its **Pin, batch and undo** and
  **AI-assisted filing** placeholders from More. Rename **Automation** to
  **Agent**, which groups Cron, Skills and Memory, across all supported languages.
- Replace the Home tab with a default Chats destination and a second Crons
  destination: Chats, Crons, Projects, Activity, More.
- Move actionable Needs you / Running now summaries above the human chat list
  without duplicating recent and completed conversation lists.
- Browse scheduled-job conversations separately, with source-aware search,
  Recent and Archived filters, local pins and access to cron-job management.
  Retain legacy cron IDs and compressed roots even when source metadata is absent.
- Share progressive history scans between the two browsers, preserve loaded
  rows on failed refreshes and continue past the old 2,000-row limit. Dashboard
  archive loading retains profile, origin and prefix and completes independently
  of active history.

### Fixed

- Preserve the previous completed reply when Stop or Stop and send cancels a
  new REST response before its first text arrives.
- Bound actual certificate-file reads to 1 MiB, fence pending picker/import
  callbacks and clear obsolete password retries when selecting another file.
- Preserve configured typed voice-stop phrases and literal slash-command text
  when adding Android attachment guidance. Leave input unchanged if the gateway
  cannot provide its voice configuration.
- Keep image-only history free of empty-text placeholders and keep hidden,
  model-only and replaced physical content out of chat exports.
- Open chats at the latest visible message without pulling a reader away from
  older history during refreshes, streaming or delegated-task inspection (#186).
- Make certificate files selectable on Android/iOS and ask for protected-file
  passwords after selection. Retain encrypted PEM retries and certificate-chain
  separators; reject an unusable PEM identity before reporting it loaded (#187).
- Remove the large received-output notice from the chat transcript. Keep its
  explanation under Chat actions → About received output, without changing
  message provenance, recovery or export details.
- Request attachment-capable chat instructions explicitly rather than inheriting
  the gateway host's terminal/TUI surface. Android adds its own versioned client
  guidance through existing chat protocols, including reused TUI sessions;
  no backend patch or Android companion is required. User-facing message text
  remains clean while raw server history retains the app-added context.
- Populate Activity from actual app-owned turn observations and honest gateway
  update metadata. Retain compression roots across restart and navigate older
  activity to the current conversation without duplicate continuation rows.
- Open web links in chat replies, selected message text and delegated-task
  transcripts in the external browser when tapped. Preserve gateway file
  downloads and keep code examples and non-web URI schemes inert.
- Verify manual Archive / Unarchive against the exact stored chat. An expired
  Quick Chat is reported restored only after its local retention change is
  durable; failed writes leave the row retryable rather than a phantom success.
- Keep separate Stop and Send controls while Hermes is responding. Remote
  Gateway sends guidance through `session.steer` without starting another turn;
  legacy REST explicitly stops its current response before sending a new one.
- Preserve newer composer edits while guidance is awaiting acknowledgement.
  Rejected or unconfirmed guidance keeps the draft, with no automatic resend or
  interrupt fallback. Both controls retain 48 dp targets on narrow screens.
- Replace completed archive snapshots independently of pending active history,
  and show incomplete/retry state when expired Quick Chat IDs remain unresolved.
- Keep newer external chat titles when an older aggregate scan completes,
  reconcile standalone renames into retained Chats, and hydrate supplied local
  pins without waiting for unrelated archive/history reads.
- Accept the hosted SDK's observed `V2 Signer:` certificate output in the
  fail-closed APK publication gate, retaining single-signer production pinning
  and logging selected SDK tool paths/build-tools revision for diagnosis.

### Added

- Generated attachments share timeline and Assets discovery: explicit `MEDIA:`
  deliveries, filesystem Markdown links and recognised successful image-tool
  results. Files stay visible independently of verbose tool details.
- Attachment popups preview images, Android PDF pages and inert text; other
  binary files retain a metadata/download fallback. Download opens the native
  save picker directly from either the card or popup, separately from Share.
- Chat attachment downloads use the same streaming 25 MiB budget as Assets.
  URL-only generated images use a separate, credential-free HTTPS connection
  only after a tap; gateway authentication never goes to the image host.

- Native **More → Assets** browser for explicit generated-file references in
  saved Hermes replies. Includes filename/source-chat search, file-type filters,
  on-demand image previews, download/share and navigation to the source chat.
- Bounded, incremental recent-chat and older-message scans with visible partial
  scope, refresh and retry for failed reads. Reads stay on the saved connection's
  Dashboard profile without resuming sessions or running an agent.
- A streaming 25 MiB per-file download budget for Assets, including chunked
  responses and authentication retries.

### Limits

- Assets is reconstructed from explicit saved deliveries and recognised media
  producer results, not a server-owned
  catalogue of all attachments, project files or outputs. Referenced files may
  have expired or been removed. Organisation placeholders are not shown:
  durable batch undo and correction-learning AI filing need separate contracts.
- This testing candidate was assisted by Hermes Agent. Automated verification
  does not establish phone acceptance, and the current stable version is unchanged.

### Thanks

- @smhc contributed the mobile certificate-picker and password-entry improvements
  in #187, with a physical Android mTLS report. Maintainer follow-ups add encrypted
  PEM and certificate-chain regressions. Original contributor commits are retained.
- Hermes Agent assisted with review, follow-up fixes and automated verification.

## [2.1.33] - 2026-10-24

### Fixed

- More → Memory now displays saved facts, not memory configuration options.
  About you opens the connected profile’s `USER.md` entries; Agent notes shows
  its `MEMORY.md` entries. Refresh, selectable text and on-demand full reads of
  long facts are read-only. External memory providers such as MemPalace are
  explicitly outside this view.
- Missing or unsupported saved-memory APIs show an actionable error rather than
  falling back to configuration or falsely reporting an empty memory store.
- Delegated-task bubbles keep a compact goal and status in the parent chat.
  Open the task timeline for its full details and model information (PR #173).
- Reasoning starts collapsed on a new chat visit. Manual expansion survives
  updates and scrolling within that visit; the app's explicit Verbose mode
  remains the open default. Gateway hints cannot reopen reasoning (PR #174).

### Validation

- Local static analysis and all 1,839 Flutter tests passed. The ARM64 debug APK
  compiled on the integrated tree. No physical-device validation is claimed.
- Release identity is `2.1.33+2176`; split codes are `21761` (armeabi-v7a),
  `21762` (arm64-v8a) and `21763` (x86_64). The upgrade floor remains `2127`.

### Thanks

- Hermes Agent assisted with implementation, independent review, documentation
  and regression tests. Existing community credits remain in the README and
  earlier entries; this release includes no new external-contributor commits.

## [2.1.32] - 2026-10-23

### Fixed

- Tool sections start collapsed on each chat visit, including while a turn is
  running. The collapsed header shows the newest in-flight call, or the latest
  call if none are running, with group status, failures and observed timing
  retained (PR #172).
- Manual expansion survives streaming updates and scrolling during a visit.
  Leaving and reopening the chat resets the choice; verbose mode remains an
  explicit open default.

### Validation

- Static analysis and all 1,795 Flutter tests passed before release preparation.
  Regression tests cover concurrent calls, failures, scrolling and reopening
  through the stored session identity. Physical-device validation is not claimed.

### Thanks

- Hermes Agent assisted with implementation, independent review and regression
  tests. Existing community credits remain in the README and earlier entries.

## [2.1.31] - 2026-10-23

### Added

- Tap a delegated-task row for a read-only timeline in a phone sheet or
  wider-screen dialog above the parent chat. Inspect recorded messages,
  actual tool call IDs, arguments/results and exposed reasoning. Refresh and
  Load older use bounded authenticated Dashboard GETs; live previews carry
  a separate label. Closing the viewer preserves the parent draft and scroll
  position, without joining, watching or controlling the child runtime (PR #167).
- Receipt-ordered live text, exposed reasoning and consecutive tool groups
  across REST/SSE, Remote Gateway and app-owned stock turns. Late tool updates
  update their original group. Stable expansion identities retain the reader's
  choice as content arrives and previews become durable history (PR #168).
- App-owned stock Gateway sessions retain user-started turns across chat-route
  removal, reopening and concurrent chats. Network recovery and process-restart
  pending markers reconcile against persisted history without resubmitting an
  uncertain prompt. This path works without the experimental turn-recovery v2
  contract.
- Quiet ongoing status entries for individual active chats, backed by one
  Android foreground service and its required disclosure. Settings includes
  device-local background-work controls and a link to battery optimisation
  settings. Turning protection off does not stop server work (PR #169).
- Opt-in Google-free UnifiedPush through a native Android connector and the
  separate `server/mobile-push` companion. Registration requires dashboard
  authentication, operator authorisation, explicit consent, exact durable
  session scopes and an encrypted challenge/confirmation. Generic encrypted
  hints, persistent event deduplication, endpoint renewal and revocation keep
  delivery separate from chat content and runtime authority (PR #170).

### Fixed

- Delegated-task recovery distinguishes spawn results from steer/stop/list
  acknowledgements. A control acknowledgement cannot finish a running child or
  stop its history refresh. Unknown statuses remain unresolved; failed,
  interrupted and cancelled tasks keep distinct terminal presentation under
  late progress. Mixed terminal groups say finished rather than implying success.
- Task-history reads require the exact stored ID and selected profile, even
  when the Dashboard resolves ID prefixes. Compression references
  need bounded same-lineage proof; a late ancestor cannot replace a verified tip,
  and an unrelated session or fork cannot supply another task's transcript.
- Task transcripts request compacted rows and respect the Dashboard's public
  content, commentary and reasoning projections, including empty/null values.
  JSON-looking public prose stays prose; duplicate raw reasoning and encrypted
  sidecars do not leak into the display. Missing tool arguments show an explanation.
- Compression gaps now carry explicit **Partial history** warnings. A missing
  verifiable newer segment can hide the final reply; omitted tool-source
  ancestors can hide earlier work even when the final reply is present. Known
  rows remain available, Refresh can retry, and reopening no longer implies
  complete history. Old tasks without durable references show unavailable.
- Preview completion preserves each reasoning run's receipt position, contents
  and expansion identity, including reasoning on both sides of a tool group.
  Ownership changes do not merge separate runs or reorder later commentary.
- Notification authorisation reflects current Android permission grants and
  revocations after resume. Passive initialisation does not repeat a permission
  prompt or retain a stale denied/granted latch. Optional chat preferences do
  not suppress Android's required foreground-service disclosure.
- Later canonical history replaces retained wire presentation after delayed persistence, including on chat reopen.
- Initial or unavailable chat history no longer duplicates live and canonical turns, without delaying sends or discarding received replies.
- Stock-turn recovery distinguishes interrupted/failed outcomes from successful
  completion. A proven-idle turn without a recorded outcome becomes inactive
  with an outcome-unknown status; partial assistant prose does not trigger a
  success alert. Canonical session identity retains per-chat drafts across
  reattachment. Pre-wire setup failures release send/alert admission without
  inventing a submitted turn or erasing a newer composer draft.
- Mobile-push operations select the saved Hermes profile for capabilities,
  registration, confirmation, revocation and event reads. Exact registration
  and confirmation retries recover lost acknowledgements without granting
  authority to pending, expired, revoked or superseded registrations.
- App-root integration initialises push after credential hydration and the first
  frame, checks queued tap authority after asynchronous lookups and opens the
  session from that authenticated lookup. Background-policy changes reach the
  active owner; native battery settings remain an explicit user action.
- README setup now describes the dashboard's authenticated password/proxy flow,
  the stock recovery path and the separate experimental exactly-once contract.
  It no longer promises that returning to the app clears all notifications.

### Compatibility and limits

- The richer task transcript requires compatible authenticated Dashboard routes;
  the API-server Bearer key alone cannot supply it. Snapshot polling does not
  reconstruct missing child references or guarantee complete compression history.
- UnifiedPush is off by default. Install and enable the companion in the intended
  server profile, configure VAPID/operator policy and install a compatible Android
  distributor before opting in. The APK does not install or configure a live
  server. One installation binds one selected connection and an explicit session
  allowlist; a push tap cannot approve an action or resubmit a prompt.
- Android Force stop, OEM battery controls, Doze, offline devices, permissions
  and distributor availability can prevent or delay delivery. A foreground
  service does not guarantee uninterrupted networking. Reopen and reconcile
  uncertain work; push is a hint rather than proof of a turn's current outcome.
- Without a verified baseline, received replies and known older context take
  precedence over unverified saved rows. The app caches ambiguous rows outside
  the combined transcript; unresolved history can remain partial.
- Release identity is `2.1.31+2174`; split version codes are `21741`
  (armeabi-v7a), `21742` (arm64-v8a) and `21743` (x86_64). The accepted base
  upgrade floor remains `2127`. Store notes cover the base and all three splits.

### Thanks

- Hermes Agent assisted with implementation, review, documentation and regression
  tests. This release builds on the community Remote Gateway and background
  keep-alive contributions credited in earlier entries and the README.

## [2.1.30] - 2026-10-22

### Fixed

- The keyboard's Enter/Return key inserts a new line. Send remains available
  through the on-screen button rather than submitting when adding a paragraph.
- The message composer remains editable during setup, attachment uploads,
  replies and reconnect recovery. Only the submitted draft is cleared; later
  setup and reply callbacks cannot erase a follow-up being typed. Leaving
  during setup retains the unsent prompt unless you have edited the new draft.
- Failed submissions restore the original prompt only when the cleared draft
  has not been edited, including when newer typing was deliberately deleted.
  Send admission is reserved before asynchronous setup to prevent duplicate
  submissions from rapid taps. Existing send/recovery guards remain in place.

### Thanks

- Hermes Agent assisted with implementation, review and regression tests.

## [2.1.29] - 2026-10-22

### Added

- Move to project in the Chats row action menu, including chats that already
  belong to another Project. Choose an active destination with a server
  folder; Hermes updates the stored chat's working folder and placement.
- Quick Chats filed into a Project leave their device-local quick retention
  schedule after the move. Messages, titles and pins stay intact.

### Fixed

- Chat rows update their Project label after a move and leave Unassigned.
  A list read started before the move cannot restore old placement metadata.
  Cancelling or a failed move preserves the original placement.

### Thanks

- Hermes Agent assisted with implementation, review and regression tests.

## [2.1.28] - 2026-10-22

### Added

- Rename chats from the Chats list and the open-chat action menu. Remote
  Gateway and REST-only connections save the title on the Hermes server,
  using the chat's stored identity without creating a new session.
- The rename dialog supports keyboard submission, trims surrounding spaces
  and prevents blank names. Cancelling or keeping the same name makes no
  request; failed saves retain the previous title and show the server error.

### Fixed

- Returning from an open chat refreshes its title in Chats. Search, exports
  and notifications use the renamed title. A list refresh started before a
  successful rename cannot restore the old title or discard other row data.

### Thanks

- Hermes Agent assisted with implementation, review and regression tests.

## [2.1.27] - 2026-10-22

### Fixed

- Project cards now update their chat counts when you return from a Project,
  reselect the Projects tab, or resume the app. An older overlapping response
  cannot overwrite newer counts or the shared Project placement cache (PR #159).

### Thanks

- No external contributors in this patch. Implementation and regression tests
  were assisted by Hermes Agent.

## [2.1.26] - 2026-10-21

### Fixed

- A new chat started inside a Project now binds the Project folder before its
  first prompt or attachment, so stock Hermes files it in the Project rather
  than creating an unassigned chat. Project detail refreshes after returning
  from the chat. A folderless Project now asks for a folder instead of quietly
  opening an unassigned chat.

### Added

- Tool activity shows a timestamp for each call when expanded and the latest
  known activity time when collapsed. Live times are labelled as observed on
  the phone; stored result times come from the server. Unknown times are
  explicitly marked unavailable, and no unobserved start time is invented.

### Thanks

- No external contributors in this patch. Implementation and regressions were
  assisted by Hermes Agent.

## [2.1.25] - 2026-10-21

### Fixed

- Reopening a tool-heavy chat now loads enough earlier history to keep the
  latest conversation visible rather than showing only collapsible tool calls.
  Older messages can be loaded on demand, and a fresh history page no longer
  discards previously loaded dialogue during an active turn.
- Home no longer labels a recently active conversation from another device as
  definitively idle. It distinguishes recent server activity from a turn the
  Android app knows is running, and sorts unfinished conversations by their
  latest activity instead of their creation time.

### Thanks

- No external contributors in this patch. Implementation and regression tests
  were assisted by Hermes Agent.

## [2.1.24] - 2026-10-21

### Added

- Android keeps an in-flight Gateway chat turn connected while the app is in
  the background, with a temporary foreground-service notification. The
  service stops when the turn settles, its socket is lost, the app resumes,
  or the activity finishes. Disconnected uncertain turns are not resent
  automatically (PR #152).

### Fixed

- Concurrent Home refreshes share pending session-list requests instead of
  starting duplicate full scans. A newer first page remains visible on Home
  and Chats when an older shared scan completes (PR #156). Issue #149 remains
  open for transfer measurements and separate API transport work.

### Thanks

- [@Thaeland](https://github.com/Thaeland) for the Android background-turn
  keep-alive, stock-gateway and existing-chat coverage, lifecycle guards and
  regressions in PR #152. Maintainer follow-up commits closed the Activity
  finish and mixed-turn shutdown edges without changing their commits.

## [2.1.23] - 2026-10-20

### Fixed

- A final Gateway answer that was already previewed no longer appears as a
  duplicate assistant bubble. Completion reconciles against the matching
  interim in the current turn; distinct commentary and late reasoning remain
  visible (PR #153).

### Thanks

- [@krotname](https://github.com/krotname) (Andrei Ovcharenko) for the
  previewed-completion fix and widget regressions in PR #153. A maintainer
  follow-up added exact-match reconciliation and further edge-case tests while
  preserving the contributor's commits.

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
