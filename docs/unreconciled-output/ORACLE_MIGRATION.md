# Oracle migration — UNRELEASED implementation handoff

Authority: the exact reviewed policy/contract/ledger and parent approval are preserved inside `oracles-raw.tar.gz`, with their SHA-256 manifest. Contract SHA `2082d6371d9fc2a7b8f9e0710f6d36212f2841d156465be405d380d5b6f0f0e3`; binding ledger SHA `d7ea1a5c1f9efa9fcbf589f1deab432770e666f3e87b762ca0eb423b32bec89f`.

## Preservation and disposition

- **R:** original safety assertion retained. Wire inputs/order, physical barriers, UUIDs, scope membership, immutable floor/WAL, raw payload roles/IDs, no-replay/request counts, route/State/controller/key/pin/draft/scroll and child read-only assertions remain binding.
- **S:** only flattened cross-source uniqueness, hidden canonical intervals/base copies, or unproved materialized retirement is superseded. C and R are now checked independently or in explicit C-first/R-second order. No weaker disjunction replaces current-answer survival.
- **A:** source-specific selector, real lazy reveal, removed-API plumbing, provenance comment or formatting; not a claim of byte-unchanged source.
- **H:** the existing three-line cleanup-only raw13 repair, preserved separately; no new production timer workaround.

`oracles-raw.tar.gz` contains exact pre-edit tracked/independent sources as non-analyzed `.harness` data, their hashes/base Git blob pointers, historical receipts, prior public API diffs and the separate H diff. All 573 base Git blobs are also enumerated; the complete initial base archive remains in the scratch evidence directory. Raw original files were archived before changing their oracles. `oracles-policy.tar.gz` contains the four separately named independent policy copies, exact original→adapted diffs, tracked-test exact diffs, and the assertion-level R/S/A ledger (old/new path, SHA, case declaration and line ranges). These are evidence files, not new tracked duplicate runnable cases. `verification.json` identifies the full reporter-derived receipts and unique case inventory.

## Two disclosed adaptation layers

The six previously accepted public adaptations (`chat_expansion_lifecycle`, `chat_presentation_state`, `late_identity_sse`, `late_identity_stock`, `late_identity_tool_state`, `normal_gateway_route_reattachment`) predate this work. Their original API_PUBLIC_ADAPTATION diffs remain intact. Obsolete global tool pins/cross-visit retention were **not** restored. This commit is a second policy layer on exact 4a53; only three of those six files need further C/R oracle changes (expansion, stock, route).

## Changed tracked oracle scope

All paths below are under `test/`; original case names are retained as historical IDs even where they mention retirement.

| File | S / A changes; all other assertions R |
|---|---|
| `normal_gateway_presentation_authority_test.dart` | Full C including99/current/later; current R no longer cleared; C tail and R tail distinguished; unknown-floor C no longer hidden. Raw reducer IDs, first-render reasoning pins, null/WAL floors and freshness schedules retained. |
| `normal_gateway_alias_received_history_test.dart` | Every materialized successful/failed donor retained; canonical current answer checked in C, not a copied suffix in R. All six wire schedules, chronology/bounds/child/reentrant cases unchanged. |
| `normal_gateway_application_session_test.dart` | Materialized text/reasoning/tool/task state retained after latest/terminal hydration; removed hidden-base API replaced by raw C plus a separate real history-window policy check. Empty-scaffold stale/incomplete/success controls unchanged. |
| `normal_gateway_route_reattachment_test.dart` | Source-qualified prompts/cards, received retention on reopen and after child completion; real lazy reveal after older paging. Same visit defaults/drafts/child/controller/request-count checks retained. |
| `normal_gateway_alias_authority_wire_test.dart` | Final unsupported erasure replaced by full C and retained current received text/tool/timeline; initial lagged-read/WAL/alias/wire checks retained. |
| `normal_gateway_alias_viewer_wire_test.dart` | Wait for accepted canonical completion, not empty received rows; all GET-only viewer/anchor/tip/same-scroll checks retained. |
| `normal_gateway_unknown_floor_route_test.dart` | Full C and one prompt/reply per R, not global1; anonymous legacy context follows existing latest-window replacement, not a removed pinned base. |
| `normal_gateway_unknown_floor_lifecycle_test.dart` | All seven real create/resume modes retain materialized R, including proven-empty floor0; exact C/R pairs independently visible. Raw create body, malformed/null floor and physical WAL assertions retained. |
| `normal_gateway_unknown_floor_wire_test.dart` | One local prompt/reply in R and one complete saved pair in C; exact one create/submit remains. |
| `normal_gateway_fresh_chat_test.dart` | Source-qualified prompt/answer pairs, wider real viewport to reveal both sources; all initial404/admission/receipt/next-send checks retained. |
| `late_identity_stock_test.dart` | C/R tool cards are no longer exclusive. Received first-render key/manual controller retained; canonical durable-ID card separately checked for its key and alias pin. True reopen still resets tool visit choice. Existing delegate inspection unwraps only source decoration, retaining every late-ID/eviction/budget assertion. |
| `chat_expansion_lifecycle_test.dart`, `timeline_spec_regressions_test.dart` | Exact C-first/R-second list retains wire prose/tools instead of destructive latest replacement. Other tests/defaults unchanged. |
| `chat_history_scroll_test.dart` | Only post-hydration cross-source repetition changes; canonical tool selector preserves terminal metadata; preview/reuse test uses a real larger viewport with unchanged per-turn counts. SSE/scroll/unread assertions unchanged. |
| `chat_history_widget_test.dart` | Real lazy scrolling reveals retained older C and received final reply independently; request and visible-content assertions unchanged. |

