# Issue #207: validated audit dispositions

The original AI-labelled report and its 3.0.1 follow-up contain 30 observations.
This candidate implements confirmed corrections and test gaps; it does not treat
the report as blanket security validation. Nothing here is a release claim.

## Scope and verification

- Baseline: `50ec30e10757e12b097b5b852d7a9589ccca6e75` (3.0.2).
- All 15 original H/M/L findings have corrections with adverse-order or response-contract regressions.
- The follow-up adds 10 corrected defects/coverage gaps, two disproved premises,
  two intentionally retained bounded behaviours, and one timing report not reproduced.
- The complete structured inventory is [findings.json](findings.json).
- Baseline strict analysis and the full 4,468-case Flutter suite passed, with no skips/errors.
  Candidate integration checks and independent review are recorded on the PR;
  component counts are overlapping and must not be added as a full-suite total.

## Finding-by-finding disposition

### H1 — fixed

The old transport Stop incremented _responseGeneration before interrupt, discarding every later submit onState callback. A valid nonterminal interrupt reconcile then reactivated _sending/_streaming after the scaffold had been cleared, but the real terminal was fenced out forever.

### M3 — fixed

Stop was visible after v2 submit admission, while session open, write-ahead persistence or submit ACK could still precede the first state callback. With _activeClientTurnId null, the old code selected legacy interruptPrompt and revoked the v2 callback generation.

### L5 — fixed

The old transport finally cleared _stopResponseInFlight without notifying the widget tree. Successful interrupt/reconcile paths often masked this by scheduling another setState; a held Stop error after disabled controls had rendered had no such state callback, leaving Send visually disabled after the boolean cleared.

### L6 — fixed

The streaming branch examined only nonempty composer text before returning. Staged attachments alone therefore led an enabled Send action to silently do nothing.

### M1 — fixed

Confirmed stalled HTTP 200/503 body and provisional-stop stalls. Apply a 60-second inactivity timeout to raw body events before UTF-8 decoding. Keepalives/tool/status/reasoning/fragmented bytes renew it; it is not a total-turn limit. Existing terminal authority, cancel-and-join, ownership, exactly-one callback and no automatic POST resend are retained.

### M2 — fixed

Confirmed false has_more plus a short pinned-root page returned root while a current lineage tip remained at offset 50. Removed that shortcut. Retain client zero-new/pin-bound exhaustion and every async authority fence; an untagged exact fallback now requires its terminal probe.

### L2 — fixed

Confirmed silent truncation with reported totals 0/1/3 and six real rows in response fixtures. This validates the response-contract defect, not a claim that a static stock server always miscounts. Removed total-driven termination; retain pin-bound zero-new window proof, requested-limit OFFSET advancement, deduplication, progressive snapshots, profile/query filters, cancellation and fail-closed maxPages cap.

### L3 — fixed

Confirmed an opaque ID containing slash, question mark, fragment, percent, spaces and Unicode escaped its path segment. Encode only the session ID using Uri.encodeComponent, preserving configured prefix and the exact paging query.

### L7 — fixed

Confirmed reset removed metadata but retained all secure bundles. Collect individually decodable saved IDs plus the sealed native binding; preserve raw pre-reset bundles, verify physical metadata removal before credential deletion, verify each deletion, restore exact raw bundles and metadata on failure, sanitize provider errors, and retain shared-list ownership/native mutation leases through settlement. Collect known certificate references only after confirmed commit; do not introduce a certificate plugin prerequisite on certificate-free/corrupt-key recovery. Regress same-ID queued replacement, lost/lying metadata ACK, delete ACK loss, failed verification/rollback and replayable native END.

### L8 — fixed

Confirmed false SharedPreferences setString acknowledgements were reported successful for create/rename/assign/unassign. Check the acknowledgement and retain a shared confirmed snapshot if cache repair also fails. Serialize reads/mutations across wrappers, fence the dirty key, and require a successful fresh physical baseline before a later mutation can save. Regress false/throwing writes, failed repair, retained/replacement readers and a later successful unrelated save. Actual Move, create and rename actions show safe localised feedback with Retry; confirmed placement and the original records survive rejection and physical reopen.

### L1 — fixed

Synchronous closed-owner invalidation, listener/flight cleanup, exact-socket fences and reentrant/queued callback fencing; preserve live replacement and open-owner rollback.

### L4 — fixed

