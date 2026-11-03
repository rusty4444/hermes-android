# Encrypted mobile-push server companion

`server/mobile-push` is a distributable, opt-in Hermes plugin named **mobile-push**.
It is shipped with this Android repository but must be installed separately on the
server. Nothing in this change installs it, changes a running profile, opens the
operator's session database for writing or registers a real push endpoint.

## Deployment prerequisites and compatibility

- Python 3.11+; FastAPI, pywebpush, cryptography and dnspython versions within the
  ranges in `server/mobile-push/pyproject.toml`. Current Hermes plugin enablement
  submits a package-manager admission transaction that prepares these declared
  dependencies with the installation's existing requirements in a managed Python
  generation. Do not mutate the selected environment with raw pip/uv commands.
  See [Hermes package management][packages]. Both the dashboard and gateway/turn
  processes must run with the admitted dependencies; restart affected processes
  when a new generation is selected.
- A Hermes build providing the current observer hooks and plugin unload ledger.
  The historical integration suite used source revision `d923a5eb`: the real
  `PluginManager` loads the same physical source in two profile homes, preserves
  worker context, disposes each owner independently and reloads unchanged source.
- Dashboard mounts must run Hermes' async `_plugin_route_secret_scope` dependency
  and expose `agent.secret_scope.current_secret_scope_home()`. That host-stamped
  home, resolved after profile-name validation, is the sole request resource scope.
  An unscoped mount returns **503** before advertising capabilities or accessing a
  store; older hosts lacking this seam cannot load this API. A home override or
  process `HERMES_HOME` alone is not evidence of a vetted request scope.
- A running Hermes dashboard/API backend that sets a **verified**
  `request.state.session.provider` and `.user_id`. A legacy/shared dashboard token,
  gateway JSON-RPC token, arbitrary bearer token or client identity header is **not**
  a principal. If the installed authentication middleware does not supply that
  verified session for the Android client's credentials, the API returns **401**.
  Provision a compatible trusted authentication provider before enabling push.
- **Current host compatibility: the dashboard's launch profile only, in trusted
  `in_process` mode.** Current Hermes forces secondary-profile user plugins into
  out-of-process hosts. The forwarded request omits the verified session object,
  so this companion fails closed with 401 there, even if an in-process setting was
  requested. Hosted/multi-tenant and secondary-profile deployment is **not
  compatible** until a separately reviewed core seam forwards a verified principal.
  Earlier cross-profile fixture results below are not current-host acceptance.
  Do not forward identity through client headers, disable auth, weaken isolation,
  or change a pooled deployment to in-process just to make this plugin work.
- Lifecycle hooks must load in every process that executes the subscribed turns.
  The dashboard API alone does not run turns or start the sender. Separate dashboard
  and gateway processes must use the same profile home and local SQLite files.
- Android must explicitly opt in, use the built-in Google-backed or an external
  compatible UnifiedPush distributor, provide
  genuine Web Push `p256dh`/`auth` keys and decrypt RFC8291 `aes128gcm` messages. An
  endpoint URL alone is not an encrypted subscription. The built-in distributor
  uses standard VAPID Web Push against Google FCM without a Firebase-admin sender,
  Firebase project or separate Google credentials on this server.
- Outbound HTTPS/DNS and a valid trusted certificate at the push service. The mobile
  device also needs authenticated access to this API for confirmation/reconciliation.
  Local/LAN services need the exact operator exception described below. Production
  never accepts a user-provided CA override or disables certificate verification.

The source contract is documented by [observer hooks][hooks] and
[dashboard backend plugins][dashboard]. No Hermes core patch is included here.

[hooks]: https://hermes-agent.nousresearch.com/docs/developer-guide/observer-hooks
[dashboard]: https://hermes-agent.nousresearch.com/docs/user-guide/features/extending-the-dashboard
[packages]: https://hermes-agent.nousresearch.com/docs/reference/package-management

## Operator installation (not performed by this implementation)

This is a manual server runbook, not an Android installer. Updating the APK or
tapping **Refresh / retry** cannot install or enable this companion. The companion
ships in this repository's `server/mobile-push` subdirectory; do not assume a
catalogue entry or use `hermes plugins install mobile-push`. An external UnifiedPush
distributor is a separate phone transport, not this server plugin. After completing
server setup below, recheck availability from the phone, then explicitly enable
**Background notifications** and grant Android notification permission. See the
[phone setup guide](mobile-push-android.md).

