# Internal messages in chat history

Hermes deliberately stores some machine-authored messages with `role: user`:
strict OpenAI-compatible providers reject system messages inserted mid-history.
That transport role does not mean the person wrote the message.

## Presentation

`BackgroundReport.fromMessage` is shared by detailed chat, quiet conversation
filtering and delegated-task history. Recognised internal messages use the
existing read-only Background task card (Background process for process reports).
Cards start collapsed, preserve expansion during the visit and reset on reopening.
Quiet chat hides them. They never become the retry prompt or get Edit and resend.

The classifier does not rewrite roles, bodies, IDs, timestamps or model-request
history. Saved and received projections remain independent. Hidden and model-only
rows remain hidden. A server's `display_content` replacement takes precedence over
the raw carrier, including null and empty replacements.

## Server-annotated messages

These are the complete current non-human user-row display kinds found in the
backend source audit. Arbitrary content with a recognised annotation does not need
a legacy wording match.

| `display_kind` | Presentation | Producer examples |
| --- | --- | --- |
| `model_switch` | Background task | Model/provider changes |
| `personality_switch` | Background task | Persona changes and clearing an overlay |
| `auto_continue` | Background task | Automatic recovery after interruption |
| `internal_notification` | Background task | Gateway notifications, plugin/bot deliveries, automated wakes |
| `async_delegation_complete` | Background task | Single/batch results, child failures, manual cron results |
| `process_complete` | Background process | Process completions and process result batches |
| `hidden` | Not displayed | Model-only scaffolding, suppressed diagnostics and hidden control prompts |

`steer` and `skill_invocation` are human input. Unknown kinds are not treated as
authority. Terminal assistant `failed_turn` notices are not user-role machinery
and are not reclassified by this change.

## Legacy standalone formats

Older producers sometimes omitted display metadata. Compatibility matching uses
whole known envelopes or exact source constants, not blanket `[System:]`,
`[System note:]`, `[IMPORTANT:]`, XML, “Kanban” or “Cronjob Response” prefixes.

| Family | Audited backend producers |
| --- | --- |
| Complete model/provider and persona pivots | `tui_gateway/server.py`, `tui_gateway/agent_callbacks.py` |
| Network/output-limit continuations, reasoning-only/fragment/tool-call nudges | `agent/conversation_loop.py` |
| No-human compaction continuation and maximum-iteration summary request | `agent/context_compressor.py` |
| Standalone preserved todo snapshots, including pruned-skill footer | `tools/todo_tool.py`, `agent/conversation_compression.py` |
| Complete LCM Recent, Session Arc, Durable and Depth-N summary groups, optionally preceded by the preserved objective | `hermes-lcm/engine.py::LCMEngine._assemble_context` |
| Browser connect/disconnect and MCP reload notices | `hermes_cli/cli_commands_mixin.py`, `hermes_cli/cli_info_mixin.py` |
| Single/batch delegation results and early child failure | `tools/process_registry_notifications.py` |
| Process completion/failure/termination/lost/start-failure, watches, watch overflow and output heartbeat | `tools/process_registry_notifications.py`, `tools/process_registry.py` |
| Labelled cron and webhook delivery mirrors | `cron/scheduler_delivery.py`, `gateway/platforms/webhook.py` |
| Automatic standing-goal continuations, contract/subgoal/failed-gate variants | `hermes_cli/goals.py` |
| Recurring heartbeat and loop ticks, including stop conditions | `hermes_cli/heartbeat.py`, `hermes_cli/loops.py` |
| Late language-server diagnostics and worker recovery | `agent/turn_stop_gates.py`, `agent/kanban_turn_recovery.py` |
| Delegated output-contract correction | `tools/delegation_output_schema.py` |
| Imported-history opening placeholder | `hermes_cli/foreign_sessions.py` |

