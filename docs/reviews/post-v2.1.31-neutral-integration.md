# Neutral integration after Android v2.1.31

## Scope and intent

- Public parent: `785f5fea7a1164a15b4f1eca62deed5b86338194` (published v2.1.31, build 2174). Preserve released delegated-task inspection, independent child observation, unknown-outcome reconciliation, structural scaffold/canonical-history handoff, canonical draft rejection guards, passive permission and profile-bound push routing/recovery.
- Hardening parent: `f36a407353b36183c5909e6859c87d6af9be4619`. Preserve submission-observation epochs, stale terminal ownership, successful-only bounded admission reads, confirmed background policy, targeted notification cleanup, monotonic native/server push fencing, vetted per-request profile scope, and application-owned bounded presentation/draft leases.
- Only this isolated integration worktree was changed. No canonical/primary/peer worktree reset or writes, live service/device use, production signing, version bump, tag, push or release.
- `pubspec.yaml` remains `2.1.31+2174`; the released README/changelog/identity test remains the baseline. New documentation describes unreleased hardening, not a new release.

## Authority decisions and clean-merge hotspots

1. **One draft lease, not two owners.** The application registry writer uses the public `ComposerDraftHandle` as its actual token. The same token reaches detached pre-wire rejection restoration. Only mounting/explicit editing claims ownership; programmatic hydration/rejection restoration, checkpoint and disposal cannot reclaim a newer canonical route. One storage queue serializes normal saves, rollback, reads and checked alias migration. Public source-preserving migration/reload survives alongside hardening clear markers, `isCurrent` fences and registry rollback/close semantics. This intentionally changes the internal f36 writer token from an opaque Object to the storage handle; focused follow-up commits must account for that integration.
2. **Admission proof precedence.** Consume the exact newly-created-empty binding once, with no fallback HTTP wait. Otherwise preserve a successful latest history baseline, or attempt the hardening bounded pre-wire read when unknown. HTTP failure/404/timeout stays unknown. Older uncorrelated received presentation cannot acquire a later turn's numeric floor. Public structural handoff replaces the older prompt-text matching helper; no duplicate retirement reducer.
3. **Settlement and observation are separate.** Keep the public nullable outcome: idle without explicit terminal status is inactive/unknown, not success. Keep hardening prior-nonterminal lifecycle identity and immutable request-start submission epoch, including runtime binding rejection. An old terminal cannot admit itself as the current lifecycle, and a resume captured before the submit wait clears cannot become authority after ACK. Independent child/task observation remains outside parent-turn admission.
4. **One root dispatcher.** Remove cleanly merged legacy duplicate push fields/dispatch methods. The generation/account-fenced resumable canonical route owner also handles public push taps and its test lookup seam. Newer intent suppresses an obsolete held lookup; sequential cold/warm taps still retain the released exact-profile route behavior. Public root/read-only task bridge remains intact.
5. **Permission initialization is not an authority read.** Preserve public passive `ensureInitialized` behavior at its default API, but use `refreshPermission:false` for internal/headless initialization and explicit root/test refresh paths. All authority reads use hardening revision+demand/trailing-read ownership. Prompting can invalidate a held old passive read without waiting for it. Root foreground opt-in happens once; resumes/Settings refresh never re-prompt after that. Keep public iOS provisional authorization support. Remove duplicate clean-merge sink methods/fixture fields/accessor/imports.
6. **Push recovery protocol choice.** Same-nonce/idempotent PUT and consumed-confirmation replay are superseded by native write-ahead nonce/revision rotation and a fresh encrypted handshake for unchanged already-approved consent. Every PUT must exceed the durable high-water mark inside the SQLite mutation transaction; DELETE-before-first-PUT is a terminal tombstone. Keep the public consumed-nonce equality ledger too: it rejects a previously committed nonce even with a higher ordinal, while revision is the only ordering authority and fences never-committed old requests. No reset of native ordinal on recovery/legacy invalidation. Lost-ACK recovery, strict blank scope, endpoint/account/profile fences and explicit profile on every retry/read/revoke remain.
7. **Profile resolution.** Use an immutable per-request Profile from the real host-stamped secret-scope home after verified principal authentication. No raw query/env fallback or router-wide mutable store/current-profile cache. Lifecycle workers retain their own captured profile. An unvetted manual mount fails closed; real-host once-mounted concurrent two-profile tests preserve the released positive behavior.
8. **Timeline and task overlay coexist.** Keep public append/replacement reasoning identity handling and independent translated read-only task modal/history/ancestry/scroll fences. Keep f36 automatic 1,024-run/1-MiB text bounds, scope ownership, bounded tool tombstones and application-owned pins. Actual pin bound is 100 per kind (at most 512), not a newly implemented 512-entry policy. No synthetic canonical rows or protocol/parser changes.