Select the dashboard's intended launch profile and its current managed interpreter
explicitly (see the compatibility restriction above). The following are operator
instructions, not commands to run against an unrelated home.
Run them from the Android repository root and replace the absolute placeholders:

```sh
export HERMES_HOME=/absolute/path/to/selected/profile-home
export HERMES_PYTHON=/absolute/path/to/selected-hermes-environment/bin/python
export TMPDIR=/absolute/path/to/private/scratch
umask 077
mkdir -p "$HERMES_HOME/plugins" "$HERMES_HOME/plugin-data/mobile-push"
chmod 700 "$HERMES_HOME/plugin-data/mobile-push"
# Refuse/inspect an existing destination instead of blindly overwriting a live plugin.
test ! -e "$HERMES_HOME/plugins/mobile-push"
cp -R server/mobile-push "$HERMES_HOME/plugins/mobile-push"
"$HERMES_PYTHON" server/mobile-push/generate_vapid.py \
  --output "$HERMES_HOME/plugin-data/mobile-push/vapid-private.pem"
```

If the generator's cryptography dependency is absent, leave the policy disabled
and complete plugin admission below first. Resolve the newly selected managed
interpreter, then generate the key before enabling the policy.

The generator uses exclusive creation, mode 0600 and never prints private material.
Keep the private P-256 PEM in a backed-up secret file, not config YAML, source control,
chat, a command argument or an Android build. The public key is returned by the
capabilities API. Config and key must be owner-only regular files (0600 or stricter);
symlink files are refused. The private database directory is mode 0700 and databases
are 0600. Preserve their WAL files when backing up a running instance; prefer an
ordinary SQLite-consistent backup or stop the plugin first. Treat subscription URLs,
auth secrets, challenge payloads and stored session scopes as private server state.

Create `$HERMES_HOME/plugin-data/mobile-push/config.json` with mode 0600. This is an
**operator-owned file**, not a client-writable route or an arbitrary plugin setting:

```json
{
  "enabled": false,
  "vapid_private_key_file": "/absolute/path/to/selected/profile-home/plugin-data/mobile-push/vapid-private.pem",
  "vapid_subject": "mailto:operator@example.org",
  "principals": [
    {
      "provider": "actual-verified-provider",
      "user_id": "actual-verified-user-id",
      "session_ids": ["actual-durable-session-id"],
      "owner_all_sessions": false
    }
  ],
  "private_endpoints": []
}
```

Use principal values from the **trusted authentication provider**, not values
claimed by a client. Session IDs must be exact durable `sessions.id` values in this
profile's `state.db`; the plugin checks that database read-only. Missing grants deny
access. `"*"` is not accepted in `session_ids`. Only an explicit operator
`"owner_all_sessions": true` grants that principal owner-wide eligibility.
Automatic clients enrol with `session_scope: "authorized"` and no `session_ids`:
the live policy then covers current and future durable sessions without typing IDs
on the phone. Restricted grants remain restricted, including after ACL changes.
Legacy explicit subscriptions retain their fixed list and are never widened by
migration. There is no automatic parent/child lineage, runtime-alias or
sibling-profile inheritance. Under a restricted grant, a new durable identity
still needs an operator ACL update; owner-wide authorised subscriptions include it
automatically. An authorised subscription can be created before the first chat.

For a personal-server owner, the principal entry can instead be:

```json
{"provider":"actual-verified-provider","user_id":"actual-verified-user-id","owner_all_sessions":true}
```

This is an explicit operator decision, not a permission the Android app grants itself.

Run `hermes plugins enable mobile-push` for the selected launch home/profile (or
`hermes --profile default plugins enable mobile-push` for the default profile).
This admission step prepares the declared `pyproject.toml` dependencies and only
publishes the plugin selection if preparation succeeds. Keep the JSON policy
disabled until the key and ACL are ready. On a dependency conflict, inspect
`hermes pm status` and correct the requirements; do not bypass admission with a
manual install. After reviewing the key and ACL, set the JSON policy's `enabled`
to true. If a new Python generation is selected, restart the affected
dashboard and gateway/turn processes after draining active work. Otherwise use
supported live activation/reload, or a planned restart. Verify the API mount,
lifecycle hooks and sender worker are active; an enabled setting alone does not
prove process activation. User-directory plugins
are required: Hermes refuses automatic backend Python import from an untrusted
project directory.
`dashboard/manifest.json` declares `api: plugin_api.py`; its router is mounted at
`/api/plugins/mobile-push`. The tiny hidden dashboard bundle intentionally adds no UI.

