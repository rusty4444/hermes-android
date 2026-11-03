# ROOT-ED8-1 bounded recovery-owner detach repair

## Scope and candidate

- Base/direct parent: `ed8db9f12b07e2392edfc7dab41b586b22167f23` (parent `37f52c1b84a1e7a1ca93c8e573e8e79badd030fc`). Branch: `fix/android-recovery-owner-detach`.
- Exclusive source: `/Volumes/Storage/Hermes/workspace/hermes-android-recovery-owner-detach`. Owned execution/evidence root: `/Volumes/Storage/Hermes/scratch/recovery-owner-detach-c0ug9b4a` (**R/** below). Tests executed in **R/app**, a private exact-ed8 Git archive with the four candidate Dart files overlaid and byte-verified against this worktree.
- This is the user's **one bounded recovery-owner lifecycle repair**. Execution evidence only: **no self-SPEC or QUALITY approval**. Parent structural/behavioural preflight, fresh affected combined Root + CORE SPEC, then independent QUALITY remain required. No further producer cycle is authorised by this handoff.

## Minimal policy change

Only `lib/core/services/gateway_turn_application_controller.dart` changes in production. `removeAsyncEventListener` now returns when its **captured session is already closed**, instead of applying the new-admission `_requireOpen` guard. Its interface documents that exact-owner cleanup is valid during/after close. No new owner, facade, DTO, transport, persistence, catch, or callback lookup was added.

This is safe because the existing `close()` synchronously sets `_closed = true`, clears **that owner's** async registrations and removes **that client's** dispatcher before awaiting registry shutdown; closing the client remains in `finally`. Late removal has nothing left to detach. It never looks up a current owner and cannot reject a replacement's request. Still-open removal is unchanged: exact local SID + identical registration token, then reject that session's orphaned requests and synchronise its dispatcher. Every setter, submit/recover/interrupt/stage operation, ownership query and sensitive answer retains its existing closed-owner admission guard. `detachAttachments` also retains its existing closed-owner rejection; this repair is listener cleanup, not broad permission to call a closed transport.

Actual consumer audit: ChatScreen retains its recovery owner and separately removes async, settled and bound registrations in `dispose`. Settled/bound removals already return when closed; activity removal directly deletes from the registry token map. Registry close synchronously clears all three registry callback maps. Making async removal consistent lets the existing remaining visit/draft/composer/scroll/`super.dispose` and root-owned unregistration run. **Neither ChatScreen nor main.dart changed.** Root's existing identical-handler ownership check is unchanged and exercised with a real newer HermesApp replacing the old tree.

Synchronous close, full configuration/account/mutation/ABA/manager fences, ed8 observer isolation, approval-origin capture, exact queue acknowledgement and request-owner qualification are unchanged. All other production lib blobs, prior C/R/B/WAL/draft/alias/outcome/public173174 policy and provenance bytes are unchanged. Version stays `2.1.32+2175`; the inherited main81d ancestry was checked locally, with no fetch or new public-head claim.

## Unchanged real-root red → green

Before editing production or adapting a permanent fixture, archived all four raw source files / five identities, hashes, reviewer full receipts, comparator logs/stacks/facts and reports under **R/raw-before**, alongside an exact-ed8 source archive and source/cache snapshots. Primary no-observer-fault SHA256 remains `b03d7e5e0e02cf919208e46215b0e66811fdcecf949bc099709db13dd48722eb`; diagnostic SHA256 remains `a63d9563a084d49fe7b38cae596b148f7c7880b72ccdb2d2811b46dca24838fb`. All replay source hashes, including original Root37 seven, CORE37 six, minimal valid-origin Root8 and recent CORE3, are in `verification.json` and **R/REPLAY-SOURCES.json**.

- `raw-five-red`: exact ed8, **5 unique; 1 success / 4 same-order cleanup errors**, exit1, terminal false, no skips/loaders. Primary and diagnostic use real HermesApp/default controller and session factories/ConnectionManager/HTTP+WS, memory secrets and mock native channels, with no throwing observer. Original `_requireOpen → removeAsyncEventListener → ChatScreen.dispose → finalizeTree` stack is preserved.
- Two default-owner held-close regressions were written before the repair. After correcting only their initial loopback/auth fixture setup, `permanent-unit-red-loopback` reproduces **2 errors**, both the exact closed-session exception from listener removal; no loader/skips.
- The same raw five sources are byte-unchanged in focused and full final execution, now **5/5 successful**, including the passing no-mutation control. No observer catch, exception suppression, teardown assertion deletion, queue clear before the primary, or timeout change was used to make them green.
- Diagnostic facts differ **only** in the two repaired fields:

| Fact | Exact-ed8 red | Fixed final |
|---|---|---|
| rootMountedAfterUnmount | true | **false** |
| handlerStillRegistered | true | **false** |
| queueEmptyAfterUnmount | true | true |
| freshChoiceBeforeUnmount | deny | deny |
| freshExactObjectDifferent | true | true |
| oldEpochRevoked | true | true |
| mutationPending | false | false |

Full original healthy-observer observations are also unchanged. Facts are in **R/{raw-five-red,full-exact-final}-widget-evidence/independent-ed8-teardown-diagnostic.json**. Original Root37-1's seven-case source remains SHA256 `c288e37bbff0d28d370a10c101d8e64d1610e6defd6953d31dc36d5f5e4061cb` and all seven pass; the prior observer-lease defect remains repaired.

## Five permanent regressions

1. `test/gateway_turn_recovery_owner_detach_test.dart`: two controlled held-journal-read cases, with and without same-ID owner replacement. Assert close remains in flight, all captured listener removals/repeated/wrong-ID/wrong-token removals are safe, then close completes. Fourteen closed-owner new-admission surfaces still throw, both while close is held and after it completes. The stock loopback fixture lacks v2: this pins close/cleanup flight and admission, not successful recovery or a particular operation error classification.
2. `test/ws_server_requests_test.dart`: one actual v2 HTTP/WS/default-owner case. Reuses connection/local/runtime/stored/approval/raw-request IDs across replacement; owner-qualified opaque request handles remain distinct. Closed old answering throws; current answering with the old handle returns false. Late old cleanup and still-open foreign/superseded/wrong-SID/arbitrary tokens neither reject the current request nor detach its listener. A fresh `deny` succeeds on the replacement socket, and the **same registration receives and answers a later request** after old cleanup. Exact current-token detach retains the existing orphan-request error (`-32601`) and is repeat-safe. Fixture additions are opt-in reused session IDs and an observable response callback; **all existing WS test bodies/assertions are literally unchanged**.
3. `test/recovery_owner_root_teardown_test.dart`: two rehosted no-observer-fault real-root schedules, not new independent SPEC coverage. Real same-value mutation revokes old origin/queue and releases its lease; stale replay fails closed and a fresh distinct same-ID `deny` remains current. After actual unmount, retained ChatScreen **and root are unmounted**, composer and scroll controllers are disposed, durable draft survives, application controller rejects new lookup, and no framework exception remains. In the second case a **new actual HermesApp** installs its handler before old-tree finalisation: old root cleanup leaves the new mounted root/handler intact; final newer-root removal unregisters it.

Permanent cases require no externally created evidence directory or file output. `RAW-TO-PERMANENT-ROOT.diff` and `PERMANENT-FIXTURE.diff` in the evidence archive explicitly label rehosting and test-only helper changes; they do not replace the byte-unchanged raw proof.

## Exact final execution and inventory

All totals are parsed unique `(suite path, test name)` identities, not mental sums. Final full raw start/done IDs, loader completion, terminal success and every case result were independently checked by **R/audit.py**.

| Gate | Actual final result |
|---|---|
| Full suite | **2553/2553 success**, exit0, done.success=true, 0 errors/skips/loader failures |
| Affected owner/root/reused CORE+Root focus | **45/45 success**, exit0, done.success=true, 0 errors/skips/loader failures |
| Whole lib and test fatal analysis | exit0, `No issues found!` |
| Four changed/new Dart files, no-write format | 4 checked, 0 changes, exit0 |
| Git whitespace check | exit0 |

All **2540 frozen ed8 identities**, **2511 accepted identities** (2404 old tracked + 107 accepted independent), and **2443 prior identities** are present and successful. The set difference from frozen2540 is exactly **13**: five newly added permanent cases, five reused latest Root identities, and three reused latest CORE identities. Reused tests, including tests historically named `Quality`, are regression evidence—not this candidate's independent approval. The overlapping425/B38/C-R26/Root59/compact11/reasoning16/cleanup13/original CORE20 cohorts all retain their exact counts and pass; do not sum these. Root59 remains46 literal +13 explicit main81d policy-copy schedules; cleanup13 is not26. Raw removed-API loaders, raw13 historical timer qualification, and superseded old unscoped Root8 inputs remain historical qualifications, not newly green or newly rerun claims.

Reproduction uses the owned `R/env.json`, not default HOME/cache:

```sh
python3 /Volumes/Storage/Hermes/scratch/recovery-owner-detach-c0ug9b4a/final_runs.py
python3 /Volumes/Storage/Hermes/scratch/recovery-owner-detach-c0ug9b4a/audit.py
```

`final_runs.py` retains exact serial `flutter analyze --no-pub --fatal-infos lib test`, focused/full `flutter test --no-pub --concurrency=2 --reporter=json`, and Dart formatter commands. `run.py` records real child exits, case identities, errors, skips/loaders and final done. `verification.json`, `case-ids.json.gz` and `evidence.tar.gz` retain those sources, receipts and outputs.

## Integrity and boundaries

- Verified Storage UUID `F7E08904-541C-463A-8BD5-284D3C146333` before writes and final audit. TMPDIR resolves to `/Volumes/Storage/Hermes/scratch`. Compatible supplied Python used filtered extraction. Toolchain output is archived.
- All **615 base Git blobs /139 lib blobs** checked against Git and before/after SHA256 in both worktree and tested archive: only the allowlisted controller and WS test differ; **613 unchanged base blobs**, with **138 unchanged lib blobs**. Two new test files and this appended evidence directory are the only additions. All old provenance directories, native/server/connection manager/policy/dependency/version files remain byte-exact. Candidate source hashes are in the receipt/archive; Parent can compare the committed blobs to them.
- **7416 borrowed third-party Dart hash/nanosecond-mtime entries and the full9554 dependency/SDK Dart superset are unchanged.** Both package config and graph plus plugin metadata were present; main rootUri=`../`, other dependency roots resolved against the original read-only repair78 config. Writable HOME/PUB_CACHE/cache facades belong to R, outside app. No pub get/install/update or borrowed Dart writes. Commands serial per app, max2 workers. Integration and observer producer worktrees remain clean at exact ed8.
- Own harness history is retained, not concealed: initial unit auth setup failed with `Session token not found` before its intended assertion-red and was replaced by the existing loopback BindingServer; one initial new wire loader used `dashboardPort` instead of the real `dashboardPortOverride`; one new wire expectation incorrectly assumed opaque owner-qualified IDs repeat, whereas real output correctly showed distinct UUID prefixes, so the new expectation now asserts common raw IDs plus separate handles. Raw primary bytes never changed. First analysis found one unused import and two new-test brace infos; fixed without suppressions. An initial formatter in the unconfigured source tree warned about lint resolution; final configured-archive format has no warning/change. All exact final focused/full/analysis/format gates were rerun after final source text.
- Existing21-second **fake-clock fixture cleanup drain** is unchanged, not a new timing proof or product timeout. Real loopback and mock native/credential channels do not establish Android provider, Keystore, physical device, process-death, live voice, or native/server acceptance. Historical native36/server126 remain historical. No build/sign/install/deploy/publication/push/tag/PR/fetch/Vault/real credentials/live server/config/model/default/fallback/other-profile/TUI work. TUI remains separately paused.

The clean directed commit is handed to Parent for its own preflight and independent review. This report is not a substitute for either review gate.
