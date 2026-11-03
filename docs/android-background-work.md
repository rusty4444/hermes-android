# Android background work

The background features first shipped in v2.1.31. Version 3.0.0 retains them,
hardens lifecycle and account authority, and adds simpler optional push setup.
Confirm a phone's installed version in Settings → About; a local build or
passing suite does not establish which build that phone runs.

## Keeping an active chat connected

Normal Remote Gateway turns belong to the application, not the open chat screen.
Leaving a chat detaches its view without cancelling its submitted turn. Reopening
that chat attaches to the retained text, exposed reasoning, tools and requests.
You can run different chats at the same time. Duplicate views of one chat share
send admission and its transport.

The timeline presents assistant text and protocol-exposed reasoning between the
tool batches where they arrived. A later update to a tool changes the original
card rather than moving it to the end. This is a presentation view, not extra
messages inserted into the server transcript. Reasoning that the server does not
expose is never inferred or displayed.

When Android backgrounds the app during unresolved work, one foreground service
protects the active connection. It is shared by active chats, not one service per
chat. Quiet chat-specific ongoing notifications identify the work and open its
chat. The native foreground-service disclosure is separate from optional chat
notifications.

In **Settings → Background work**, **Keep chats active in the background** controls
this protection. A stored choice must be loaded before protection can start.
Turning optional notifications off does not hide Android's required service
disclosure. Android notification permission is still required for ordinary chat
notifications.

When a connection uses the stock Hermes gateway's API-server transport
(REST `POST /v1/chat/completions` + SSE), a send registers as an active turn
for its whole streaming lifetime, so the same protection engages while the
turn is in flight. This raises process priority while backgrounded; it does
not survive force-stop, Doze kill or an OEM battery killer, and on this
transport there is still no durable run to reattach to after a real process
death (tracked in #149).

This is not a guarantee of uninterrupted networking. Doze, network changes,
manufacturer battery policies, low memory and process termination can interrupt a
connection. The battery-settings button opens Android settings; it does not grant
an exemption or promise that selecting Unrestricted solves every restriction.

## Reconnect and process restart

The app does not resend a submitted prompt after a disconnect. Recovery
resumes the durable server session and reconciles its authoritative history. A
running or unknown server status is not treated as a successful final response.
A proven-idle turn with no recorded terminal outcome becomes inactive with an
outcome-unknown status and no success/failure alert. Recovery observations captured
before the submit wait finishes cannot settle its later turn, even when delivered
after acknowledgement.

The app stores a minimal pending-turn receipt for restart recovery. It does not
journal the prompt, password, approval answer or secret in that receipt. Retained
live text and tools are in-memory presentation state; after process death the
server's durable history is the source of truth. While a live copy is retained,
replacement requires a complete valid `persisted_turn` receipt from that turn's
owned successful response and fresh history containing all addressed rows and its
completed final reply. Without that proof, or while history lags, independently
sourced copies can remain; do not resend an uncertain prompt. Loading older
history does not discard a still-retained turn.

Without an enabled push transport, a terminated app cannot learn
about completion until it runs and reconnects. Android Force stop blocks background delivery and is not a supported way to test
background push.

## Scheduled-job messages in chat history

Recognised scheduled-job setup appears as a neutral **Background task** card,
not a message attributed to you. The card starts collapsed in Verbose Mode and
is hidden in conversation-only mode. Expanding it retains the complete recorded
prompt, including loaded skills and run context. This changes presentation only:
stored roles/content and model request history remain unchanged, and generated
setup is not selected as the prompt for Regenerate response.

Compatibility matching covers the complete current cron hint and older skill
scaffolds attached to a legacy cron-run message identity. A skill header alone
in an ordinary chat is not enough. Explicit human/public/hidden annotations and
available merge witnesses take precedence; normal follow-ups remain user input.
Text matching is not authenticated provenance, and an API that omits annotations
cannot distinguish a byte-identical human copy from generated setup.

## Optional encrypted background notifications

Background notifications are a separate opt-in for server-originated hints when
a live socket is unavailable. In 3.0.0, enable them in the saved connection's
Settings and grant Android notification permission. Automatic subscriptions
follow the verified login's authorised current and future durable chats; old
selected-session consent is not widened without disable/re-enable.

Both phone transports require the separately installed, enabled and
operator-authorised [server companion](mobile-push-server.md), its private VAPID
key, live policy grants, and active API plus turn-hook/sender worker. A trusted
authenticated dashboard login is required; a shared API bearer token or a
client-supplied identity header is not a substitute. The phone's retry action
cannot install server software.

On phones with working Google Play Services, the built-in Google-backed
transport needs no Firebase project, Firebase credentials or separate distributor
app. Google-free phones need a compatible external UnifiedPush distributor,
available as the advanced alternative. Neither transport removes the server
prerequisite. See [Android push setup](mobile-push-android.md) for registration,
privacy and supported host/profile limits.

The encrypted endpoint challenge must complete before activation. Subscription
renewal, revocation, account edits and recovery must preserve generation/nonce
fences; old proofs and notification taps cannot regain authority after disable.
Lost registration responses and expired pending proofs must be recoverable without
asking the user to approve a new account or a broader scope.

Push carries an opaque event hint, not chat contents, a command, or approval
authority. The app resolves the hint through the authenticated server API and
checks current consent again before opening the chat. Push does not submit a prompt or answer an approval without user input. Disabling push removes local authority
first; a failed server revoke remains pending for a later authenticated retry.

The inspected Hermes isolated plugin host does not forward the trusted ASGI
session required by this companion. That deployment fails closed until a trusted
core integration seam is available. Read the server guide before installation;
this repository does not install a live plugin or configure a distributor.

## Acceptance checks on a phone

Confirm the installed build in **Settings → About**, then test against the intended
Gateway and record the phone model, Android version and battery policy.

1. Start one turn, leave its screen, return and confirm it was submitted once.
2. Background and lock the phone during work. Confirm one foreground-service
   disclosure and a quiet ongoing entry for the active chat.
3. Tap that entry with another route open. Confirm the intended chat is focused
   without a Flutter error, duplicate submission or stale-account navigation.
4. Start a turn in each of two chats. Completing one must not stop protection for the
   other. When all work settles, ongoing entries and protection must stop.
5. Interrupt networking and restore it. Confirm recovery does not resend the prompt.
   When a complete valid `persisted_turn` receipt from the owned successful
   response and fresh history cover every addressed row and its completed final
   reply, confirm the covered live copy is retired in favour of those saved rows.
   Without that proof, independent copies can remain; do not resend an uncertain
   prompt.
6. Test protection and optional notifications as separate controls. Deny notification
   permission, grant it later in Android settings, and return to the app to check
   that permission state refreshes without another unsolicited prompt.
7. If push is configured, test endpoint renewal, a restarted app during pending
   registration, completion with the app process absent, expired proof recovery,
   disable/re-enable and stale notification taps. Do not call a foreground-only
   notification test evidence of killed-process distributor delivery.

For a disposable emulator and labelled local fixture, use the
[developer smoke test](android-background-smoke-test.md). That fixture performs no
model inference and is not a production Gateway or distributor acceptance test.