The lifecycle runtime captures its profile home immutably at registration. The
dashboard router is mounted **once**, but resolves an immutable Profile for **each
verified request**, from the host's vetted secret-scope home (including the launch
profile). This companion-side isolation model does not override the current host's
launch-profile-only deployment restriction. It never derives paths from the raw
query, changes process environment, or keeps a shared mutable "current profile".
Capabilities, durable-session reads, registration/confirmation, events and DELETE
all use that request's policy and
`plugin-data/mobile-push/outbox.sqlite3`. There is no router-wide store/worker cache;
database connections are bounded and closed after each operation. DELETE remains
available for owned revocations after push is disabled, only in the vetted home.

Android explicitly forwards the saved connection's `gatewayProfile` as `profile`
on **every** push request, including capabilities, confirmation, revoke, event
paging and bounded authentication retries. The generic DashboardClient helpers do
not add it automatically. Local connection-binding/epoch checks still invalidate
held capability and handshake responses if the selected saved profile changes.

ACLs, endpoint exceptions, key path and enabled policy are re-read on operations and before sends;
update this JSON by an atomic private-file replacement. Enabling after a disabled
startup requires supported lifecycle-process activation/reload or a restart to
acquire hooks/worker. Disabling the JSON policy halts sends but keeps pending
bounded state until expiry. Unload stops this owner's worker; a forced reload
acquires a new owner, never another profile's worker. Managed Hermes interpreter
replacement must preserve admitted plugin
dependencies through package management; do not assume a one-off pip install
survives an update or inject a second site-packages tree into a running process.

### Optional exact LAN exception

Public HTTPS services are the default. For an operator-controlled private distributor,
use **both an exact lowercase host and exact literal IP addresses**, never wildcards
or CIDRs:

```json
"private_endpoints": [
  {"host": "push.home.example.org", "ips": ["192.168.1.40"]}
]
```

The TLS certificate must still be trusted and valid for that hostname. Every DNS
answer must be permitted. The same address under a different host is not permitted.
Unspecified, multicast and mapped/transition addresses remain refused. Tests use an
explicit `receiver.example.test` → `127.0.0.1` exception and a generated test-only CA;
that resolver fixture/CA injection is not a production setting.

## Registration fence upgrade

Deploy client and server together, draining/restarting **all** dashboard and lifecycle
processes on this source. Do not leave old code serving writes against the migrated
SQLite database. No live upgrade/deployment is performed by these changes.

The server adds `registration_revision INTEGER NOT NULL DEFAULT 0` transactionally.
Existing active/pending rows are moved once to `upgrade_required`: generation advances,
endpoint/keys/proof and queued deliveries are cleared, and the installation/owner and
revision floor are retained. An upgraded client's higher revision plus fresh nonce
can register that same installation and complete a fresh encrypted proof. Revoked
rows stay terminal, including across migration/restart. No revision or generation is
reset; tombstones are not pruned. Old clients' revision-less PUTs are rejected (422),
and upgraded clients reject a capabilities response without `registration_fence:1`
before requesting permission. Old pending proofs cannot activate after migration.

The revision comparison and registration update share `BEGIN IMMEDIATE`, after
external validation. Holding an old handler in DNS before commit, then activating a
new revision and releasing the old handler, must leave **all** new authority/events/
outbox unchanged. Closing the old TCP connection does not establish cancellation.
Lost post-commit acknowledgements still use native journal/revision recovery; this
pre-commit fence is separate from discarding stale Dart callbacks.

DELETE of an as-yet-uncommitted installation creates an owned, terminal tombstone
rather than returning 404. This also fences a first PUT whose handler commits after
disable. Existing-owner revocation stays available after operator grants are removed;
new tombstones require an admitted principal and available registration capacity
(429 leaves revocation explicitly pending on Android; no successful DELETE is
reported without a tombstone). A later re-enable/scope change uses a
new installation, never revives the revoked ID even with a larger revision. Server
404/410 delivery revocation likewise requires explicit disable/re-enable on Android.
Tombstones count toward `max_registrations`; do not delete them to reclaim capacity
while abandoned requests/credentials could still exist. Operators must provision
capacity for consent churn; this implementation does not offer tombstone garbage
collection or a cross-device revision-reset/recovery endpoint.

