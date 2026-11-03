# Neutral integration after published Android v2.1.32

## Scope, parents and both intents

- Exclusive integration branch: `feat/android-post-2.1.32-integration`, prepared at `77413e3be47f929fff5b328e1fb62584228cb040`. Only `/Volumes/Storage/Hermes/workspace/hermes-android-post-2.1.32-integration` and dedicated scratch evidence were written.
- Published parent: `459022b93fe1e422cf03bee74862a9a4fefe4fe2`, annotated `v2.1.32` dereference, common base `785f5fea7a1164a15b4f1eca62deed5b86338194` (v2.1.31). A read-only GitHub recheck at `2026-10-23T13:02:18Z` still found this main head and latest stable v2.1.32, published `2026-10-23T09:35:29Z`.
- **Published intent:** tools start collapsed on every new chat visit, running or finished; preview the newest nonterminal call, otherwise the last call. Retain group failures/status/timing. Manual choices survive updates and lazy remounts within the visit; reopening resets them. Explicit verbose remains an open default.
- **Unreleased intent:** retain app-owned stock turn/admission/WAL/recovery and history-read authority, nonsecret durable receipts, bounded receipt timelines, canonical aliases/drafts/writer leases, notification/privacy/transaction fences, independent read-only child viewing, scroll and reasoning choices.
- `git merge --no-commit --no-ff 459022b93fe1e422cf03bee74862a9a4fefe4fe2` produced **zero textual conflicts**. A clean merge was not sufficient: app-owned tool pins contradicted the new published visit lifetime.

## Explicit design answer (human-veto point)

**Choose published per-visit tool choices. The old cross-visit tool-pin premise is superseded.** Do not auto-expand running groups and do not clear the whole registry on navigation. An actual `_ChatScreenState` owns one tool visit; its existing `ToolActivityGroupPins` object is the visit token. Pushing a covering route or returning to the retained canonical Route keeps that State and its choices. Actual disposal closes only that token; a new State starts without manual tool choices. Distinct prebinding views remain independent when their chat identities converge.

The registry retains bounded **identity-only** tool aliases and fans learned IDs to live visits. Alias binding transfers the visit tokens, not their manual values. No parallel timeline/recovery reducer or draft owner was added. The public `GatewayActivityCard` is byte-identical to the published parent, including explicit verbose and two-line preview behavior.

### Stable tool-visit API / integration hotspots

- `ChatPresentationState.openToolVisit() -> ToolActivityGroupPins`: acquire once in `ChatScreen.initState`; retain through lazy children, streaming and route cover.
- `closeToolVisit(ToolActivityGroupPins)`: call only on actual State disposal. Resolve the same redirected root, unregister/clear that visit only.
- `aliasTool(String groupId, String durableId)`: the existing stock and SSE ingress publish learned identity into the registry's bounded alias ledger and each live visit. New visits inherit aliases but no choices.
- `ToolActivityGroupPins.inheritAliasesFrom(...)`: replay identity links without importing another visit's manual values; retain existing 100-entry pin/alias bounds.
- `ChatPresentationState.reasoningPins`, its accessor, and `target._reasoningPins.mergeMissingFrom(source._reasoningPins)` are **unchanged**. Composer writer admission, reads, intent chronology, persistence, rejection restoration and alias handoff are unchanged. The stock owner changes only its tool-alias sink call.

## Every public hunk and semantic resolution

Locations below are the published base-to-parent hunk starts (`parent-hunks.json` records exact headers). **D** = disjoint-intent, combine/retain both; **Q** = same-question-different-answer, explicit answer chosen; **S** = superseded premise. There were no marker hunks to resolve.