## Every textual conflict hunk

The locations below are the **original halted-merge** file/line positions (before marker removal/formatting), with stable per-file hunk numbers. The full original blocks and both merge-base diffs are retained in scratch evidence. This table classifies all 62 hunks, including generated-equivalent/test/documentation decisions.

| Original file:line / hunk | Class | Resolution and rationale |
| --- | --- | --- |
| `docs/mobile-push-android.md:35` H1 | superseded | Document stricter monotonic paired protocol and host-stamped per-request scope; legacy same-nonce replay premise is superseded, not the lost-ACK recovery requirement. |
| `docs/mobile-push-android.md:203` H2 | superseded | Document stricter monotonic paired protocol and host-stamped per-request scope; legacy same-nonce replay premise is superseded, not the lost-ACK recovery requirement. |
| `docs/mobile-push-server.md:120` H1 | superseded | Document stricter monotonic paired protocol and host-stamped per-request scope; legacy same-nonce replay premise is superseded, not the lost-ACK recovery requirement. |
| `docs/mobile-push-server.md:263` H2 | superseded | Document stricter monotonic paired protocol and host-stamped per-request scope; legacy same-nonce replay premise is superseded, not the lost-ACK recovery requirement. |
| `docs/mobile-push-server.md:447` H3 | superseded | Document stricter monotonic paired protocol and host-stamped per-request scope; legacy same-nonce replay premise is superseded, not the lost-ACK recovery requirement. |
| `lib/core/models/chat_timeline.dart:305` H1 | disjoint-intent | Equivalent receipt identity contract; retain public wording. |
| `lib/core/models/chat_timeline.dart:329` H2 | same-question-different-answer | Keep public replacement/suffix reconciliation: explicit replace must not duplicate an already confirmed snapshot; append receipt runs remain untouched. |
| `lib/core/screens/chat_screen.dart:536` H1 | same-question-different-answer | Use application registry writer lease as single route draft authority; adapt public rejection restoration to it. |
| `lib/core/screens/chat_screen.dart:1189` H2 | same-question-different-answer | Close lease before local controller so detached checkpoint cannot erase replacement draft. |
| `lib/core/screens/chat_screen.dart:1235` H3 | same-question-different-answer | Flush only current lease on pause. |
| `lib/core/screens/chat_screen.dart:4595` H4 | same-question-different-answer | Checkpoint submitted prompt with existing lease, retain until wire acceptance. |
| `lib/core/screens/chat_screen.dart:4605` H5 | same-question-different-answer | Commit through current writer, no second prompt state owner. |
| `lib/core/screens/chat_screen.dart:4619` H6 | same-question-different-answer | Restoration setter suppresses explicit edit claim; writer.save rejects stale route. Preserve public rejection guard via unified lease. |
| `lib/core/services/composer_draft_store.dart:6` H1 | same-question-different-answer | One shared physical queue and ComposerDraftHandle token back application registry writers and detached rejection recovery. Keep public source-preserving checked alias migration; hardening remove/clear markers + rollback + isCurrent fences. No second route owner. |
| `lib/core/services/composer_draft_store.dart:199` H2 | same-question-different-answer | One shared physical queue and ComposerDraftHandle token back application registry writers and detached rejection recovery. Keep public source-preserving checked alias migration; hardening remove/clear markers + rollback + isCurrent fences. No second route owner. |
| `lib/core/services/composer_draft_store.dart:219` H3 | same-question-different-answer | One shared physical queue and ComposerDraftHandle token back application registry writers and detached rejection recovery. Keep public source-preserving checked alias migration; hardening remove/clear markers + rollback + isCurrent fences. No second route owner. |
| `lib/core/services/composer_draft_store.dart:287` H4 | same-question-different-answer | One shared physical queue and ComposerDraftHandle token back application registry writers and detached rejection recovery. Keep public source-preserving checked alias migration; hardening remove/clear markers + rollback + isCurrent fences. No second route owner. |
| `lib/core/services/composer_draft_store.dart:331` H5 | same-question-different-answer | One shared physical queue and ComposerDraftHandle token back application registry writers and detached rejection recovery. Keep public source-preserving checked alias migration; hardening remove/clear markers + rollback + isCurrent fences. No second route owner. |
| `lib/core/services/mobile_push_api.dart:12` H1 | disjoint-intent | Preserve explicit profile on every request plus strict full-token scope validation. |
| `lib/core/services/mobile_push_service.dart:388` H1 | superseded | Same-nonce replay cannot fence uncommitted old PUT. Native write-ahead recovery rotates nonce and monotonic revision, retaining consent. |
| `lib/core/services/mobile_push_service.dart:422` H2 | same-question-different-answer | Require pending response echoing exact native nonce AND revision. |
| `lib/core/services/mobile_push_service.dart:470` H3 | disjoint-intent | Require integer generation as well as exact generation equality. |
| `lib/core/services/normal_gateway_application_session.dart:470` H1 | disjoint-intent | Keep nullable public unknown outcome and immutable submission-pending epoch. |
| `lib/core/services/normal_gateway_application_session.dart:552` H2 | disjoint-intent | Public fresh-only observation includes hardening retirement intent. |
| `lib/core/services/normal_gateway_application_session.dart:565` H3 | superseded | Public identity-based retirement also safely handles empty scaffolds; no parallel retirement owner. |
| `lib/core/services/normal_gateway_application_session.dart:703` H4 | disjoint-intent | Consume exact newly-created-empty proof without HTTP; otherwise retain bounded successful prewire canonical GET only when history unknown. Unknown/404 never zero; protect older unknown received projection. |
| `lib/core/services/normal_gateway_application_session.dart:1266` H5 | disjoint-intent | Keep public idle-is-unknown settlement, reuse status/running variables already captured after immutable epoch check. |
| `lib/core/services/normal_gateway_application_session.dart:1354` H6 | same-question-different-answer | Use same lease for detached rejection restoration; no fallback unowned write when lease was supplied. |
| `lib/core/services/normal_gateway_application_session.dart:1534` H7 | superseded | Public scaffold handoff uses structural/durable proof, replacing old prompt-text matching. |
| `lib/core/services/normal_gateway_application_session.dart:1550` H8 | superseded | Public identity-based canonical/scaffold retirement subsumes hardening late hydration without text matching. |
| `lib/core/services/turn_notification_service.dart:493` H1 | same-question-different-answer | Trailing read demand plus prompt revision fences stale grants/revocations. |
| `lib/core/services/turn_notification_service.dart:566` H2 | same-question-different-answer | Invalidate older reads synchronously rather than blocking prompt behind held passive read. |
| `lib/core/services/turn_notification_service.dart:582` H3 | same-question-different-answer | Keep fresh trailing authorization algorithm; integrate public ensureInitialized passive-read entry without recursion. |
| `lib/main.dart:230` H1 | disjoint-intent | Retain root test lookup seam with owner/policy/client injection boundaries. |
| `lib/main.dart:249` H2 | disjoint-intent | Retain all matching constructor seams. |
| `lib/main.dart:378` H3 | same-question-different-answer | Use fail-closed confirmed policy root startup and single first-frame push initialization. |
| `lib/main.dart:880` H4 | superseded | Legacy one-shot navigation is subsumed by generation/account-fenced resumable canonical routing; retain public test lookup in guarded resolver. |
| `lib/main.dart:1165` H5 | same-question-different-answer | Invalidate pending navigation and clean owned subscriptions, keep shared push lifetime. |
| `server/mobile-push/dashboard/plugin_api.py:24` H1 | same-question-different-answer | Resolve verified host-stamped secret_scope_home only, after principal; no environment-derived profile. |
| `server/mobile-push/mobile_push/api.py:82` H1 | same-question-different-answer | Immutable authenticated per-request Profile; no mutable/router store cache. |
| `server/mobile-push/mobile_push/api.py:142` H2 | superseded | Profile dependency already captured after authenticated principal. |
| `server/mobile-push/mobile_push/api.py:163` H3 | same-question-different-answer | Short-lived per-operation Store for captured profile. |
| `server/mobile-push/mobile_push/api.py:179` H4 | same-question-different-answer | Confirm policy and Store use captured profile. |
| `server/mobile-push/mobile_push/api.py:200` H5 | disjoint-intent | Strict ID validation plus terminal DELETE-before-PUT tombstone in vetted profile. |
| `server/mobile-push/mobile_push/api.py:218` H6 | same-question-different-answer | Events use captured profile for policy, durable reads and Store. |
| `server/mobile-push/mobile_push/store.py:66` H1 | disjoint-intent | Keep transactional strict revision migration without generation reset PLUS public consumed-nonce equality ledger. Monotonic revision fences precommit handlers; consumed-nonce tombstones additionally reject previously committed nonce reuse. Supersede only idempotent same-operation replay, not either security fence. |
| `server/mobile-push/tests/test_host_lifecycle.py:115` H1 | superseded | Raw home override is no longer verified host scope; retain explicit fail-closed test and real-host profile tests. |
| `server/mobile-push/tests/test_host_lifecycle.py:136` H2 | superseded | Unvetted mount must fail 503; two-home behavior is proven through real host scope in dedicated tests. |
| `server/mobile-push/tests/test_transport.py:115` H1 | disjoint-intent | Keep Python 3.11 SSLContext compatibility explanation. |
| `test/chat_history_scroll_test.dart:1148` H1 | disjoint-intent | Equivalent fixture variable naming. |
| `test/chat_history_scroll_test.dart:1157` H2 | disjoint-intent | Equivalent append/replacement assertions; public concise fixture retains both and exact expansion expectations. |
| `test/chat_reattach_resync_test.dart:1122` H1 | disjoint-intent | Model explicit completed status for successful lag fixtures AND genuine failure inflight outcome; idle-only outcome separately unknown. |
| `test/chat_timeline_test.dart:354` H1 | disjoint-intent | Keep public receipt-ID/snapshot assertions; add complete hardening barrier variants separately with all assertions. |
| `test/chat_timeline_test.dart:399` H2 | disjoint-intent | Keep public receipt-ID/snapshot assertions; add complete hardening barrier variants separately with all assertions. |
| `test/large_session_restore_test.dart:213` H1 | disjoint-intent | Keep explicit HTTP fixture cleanup and app-owned controller. |
| `test/mobile_push_service_test.dart:44` H1 | disjoint-intent | Combine mutable authenticated clientFactory and failNativeOnce seam with strict revision/profile fixture + native restart helpers; keep both recovery regression sets and adapt superseded replay assumptions. |
| `test/mobile_push_service_test.dart:204` H2 | disjoint-intent | Combine mutable authenticated clientFactory and failNativeOnce seam with strict revision/profile fixture + native restart helpers; keep both recovery regression sets and adapt superseded replay assumptions. |
| `test/mobile_push_service_test.dart:286` H3 | disjoint-intent | Combine mutable authenticated clientFactory and failNativeOnce seam with strict revision/profile fixture + native restart helpers; keep both recovery regression sets and adapt superseded replay assumptions. |
| `test/normal_gateway_route_reattachment_test.dart:312` H1 | disjoint-intent | Preserve public canonical/older-page/task-observer regressions; add complete hardening reopen/tool-retirement scenario independently. |
| `test/normal_gateway_route_reattachment_test.dart:402` H2 | disjoint-intent | Preserve public canonical/older-page/task-observer regressions; add complete hardening reopen/tool-retirement scenario independently. |
| `test/normal_gateway_route_reattachment_test.dart:438` H3 | disjoint-intent | Preserve public canonical/older-page/task-observer regressions; add complete hardening reopen/tool-retirement scenario independently. |
| `test/normal_gateway_route_reattachment_test.dart:859` H4 | disjoint-intent | Retain public task source/custom history/paging fixture, hardening push-route reopen/history counters and explicit successful outcome (idle alone unknown). |