The isolated fence verification completed **100 server tests** on Python 3.11.15
against Hermes source `d923a5eb48`, including all three real-host tests and the eight
open/abandoned-socket pre-commit interleavings. The paired client completed **62
focused Dart push tests**, **1,721 full Flutter tests**, **28 native push JVM tests**,
clean full static analysis and a debug APK build. These are local fixture/build
results, not deployment or physical-distributor acceptance.

## Exact API contract (schema 1)

All routes require the verified session object. Identity is only the tuple
`(request.state.session.provider, request.state.session.user_id)`; no identity headers,
request fields, query parameters or service-token principal fallbacks are accepted.
Mutating JSON bodies are strict (extra fields denied), at most 32 KiB.

### `GET /api/plugins/mobile-push/capabilities`

```json
{"schema":1,"registration_fence":1,"session_scope_modes":["explicit","authorized"],"transports":["webpush"],"vapid_public_key":"base64url-uncompressed-P256-public-key","enabled":true}
```

Missing/disabled config or an ungranted verified principal yields `enabled:false`
and an empty public key. No verified session yields 401 even on this endpoint.
Invalid private config/key yields generic 503 rather than leaking secret details.

### `PUT /api/plugins/mobile-push/registrations/{installation_id}`

Automatic clients send the following body. `authorized` is an explicit consent to
the authenticated principal's current and future server-authorised durable chats;
it does not grant access or override operator policy.

```json
{
  "endpoint":"https://push-service.example.org/opaque-subscription-path",
  "keys":{"p256dh":"real-base64url-65-byte-P256-public-key","auth":"real-base64url-16-byte-auth-secret"},
  "registration_nonce":"fresh-client-base64url-random-nonce",
  "registration_revision":1,
  "event_kinds":["turn_done","turn_error","input","input_resolved"],
  "session_scope":"authorized"
}
```

Do not send `session_ids` with authorised scope, even an empty/null list. Conflicting
fields and unknown modes are rejected. Legacy explicit clients omit `session_scope`
(or set it to `explicit`) and retain the required non-empty list:

```json
{
  "endpoint":"https://distributor.example.org/opaque-subscription-path",
  "keys":{"p256dh":"real-base64url-65-byte-P256-public-key","auth":"real-base64url-16-byte-auth-secret"},
  "registration_nonce":"fresh-client-base64url-random-nonce",
  "registration_revision":1,
  "event_kinds":["turn_done","turn_error","input","input_resolved"],
  "session_ids":["exact-durable-session-id"]
}
```

Returns HTTP 200:

```json
{"generation":1,"status":"pending","registration_nonce":"fresh-client-base64url-random-nonce","registration_revision":1}
```

`installation_id` and session IDs are 1–200 ASCII characters from
`A-Z a-z 0-9 _ . : @ -`. Use a globally unique random installation ID. The nonce is
16–128 base64url characters; use fresh cryptographic randomness on **every** update.
`event_kinds` has 1–4 entries from exactly the four values above; explicit-mode `session_ids` has
1–128 exact durable IDs; duplicate scopes are rejected. Keys are validated as a real
P-256 point and a 16-byte auth secret, not merely plausible strings.

An update, including endpoint/key/scope rotation, advances generation, requires a
nonce different from the current one, immediately returns to pending and invalidates
all older queued deliveries/challenges. `registration_revision` is a strict integer
1–9007199254740991 and must exceed the stored high-water mark inside the authority
write transaction (409 for equal/lower). Nonces have no ordering meaning. Revocation
is terminal for an installation; new explicit consent must create a new random ID.
An existing installation belonging to another principal returns 404. Operator ACL
failure/non-durable scope is 403; malformed/unsafe subscription is 422; changed-body,
revoked or superseded nonce replay is 409; capacity is 429. No wildcard/default
session grant is inferred.

An exact replay of a committed PUT returns 409 because its ordinal is already
consumed. It does not mutate authority or delete queued ordinary hints. Lost PUT
or confirmation acknowledgements are recovered by the paired Android client's
native write-ahead journal: it atomically advances its durable revision, rotates
the nonce and performs a fresh encrypted handshake for the **same consented**
endpoint/account/session scope. No permission or expanded-consent grant is inferred.
The new generation invalidates old proofs and delivery authority; durable ordinary
events remain available through the authenticated event feed.

