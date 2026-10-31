# Neutral main81d integration — UNRELEASED

## Decision requiring explicit parent acceptance

Merge exact `dfa65072439e79edf744be213defc91f30293f9b` and `81d10e7fbdc0ddd499d77a104d05f1d61b70808d`, merge base `459022b93fe1e422cf03bee74862a9a4fefe4fe2`. Actual merged PR173/174 bodies and both diffs were read. Published identity remains **v2.1.32 / 2.1.32+2175**; neither newer main PR is a release.

**Choose PR174's actual-visit reasoning policy.** This explicitly supersedes the older 459-based “only tools reset on disposal; reasoning is app-global” premise, for manual reasoning expansion only. Reasoning defaults collapsed despite run/message gateway verbose hints; explicit app Verbose remains the expanded-default override, unless manually closed. A real disposed/reopened State gets fresh preferences. Parent can veto this design decision; it is not an incidental test fix.

The minimal adapter gives each mounted State a separate existing bounded `ToolActivityGroupPins` token for reasoning (100 values/100 aliases), independently of tools. Registry binding transfers live tokens, never manual values between independent prebinding views. IDs are already scope-stable from first render, so no new reasoning correlation/alias ledger is invented. Cover, lazy remount, late IDs, verified local/stored convergence and open task modals retain the token. Disposal closes only that visit. Same-State account/config/controller or unrelated-chat replacement gets a fresh reasoning token. A visit-keyed subtree discards the old card-local controller choice on such replacement **while preserving the existing inner reasoning key/ID**; the new replacement regression genuinely failed without this wrapper. No new received owner or unbounded Map.

## Every upstream hunk and marker decision

Line locations are base-to-main hunk starts; exact headers/diffs are in the evidence archive. D = disjoint-intent, Q = same-question-different-answer, S = superseded premise.

| Path / hunk | Class | Resolution and rationale |
|---|---|---|
| `chat_screen.dart:375` | Q | Keep our application registry/writer/controller ownership; implement peer actual-visit reasoning policy using bounded tokens rather than its unbounded route Map. |
| `chat_display_items.dart:158` | Q | Live runs use only explicit app Verbose. Preserve our independent C/R projector and eviction/tombstone behavior. |
| `chat_display_items.dart:185` | Q | Stored reasoning ignores `_gateway_reasoning_verbose` for expansion, not body retention. |
| `delegated_task_timeline.dart:226` | D | Exact peer model/detail additions and duplicate-live-preview guard; same scrollable read-only modal/controller. |
| `gateway_insight_card.dart:209` | D | Exact peer one-line ellipsised goal, status/model subtitle, indicators, intact callback/task data; no giant inline detail. |
| `chat_display_items_test.dart:346` | S | Exact peer renamed gateway-autoopen premise. |
| `chat_display_items_test.dart:358` | S | Exact peer collapsed-default assertion. |
| `chat_history_scroll_test.dart:197` | D/S | Peer explicit close tap replaces reliance on metadata autoopen; opposite pins, keys, States, order remain. |
| `chat_history_scroll_test.dart:1116` | S | Exact peer case rename documents no automatic expansion. |
| `chat_history_scroll_test.dart:1149` | S | Metadata no longer opens reasoning; text remains inspectable. |
| `chat_history_scroll_test.dart:1172` | D/S | Retain all peer collapsed-default/manual-open and receipt-order assertions, plus our earlier C/R controls. |
| `chat_timeline_test.dart:41` | D | Combine peer two app-Verbose cases with our eviction/identity tests; no declarations removed. |
| `compact_delegated_task_card_test.dart:0` | D | Exact peer file, all 11 cases, byte-identical to81d. |
| `normal_gateway_route_reattachment_test.dart:262` | Q | Keep peer actual Navigator pop/canonical reopen, active/completes-away, retained body and one submission; only explicit C/R lazy reveal/taller fixture geometry added. |
| `normal_gateway_route_reattachment_test.dart:846` | D | Combine peer navigable fixture with our push mode, resume hook and physical read accounting; neither helper replaces the other. |
| `normal_gateway_route_reattachment_test.dart:891` | D | Retain peer route wrapper. |

Three marker regions: ChatScreen preference authority (Q), timeline test insertions (D), route helper (D). No wholesale ours/theirs resolution. The two task production files and compact test are byte-identical to81d.

## Clean authority hotspots / unchanged contracts

- `chat_presentation_state.dart` is the necessary extra adapter beyond markers. Its draft writer, edit chronology, lease transfer, persistence and rejection restoration are unchanged. Tool alias ingress/visits and their public defaults are unchanged.
- Root intent/proof versus ordinary navigation, single-flight/account/profile/paging/notification/keepalive/partial cleanup and no replay remain unchanged. The exact same-visit **120→120** Root control passes; no universal text-anchor guarantee is introduced.
- Entire `normal_gateway_application_session.dart`, history-window row-only merge, physical request-start tokens/non-promoting fences, latest/deferred/cold/older-page/error/reentrant/latch behavior are byte-unchanged fromdfa. Permanent B36 is byte-unchanged; B38 passes.
- Complete accepted loaded/paged C and bounded labelled unconfirmed R remain independently ordered/projected; no materialized-success retirement, donor partition, text/ordinal/timing correlation, copied canonical API, synthetic model/HTTP/WAL rows or body journal. C first/R second/auxiliary once; same lazy source keys, inner IDs, current-owned voice/unread/export, GET-only child controller/anchors/tips and drafts remain.
- Received bounds and lifetimes are unchanged: shared1024 runs/1048576 UTF-16 code units/1024 tombstones; existing live/prior256 each, settled combined guard256 rows/512 tools, field262144, task128 and pin/alias100. This is not a new per-section budget or universal byte-memory claim.
- README's obsolete hidden-saved-rows wording is corrected and the unreleased policy linked. Historical review documents and frozen `docs/unreconciled-output/` archives are not rewritten.

