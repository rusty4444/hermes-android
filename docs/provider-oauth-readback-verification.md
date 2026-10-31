# OAuth current-account identity blocker verification

Scope: local `fix/oauth-account-final`, based on
`1a1b410bfbb790bde0dbf19941c386d9501e2ea0`. No remote writes, host/network,
login, credentials or configuration changes.

## Contract correction

The earlier matching-session verification claim was incorrect. Reviewer source
inspection of `hermes_cli/web_routers/oauth.py:893–898` and
`hermes_cli/web_server_oauth.py:232–239` establishes that approved session state
is historical. Session A continues to return A's `account_email` after host
account B replaces A; the catalog can simultaneously report `logged_in: true`.
Neither response identifies the current account, and repeating A is not an
independent identity read.

Removed the verified-account UI state and same-session identity re-poll. Every
approved provider now uses the existing translated approval/verification-unavailable
notice. The same-profile redirect-rejecting catalog refresh remains solely for
unverified credential availability. Catalog failures do not turn received approval
into a login failure. No unsupported endpoint, generic inventory/analytics read,
or model/config write was added. Device login, external browser, cancellation,
expiry and profile/client lifecycle contracts remain intact.

Preserved all 32 OAuth and 15 quota keys and their translations in every shipped
locale, including the now-unused verified-account key for localization stability.
The obsolete key is never rendered as a successful account claim.

## Regression coverage

- A approval reaches the screen; catalog is held; B replaces the current account;
  catalog reports logged-in; replay A still reports A. No signed-in claim or email
  is rendered, no identity re-poll is issued, and subsequent login remains usable.
- Missing identity, malformed/missing/logged-out catalog and catalog network error
  finish as approval/unverified without cancellation, code, spinner or late expiry.
- Held catalog success, no-identity success and network errors are ignored after
  profile replacement and disposal.
- Every shipped locale renders unverified approval for both Nous and Codex;
  translation/placeholder parity and quota coverage remain enforced.
- More Usage explicitly includes Provider sign-in first, with offline gating
  retained. Settings replacement tests settle lazy-list geometry and assert a
  hit-testable default button before starting held write/readback, preserving all
  selected-profile and injected-client-ownership assertions.

## Executed gates

- Serial focused gate: **214 passed**:
  `flutter test --no-pub --concurrency=1 test/provider_oauth_test.dart test/provider_oauth_l10n_test.dart test/provider_account_usage_test.dart test/more_pane_test.dart test/chats_crons_navigation_test.dart test/application_root_navigation_authority_test.dart test/mtls_independent_transports_test.dart test/provider_review_test.dart test/selected_profile_model_routing_test.dart --reporter expanded`.
- `flutter analyze --no-pub --fatal-infos --fatal-warnings`: **No issues found**.
- `dart format --output=none --set-exit-if-changed` over all six changed Dart
  files: **0 changes**. `git diff --check`: **passed**.
- Programmatic comparison against the base proves all 11 ARBs unchanged, each
  retaining all **32 OAuth / 15 quota** translations.
- Local logs: `/Users/sam.russell/.hermes/cache/scratch/oauth-account-final-focused.log`
  and `oauth-account-final-analysis.log` in the same directory.

The initial focused attempt caught an incorrect English substring in the new
regression expectation; corrected to the existing translated message before the
complete passing run. The parent full-suite log confirmed the Settings failure
was an off-screen missed tap, not a selected-profile contract failure. Both
reported integration files pass with their semantic assertions retained.

No production OAuth exchange or full suite was run for this patch. Parent
integration owns the full-suite rerun and independent review.
