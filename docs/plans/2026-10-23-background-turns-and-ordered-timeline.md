# Background Turns, Push and Ordered Chat Timeline Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement and review this plan task-by-task.

**Goal:** Keep user-started Hermes turns observable across Android route/background transitions, recover safely after network/process loss, deliver opt-in server push, and render assistant/reasoning/tool events in receipt order.

**Architecture:** Keep stock Gateway ownership alongside, not inside, the experimental recovery-v2 registry. A connection-scoped application session owns stock transports and per-chat immutable snapshots. The application controller also owns shared chat presentation identity, composer writer admission and bounded reasoning expansion choices. Following published v2.1.32, tool choices instead belong to each actual mounted chat visit, with identity aliases shared by the registry; covering a route preserves the visit, disposal ends it. A pure timeline reducer holds presentation boundaries without introducing synthetic wire-history messages. One native foreground service protects unresolved work, with quiet per-chat notifications. A separately installed, authenticated mobile-push plugin sends encrypted UnifiedPush hints; hints never authorise approval or resubmission.

**Tech stack:** Flutter 3.44.0 / Dart 3.12, existing JSON-RPC + REST/SSE, Kotlin foreground service and UnifiedPush connector, Python/FastAPI companion plugin with SQLite outbox and RFC8291 Web Push.

## Baseline and scope

- Android base: fetched origin/main `63670ab3bb0fa76c9aa43b86ea8591bcb8d234b2`; latest stable v2.1.30.
- Main implementation worktree: `/Volumes/Storage/Hermes/workspace/hermes-android-background-turns`.
- Independent timeline worktree: `/Volumes/Storage/Hermes/workspace/hermes-android-ordered-timeline`.
- Existing unrelated dirty checkouts remain untouched. No stable merge/release, F-Droid change, live gateway restart, default model change or external registration without the appropriate handoff/approval.
- Baseline dependency resolution and keepalive/release-identity tests pass. Java17 exists at `/opt/homebrew/opt/openjdk@17`. No attached Android device; device evidence must remain explicitly unverified.

## Task 1: Ordered presentation reducer and stream integration

**Files:** add `lib/core/models/chat_timeline.dart`; update `lib/core/utils/chat_display_items.dart`, stream paths in `lib/core/screens/chat_screen.dart`, `lib/core/widgets/gateway_insight_card.dart`; tests in `test/chat_timeline_test.dart`, projection/stream/scroll suites.

1. Write failing reducer tests for text A -> exposed reasoning -> tools 1/2 -> text B -> tool 3 -> text C, then late completion of tool 1.
2. Implement stable-ID receipt-ordered text/reasoning/tool runs. Only adjacent tool runs group; late tool updates never move a run. Reasoning snapshots replace their scoped run. Never infer thinking content from pauses/status.
3. Integrate both SSE and normal WS without changing canonical request history or concatenating split text into duplicate bubbles. Preserve message/interim/completion snapshot semantics and durable-row history order.
4. Retain tool timestamps/pins, markdown, media, voice, follow-scroll and stable reasoning-collapse keys. Hydration reconciles optimistic presentation rather than duplicating it.
5. Run focused tests and analysis serially in the timeline worktree; commit only this feature.

## Task 2: Application-owned stock Gateway controller

**Files:** new `lib/core/services/normal_gateway_application_session.dart` and bounded pending-turn store; update `gateway_turn_application_controller.dart`, `desktop_gateway_client.dart`, `chat_screen.dart`, `main.dart`; focused owner/recovery/widget tests.

