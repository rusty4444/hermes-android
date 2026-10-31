# Hermes mobile-push companion

Opt-in encrypted Web Push delivery for Android UnifiedPush distributors. This is a
separately installed Hermes plugin, **not a running service or a live installation**.
No FCM dependency. Notifications are hints, never approval or execution authority.

See [installation, protocol and security notes](../../docs/mobile-push-server.md).

```sh
export TMPDIR=/absolute/path/to/private/scratch
uv venv --python 3.11 "$TMPDIR/mobile-push-tests"
uv pip install --python "$TMPDIR/mobile-push-tests/bin/python" './server/mobile-push[test]'
"$TMPDIR/mobile-push-tests/bin/python" -m pytest server/mobile-push/tests \
  --basetemp="$TMPDIR/mobile-push-pytest" -q
```

The ordinary suite uses synthetic profile databases, trusted fixture identities and
an explicitly allowed TLS receiver on loopback. Optional real Hermes manager/loader
tests run when `HERMES_AGENT_SOURCE` is set (see the full guide).

## Session selection and generation-bound reconciliation

Capabilities remain schema 1 and advertise
`"session_scope_modes": ["explicit", "authorized"]`. The registration revision
fence and encrypted nonce/generation challenge are unchanged.

- **Explicit (legacy default):** omit `session_scope`, or send
  `"session_scope": "explicit"`, with 1–128 unique exact `session_ids`. Every ID
  must be durable and allowed by the authenticated principal's operator ACL.
- **Authorized:** send `"session_scope": "authorized"` and **omit** `session_ids`.
  Null, empty lists and conflicting fields are rejected. An admitted principal
  can enroll before creating its first session; current and future durable
  sessions become eligible only while permitted by the live operator ACL in the
  selected profile. This does not grant ownership: restricted session lists stay
  restricted; only operator-configured `owner_all_sessions` permits all durable
  sessions. No wildcard, parent-session inheritance or token/header identity
  fallback is supported.

Authorized clients reconcile with:

```http
GET /api/plugins/mobile-push/events?installation_id=PHONE&generation=1&after=0&limit=100
```

Both binding parameters are required together. The installation must be an exact
valid ID and generation a positive decimal integer within signed 64-bit range.
Only an owned, active registration at that generation can read a bound page.
Successful pages (including empty pages) echo `installation_id`, integer
`generation`, and `session_scope`; events are filtered by the registration's
session scope, subscribed event kinds, current ACL and current durability. Bound
pages omit challenge metadata. Cursors advance across filtered rows; use
`next_cursor` and `has_more` rather than assuming every stored event is visible.
Pending, revoked and stale generations return 409; missing/foreign registrations
return 404. Unbound legacy event requests retain their prior response format.

Existing databases migrate to `session_scope='explicit'`, without broadening
subscriptions or resetting revision/generation fences. Renewals must resend their
intended scope, fresh nonce and higher registration revision. Confirmation,
enqueue, send and reconciliation recheck scope; normal events require a durable
session at enqueue and send. DELETE tombstones remain terminal, including when
DELETE beats the first PUT. No live deployment is performed by these tests.
