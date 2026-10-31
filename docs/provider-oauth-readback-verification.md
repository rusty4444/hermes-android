# OAuth readback blocker verification

Scope: reviewer `on7a2bc5ca`, local branch `feat/provider-oauth-rc3`. No remote, login or configuration changes. The initial security commit left ARBs/generated localization untouched; subsequent integration merged both requested localization heads and regenerated from merged ARBs.

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

## Integrated localization and final gates

Preserved ancestry of OAuth localization `48507537d270115b4a471d034de8a748fdacbcb4` and Usage localization `1003963dc507c1d6eba605b9771f71660f938c43`. Reconciled OAuth screen conflicts by retaining scoped account verification and removing generic post-approval refreshes, while adopting typed localized reason notices and localized Settings/More entry points. Model/client typed reasons merged without discarding security changes.

Added actual translations in all 11 shipped ARBs for `provider_oauth_checking_account`, `provider_oauth_verification_unavailable`, `provider_oauth_verified_account` (typed `email` placeholder), `provider_oauth_credentials_unverified`, and `provider_oauth_account_status_unknown`. Removed obsolete signed-in/refresh-success keys to prevent misleading claims. Regenerated localization from merged ARBs with `flutter gen-l10n`. Generator still reports 35 unrelated untranslated messages per non-English locale; OAuth and quota scoped translation tests prove no English fallback in their scopes.

Final combined serial gate:

`flutter test --no-pub --concurrency=1 test/provider_oauth_test.dart test/provider_oauth_l10n_test.dart test/provider_account_usage_test.dart test/more_pane_test.dart test/chats_crons_navigation_test.dart test/application_root_navigation_authority_test.dart test/mtls_independent_transports_test.dart --reporter expanded`

**193 passed**. OAuth localization coverage includes actual verified/unverified approval rendering across every shipped locale, all OAuth ARB keys and placeholders, consent/errors and navigation entry labels. Raw local log: `/Users/sam.russell/.hermes/cache/scratch/oauth-integrated-focused.log`.

Final full `flutter analyze --no-pub --fatal-infos --fatal-warnings`: **No issues found**. Format checks across all eight touched source/test Dart files: **0 changes**. Staged and unstaged `git diff --check`: **passed**. An initial integrated test run exposed a missing localization delegate in the new redirect test wrapper; added the delegates and reran the complete focused gate successfully. No full suite was run.