1. Add deterministic failing tests for pop/reopen streaming, duplicate routes, two active chats and local/stored alias ownership.
2. Add `normalSessionFor(connection)` -> per-chat app owner alongside v2, preserving existing v2 test interfaces. Scope by saved ID + normalised API/Gateway origins/prefixes/profile + credential digest.
3. Reserve admission synchronously before awaits. Keep screen-owned cancellable preparation/draft revision semantics; transfer prepared execution to owner. Live callbacks must not capture disposed widgets. Detach only the UI.
4. Preserve event/request ownership and stream snapshots across route changes; retain requests without route-based rejection. Use one event ingress to prevent doubled tokens. Rebind known sessions by resume-only after loss; do not create replacements for submitted work.
5. Persist a write-ahead uncertainty marker before invocation. Track actual wire emission with existing onSent boundary. Never retry prompt.submit after emission; RPC acknowledgement is not completion.
6. Recover via fresh durable message identities and resume running/status metadata, not transcript count or old retained assistant rows. Unknown baseline/status stays honestly unresolved. Background active recovery remains single-flight with capped delays, no attempt exhaustion and generation checks after awaits.
7. Restore pending markers after process restart as reconciling; no credentials, prompt, reasoning, secret answers or runtime socket IDs in markers. Persist settlement before clearing state.
8. Forward root lifecycle to normal owners and expose app-wide plain-data active-chat metadata for notifications. Maintain explicit disposal/config revocation behaviour.
9. Test controlled prepare/dispose, socket/history generation races, failure before/after emission, approval replay and restart boundaries. Commit only owner implementation files.

## Task 3: Foreground protection, per-chat notifications and background controls

**Files:** `connection_keepalive_service.dart`, `turn_notification_service.dart`, `ConnectionKeepAliveService.kt`, new background preference/settings widget and platform helper; app-root integration in Task 2.

1. Extend plain notification data with `ongoing`, `silent`, `onlyAlertOnce` and deterministic cross-process IDs in a separate namespace from native 4705.
2. Publish one quiet ongoing entry per unresolved chat with title/status and local+stored+connection identity; target cancellation instead of cancelAll on route resume. Completion/failure/attention dispatch belongs to application owner, respects kind preferences and does not duplicate screen dispatch.
3. Keep exactly one native FGS bounded to active work; start on the permitted leave-foreground transition and handle refusal without wedging UI. Reconnecting work is unresolved, idle sockets are not work. App/task shutdown respects Android/user intent.
4. Add background-work preference and battery-settings affordance with honest Doze/process-death limitations; never auto-exempt or acquire an unbounded wake lock.
5. Test per-chat settle while sibling remains active, stale async starts, deep links with bound draft IDs, preferences, title updates and notification cleanup.

## Task 4: Opt-in encrypted UnifiedPush contract and server plugin

**Server files:** self-contained `server/mobile-push/` plugin (manifest, hooks, SQLite store/outbox, sender, dashboard API, tests and installation docs). Do not modify or deploy live Hermes core.

Implement actual endpoints under `/api/plugins/mobile-push`:
- `GET /capabilities`: schema `1`, transport `webpush`, VAPID public key, activation support.
- `PUT /registrations/{installation_id}`: endpoint, Web Push keys `p256dh`/`auth`, fresh client `registration_nonce`, explicit `event_kinds`, explicit `session_ids`; returns server `generation` and pending challenge status.
- `POST /registrations/{installation_id}/confirm`: supplied challenge and generation activate only that current registration.
- `DELETE /registrations/{installation_id}`: revoke and invalidate queued deliveries.
- `GET /events?after=...`: principal-scoped bounded cursor reconciliation, with no cross-principal/session leaks.

Security contract: verified `request.state.session` principal only; no auth identity headers/client fields. Enforce operator-managed principal->durable-session authorisation (deny by default; any owner-wide wildcard must be an explicit operator grant). Endpoint is not authority: require proof-of-delivery challenge. Validate URL/DNS at delivery, reject credentials/redirects/non-global addresses except explicit operator-managed exact endpoint hosts. Only send encrypted bounded hints with schema/event ID/event kind/generation/registration_nonce/expiry and optional challenge. No chat contents, titles, approval tokens, commands, arbitrary navigation URLs or Hermes credentials in push. Recheck consent/generation/authz at send time. Persist bounded outbox with leases/retries/expiry/dedup; 404/410 revoke endpoints. Hook `on_session_end` outcome flags and human-input requested/resolved; bind durable IDs/lineage safely and avoid legacy incomplete payloads.

