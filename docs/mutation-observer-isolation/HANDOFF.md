# ROOT37-1 / P2 — narrow implementation handoff

Implementation and execution evidence only. **No SPEC, QUALITY, integration or deployment approval.** Parent owns fresh Root SPEC and affected CORE reassessment before QUALITY.

## Change and policy

- Direct base: `37f52c1b84a1e7a1ca93c8e573e8e79badd030fc` (its parent `78e3d11b64095d08266ca15882a1468793c73910`). Branch: `fix/android-mutation-observer-isolation`.
- Only production change: `lib/core/services/connection_mutation_barrier.dart`, one per-listener `try/catch` in synchronous snapshot delivery: **7 insertions, 1 deletion**. All-ID epoch invalidation still completes before any observer. Exact pending refcounts, nested/reentrant/overlapping ownership and idempotent release are unchanged.
- An optional observer's thrown object no longer escapes `begin`, skips later observers or prevents the caller obtaining its lease/entering its own storage or recovery boundary. Nothing is released on an observer's behalf; epochs are never rolled back.
- Diagnostic decision: **none**, bounded at zero bytes/state. No exception formatting, raw metadata/credentials/provider logs, asynchronous rethrow, global error handler or warning suppression.
- The actual manager's sanitized storage errors still propagate; its metadata reads, physical transactions, rollback and native BEGIN/END/finally remain byte-identical. No cached authority, fabricated I/O, queue clearing, callback removal, authority/controller/DTO/API change or timeout change.
- Version stays `2.1.32+2175`; native/server, dependencies, models/config/defaults, old provenance and all other production files are unchanged.

## Exact adverse reproduction

The reviewer's seven-case source was copied and hashed **before** implementation. Original and executable copies retain SHA256:

`c288e37bbff0d28d370a10c101d8e64d1610e6defd6953d31dc36d5f5e4061cb`

**No A/H or semantic adapter was applied.** The harness creates its required `review-evidence/` directory before execution. Both primary cases retain real HermesApp/default session factories, real ConnectionManager, root-owned unrelated B approval, pause, actual saved-key corruption `['{']`, real failed A mutation, restored metadata, real successful A successor, and separate real reset.

| Execution | Actual reporter result |
|---|---|
| Exact37, unchanged reviewer Root7 | 5 pass / 2 assertion errors; exit1, terminal false; zero skips/loaders |
| Fixed tree, same exact Root7 | 7/7 pass in focused and both complete runs; exit0, terminal true |
| Exact37, final permanent regression bytes | 8 errors; exit1, terminal false; zero skips/loaders |
| Fixed tree, final permanent regressions | 8/8 pass; zero errors/skips/loaders |

Fresh base facts: unrelated B object survives, A pending after failure=true, successor physically commits=true, pending after successor=true, successor current=false; reset clears corruption=false. The actual root prune/owner/getConnections stack reaches `begin` before any native BEGIN.

Fresh fixed facts: same B object survives, A pending after failure=false, successor physically commits=true, pending after successor=false, successor current=true; reset clears the actual corrupt key=true. The remaining failure is the caller's own sanitized storage-read error, now inside its transaction boundary—not a swallowed mutation error. Permanent assertions additionally check B's restored current authority, unchanged credentials after the failed edit and physical key absence after reset/reload.

## Permanent regressions

- `test/connection_mutation_barrier_test.dart`: five cases covering Error and Exception isolation, all-ID invalidation visible even to the first throwing observer, healthy later delivery, duplicate IDs, overlap/refcounts, idempotence, stale epochs, reentrant nesting/listener snapshot changes and empty-ID recovery delivery. Observer callbacks collect facts; their assertions occur outside the deliberately caught boundary.
- `test/connection_mutation_observer_root_test.dart`: the two actual-root corrupt-store schedules with exact queued-B identity/current-authority and fresh-A/reset assertions.
- `test/support/mutation_observer_root_fixture.dart`: narrow fixture reuse, not a blind copy of the extended root suite. Uses existing loopback server, memory credentials and journal fixture. Keeps real root/controller/manager paths. Writes no evidence files and never clears B before primary or teardown assertions. The inherited 21-second widget-only recovery timeout drain is disclosed; no product timeout was changed.
- `test/connection_mutation_observer_transaction_test.dart`: controlled write-failure and native-END-acknowledgement futures with throwing and healthy observers. Queued A successor cannot begin before END acknowledgement; sanitized failure, rollback, two matching BEGIN/END lifetimes, fresh physical credentials and final current authority remain asserted. Channels/credentials are fixtures, not Android provider proof.

All exact case IDs/statuses and raw error events are preserved in `verification.json`, `case-ids.json.gz`, and the archived per-run receipts/logs.

