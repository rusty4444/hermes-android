# Combined approval-authority / received-outcome repair

**Implementation handoff, not independent SPEC or QUALITY approval.** Parent review/integration, fresh affected combined CORE and Root/public SPEC, then independent QUALITY remain required. Nothing was published or deployed.

## Frozen ancestry and scope

- Exact sole-writer base: `78e3d11b64095d08266ca15882a1468793c73910`, with unchanged `dfa65072439e79edf744be213defc91f30293f9b` / `81d10e7fbdc0ddd499d77a104d05f1d61b70808d` ancestry.
- Worktree: `/Volumes/Storage/Hermes/workspace/hermes-android-approval-authority-received-outcomes`; branch `fix/android-approval-authority-received-outcomes`.
- Published identity remains **2.1.32+2175**. No dependency/lockfile, native/server, release/signing, live configuration/provider, device, Vault, other-profile or TUI change. Existing frozen provenance archives/ledgers and prior review documents are byte-unchanged.
- Working evidence: `/Volumes/Storage/Hermes/scratch/repair78-sw4ni6sb`. Committed durable evidence: this directory's `verification.json`, `case-ids.json.gz`, `evidence.tar.gz`, `ARTIFACT-HASHES.json` and `ORACLE_LEDGER.md`.

## P1: approval authority through the whole intent lifetime

`NotificationApprovalAuthority` stores the existing `MobilePushService.binding(SavedConnection)` fingerprint, shared `ConnectionMutationBarrier` epoch and revocable owner validity. The fingerprint uses the complete saved configuration plus credentials/profile; no weaker host/session/request heuristic was introduced. The DTO/payload contains no plaintext credential. A fingerprint is not server authorization.

New local approval notifications carry **`approvalAccount`** (complete binding hash) and **`approvalMutation`** (opaque process UUID plus mutation epoch). Origin is frozen when the notification's application/route owner is created, not minted from the account that exists when an old response is resumed. Root captures a ticket at response ingress before lifecycle deferral or credential awaits. It captures the actual manager, physically refreshes saved metadata/credential authority before automatic dispatch, and invalidates the ticket on manager/root/session replacement, pending mutation, removal/recreate and ABA.

The existing deferred-response path retains several unrelated scoped approval intents instead of one overwritable raw slot; ordinary navigation remains latest-intent navigation. Existing approval dispatch remains the sole dispatcher. Mutation begin, resume, owner close and consumption prune obsolete intents. Root and route revalidate before dispatch even if eager pruning has not run. Dispatch owners are captured before awaits: an unresolved old attempt never falls through to a replacement owner.

Queue deduplication/single-flight are account/epoch/owner scoped. Revoked old flights cannot starve a valid fresh action with reused IDs. Acknowledgement removes only the **exact owned queue object**. Normal-owner post-await input cleanup also checks the captured input object. A reply already sent on its captured old socket is not retroactively cancellable.

Unscoped legacy automatic approval/rejection **fails closed**; ordinary body taps and manual-review navigation still work. A well-formed scoped other-process origin can be admitted only with the complete current binding, fresh physical credentials and an exact live owned backend request. Old socket request IDs are not guessed/remapped by raw peer ID. The cold-origin positive fixture is a simulation, not OS launch/process-death evidence.

## P2: bounded received lifecycle facts

`ReceivedScopeOutcome` is a tiny immutable UI-only DTO: existing operation ID, existing received scope anchors and `completed` / `failed` / `unknown`. Facts are recorded only at the existing authoritative owned settlement, never from a history row, body, timing, role, floor, UUID resemblance or ordinal. Pre-wire rejection records no failed server turn; local interruption/recovery/unknown is not relabelled definite backend failure.

Facts survive later reservations/cancellation, sequential turns, detachment and verified alias/donor import. They travel in the existing bounded owner presentation and imported presentation containers. Anchors are intersected with retained rows/runs; metadata is pruned with actual scope eviction and owner/account close. There is no separate unbounded turn map, body reducer/buffer, durable journal or synthetic canonical/model/HTTP/WAL row.

UI/export consume the same scope-associated metadata. One existing received provenance caption carries each operation's localized outcome; no extra lazy-list cell or changed inner card key is needed. Long captions are single-line ellipsized with their full text available to accessibility. Export keeps C first / labelled R second / Aux once and includes the same honest known lifecycle fact. Unknown copy was added to all eleven ARB locales and generated L10N. Imported tool association uses exact projected activity objects rather than a reusable public tool string.

C/R completeness, receipt/source order, accepted history-read start authority, composer/WAL/admission/no-replay, child observer/viewer, current-owned speech/unread, existing retention/tombstone/text/tool/task limits, actual State/controllers/keys/manual pins/draft/selection and exact 120→120 controls remain regression gates. No outcome metadata becomes received speech, a model input or an additional completion notification.