Test auth, foreign principal, explicit session denial, registration rotation/revocation, challenge, duplicate/out-of-order events, restarts/outbox leases and real Web Push encryption against a local explicitly allowed receiver. Run Python tests with TMPDIR under Hermes scratch. Document plugin-isolation compatibility rather than weakening auth.

## Task 5: Android UnifiedPush integration and startup recovery

**Files:** new push preferences/registration controller/settings/receiver; native connector + manifest/build config; minimal root hooks, existing DashboardClient API reuse and tests. Integration must be optional and non-disruptive without a distributor/plugin.

1. Prefer native `org.unifiedpush.android:connector:3.3.5` after verifying its source API/build compatibility, to avoid transitive Flutter AGP drift. Use actual encrypted subscription keys from connector, never invented values.
2. Add opt-in settings with distributor selection, registration status, explicit connection/session scope and revoke. Store credentials using existing secure abstraction, no secrets in SharedPreferences/logs.
3. Background/native receiver must work without Activity/UI, require decrypted payload, validate durable consent/nonce/generation/expiry and persist event dedup. Show generic notifications only; no approval authority in push.
4. Register/confirm with real authenticated plugin endpoints. Endpoint rotations invalidate old local generation; disable revokes local authority immediately then attempts server revoke. Preserve retry/recovery state rather than reporting false success.
5. Feed current approved hints/taps to authenticated reconciliation; resolve stored/local identity via app owner, reject removed/changed connection scopes after awaits. Never resubmit/approve from push.
6. Exercise protocol/state with fixture API and receiver tests, then actual release Gradle build. Physical killed-process delivery needs user device + installed distributor and configured server; report that prerequisite honestly.

## Task 6: Integration and reviews

1. Integrate timeline and push commits into the background branch, preserving each feature commit and resolving overlapping chat/root edits deliberately.
2. Specification reviewer checks every goal and test seam first. Fix important gaps, then independent quality/security reviewer reproduces race/security cases. No self-review substitutes.
3. Update README/CHANGELOG and feature/setup docs in Australian English without claiming an unapproved stable release. Keep AI disclosure and latest-three stable release summary intact.

## Task 7: Validation and handoff