Nonce hashes are also retained as per-installation equality tombstones across
rotation/revocation, independently of event TTLs. A previously consumed nonce cannot
return even with a higher revision. They do not establish ordering: the monotonic
revision comparison in the mutation transaction is what fences a delayed handler
that never committed its nonce. Existing databases seed their current nonce on
open; previously discarded nonce history cannot be reconstructed.

The pending registration receives an **encrypted challenge hint** through its supplied
endpoint/keys. Until confirmation it receives no ordinary turn/input hints. Merely
registering a URL, reading its metadata from `/events`, or knowing an event ID cannot
activate it.

### `POST /api/plugins/mobile-push/registrations/{installation_id}/confirm`

```json
{"generation":1,"challenge":"challenge-from-decrypted-push-only"}
```

Returns `{"generation":1,"status":"active"}` only if the principal owns the current
pending registration, generation is exact, the proof matches in constant time and
the configured challenge deadline/current ACL permit activation. Successful
confirmation clears the proof hash. Invalid, expired, already-consumed, revoked or
superseded confirmations return 409 (a pending proof with current ACL removal:
403). Lost confirmation acknowledgements require the fresh fenced handshake above,
not replay of an expired/consumed proof. No clear proof is returned by PUT,
confirmation or events. Challenge proof is stored hashed; the clear challenge is
only in the private queued encrypted-push payload and is cleared on successful
send/confirmation/revocation/expiry.

### `DELETE /api/plugins/mobile-push/registrations/{installation_id}`

Returns `{"generation":2,"status":"revoked"}` (the actual next generation).
Revokes ownership's registration, clears endpoint/keys/challenge and invalidates its
queue. Repeat deletes return the same terminal generation without changes. The owning verified principal may
revoke after the operator disables push/removes its grant. Another principal gets
404; no session gets 401. Tombstones retain ownership/generation to reject replay.

Send and revoke/update serialize through a SQLite write transaction: **successful**
revocation cannot be followed by a newly initiated send of the old generation. A
busy in-flight send yields generic 503 instead of a false successful revocation;
retry with bounded backoff. Already accepted push messages cannot be recalled, so
Android must immediately revoke local consent and reject old generation/nonce hints.

### `GET /api/plugins/mobile-push/events?after=0&limit=100`

Automatic clients must additionally send `installation_id` and its current active
`generation`. These fields are required together. The server checks ownership,
active generation, live ACL, durability, event kinds and stored registration scope;
it echoes `installation_id`, integer `generation` and `session_scope` on every page.
The client rejects any mismatched/missing echo before accepting that page. Pending,
superseded or revoked generations cannot authorise event routing. Legacy unbound
queries remain supported for older explicit clients, which retain their local list.

```json
{
  "events":[
    {"cursor":2,"event_id":"opaque-id","kind":"turn_done","session_id":"durable-id","turn_id":"opaque-turn-id","created_at":1800000000,"expires_at":1800003600}
  ],
  "next_cursor":2,
  "has_more":false
}
```

`after` is a non-negative signed-64-bit integer cursor, exclusive. `limit` is 1–200
(default 100). Cursors are profile-database global but results and pagination are
principal-only; gaps are normal. Advance to `next_cursor`, follow `has_more` until
false and deduplicate by `event_id`. Only currently authorised, still-durable session
routes are returned. Expired/cancelled attention entries are omitted. No title,
content, command, arbitrary navigation URL or approval response token is returned.

`input`/`input_resolved` events carry `session_id` and observer `request_id` (optional
`turn_id` is absent when the upstream hook has no durable turn correlation). That
observer ID is **not** an RPC approval identifier: open the relevant session and
reconcile its authenticated current state; never construct/submit an approval from
it. A `challenge` event instead has `installation_id` and no session ID/turn ID.
It is metadata only and **never exposes the challenge proof**. Its installation and
principal scope are server-owned.

The authenticated events API is the routing authority; it is not an unlimited
transcript or a proof that an old attention request still exists. After a retention
window, missed hooks or connectivity loss, reconcile current authenticated chat state.

## Consuming client/server protocol smoke test

With Flutter dependencies fetched and the server test dependencies installed, run
from the repository root:

```sh
MOBILE_PUSH_DART_SMOKE=1 python -m pytest -q -s \
  server/mobile-push/tests/test_dart_contract_smoke.py
```

