# Host-managed provider sign-in

Native entry points: **More → Usage → Provider sign-in** and **Settings → Provider sign-in**.

## Audited host contract

Source inspected: installed `hermes_cli/web_routers/oauth.py` and
`hermes_cli/web_server_oauth.py`. All paths are relative to the saved dashboard
origin/prefix, with the selected `profile` query on every request:

- `GET /api/providers/oauth` returns `providers` with `id`, `name`, `flow`, and `status.logged_in`.
- `POST /api/providers/oauth/{provider_id}/start` returns `session_id`,
  `flow: device_code`, `user_code`, `verification_url`, `expires_in`, `poll_interval`.
- `GET /api/providers/oauth/{provider_id}/poll/{session_id}` returns the exact
  session identity and `pending`, `approved`, `denied`, `expired`, `cancelled`, or `error`.
- `DELETE /api/providers/oauth/sessions/{session_id}` cancels a pending host session.

The current catalog supports device authorization for Nous, OpenAI Codex,
MiniMax and xAI. External/unknown flows are displayed but disabled. Anthropic,
Claude Code, Qwen and other external providers require host-side CLI setup.
`POST .../{provider_id}/submit` exists but unconditionally rejects all providers;
therefore the app does not invent a callback/manual-code submission flow.
Device codes are shown transiently for entry into the provider's own browser page.

## Security and lifecycle

Remote sign-in requires HTTPS and configured dashboard password or trusted proxy
authentication. Existing dashboard cookie/proxy/loopback auth and mTLS construction
are retained. No fallback transport is created after TLS identity failure. OAuth
requests reject redirects, preserve the selected profile and prefix, validate path
identifiers, and never show response bodies or raw exceptions.

Only strict HTTPS verification URLs without userinfo, whitespace, backslashes,
fragments or non-default ports can open through `url_launcher` in external-browser
mode, on explicit tap. Dashboard headers and client identity are never passed to
the browser. Provider tokens, token previews and raw error detail are neither
retained in models nor logged/persisted by this feature. Sessions and temporary
codes exist only in route memory and disappear on completion/cancel/disposal.

Polling is single-flight, no faster than the host interval, paused while the app
is backgrounded, and bounded by the shorter of host expiry and the host's
15-minute session TTL. A stale start is cancelled through its captured old client
before an owned client is closed; stale polls cannot update a replacement route.
Explicit cancellation failure is shown as uncertain, not as confirmed host abort.
Process death/network loss can prevent cancellation; host expiry remains final.

On approval, the app refreshes only the same-profile OAuth catalog through its
redirect-rejecting transport. An approved poll alone never establishes sign-in:
the matching provider must report an explicit `status.logged_in: true`. Only Nous
currently exposes account identity (`account_email` on the poll response); the app
requires that nonempty identity to match a second approved read of the exact same
profile/session before showing verified success. Other providers show **Approval
received; account verification unavailable**, not **Signed in**. Changed/missing
identity, logged-out/malformed catalog and failed readback also remain unverified.
Catalog credential availability is explicitly distinguished from verified identity.

No automatic generic model/analytics requests are made after approval: these do
not establish account identity and their generic transport follows redirects.
Opening a provider Usage screen triggers its existing controlled initial reads;
its Refresh action explicitly retries them. OAuth never calls model/config write
APIs. The host's Nous free-tier
replacement flow can itself change host defaults; the UI warns about this existing
host behavior rather than claiming token-only host side effects.

## Verification scope

`test/provider_oauth_test.dart` covers public model validation, URL/identity safety,
profile/prefix/auth wire behavior, redirect rejection, unsupported transport,
success/failure/pending/expiry/cancel, single-flight start and poll, stale/disposed
responses, background/resume, browser failure, TLS fail-closed retry and narrow
large-text layout. Fixtures are synthetic and based on the audited contract; no
production OAuth or provider token exchanges are run.
