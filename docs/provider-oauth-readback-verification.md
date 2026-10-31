# OAuth readback blocker verification

Scope: reviewer `on7a2bc5ca`, local branch `feat/provider-oauth-rc3`. No remote, login, configuration, ARB or generated-localization changes.

## Audited contract and behavior

Inspected installed `hermes_cli/web_routers/oauth.py` (`_status_card`, `_PROVIDER_STATUS`, `poll_oauth_session`) and `hermes_cli/web_server_oauth.py` (`_record_sign_in_state`). Catalog exposes credential state, not account identity. Nous poll exposes `account_email`; Codex/MiniMax/xAI do not expose an audited account identity. Source labels, token previews, model inventory and analytics must not stand in for account identity.

Verified success now requires explicit same-profile catalog `logged_in: true` plus matching nonempty Nous identity on a second approved read of the exact same session. Missing/changed identity, logged-out/malformed/missing provider status, errors, replaced authority and disposal cannot establish success. Other providers retain honest approval-with-verification-unavailable copy. Catalog rows distinguish reported credentials from verified identity.

Removed automatic generic inventory/analytics reads after approval. All remaining approval reads use the existing redirect-rejecting OAuth transport, preserving selected profile, dashboard prefix, cookie/proxy auth and mTLS. Usage continues to perform its own initial reads on navigation and explicit refresh; no OAuth model/config writes were added.

## Executed focused gates

- `flutter test --no-pub test/provider_oauth_test.dart --reporter expanded`: **38 passed**.
- `flutter test --no-pub test/provider_account_usage_test.dart --reporter expanded`: **28 passed**.
- `flutter test --no-pub test/mtls_independent_transports_test.dart --reporter expanded`: **5 passed**.
- `flutter analyze --no-pub --fatal-infos --fatal-warnings`: **No issues found**.
- `dart format --output=none --set-exit-if-changed lib/core/models/provider_oauth.dart lib/core/screens/provider_oauth_screen.dart test/provider_oauth_test.dart`: **0 changes**.
- `git diff --check`: **passed**.

Regression coverage includes held readback before success, changed/missing account, readback failure, logged-out/missing catalog status/provider, unsupported account identity, stale catalog/identity reads after profile replacement/disposal, and a post-approval authenticated 307 to another origin. The redirect regression checks `followRedirects: false`, expected prefix/profile/cookie on dashboard calls, no unexpected generic endpoint, no attacker-origin request and no success claim.

No full suite or production OAuth exchanges were run. An initial analyzer run found three test-only brace lints; fixed before the final passing gates.

## Localization integration handoff

No ARB/generated files changed. Suggested exact English messages and keys for the parent localization merge:

- `providerOAuthCheckingAccount`: `Approval received. Checking host account…`
- `providerOAuthVerificationUnavailable`: `Approval received; account verification unavailable. Open Usage to refresh account usage.`
- `providerOAuthVerifiedAccount` (`email` placeholder): `Signed in on the Hermes host as {email}. Open Usage to refresh account usage.`
- `providerOAuthCredentialsUnverified`: `Host reports credentials available; account identity unverified.`
- `providerOAuthAccountStatusUnknown`: `Host account status unavailable.`

Existing `Not signed in on host` text is unchanged. Remove obsolete approval refresh/signed-in keys during integration if no longer referenced.