This opt-in test launches the production Dart `MobilePushApi` and `DashboardClient`
over loopback TCP against the actual Python router/models/store/runtime. It checks
authorised registration, future-chat events across cursor pages, generation-bound
responses, bounded login retry, rotation and revocation. Its test subscriber decrypts
real TLS Web Push and independently verifies VAPID. The password-cookie provider,
fixed disposable profile and decrypted-proof handoff are fixture seams—not installed
Hermes authentication, host profile resolution, Android connector or Google delivery.
The test is skipped in ordinary Python runs unless explicitly enabled.

## Push payload, hooks and delivery semantics

Database upgrades add a scope column defaulting to `explicit`; existing consent is
never broadened to `authorized`. Scope changes require a new user opt-in, fresh
installation and encrypted handshake. Endpoint renewal/recovery retains the selected
scope. Live ACL removal and durable-session deletion suppress future sends and
reconciliation; messages already accepted by a push service cannot be recalled.

The JSON plaintext encrypted using RFC8291 `aes128gcm`, with RFC8292 VAPID auth:

```json
{"schema":1,"event_id":"opaque-id","kind":"turn_done","generation":1,"registration_nonce":"client-nonce","expires_at":1800003600}
```

Only these fields are allowed; `kind:"challenge"` additionally carries `challenge`.
There are **no** session IDs, titles, chat/prompt/answer contents, commands, approval
codes, credentials or navigation URLs in the hint. `expires_at` is Unix seconds.
An accepted distributor response means only push-service acceptance, not device
receipt or that a user has read/reconciled anything.

- `on_session_end` requires durable `session_id`, explicit `turn_id`, boolean
  `completed`/`failed`/`interrupted`, and `turn_exit_reason`. Failed emits `turn_error`;
  completed emits `turn_done`; interrupted/incomplete/legacy payloads emit neither.
  `task_id`, model, platform and text are not copied into hints or routing records.
- `on_human_input_request`/`on_human_input_resolved` observe `approval`, `clarify` and
  `sudo` waits. Only durable session identity and observer request ID are retained.
  No `pre_approval_request` command payload is consumed. Resolved-first order is
  recorded as a tombstone so a later request cannot resurrect attention; terminal
  turns also cancel open attention. These hooks never answer, approve or deny.
- Hook enqueue uses bounded SQLite lock waits (25 ms per write attempt; durable
  session reads wait at most 100 ms). A separate **durable inbox** buffers observers
  during an in-flight network send, so the outbox's send/revoke lock does not drop
  normal concurrent turn completion. Inbox entries capture registration generations
  at observer admission and cannot adopt a later re-registration/consent. The worker
  drains inbox resolutions before initiating further hints. Disk failure, both databases busy or a capacity/expiry
  overflow can still lose a hint; hooks fail open and never block execution for
  network delivery. Reconcile chat state rather than treating push as a ledger of
  all possible runtime transitions.
- The profile-owned worker polls at one-second idle intervals. Committed outbox
  jobs/leases survive restarts. Leases are transactional and 30 seconds long;
  concurrent workers cannot double-send a claimed job. Up to five attempts use
  capped exponential backoff (cap 300 seconds), constrained by expiry. HTTP
  404/410 revoke the registration and advance generation; 408/429, transport and
  server failures retry. No response body is retained or logged.
- Before sending, recheck enabled policy, principal/session ACLs, current durable
  session, event kind consent, generation, attention state and expiry. Validate
  URL/DNS again on every attempt. HTTPS only, no URL userinfo/fragments/control
  characters/redirect following. Every answer must be globally routable unicast
  (or an exact private exception), excluding mapped/transition address tricks.
  Bounded DNS resolution uses two-second A/AAAA lifetimes; the verified address
  is connected **directly** without DNS lookup again, with original-host TLS SNI
  and certificate verification. No environment proxy, cookies, Hermes bearer token
  or client identity headers are sent to the distributor. Response status/header
  reads have a total deadline and an 8 KiB cap, including slow-drip peers.
- Normal events expire after one hour; challenges after five minutes. Retain at most
  10,000 events, 10,000 inbox rows and 10,000 attention tombstones; tombstones expire
  after two hours. At most 256 registrations (including revoked tombstones) per
  profile bound state/abuse without allowing generation reuse. Outbox rows are
  bounded by retained events × registrations; successful/exhausted rows retain only
  dedup metadata until their event expires. Old cursor gaps/expired events are not
  replayed indefinitely. Physical SQLite allocation is reused, not automatically
  shrunk; an operator may perform ordinary offline SQLite maintenance if needed.