## Permanent test union and explicit premise adaptations

No original test file was deleted or skipped. Both independent append/barrier timeline loops and both canonical route-reopen regressions are retained. Source test declarations were enumerated programmatically from both parents before hand-back; renamed declarations are recorded in `android-2131-source-test-manifest.json`.

- Public completed-presentation/scaffold/unknown-floor tests now use explicit correlated lifecycle fixtures where they require a known successful terminal. Their transcript/identity/tool/child/paging assertions remain. Unknown-floor admission fixtures make the newly added admission GET genuinely unavailable instead of accidentally returning canonical data and proving a floor. Existing f36 admission-200/404/timeout and stale epoch/terminal tests remain.
- f36 epoch/fresh-chat/terminal-owner/wire fixtures that expect **known success** provide explicit completed resume status; retained old idle and retained stale failures remain old/unknown in their harmful schedules. The public stock idle/partial/no-alert tests remain unchanged.
- Released push recovery tests retain lost PUT ACK, lost confirm ACK, local generation/activation persistence gap, process restart, expiry, changed scope, current policy, revoked/superseded proof and real-cookie/TLS proof schedules. Exact replay is now asserted to reject read-only; successful recovery requires a newer revision, unused nonce, fresh encrypted proof and unchanged approved scope. Both security fences and old/new queued-delivery assertions remain. Seven server recovery tests remain seven tests, with three names updated to describe the new protocol.
- The public raw-home override test becomes fail-closed unvetted-scope coverage; actual once-mounted host tests cover positive two-profile behavior with the real trusted scope. No environment fallback was reintroduced to preserve a fake mount.
- The public held passive denial test now asserts immediate prompt invalidation plus a fresh trailing read, not the weaker requirement to block the prompt behind an old read. Public passive-default initialization tests and f36 no-headless-read tests both run against distinct explicit boundaries. Root permission regression establishes one initial foreground request and verifies the total never grows on resume/Settings.
- Root tap tests separately preserve the original sequential cold/warm exact-profile route stack and the harmful newer-tap-during-held-lookup order (only the newer route may mount).
- The f36 replacement-reassignment test has an identical assertion body under the public clearer title. Its old 2.1.30 identity test premise is superseded by the unchanged public 2.1.31+2174 identity assertion, not deleted acceptance.