## Third explicit oracle layer

The original public-tool API layer and later C/R layer remain frozen. `docs/main-81d-integration/evidence.tar.gz` adds raw parent test sources/manifests/declarations, prior reporter IDs, actual PR bodies, exact third-layer diffs, assertion/hunk ledger, adapted independent `.harness` copies, commands/raw JSON reporters, cache/source proofs and local build evidence. No original adverse input, physical barrier, UUID/WAL/floor, no-wire/replay, draft/lease/controller/key/scroll or child safety assertion is dropped.

- `chat_expansion_lifecycle_test`: only true-dispose reasoning retention oracle is superseded; same inner keys/run IDs/body and tool reset checks retained. Actual old oracle failed as expected before adaptation.
- `chat_presentation_state_test`, `late_identity_tool_state_test`, `normal_gateway_presentation_authority_test`: acquire explicit reasoning visits and inspect the same token across aliases; bounds/account/sibling isolation and all raw identity/freshness controls retained.
- Two independent Root/public copies have explicit `_main81d_policy_test.dart` names. `review_root_public_cc_spec` changes only the post-dispose reasoning default in its eight original schedules, not earlier same-view120/key/pin/draft/ownership assertions. `review_public_visit_preview_cc_spec` replaces global merged reasoning values with separate visit values in two schedules, retaining all tool identity-only fanout/bounds/close checks; its other three cases are unchanged. Five remaining Root/public files /46 cases are byte-unchanged. All59 original schedules run, not59 unchanged files/cases.
- Three old case names are renamed exactly as peer174; the executable inventory maps those names explicitly. Prior2412 → final2443 is **15 peer additions +16 new adapter cases**, not lost cases. The retained421-file cohort now runs425 because it also includes peer's two timeline/two reopen additions; all original421 IDs remain.

## Executed verification

Own scratch HOME, PUB_CACHE outside app, relocated package config plus package graph; read-only prewarmed dependencies. Flutter3.44.0 / Dart3.12.0 / OpenJDK17. Serial gates, at most2 test workers. Counts below overlap and are not summed.

| Gate | Unique passing cases |
|---|---:|
| Complete tracked | 2336 |
| Complete tracked + accepted independent copies | 2443 |
| Original retained421 + four peer cases | 425 |
| New C/R policy | 26 |
| B physical request-start matrix + two prior policy copies | 38 |
| Prior received / prior presentation | 22 /22 |
| Root/public | 59 |
| Original late draft/tool owner repro cohort | 53 |
| Broader draft-owner rerun | 68 |
| Existing cleanup-only harness | 13 |

All acceptance gates have process exit0, reporter terminal success, **zero errors/skips**. Fatal analysis of all lib/test passes. Formatting check covers all99 Dart files changed since published459, without reformatting unrelated older files. All586 test-input blobs matched before/after tests and build, before documentation-only packaging; the final committed-tree audit is recorded in the final scratch receipt. 570 of584 original dfa files are byte-unchanged (14 deliberate modifications plus two new test files before documentation). All7416 borrowed dependency Dart hashes and mtimes match.

Raw originals are separate evidence, not acceptance green: four removed-history-API probes still fail to load (four loader failures/seven error events); raw13 still gives12 passes plus its known post-assert pending-timer harness error. Existing cleanup13 is the same content, not13 extra distinct cases. No production timer workaround. Initial new-fixture offscreen/pending-spinner errors and absent `review-evidence/` output directory are logged and fixed in harnesses, not relabelled product failures. No old pin oracle was silently weakened.

## Build and limits

Fresh offline **unsigned local debug** compilation succeeds without source Gradle edits. Final artifact: `app/build/app/outputs/flutter-apk/app-debug.apk` under the evidence scratch root, SHA-256 `d37064d289d55c990f5e6288df96f73b3aeaabc235020c4f58ba888dee90f359`; dev package/version `com.hermesagent.hermes_android.dev` / `2.1.32-dev` /2175. SDK apksigner correctly rejects the final artifact as unsigned. An initial late Gradle override was ineffective and produced an automatically debug-signed scratch APK; this is disclosed, not claimed unsigned. The corrected scratch-only `androidComponents.finalizeDsl` hook disables signing before variant creation. No production key/properties/Vault access, release signing, install or distribution. Initial apksigner invocation lacked JAVA_HOME and was a verification-preflight failure, not unsigned proof. Existing KGP migration and untranslated-label warnings remain.

No native36/server126 test rerun is claimed; these are historical reuse only. No real device/provider/voice/OS-kill/distributor/live server/config/default/fallback/other-profile/TUI, release, push, tag or PR action. Tests use controlled mocks/loopback. SSE gates exercise stored reasoning choices during actual SSE text streaming; no unsupported SSE reasoning protocol is invented. This is an implementation/verification handoff, **not independent SPEC or QUALITY**. Parent owns fresh frozen combined CORE and Root/public SPEC, then QUALITY.