- Delivery is **at least once**, not exactly once: a crash after distributor
  acceptance but before the SQLite commit can cause a retry. Clients must dedup
  persistent `event_id`, validate schema/generation/nonce/expiry and current local
  opt-in, and reconcile routing over the authenticated API. Cancellation cannot
  retract a push already accepted by the distributor; resolved/current state wins.

## Reproducible tests

From the repository root, use an isolated environment and an explicit scratch path:

```sh
export TMPDIR=/absolute/path/to/private/scratch
uv venv --python 3.11 "$TMPDIR/mobile-push-tests"
uv pip install --python "$TMPDIR/mobile-push-tests/bin/python" './server/mobile-push[test]'
"$TMPDIR/mobile-push-tests/bin/python" -m pytest server/mobile-push/tests -q \
  --basetemp="$TMPDIR/mobile-push-pytest"
"$TMPDIR/mobile-push-tests/bin/ruff" check server/mobile-push
"$TMPDIR/mobile-push-tests/bin/ruff" format --check server/mobile-push
```

The real-host integration tests additionally require an inspected Hermes source
checkout and its installed dependencies (these variables are read-only inputs):

```sh
export HERMES_AGENT_SOURCE=/absolute/path/to/hermes-agent-source
# Dependencies used by the inspected Hermes manager/loader on Python 3.11:
uv pip install --python "$TMPDIR/mobile-push-tests/bin/python" ruamel.yaml python-dotenv rich
# Optional fallback for dependencies already in a selected Hermes environment:
# use the SAME Python minor version as the test interpreter, not a 3.14 site
# directory with a 3.11 interpreter (compiled extensions are not interchangeable).
export HERMES_AGENT_SITE_PACKAGES=/absolute/path/to/matching-hermes-environment/lib/python3.11/site-packages
# Repeat the pytest command above with these variables set.
```

No source checkout means the host integration tests are explicitly skipped;
release/review verification requires the full suite with zero skips. The
once-mounted real-dashboard regressions switch two disposable homes with opposite
policies in both directions, distinct VAPID keys, colliding installation/session
IDs, independent proofs/events/outboxes, disabled-profile revocation, policy/ACL
reload and read-only durable-session checks. Each operation is also held across a
concurrent request for the other home. A paired real PluginManager/worker test
checks that each lifecycle owner's hooks, sends and teardown match the same files
used by the once-mounted dashboard routes. Fixture authentication supplies the
verified session; no test claims an installed provider automatically does so.

The paired profile-scope revision was verified with **116 passed, zero skipped**
on Python 3.11.15 against Hermes `d923a5eb`, including all 19 real-host tests. The
ordinary crypto tests use an actual TLS loopback receiver. Earlier pre-profile
baselines ran with 80 passed on both Python 3.14.7 and Python 3.11.15.
The fenced protocol extends these with a real uvicorn/FastAPI/SQLite loopback test
matrix: old pre-commit handler released after recovery, endpoint renewal, disable,
or fresh consent, with both open and abandoned TCP connections. Snapshot assertions
cover authority, events and outbox after another Store open/restart. Additional
negative tests cover missing/coerced/equal/lower/overflow revisions, nonce ordering,
terminal revoked IDs, and upgrade of the actual previous database schema. Test-only
uvicorn is included in the `[test]` dependencies. A Starlette TestClient/httpx
deprecation warning is upstream, not a skipped test.

The receiver uses real pywebpush encryption, independently decrypts with the generated
subscriber private key/auth secret, verifies the VAPID JWT signature/audience and
confirms registration using only the decrypted challenge. It exercises encrypted
input/resolution/turn hints and authenticated event-ID routing. DNS fixtures are
explicitly patched to a loopback address authorised by the operator exception; tests
do not pretend that a public distributor or a physical Android device was contacted.
Other tests cover missing/forged/foreign principals, session ACLs and lineage denial,
rotation/revocation/expired proof, dedup, queued attention races, retries/leases and
restart, busy-inbox persistence, SSRF/mixed answers/pinned connect, redirects,
permissions and safe generic failures.

**Still unverified deployment acceptance:** install/trust/auth-provider configuration
on the intended server; loading hooks in its real turn processes; a reachable genuine
UnifiedPush distributor; the Android connector's production subscription/decryption
and authenticated confirmation; delivery with a real background/killed process,
notification permissions, lock screen and battery constraints. No claim of deployed
or physical-device success is made by the local suite.