## Executed verification and evidence

- Flutter 3.44.0 / Dart 3.12.0; `flutter pub get`, fatal-info analysis, the full Flutter suite, main debug APK build and targeted native MobilePush unit tests were actually executed in this worktree. The pre-freeze full suite completed 1,991 non-hidden tests, zero failures/skips; a sequential route control was subsequently added. Frozen-merge rerun totals are recorded in the final evidence JSON, not inferred from declarations.
- Python 3.11 parent test environment, `HERMES_AGENT_SOURCE=/Users/sam.russell/.hermes/hermes-agent` at the supplied source, full mobile-push suite: **126 passed, zero skipped**; Ruff check passed. This includes the real once-mounted host, password-cookie, SQLite and TLS encrypted-proof tests. One upstream Starlette/httpx deprecation warning remains.
- Native MobilePush policy/receiver XML: **28 tests, zero failures/errors/skips**. Debug APK built without copying any production key.properties or release signing material. Existing Flutter KGP migration and missing translation warnings are not concealed or treated as failures.
- `TMPDIR=/Users/sam.russell/.hermes/cache/scratch`, Java 17 and the public SDK configuration were used. No package installation into the shared environment, live configuration, emulator/device, Vault or release action.
- Scratch authority evidence: `android-2131-merge-public-conflict-diffs.txt`, `android-2131-merge-hardening-conflict-diffs.txt`, `android-2131-original-hunks.json`, `android-2131-hunk-decisions.json`, `android-2131-source-test-manifest.json`.
- Frozen integration gate script/result: `verify_android_2131_neutral.py` and `android-2131-neutral-final-<merge-sha>.json` in the same scratch directory. It records exact commands, exit codes, test counts, commit/tree/parents, artifact hash and final status.