## Fresh verification and integrity

- Final full JSON reporter: **2540 unique / 2540 pass**, exit0, `done.success=true`, zero errors/skips/loaders. All **2511 accepted identities** are present and pass (2404 tracked +107 accepted independent); all prior2443 identities retained.
- Additional identities in this run are reused minimal valid-origin Root8, unchanged reviewer Root7, unchanged CORE37 six-case probe and eight permanent regressions. These are not all newly independent tests.
- Final focused run: **346 unique / 346 pass**, exit0/terminal true/zero errors/skips/loaders. Includes connection-list/manager/prerequisite-read/native-bridge Dart controls, approval authority, original CORE20, minimal valid-origin Root8, both current reviewer probes and all new regressions.
- Verified overlapping full-run cohorts, **not additive**: retained425, B38, C/R26, Root59, compact11, reasoning16, cleanup13 and original CORE20. All pass. Root59 and cleanup13 retain their already disclosed policy/cleanup provenance; no new adaptation.
- Fatal whole-lib/test analysis: `flutter analyze --no-pub --fatal-infos lib test`, exit0, `No issues found!`.
- Final no-write formatter: changed production file + four new Dart files, zero changes/exit0. Git whitespace checks clean.
- All606 original Git blobs checked before tooling and after: only the allowlisted barrier differs; all139 lib blobs accounted for. New test/helper bytes match the executed archive. Frozen old provenance remains untouched.
- All **7416 borrowed third-party Dart hashes and nanosecond mtimes**, plus the **9554 dependency/SDK Dart superset**, match independent before/after snapshots. No pub get/install/upgrade or borrowed-source modification.
- Both package config and graph plus plugin metadata provided; main rootUri=`../`, borrowed dependencies resolved absolutely against their original config. HOME/PUB_CACHE are owned siblings outside the app. Flutter commands were serial per app, max2 test workers.
- Storage UUID checked before writes and audit: `F7E08904-541C-463A-8BD5-284D3C146333`.

Owned-harness corrections are retained honestly: an initial new transaction assertion counted four deliveries after an additional physical export; it now asserts four before export and five after its legitimate empty-ID lease. Two initial helper lint infos and one new-unit format check were corrected without suppression, then final exact full/analysis/format reran. No loader or missing-directory failure occurred. No pre-existing oracle was weakened.

Historical raw4 removed-API loaders, raw13 post-assert timer issue, unsafe raw Root8's two unscoped-admission failures and native36/server126 remain historical qualifications, **not freshly rerun unchanged-green/native/server credit**. Fresh minimal Root8 SHA remains `7a9f6d0bb930282ed2e1bb324dc647562ff318fd08633f0ec32062ace459cca6`; fresh CORE37 six-case SHA remains `6f79288605ad8f5f6ea0173f268e4e049050bc2fde0ac18a8f449761dd92e730`.

## Artifact handles / replay

Absolute owned evidence root:

`/Volumes/Storage/Hermes/scratch/mutation-observer-isolation-37`

- `exact37-source.tar.gz`: complete exact-base archive; SHA in `verification.json`.
- `ORIGINAL-ROOT37.dart.harness`, `base37-raw-seven{.log,-receipt.json,-widget-evidence/}`: original bytes and fresh actual two-red proof.
- `base37-permanent-final-bytes{.log,-receipt.json}`, `full-final-exact{.log,-receipt.json,-widget-evidence/}`, `focused-final{.log,-receipt.json,-widget-evidence/}`.
- `SOURCE-{BEFORE,AFTER}.json`, `CACHE-{BEFORE,AFTER}.json`, `PRODUCTION.diff`, `FINAL-RECEIPT.json`.
- `evidence.tar.gz` here contains raw commands/logs/receipts/facts, source/cache manifests, original reviewer source, exact final permanent tests and accepted independent replay sources. Extract only into a new owned directory, never over borrowed sources.

Permanent tests require no evidence directory. To replay the exact reviewer source in an independently prepared app with verified dependencies, copy `ORIGINAL-ROOT37.dart.harness` to `test/independent37_root_adverse_test.dart`, create app-local `review-evidence/`, then run:

```sh
/opt/homebrew/bin/flutter test --no-pub --concurrency=2 --reporter=json test/independent37_root_adverse_test.dart
/opt/homebrew/bin/flutter test --no-pub --concurrency=2 --reporter=json test/connection_mutation_barrier_test.dart test/connection_mutation_observer_root_test.dart test/connection_mutation_observer_transaction_test.dart
```

No build/sign/install/device/Vault/real account/provider/live server/config/model/other-profile/TUI/push/tag/PR/release actions. TUI remains paused. Parent review/integration and independent fresh reassessment remain outstanding.