| File / original hunk start | Class | Decision |
| --- | --- | --- |
| `.github/workflows/pr-quality.yml:46` | S | Keep published required base `2175`, not prior `2174`. |
| `.github/workflows/release.yml:71` | S | Same exact published identity floor; no publication action. |
| `CHANGELOG.md:4` | D | Preserve published 2.1.32 entry and its historical validation claims verbatim. |
| `README.md:1` | S | Published latest header is 2.1.32. |
| `README.md:14` | S | Published version/build and current-release description win; unreleased hardening remains separately labelled. |
| `README.md:75` | Q | Published per-visit tools/current-call preview, not cross-visit tool choice. |
| `README.md:112` | D | Keep new 2.1.32 description alongside unreleased work. |
| `README.md:135` | S | Published latest-three summary removes 2.1.29; full changelog remains. |
| `README.md:586` | S | Preserve exact published ABI examples 21751/21752/21753. |
| `README.md:698` | D | Keep AI assistance disclosure and existing community credits. |
| `fastlane/metadata/android/en-US/changelogs/2175.txt:0` | D | Keep exact published store notes. |
| `fastlane/metadata/android/en-US/changelogs/21751.txt:0` | D | Keep exact published ABI notes. |
| `fastlane/metadata/android/en-US/changelogs/21752.txt:0` | D | Keep exact published ABI notes. |
| `fastlane/metadata/android/en-US/changelogs/21753.txt:0` | D | Keep exact published ABI notes. |
| `lib/core/widgets/gateway_activity_card.dart:49` | Q | Published visit-local manual-choice contract. |
| `lib/core/widgets/gateway_activity_card.dart:66` | Q | Never auto-open active tools; explicit verbose only. Newest nonterminal else last-call preview. |
| `lib/core/widgets/gateway_activity_card.dart:110` | D | Select preview without changing status/failure/timing aggregation. |
| `lib/core/widgets/gateway_activity_card.dart:168` | D | Published two-line name/status preview only while collapsed. |
| `pubspec.yaml:1` | S | Keep `2.1.32+2175` unchanged; retain existing hardening-only dev test dependency elsewhere. |
| `test/chat_history_scroll_test.dart:445` | S | Open before explicitly pinning closed; retain completion/older paging schedule. |
| `test/chat_history_scroll_test.dart:453` | D | Scroll to actual final bubble despite lazy extent estimates; retain exact timeline order. |
| `test/chat_history_scroll_test.dart:562` | S | Explicit open then close under new default; reasoning pins/order assertions unchanged. |
| `test/gateway_activity_card_collapse_pin_test.dart:18` | S | Actual controller state is authoritative, not a name now visible in the preview. |
| `test/gateway_activity_card_collapse_pin_test.dart:40` | D | Keep published pump explanation. |
| `test/gateway_activity_card_collapse_pin_test.dart:53` | Q | Published closed initial state, in-flight preference and concurrent latest preview; explicit manual closed pin persists. |
| `test/gateway_activity_card_collapse_pin_test.dart:85` | S | Open then close before progress/time update. |
| `test/gateway_activity_card_collapse_pin_test.dart:95` | Q | Untouched tools remain closed across completion/new calls; manually opened tools remain open within visit. |
| `test/gateway_activity_card_collapse_pin_test.dart:147` | S | Explicit verbose remains; obsolete auto-collapse/reopen premise replaced by failure/empty/current-preview coverage and retained manual expansion tests. |
| `test/gateway_activity_card_projection_pin_test.dart:83` | S | Controller, not title text, proves expansion. |
| `test/gateway_activity_card_projection_pin_test.dart:293` | S | Explicitly open then close before list relocation. |
| `test/gateway_activity_card_projection_pin_test.dart:321` | S | Same explicit choice before progress/reprojection. |
| `test/gateway_activity_card_projection_pin_test.dart:414` | S | Same explicit choice before lazy eviction. |
| `test/gateway_activity_card_projection_pin_test.dart:444` | S | Independent groups retain manual choices; closed previews are not body rows. |
| `test/gateway_activity_card_test.dart:123` | Q | Running activity starts closed with preview. |
| `test/gateway_activity_card_test.dart:132` | S | Detail/status body hidden until opened, current-call header remains. |
| `test/gateway_activity_test.dart:220` | S | Inspect preview closed, then explicitly open for exact detail/status rows. |
| `test/normal_gateway_route_reattachment_test.dart:262` | D | Both running-away/completed-away canonical reopen scenarios retained; fixture explicitly holds history empty to test retained tools, not authoritative retirement. |
| `test/release_identity_test.dart:4` | S | Exact published release identity test replaces prior version's assertion. |
| `test/release_identity_test.dart:13` | S | Exact 2.1.32, base2175, upgrade floor and arm64 21752. |
| `test/release_identity_test.dart:42` | S | Published release workflow required floor2175. |
| `test/release_identity_test.dart:67` | S | Published PR floor and all four store-note files retained. |

Additional clean semantic hotspots, against unreleased 77413 (not unrelated refactoring):