## Focused late-identity follow-up integrated

After the base neutral merge, the parent supplied `e41b405f97c9129fe568a11372380a34754552df`
(parent f36). Its six production files and five permanent regression files were
cherry-picked onto the public+f36 combination. No new push/root/native changes were
included. All 53 focused-worker cases remain unchanged; combined verification also
includes the released composer-alias/rejection, unknown-floor/create proof, owner,
stale-terminal and observation-epoch regressions.

### Additional textual conflicts

The positions below refer to the halted focused cherry-pick. Both original blocks
and the focused diff are retained as `android-2131-e41-original-hunks.json`,
`android-2131-e41-hunk-decisions.json` and `android-2131-e41-focused-diff.txt`.

| Original file:line / hunk | Class | Decision |
| --- | --- | --- |
| `lib/core/services/chat_presentation_state.dart:155` H1 | disjoint-intent | Retain the shared public storage lease token/getter used by rejection recovery, and add focused binding callback ownership/cleanup. Callback follows the same writer token; do not restore an independent Object owner. |
| `lib/core/services/composer_draft_store.dart:235` H1 | same-question-different-answer | Use focused checked alias/target/marker rollback and physical ACK-loss handling within the existing shared _serialized queue. Keep public source retention and canonical ownership handoff (including a physically committed alias after ACK loss). Adapt resolved key helpers, not a second bind or queue. |

