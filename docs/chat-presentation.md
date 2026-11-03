# Chat presentation

## Verbose Mode

With Verbose Mode off, you see user messages and assistant replies with successful
completion evidence. The transcript hides commentary, incomplete or failed replies,
tools, reasoning, delegated tasks, background reports and source diagnostics.
Approvals and input requests remain accessible in both modes.

With Verbose Mode on, you can inspect the retained detail. Tools, reasoning,
delegated tasks, background reports, notices and message metadata start collapsed.
Your expansion choices survive updates and lazy scrolling during the visit.
Closing and reopening the chat resets those choices. Covering a chat with a task
inspector does not start a new visit.

Machine-authored model/personality notices, automatic recovery, internal
notifications and recognised legacy automation messages use Background task cards,
not user bubbles. Process reports keep their Background process cards. Quiet mode
hides these details. See [internal-message classification](internal-message-classification.md)
for supported formats and the limits of old history without provenance metadata.

## Completion and saved history

A successful response receipt confirms received prose. An owned successful turn
terminal can confirm the current final response, but cannot promote earlier interim
commentary. Ordinary stream EOF, an idle gateway and a durable row ID do not prove
that an assistant finished its reply. A definitive failure revokes that response's
completion marker before storage cleanup finishes; admission stays blocked until
its existing recovery and persistence checks permit another prompt.

For saved assistant rows, quiet mode requires source-local completion metadata,
such as a successful status or `finish_reason: stop`. Some gateways omit that
metadata from saved messages. Quiet mode hides those rows, including older answers;
use Verbose Mode to read them. App-owned received replies survive route reattachment
while their owner remains alive. After an app restart, saved history must supply
its own completion evidence. REST/SSE received replies remain local to the chat
visit.

The app keeps saved and received Remote Gateway output as independent sources.
Verbose Mode labels them and can show repeated prose across the sources. A complete
`persisted_turn` receipt from an owned successful response, plus fresh history
containing all addressed rows and its completed final reply, can prove a handover
and retire the covered live copy. Matching text, an admission baseline or idle
status cannot prove correspondence. Older gateways or lagging history may retain
both sources. Quiet mode hides source labels; it does not infer identity. These
presentation rules do not remove raw messages or add synthetic request history.

After a successful REST/SSE reply, a stale history GET must not erase its received
body or receipt timeline. Handover requires the final response's own durable ID and
a saved, successful response with that same ID. The current SSE protocol supplies
no such message ID, so the app retains that reply for the visit. Matching text,
newer IDs and message order cannot establish correspondence.

## Current activity

One bar above the composer shows the current tool or other active work in either
mode. During tool use, it includes the tool name and the latest short context or
progress preview supplied by the gateway, for example **Using Terminal: Running
the regression tests…**. Exposed reasoning shows **Reasoning**, not the reasoning
body; status updates can show work such as compacting conversation context.

Both Remote Gateway and REST/SSE connections update this bar. REST/SSE reads
`delta.reasoning_content`, `hermes.tool.progress` and `hermes.status`; gateways
that do not emit these events retain the generic responding indicator. Reasoning
and status alone never count as a completed reply. Verbose Mode still controls
the transcript details, not whether the current activity is visible.

Saved tools and late updates from older delegated tasks do not start the bar.
Completion removes the active indicator. Stop hides it for that turn without
claiming the gateway has accepted another prompt. Failure and uncertain-outcome
notices use the same area without a typing spinner.
