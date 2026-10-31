# Sending while Hermes is working

The composer keeps **Stop** and **Send** as separate buttons during a response.
You can type a multiline message without waiting for the current run to finish.
Return inserts a newline; tap Send to submit.

## Remote Gateway

- **Send** queues your text as guidance for the current run using `session.steer`.
  It does not interrupt tools, cancel generation or start another `prompt.submit`.
- Hermes reads the guidance at a safe boundary. The acknowledgement means queued,
  not that Hermes has already acted on it. Output already in flight may continue.
- **Stop** still requests interruption, including while a Send acknowledgement is
  pending. Sending guidance does not replace or disable the Stop control.
- Guidance is text-only. Attachment and model changes remain gated while a run is
  active. Send also remains gated during initial preparation and reconnect recovery.
- On acknowledgement, only the submitted composer edit is cleared. Text you type
  or deliberately clear while waiting is preserved.
- If the gateway rejects guidance or does not support steering, the draft stays
  available. Wait for the response to finish, or use Stop, then send normally.
- If delivery cannot be confirmed after a connection failure or timeout, check the
  chat before retrying. The server has no idempotency key for steering, so the app
  never automatically retries it or falls back to a second prompt.
- If the run ends before its guidance acknowledgement arrives, the draft stays
  available with an unconfirmed-delivery notice. Check history before retrying:
  the late acknowledgement does not prove whether that guidance was consumed.

## Legacy REST and other non-steering transports

The legacy OpenAI-compatible SSE stream does not expose a steerable run handle.
Its active-send button is therefore labelled **Stop and send**: it closes the
current response through the existing Stop operation, then submits the captured
text as a new prompt in the same chat. It does not resend the previous attachments.
If stopping fails, the new prompt is not submitted and the draft is restored
unless you have already edited it. This is an interruption, not steering.

The separate Stop button still stops without sending the draft.

## Validation scope

Regression tests cover actual JSON-RPC frames against a loopback gateway,
acknowledgement and completion races, duplicate callbacks, newer edits, route
replacement, REST cancellation ordering and a 320 dp keyboard viewport at 200%
text size. These tests do not replace physical-phone acceptance testing.