Quoted/code-fenced examples, ordinary mentions, generic bracketed text, incomplete
frames and sealed notices merged with a human follow-up remain human. Attached
memory, hooks, runtime notes, skill expansions, a pending model note and recovery
notes accompanying a *new* human request do not make that whole request internal.
Pure compaction summaries retain the existing hidden/public projection policy;
composite carriers must keep their server-projected human content.

LCM's unannotated summary group is different: `_assemble_context` emits either
`role: assistant` or `role: user` to preserve role alternation. A complete group
uses Background task presentation in either role (including the `agent` alias).
Recognition requires matching depth labels, numeric node IDs and complete
`[Expand for details: …]` footers, with only the producer's separator between
summaries. An optional preserved-objective prefix must lead into a complete group.
The full original body is retained on expansion. Ordinary long replies, quoted
examples, incomplete envelopes, appended human text, merge witnesses and explicit
public/human display metadata are not reclassified. A byte-identical copy remains
ambiguous; this is presentation compatibility, not a provenance guarantee.

An untyped row with an absorbed-message witness (the persisted
`absorbed_message_uids` column or its live counterpart) is not standalone.
Keep it human rather than guessing where an open-ended notification/result stops
and the absorbed human request begins. Explicit server kinds and public-content
projections retain their normal precedence.

### Compatibility limit

Text matching is a display heuristic, not authentication or provenance. A human
copy of a complete untyped machine message is inherently indistinguishable from
that message. Open-ended result/delivery envelopes can contain arbitrary output.
Arbitrary untyped webhook templates, plugin injections, bot/task prompts, custom
kanban notifications and other unrecognised producer text therefore remain human
unless the server annotates them. Do not solve missing provenance by hiding all
messages with a reserved-looking prefix. Producers should supply the appropriate
known kind (or `hidden`) when adding a new automated turn.

Bracketed personality/process compatibility stops at the first complete outer
frame, including when a human follow-up ends with an Android context footer or
`[yes/no]`. Ambiguous untyped output with unbalanced brackets remains human;
annotated reports do not have this limitation. Variable fields are scanned with
fixed literal boundaries rather than backtracking wildcard regexes. Multiline
delegation goals and process-watch attribution are supported.

The source audit also covered scheduled-job execution prompts, coalesced gateway
completion delivery, CLI handoff, Graph/Raft/Yuanbao automation and verification
hooks. Their typed forms are covered by the table above. Unannotated forms without
one of the complete supported envelopes are deliberately not guessed from prose.

## Regression fixtures

`tools/capture_internal_message_fixture.py BACKEND_ROOT` runs with the backend's
Python dependency environment. It captures actual producers, constants and
selected producer f-strings, stages them through `_stage_turn_user_message`,
persists them in disposable `SessionDB` and calls the real API client projection.
The fixture records its backend revision. Database access is restricted to the
sandbox and network connections are forbidden; no existing chat is inspected.
The capture supplies known display kinds when staging typed cases; it exercises
the real API projection, not an end-to-end run of both history serializers.
It supplies fixed timestamps and deterministic caller message UIDs so repeated
captures are byte-identical without changing any producer body or projected field.
The separate `merged_internal_background_messages.json` fixture runs real
consecutive-user repair and disposable persistence, then captures both the API
and Dashboard projection functions. It verifies that their surviving merge
witness keeps absorbed human follow-ups visible and owns the reply's retry.

`tools/capture_lcm_summary_fixture.py BACKEND_ROOT LCM_ROOT` separately captures
synthetic DAG nodes through the real LCM assembly method, disposable SessionDB
persistence, and both API and Dashboard projection functions. It records source
revisions and the engine source digest; no model calls or existing conversations
are used. This exercises projection functions, not complete HTTP serializers.

The tests check full-body preservation, source separation, quiet/verbose policy,
retry ownership, public/hidden precedence, quotes and human tails, CRLF bodies,
real ChatScreen cold-load/refresh/reopen behaviour and delegated-task cards.
Delegated coverage includes independent report pins across actual lazy eviction,
scroll-storage isolation, refresh, reopening and same-State controller replacement.
