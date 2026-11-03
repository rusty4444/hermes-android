# Combined PR235 + PR237 + PR238 — local integration

## Exact ancestry and scope

Owned worktree `/Volumes/Storage/Hermes/workspace/android-rc-provider-combined`, branch `fix/rc-provider-combined`.

- Integration baseline: `81e99b2098cf07ca459452efd5adc3573453373c` (not the stale local `main` ref).
- Reviewed provider stack: `5b58b3d5dccdb939cd5a4be0d5467d7f58c63105`.
- Reviewed Portal implementation: `9d9b29056e495b3b88b848a29cd58797922eb7fa`.
- Combined merge: `0afdb2987e32c3a97cdd345d067c7b3e6710ee4d`, with those two reviewed heads as its parents.
- Portal route regression: `f0ff4ed85ac3917075f45399fba92ba29fce2028`.
- Independently repaired Portal TLS head: `1e92ac35632e7229e8e7f65547e801a5024d5b57`.
- **Validated code head**: `5168b168a67f9eabed837d6edfc7982d19c510a8`, merge parents `f0ff4ed85ac3917075f45399fba92ba29fce2028` and `1e92ac35632e7229e8e7f65547e801a5024d5b57`.

All above source heads, original PR237 `7528e5966fa528d0f2f8b1b8a1f40b71260cbec5`, and original PR238 commits `25ab78c3decf03c0759d60ae3c4a06b47ca452bd` / `55e0aa551d7d2966cc4af2ddf35bd1d380743d3c` are verified ancestors of the validated head. Contributor histories were merged, not squashed or rewritten. Other review worktrees were not modified.

This is a local integration artifact, not approval or a substitute for the parent's eventual individual PR merges and final ancestry reconciliation.

## Reconciliation

- Kept the newly reviewed read-only Portal screen despite provider stack's intentional deletion of the stale inherited screen. Restored its More entry **and Workspace route**, alongside lazy discovered provider entries.
- Unified duplicate dashboard `getModelsAnalytics` into the Portal contract with optional `days` and selected `profile`; retained actual Portal/usage GETs, not obsolete API-server helpers. No credential entry, plaintext key storage, direct provider auth, balances, invented model prices or Free-cost claims restored.
- Regenerated localization outputs from combined ARBs. All 11 shipped ARBs contain the combined Portal/provider/auxiliary keys.
- Retained dashboard origin/auth/mTLS boundaries; passed selected gateway profile into the Workspace-owned dashboard and standalone provider usage clients.
- Hardened analogous provider-screen synchronous client/certificate construction failure: nullable ownership, safe translated failure/retry, no unauthenticated fallback, connection/provider replacement generations, old completion rejection, safe disposal.
- Added real changed provider/model selection success with readback, `ok:true` but mismatching readback rejection, invalid-certificate retry/disposal, held old analytics versus replacement, and held/retried lazy single-flight Workspace discovery plus Portal route coverage.
- Preserved auxiliary endpoint read-only policy and serialized guarded mutations, obsolete Portal preference deletion, exact marker handling, and notice expand/collapse regressions.

## Final verification

Flutter 3.44.0 / Dart 3.12.0. Explicit `TMPDIR=/Users/sam.russell/.hermes/cache/scratch`.

Evidence directory: `/Users/sam.russell/.hermes/cache/scratch/provider-combined-evidence/`.

At validated code head `5168b168a67f9eabed837d6edfc7982d19c510a8`:

- `flutter analyze --no-pub --fatal-infos`: **exit 0**, no issues (`analyze-final.log`, `analyze-final.exit`).
- Focused 13-file suite, JSON reporter: **332 visible tests passed**, **exit 0**, zero errors/skips/unfinished IDs, terminal `done.success=true` (`focused-final.jsonl`, `.stderr`, `.exit`, `.summary.json`). Includes provider/Portal/More/Workspace/settings/active+archive refresh authority, timeline marker/notice, connection manager, certificate/TLS factory, and real search mTLS tests. 349 total start/end records include hidden loading/hooks; do not report those as visible test count.
- Full suite: **4,883 visible tests passed**, **exit 0**, zero errors/skips/unfinished IDs, one terminal `done.success=true`; real driver completed in **400.48 seconds** (`full-final.jsonl`, `.stderr`, `.exit`, `.summary.json`). 5,257 start and end records include hidden loading/hooks. Head before and after matches the validated code head. Background process was explicitly awaited to completion, not left running.
- `dart format --output=none --set-exit-if-changed` for all 26 changed Dart files against the exact baseline: **exit 0**, zero changes.
- `flutter gen-l10n`: **exit 0**, generated no further tracked differences. All 11 ARBs checked for combined keys; none missing.
- `git diff --check`: clean; source worktree clean before this evidence-only document.
- Ancestry checks saved in `ancestry-final.json`.

`verify_suite.py` in the evidence directory executes the real Flutter command, retains its actual exit, parses machine JSON, compares testStart/testDone IDs and the terminal done event, and rejects errors, non-JSON records, unfinished IDs or a changed HEAD. Focused/full totals overlap and are not additive.

## Failed/intermediate attempts (not passing evidence)

- Initial focused run exposed a test assertion on an unbuilt offscreen lazy More row; fixed by checking actual pane entries rather than assuming all scroll children exist.
- Second focused run exposed the auto-merged stale More expected ID list omitting the restored Portal entry; corrected to include it.
- Extra boundary run requested nonexistent `dashboard_client_password_auth_test.dart`: actual exit 1, one load error, no unfinished tests. Correct final 13-file command uses existing connection-manager auth coverage and real mTLS coverage. Its failure remains in `focused-provider-boundaries.*`, not counted as passing evidence.
- Pre-TLS runs are preliminary only; final focused/full runs include the exact independent TLS repair.

## Remaining gates

No remote writes, pushes, comments, GitHub merges, tags, releases or live backend mutations performed. Parent owns all remote actions. Fresh PR CI/reviewer acceptance and eventual final-parent-tree validation remain independent gates. No Android APK/native build, phone installation/runtime smoke, or live server usage/routing validation was performed. Any further source integration requires rerunning gates on that exact resulting head; this evidence document is the only subsequent repository change.