The immutable accepted inventory is **39 files /421 cases**, not the 42-file union including nine/raw13/cleanup13. All cases were rerun. Three additional prior-presentation files /22 cases and prior received22 remain distinct overlapping gates. No case was skipped or removed.

## Independent copies and raw outcomes

| Raw original | New copy / disposition |
|---|---|
| `independent_spec_77413_adverse_test.dart` SHA `842fba03b54d2c9cbfaf67c6234c2996d88daf81d654e00c486994c9e8d28637` | `independent_spec_77413_adverse_unreconciled_policy_test.dart`: nine original schedules. S hidden prefix/global prompt uniqueness; A canonical checks target C; new R current retention assertion. Reasoning/widget/stale/unsubscribe/wire safety retained. |
| `independent_spec_cc009ac_boundary_test.dart` SHA `c1fa287e69c1fa786e36dc281a2b9096f2210bcc66154d23a3b5024039b7319b` | Four-case `_unreconciled_policy_test.dart` copy. Old disjunction/summed visible1 replaced by canonical current once **and** current received once, with visible badges; same missing-response HTTP/WS schedules and actual400/1000 State. |
| `independent_spec_cc009ac_request_start_test.dart` SHA `b20a79d490745fac3be5d87dff9519f16fba849ffe4e3361a35d874c04935f88` | Two-case policy copy: removed projection API / C-specific suffix selector only. Exact physical held-menu GET, newer103 authority, same-State assertions retained. B's permanent36 source is byte-unchanged. |
| `history_authority_ambiguity_counterexample_test.dart` SHA `02a34c949b48a2681e7115f3bc737797013acac2de5eae6f02ee94c1687bff28` | Policy copy executes the same real wire worlds and requires equal observations and equal truthful C/R projection, including99 plus both received scopes. No DTO-only replacement. |
| Raw13 SHA `da23f36c7524128c7db3049df22bee9d7985201a8b2cf927554dd9643f73d6c6`; cleanup13 SHA `45e4868f0ea9d9786745c0c3798a1771fbe5418b2aeddff42932f8cf1abfda60` | Both unchanged. Raw13 actually gives12 passes +1 known post-assert pending-timer error; existing three-line H copy passes13. They are not26 distinct content cases. |

The raw nine/two/four/ambiguity sources honestly no longer load after the removed hiding API; `final-raw-removed-api` records four loader failures, not semantic red tests or fabricated old green. Their actual historical B outcomes are preserved: nine/two pass, four expected A assertion failures, ambiguity one deliberate assertion failure. The new baseline-compatible ordinary-success/close tests produced **two genuine assertion reds on4a53**, then pass on this tree; initial test-constructor setup mistakes are separately logged, not counted as reds.

All seven Root/public probe files remain byte-unchanged and **59/59 pass** after the renderer change, including immutable intent proof, pending-vs-active consent, account/profile/pagination/alias authority, independent visits, exact120→120 scroll, durable draft and no-replay/targeted cleanup. This is regression evidence, not independent approval.

## Evidence location and harness corrections

Complete commands, raw JSON reporter streams, per-case IDs/errors/done, source/cache/format manifests and intermediate outcomes: `/Volumes/Storage/Hermes/scratch/p2a-unreconciled-_flkt2h9/`. Scratch may be pruned; committed compressed raw/diff/ledger evidence and Git base/blob pointers preserve review provenance independently.

Intermediate setup/producer errors were fixed, not relabelled: missing `review-evidence/` fixture directory; new fixture imports/constructor signatures; an awaited live send that correctly waited for terminal; platform TTS arguments differ on macOS versus Android; lazy items require real reveal; ongoing tool spinners require explicit terminal before `pumpAndSettle`; lint braces/deprecation; and hidden setup/teardown pseudo-test counting. No production timer hack, automatic replay, weakened B freshness assertion, or oracle skip was introduced. Final acceptance gates have terminal success, no errors/skips, and matching tested source hashes.