| File / region | Class | Decision |
| --- | --- | --- |
| `chat_presentation_state.dart` binding | Q | Transfer visit registrations/identity aliases, never merge manual tool values across routes. Keep reasoning/draft binding unchanged. |
| `chat_presentation_state.dart` close | D | Configuration close clears registered tool visits; real route exit does not close the registry. |
| `chat_presentation_state.dart` tool accessors | S | Replace global manual-tool accessor with visit acquire/close and ingress alias API. Keep the existing pin type and bounds. |
| `chat_screen.dart` tool field/init/dispose | Q | One actual State = one visit, including while covered. No focus/pop notification resets. |
| `chat_screen.dart` learned-ID ingress | D | Publish identity through the registry so all live visits learn the link without sharing choices. Projection-local group aliases/tap callbacks still use that visit's pins. |
| `normal_gateway_application_session.dart` learned-ID sink | D | Call `aliasTool`; no admission, WAL, recovery, suffix, child or reasoning change. |
| `tool_activity_group_pins.dart` helper | D | Copy alias metadata only using existing bounded alias logic; no additional reducer. |
| `chat_expansion_lifecycle_test.dart` | S | Both start closed and are explicitly opened. Reopening resets tool choice only; reasoning choice and stable keys/run IDs remain. |
| `late_identity_stock_test.dart` | S | Keep all late-ID/detached schedules; new visits reset tool choice, then explicit open verifies retained canonical tool/status/prose. Separate ambiguous-ID and eviction/saturation controls remain. |
| `late_identity_sse_test.dart` | S | Same lifetime adaptation on actual SSE frames; retain identity/no-replay/eviction/ambiguity assertions and canonical row key. |
| `chat_presentation_state_test.dart` / `late_identity_tool_state_test.dart` | S | Acquire explicit visit pin stores; retain bounds/credential isolation and draft/clear/writer assertions. Add prebinding convergence tests in both directions. |
| `normal_gateway_route_reattachment_test.dart` added covered-route test | D | Real Navigator cover/pop preserves original State/open choice despite a second closed choice and late-ID update; true disposal/reopen resets, detail and one-submit assertions retained. |
| README unreleased section / implementation-plan architecture and pin paragraph | S | Update latest baseline and tool lifetime explicitly; keep prior integration report and historical evidence as historical. |

## Parent-test union and adapted oracles

Both parents' test declarations were enumerated **before editing** in `parent-test-declarations.json`; `test-union-audit.json` refines first-argument identities and records every difference. Declaration totals include group/helper declarations and parameterised loops, **not completed runtime tests**.

- Unreleased: 1,206 `test`, 673 `testWidgets`, 125 `group`; published: 1,064 / 593 / 125. Union: 2,015 distinct declaration identities including groups. No test file deleted, no skip added.
- Six prior labels are superseded by the published parent: progress/time wording; untouched auto-open/close -> untouched collapsed; verbose wording; obsolete auto-collapsed reopen case -> published manual/failure/empty coverage; running-auto-open -> running-closed preview; release identity2.1.31 ->2.1.32. The precise labels and new equivalents remain in the audit/source diffs. This is an explicit public contract change, not weakening data safety.
- Three public labels were **already superseded before this merge** by 77413: exact-nonce PUT retry -> rotated fenced authority; expired same-generation challenge -> renewed authority; held passive denial finishing before prompt -> stale denial cannot overwrite the concurrent grant. Existing 2.1.31 integration report documents these stricter protocols; this merge does not edit those production/tests.
- New declarations: the two-direction prebinding-visit unit loop and one covered-route widget case. Existing late-ID stock/SSE loops retain every detached/identity schedule. Collapsed name text is never used as an expansion oracle: actual controllers and exact body status/detail rows distinguish UI choice from retained data.
- The public completed-away fixture originally collided with the unreleased helper's automatic assistant-only durable history. Explicit `history=[]` keeps its intended retained-tool case; separate canonical-retirement tests still require optimistic tools to disappear on authoritative hydration. No canonical result/detail data is invented.

## Executed verification

Evidence directory: `/Volumes/Storage/Hermes/scratch/post-v2.1.32-neutral-integration`. Runner `verify.py` records exact commands, source hashes, per-suite/case identities, completed non-hidden `testDone` events, terminal `done`, exits and APK receipt. Overlapping/repeated runs are not added together.

All final gates ran serially against the same production/test source with TMPDIR `/Users/sam.russell/.hermes/cache/scratch`, JDK17 and the existing Android SDK. `verified-summary.json` records exact expanded commands and case identities. All 319 tracked library/test files still match their pre-gate SHA-256 values after compilation.