Run serially against fixed source in the integrated worktree:

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
flutter pub get
# Format every changed Dart file from the recorded base.
git diff --check
flutter analyze --no-pub --fatal-infos
flutter test --no-pub --reporter json > <fresh-scratch-results.jsonl>
# Require a successful terminal done event; count non-hidden testDone records.
python3 -m pytest server/mobile-push/tests -q
flutter build apk --release --split-per-abi --split-debug-info=symbols
```

Copy ignored production signing configuration from the established signing directory without printing it. Verify all three APK package/version/code/ABI/signatures/hashes with the skill verifier and established production signer. Keep test identity upgrade-safe and separate from stable main if publishing a prerelease. Do not publish/merge/F-Droid-update while blockers, review edits or builds remain active.

Device acceptance: start two chats; interleaved text/thinking/tools; Home/lock; navigate away/reopen; Wi-Fi loss/reconnect; approval without chat route; process kill (not Force stop) and encrypted push; revoke/rotate; disable notifications/background; no duplicate prompt submissions and no orphaned ongoing entries. Without device evidence, report these as pending, not passed.

## UI lifecycle quality follow-up

- `ChatPresentationRegistry` lives under the application controller's existing configuration/credential digest scope, without opening a transport for REST-only chats. Local/stored bindings join presentation identity as well as transport identity. Scope replacement, connection revocation and application closure invalidate old writers and held reads; pin state is not persisted or shared across accounts.
- A route obtains a composer writer lease on mount. Explicit text editing can reclaim authority when an older covered route becomes current again. Hydration, selection-only changes, send rejection, lifecycle checkpoints and disposal cannot reclaim it. The shared intent generation fences queued durable writes, including explicit empty clears. The authoritative unsent value also survives cancellable preparation without placing prompt text in a pending-turn receipt.
- Draft strings keep their existing connection/session preference namespace and empty-delete behaviour. Serialised identity-only alias/clear records permit canonical reopening and preference-cache restart. Migration prefers an existing canonical value or clear, writes the target before its redirect, and leaves the source usable on a rejected target write. Preference I/O remains best-effort, not a transactional database or an on-device durability claim.
- Explicit reasoning expansion pins retain their 100-entry bound per retained chat. Published v2.1.32 supersedes cross-visit tool choices: tool pins have the same 100-entry bound per mounted visit, survive lazy remounts and learned identity within that visit, and reset on real close/reopen. Alias joining shares tool identities, never another visit's choices. Canonical hydration/paging continue to use stable run/tool/row keys. Historical verification below predates that policy change; see [the v2.1.32 neutral integration](../reviews/post-v2.1.32-neutral-integration.md) for current evidence and remaining review blockers.
- Every receipt reducer mutation enforces 1,024 runs and 1,048,576 text code units, including REST/SSE ingestion before ListView projection. Receipt ownership survives full run eviction so canonical assistant accumulators and unmatched tool queues cannot resurrect evicted presentation. Latest durable hydration clears that ownership atomically; older paging does not.
- Identity-only evicted-tool tombstones are capped at 1,024 and survive scope-anchor pruning until durable hydration. If that ledger saturates, an unmatched terminal-only tool receipt is ambiguous and is conservatively omitted; retained tool updates and new tool starts still work. Durable history remains authoritative. These are live presentation bounds, not bounds on canonical request history or the HTTP client's completed response accumulator.
- Permanent regressions: `chat_draft_lifecycle_test.dart`, `chat_expansion_lifecycle_test.dart`, `chat_sse_retention_test.dart`, `chat_presentation_state_test.dart`, and the additional multi-scope/evicted-tool cases in `chat_timeline_test.dart`. The independent reviewers' original five failing widget cases were run against the unchanged base and again after the production fix; the SSE case inspects the actual ListView delegate, not merely reducer state.

No device/emulator, live gateway, credential, signing or release actions belong to this follow-up. Native compilation, physical lifecycle behaviour and independent SPEC/QUALITY acceptance remain separate gates.

### Recorded local verification

Exclusive branch `fix/android-chat-view-lifecycle`, based on `c5be62bf0f06c730ed76aa722c2b06cd03413fb7`. All Flutter commands ran serially in that branch's worktree with `TMPDIR=/Users/sam.russell/.hermes/cache/scratch`; no primary-checkout Flutter execution.

| Gate | Actual result | Scratch evidence |
| --- | --- | --- |
| Original reviewer probes before production edits | 37 completed: 32 passing existing cases, all five reported widget assertions failing | `chat-view-red.jsonl` |
| Same unmodified reviewer probes after the initial production fix | 37/37 passed, terminal `done.success=true` | `chat-view-green2.jsonl` |
| Permanent lifecycle/retention/store/composer focused cases | 58/58 passed, zero error events, terminal `done.success=true` | `chat-view-focused-final.jsonl` |
| Final full Flutter suite after all production edits | **1,790/1,790 passed**, zero skipped/error events, terminal `done.success=true`, Flutter exit 0 | `chat-view-full-verified.jsonl` |
| Final `flutter analyze --no-pub --fatal-infos` | No issues, exit 0 | `chat-view-analysis-final.log` |
| Formatting and staged/unstaged `git diff --check` | 14 changed Dart files formatted, both diff checks clean | Local command output |

The active SSE regression now has exactly 1,025 display rows (one user plus 1,024 receipt runs), checks the retained first/last tools, and rejects a late evicted completion without adding a fallback card. The text-budget widget assertion counts the actual production delegate's assistant content, with a second token verifying the limit is reapplied. Full-suite checks retain the existing real-wire terminal/submission-epoch, LF/CRLF UTF-8, preview-reasoning, latest hydration and older-paging guards. Independent reviewers must still run their own acceptance passes; these local results do not close the parent task.