Reject forgotten/foreign local clarify handles before RPC; fence late lock completions; preserve active peer batches and genuine legacy IDs.

### L9 — fixed

Validate owner/binding before mutating resume-only policy or stored-key mapping; preserve accepted durable resume-only behavior.

### M4 — fixed

Real StartupApp with getInitialShare returning a MethodChannel PlatformException leaves the Future.wait rejected and splash animating; regression records PlatformException stack through AndroidShareIntentService.initialize and _StartupAppState._initialize plus pumpAndSettle timeout.

### M5 — fixed

Real ProjectsGatewayClient/ProjectsRepository feeding mounted WorkspaceScreen marks unsupported projects.tree as confirmed empty. The original-source regression renders a false Unassigned metadata chip on the filed row; held stale unsupported also puts the filed chat in the actual Unassigned filter.

### V1 — fixed

Confirmed missing cross-run reclamation; added versioned process-held OS locks and next-video-stage reaper.

### V2 — fixed

Rollback reproduces cleanup StateError masking exact original codec PlatformException; original now wins while close retains independent failure/pending result.

### V3 — fixed

Inspected installed video_player 2.11.1; removed testing-only playerId/private-completer inference; public dispose success alone permits deletion.

### V4 — fixed

Shared raster/video/audio predicates align Assets kinds and card/viewer candidates; SVG is intentionally an image asset with inert text renderer.

### V5 — fixed

Reject WMV/ASF before I/O. Blanket FLV/F4V unsupported premise disproved: Media3 1.9.2 includes FlvExtractor and f4v MP4 brand.

### V6 — fixed

Direct raster helper handles mixed case itself; restored case-sensitive mutant fails on PNG.

### V7 — intentional

Two retained preview routes intentionally keep distinct native/file resources, pause covered playback, and never auto-resume. Native-dispose join is tested before deletion.

### D1 — fixed

Production limits are unchanged; the testing-only sink seam exposes real buffered bytes. Each cap regression keeps the other limit at 256 KiB, above the entire 128 KiB native output plus 16 initial bytes. Removing either guard alone fails only its matching regression; the other guard cannot mask the missing check. All 52 document tests pass after restoration. A collect-before-check mutant still throws but retains 65,552 bytes instead of 16 and is rejected by the retention assertion.

### D2 — fixed

Nine invalid unused entry names accompany valid selected main XML; both local and central names changed consistently, eliminating wrong-cause rejection.

### D3 — fixed

Coherent unused nested local record overlaps another stored entry. Positive control renders, overlap guard alone rejects fixture.

### D4 — disproved

Dart URI normalization preserves leading relative parent segments, including encoded variants; manual parent guard is live and retained.

### D5 — fixed

Complete two-sheet XLSX succeeds at cap 2 and rejects cap 1; removed cap passes old tests but fails new test.

### D6 — disproved

utf8.decode consumes leading BOM. Real parser BOM+declaration round trips succeed for every selected DOCX/XLSX/PPTX part.

### D7 — intentional

Retained immutable snapshot/off-isolate parse with fixed budgets; analytical extra-copy cost is not a measured 4x RSS guarantee.

### F-flake — not reproduced

Not reproduced in unchanged parent full baseline or this lane baseline/final focused runs; no deterministic fixture defect established, no test rewrite.

## Preserved limits

- No outcome is inferred successful from an idle server, and uncertain prompts are never automatically resent.
- The SSE guard is 60 seconds of body inactivity, renewed by every received body event; it is not a total turn deadline.
- Cross-run video reclamation is attempted on the next video preparation. Marked, unlocked old-process directories can be reclaimed; unmarked legacy directories remain untouched.
- Failed or pending native release retains its locked source; timeouts and route disposal do not prove reader termination.
- Covered video previews pause but retain their own resources and never auto-resume. There is no aggregate cross-card player cap.
- Parser copies stay within existing input/output budgets; no measured RSS, codec, battery or physical Android claim is made.
- Credential reset can clean known decodable IDs and sealed native bindings, not enumerate unknown keys lost from wholly unreadable historical metadata.
- The reported root-navigation flake was not reproduced; its assertions were not weakened.

See [preview evidence and design details](previews.md). Thanks to @Thaeland for
the original audits and explicit provenance/false-positive notes. Hermes Agent
assisted with reproduction, implementation, documentation and regression tests.