| Gate | Actual final result |
| --- | --- |
| Existing offline `flutter pub get --offline` | Exit0; no lockfile/dependency upgrade. |
| `flutter test --no-pub --concurrency=2 --reporter=json <47 exact focused files>` | **553 completed successes, zero errors/skips**, terminal `done.success=true`, exit0. Covers public cards/projection/scroll, both parent late-ID/route/draft/timeline/owner/recovery/epoch/unknown controls and read-only viewer wire tests. |
| `flutter test --no-pub --concurrency=2 --reporter=json` | **2,207 completed successes, zero errors/skips**, terminal `done.success=true`, exit0. Focused tests overlap this total and are not added to it. |
| `flutter analyze --no-pub --fatal-infos` | No issues, exit0, including production and tests. |
| `dart format --output=none --set-exit-if-changed <70 Dart files changed since published459>` | Zero changes, exit0. |
| `git diff --check 459022b93fe1e422cf03bee74862a9a4fefe4fe2` | Clean, exit0. |
| `flutter build apk --debug --no-pub` | Actual production Flutter/Android debug compile, exit0. No release signing material present or used. |
| `aapt dump badging` and `apksigner verify --print-certs` | Both exit0; debug identity `com.hermesagent.hermes_android.dev`, `2.1.32-dev`, code2175, all three native ABIs; Android Debug certificate. Not a production-signed or installed APK. |

Debug artifact: `build/app/outputs/flutter-apk/app-debug.apk`, 166,567,051 bytes, SHA-256 `bc7cd3f4772e4c35f348a231275e90313cc5aa381fbf86aa0c1aa8ee9dd86883`. `artifact-receipt.json` contains full badging, signer and source-hash checks.

Both stock and SSE late-ID tests now additionally hydrate via a hit-testable real Refresh action **without disposing the State**, verify an increased physical history-request count, retain the open pin through canonical row-key replacement, then separately close/reopen and require collapsed default before explicitly inspecting the retained completed tool/prose. This preserves within-visit alias continuity instead of replacing the old cross-visit oracle with a weaker data test.

Read-only repository-wide formatting reports the known **53** files (exit1). Every one is byte-identical to both77413 ande497d10; `repository-format-debt.json` records each path comparison. No blanket formatting was applied. Existing KGP migration and untranslated-message build warnings remain in the build log.

Earlier exploratory logs are retained: `initial-focused.jsonl` had121 successes/7 fixture assertion errors (assistant-only history intentionally retired the public completed-away tools; newly added raw stored-result `ok` assertions were not an existing rendered body contract). The fixture now explicitly tests lagging history and exact `Completed` body rows/retained tool identity. `second-focused.jsonl` passed42; strengthened same-visit hydration passed12. The first broad run passed all tests/build but exposed one new missing-braces lint; it was corrected and **all** final gates above rerun. Those overlapping/exploratory counts are not added to the final totals.

## Exactness and limits

- Public release identity remains `2.1.32+2175`, CI required base2175 and store codes21751/21752/21753. This is an unreleased merge, **not** a versioned candidate. Any future candidate must exceed the then-fresh published base (currently2175), not2174. No bump, tag, push, PR, release, production signing, install or live service/device action.
- `android/`, `server/`, `lib/main.dart`, timeline and insight models remain byte-identical to77413. `source-audit.json` records per-file Git blobs/SHA-256 and explicit path comparisons. Existing native/server test receipts therefore remain qualified unchanged-component evidence, not rerun/combined approval. A fresh debug APK is compilation evidence only.
- Parent's new CORE SPEC is **FAIL / REQUEST_CHANGES**, report `/Volumes/Storage/Hermes/scratch/spec-77413-core-nrkjtk4e/SPEC_REVIEW.md`: retained failed donor truncates/freezes the canonical suffix; namespaced donor reasoning loses its pin and lends it to independent current reasoning on the same mounted route. Neither was changed here. `reasoningPins` API/binding is frozen for its separate producer. Passing tracked tests do not negate the independent failures.
- Root navigation producer `dc8b6dc8b4823abe9a22640f88ce0d5980e0a353` remains unconsumed. Parent owns its subsequent integration. This merge neither fixes nor reverts the known ordinary-navigation/push-authority issue.
- Parent must integrate separate fixes, independently rerun fresh combined SPEC then QUALITY, and repeat full final gates before any publication. Prior component approvals and this neutral integration are not whole-source acceptance. No physical-device or killed-process push delivery is claimed.