### Clean-merge semantic integration

- Preserve the focused actual incoming receipt alias for presentation binding
  **and** the released public local-alias durable draft binding. A reused canonical
  owner's immutable ID is not substituted for the receipt's local alias.
- Binding repair callbacks follow the application root's current writer and are
  cleared on close. Keep the shared `ComposerDraftHandle` token, public no-reclaim
  rejection restoration, untouched-composer revision check and normal-owner-ready
  hydration fence; do not restore the focused branch's independent Object token.
- Transactional bind runs inside the existing shared physical queue. Keep the
  public source copy after successful alias publication and canonical writer
  ownership. Add focused target/clear-marker/alias rollback, physical reload and
  ACK-loss handling. A physically committed alias after rejected rollback keeps
  its target **and** reaches the same ownership handoff; it is not treated as a
  phantom or allowed to erase a newer canonical draft. Source clear markers migrate.
- Keep focused learned-tool-ID aliases in the same bounded eviction ledger and
  shared unambiguous non-start correlation across stock/SSE. Bridge expansion pins
  at ingress even with the route absent. Public delegated-task observation and
  append/replacement reasoning, plus immutable admission/epoch/terminal fencing,
  are unchanged.
- Bounds remain 100 pins/aliases per pin kind, 1,024 tombstone **identity keys**
  (a learned local/durable pair consumes two), 1,024 runs and 1 MiB retained text.

The first combined focused run completed **138 tests, zero failures/skips,
with terminal success; fatal-info analysis passed. The final frozen-head gate
reruns the entire Flutter suite, APK build, native and server tests. Worker-only
approval is not reused as approval of this combined source.

## Remaining review/release status

1. **P1 push account mutation remains pending:** initially disabled, enable(A)
   held while editing the saved connection to B can activate obsolete A. Separate
   focused account-mutation worker owns the fix. No duplicate implementation here.
2. The four reported UI findings (canonical-first local receipt/draft alias,
   failed alias publication/cache poison, learned-tool-ID resurrection, and pre-ID
   expansion pin handoff) now have the supplied focused implementation and all
   permanent regressions integrated. Their combined focused tests pass; fresh
   independent SPEC/QUALITY approval of this exact combined source is still needed.
3. Parent must reconcile the pending push fix, obtain independent combined-source
   approval and run signing/manual acceptance gates before release. No release,
   version bump, push, device or live-service action was performed here.