## Executed verification

All Flutter operations were serial per owned app, max two test workers, Flutter **3.44.0**, Dart **3.12.0**. HOME/PUB_CACHE are owned siblings outside the test app; package config/graph/plugin metadata were relocated, main package remains `../`, and borrowed package URIs resolve against their original configuration.

| Execution | Actual result |
|---|---|
| Exact original CORE20 + raw ROOT8 on base, before production edits | 28 cases; 22 pass, 6 assertion errors; exit1 / terminal false; no skips/loaders |
| Fresh separate exact-base repeat, CORE20 + minimal valid-origin ROOT8 | 28 cases; 22 pass, 6 assertion errors; exit1 / terminal false; original queue evidence preserved separately |
| Final exact CORE probes + minimal two-field root adapter | **28/28 pass**, exit0 / terminal true, no errors/skips/loaders |
| Final complete accepted inventory + additions | **2511/2511 pass**, exit0 / terminal true, no errors/skips/loaders |
| Existing base identities retained in that run | All **2443**, no missing or renamed identity |
| Tracked tests including new permanent tests / accepted independent sources | **2404 / 107**, within the same 2511, not additive cohorts |
| Additional executable identities versus base | **68**; includes reviewer CORE20 and eight rehosted/adapted root schedules, not 68 newly independent schedules |
| Fatal analysis | `flutter analyze --no-pub --fatal-infos lib test`: exit0, no issues |
| Generation / formatting / whitespace | gen-l10n unchanged on regeneration; 31 necessary Dart files checked, zero remaining formatting changes; `git diff --check` clean |

Overlapping cohorts freshly executed within the complete run: retained425, B38 (original B36 unchanged), C/R26, Root/public59 (46 literal + 13 schedules in the two existing explicit main81d policy copies), compact11, reasoning-visit16, cleanup13. Other prior cohorts overlap the preserved 2443 identities; do not add them. Historical native36/server126 were **not freshly executed**.

`verification.json` records command exits, reporter terminal values, error/skip/loader counts and all case identities. `evidence.tar.gz` retains intermediate failures rather than relabelling them passes. The earlier full 2443 run exposed eleven unscoped fixture admissions; explicit origin API plumbing retained all existing assertions. Fixture setup/compilation/async-pumping/ordinary-HTTP credential expectations and an invalid initial Python-3.9 baseline attempt are classified in `ORACLE_LEDGER.md`. Two extra permanent regressions were also observed red before their final fixes: imported same-string tool outcome association, and a revoked manager-owner flight starving a fresh same-ID action.

## Precisely exercised production boundaries

- The valid-origin original root schedule still admits the same action, then performs the real same-saved-ID credential/profile mutation, pauses/resumes and checks exact old-object revocation. In the separate base repeat, `bindingChanged`, `oldOwnerReplaced`, `sameSavedId`, `sameOldActionObjectRetained` are all true; in final root evidence the obsolete action is gone.
- An actual root + production DesktopGatewayClient + loopback HTTP/WS fixture proves **zero replies on the replacement-profile socket before a fresh action**, followed by exactly one valid fresh `deny`. It also permits one already-on-wire old-owner reply before mutation. This is a controlled safety-negative/positive wire test, **not a claim that the original baseline executed a wrong-account RPC**, nor physical native delivery/provider evidence.
- Held success/false/throw, root disposal, pending secure writes, profile/credential/ABA/removal-recreate, independent real manager caches, multiple unrelated account/session deferrals, exact-entry acknowledgement and fresh same-ID progress are covered. Held recovery-session replies and same-root manager replacement are explicitly injected/embedder schedules, not claimed default stock UI sequences.
- Stock ID-less failure plus physical resume, identified failure, later success, complete C/R, same mounted identities and real SharePlus export are exercised at 400/1000 widths. Additional owner/projection tests cover inverse outcomes, unknown, preparation cancellation, pre-wire rejection, aliases/import, reasoning/tool-only scopes, partial scope retention, eviction and bounds.

## Integrity

All 590 original Git blobs were verified on base. Final worktree/app lib/test hashes match their pre-tool snapshots (341 / 358 files); no tool-induced source drift. All **7416 borrowed third-party Dart hashes and nanosecond mtimes**, and the wider **9554 dependency/SDK Dart entries**, match the frozen baseline. Storage UUID was verified before writes and at final audit: `F7E08904-541C-463A-8BD5-284D3C146333`.

No production acceptance verdict is issued here. The prior independent REQUEST_CHANGES reports remain historical inputs, not silently overwritten approvals.
