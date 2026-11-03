# Provider stack review — local only

## Scope and ancestry

- Integration branch: `fix/rc-provider-stack`, worktree `/Volumes/Storage/Hermes/workspace/android-rc-providers`.
- Original PR237 `7528e5966fa528d0f2f8b1b8a1f40b71260cbec5`; PR238 includes `25ab78c3decf03c0759d60ae3c4a06b47ca452bd` and `55e0aa551d7d2966cc4af2ddf35bd1d380743d3c`. All original contributor commits and authors remain ancestors.
- Current main `81e99b2098cf07ca459452efd5adc3573453373c` merged with original238 in `32024165ab5e22dde921b7025722cae47b2f74e1`. Conflicting inherited PR235-era files reconciled to current main, not stale stack versions. `0e684e6e3c54a74d8d533c813853eb24c90f0cf8` removes the now-unreferenced original PR235 portal screen; parent must integrate its independently reviewed PR235 implementation afterwards. No other worktree touched.
- PR237 repair: `8419f8179e2ec474a41de591f93f08553094aa71`; follow-up discovery fix `05447fff`.
- PR238 repair: `b984d4bb89d7d5af2087ed795751f368301aae67`.
- Repair commits share contracts/l10n and are intended as an ordered integration stack, not independently cherry-picked standalone replacements for original PRs.

## Findings and changes

1. Provider keys had no real consumer and were stored plaintext in global SharedPreferences. Removed entry/storage/status claims entirely. Read-only usage pages explicitly direct credential setup to Hermes server. No new direct provider requests or credential fields.
2. Provider detection incorrectly called API-server `/api/model/options` and read `id` rather than the dashboard's canonical `slug`. Uses existing owned dashboard client, normalized origin/prefix/proxy/auth/mTLS and lazy single-flight More discovery. Lazy opening also permits retry after a prior unavailable probe.
3. Catalogue join lost retired models and invented zero usage and “Free” prices. Analytics are now independently filtered by provider, keep all recorded models, and show estimated/reported cost separately; missing is `—`, zero is `$0.0000`, never “Free”. Claims no longer mention credits/account balance/model pricing.
4. Auxiliary endpoint was coupled to main-settings load, swallowed write errors, falsely announced success, used unsafe late setState, permitted overlapping saves/reset, and could clear custom endpoint context. Separate optional child load, lifecycle fences, screen-wide single-flight writes, `ok:true` requirement and exact assignment readback now gate updates. Custom endpoint rows are read-only and unsupported endpoint providers are excluded. No API-server auxiliary methods or unneeded WebSocket wrappers.
5. New copy translated across all 11 ARBs and generated localisation outputs; provider names/task identifiers remain canonical. Narrow/large text and Japanese usage covered.

## Read-only backend audit

Source `/Users/sam.russell/.hermes/hermes-agent`, revision `bf0203a794a07aac3ff764972ab9087baa4e4f4e`:
- `hermes_cli/inventory.py:76` `build_models_payload`: canonical model-options providers.
- `hermes_cli/web_routers/analytics.py:304-405`: recorded `{models, totals, period_days}`; models include provider, model, sessions, input_tokens, output_tokens, estimated_cost, actual_cost. No account credits/pricing contract.
- `hermes_cli/web_routers/models.py:219-269`: auxiliary task rows with base_url, plugin metadata/inherit_from/effective.
- `hermes_cli/web_routers/models.py:376+`: assignment POST can return HTTP 200 `ok:false` with expensive-model confirmation.
- `hermes_cli/web_server_config.py:818-888`: task/reset semantics; same-provider blank endpoint does not necessarily clear a stale endpoint. Custom endpoint rows deliberately not edited by incomplete mobile picker.

No live server mutations, model routing changes, remote writes, GitHub comments, pushes or releases.

## Reproduction and logs

SDK Flutter 3.44.0 / Dart 3.12.0, matching main CI. Commands from owned worktree:

```sh
flutter pub get
flutter gen-l10n
flutter analyze --no-pub --fatal-infos
flutter test --no-pub --reporter=expanded test/provider_review_test.dart test/more_pane_test.dart test/workspace_screen_test.dart test/settings_update_controls_test.dart test/active_scope_refresh_test.dart test/browser_refresh_authority_test.dart
flutter test --no-pub --reporter=expanded
```

Logs under `/Users/sam.russell/.hermes/cache/scratch/`:
- `providers-analysis-initial.log`: 7 errors, 4 warnings, 3 infos at interim main merge; original PR235 screen remained without its helpers. Removed instead of duplicating parent's review.
- `providers-analysis-2.log`: 3 infos; `providers-analysis-3.log`: 1 info; fixed.
- `providers-analysis-final2.log`: zero issues at final code revision.
- `providers-focused-final2.log`: 134 passed, zero failures at final code revision.
- `providers-full-final.log`: first combined full run: 4836 passed, 11 failed (8 overlapping scoped refresh cases, 1 browser archive refresh, 2 workspace scope-loading cases). Eager discovery polluted dashboard mock request order. Fixed production discovery to lazy More rather than relaxing tests.
- `providers-full-final2.log`: **4847 passed, zero failed, zero exception markers, exit 0** in 09:43 at `05447fffbec91f16d29edc51260bd06e1a2a26b6`. All 19 Dart files changed against current main pass `dart format --output=none --set-exit-if-changed`; `git diff --check` clean. Subsequent commit contains this evidence document only.

## Deliberate limits / follow-up

- No account credit balance or direct provider authentication, because no audited contract/consumer supports them.
- No broad reset-all action: the old action cleared every built-in/plugin auxiliary pin and endpoint without confirmation. Current UI edits individual supported task routes; custom routes stay read-only on mobile.
- Expensive-model confirmation is not bypassed: rejected guarded writes show optional-settings failure; use server UI for explicit confirmation.
- No on-device APK/native build requested or performed. Widget and Dart verification do not establish phone runtime behavior.
- Full parent integration with independently reviewed PR235 still needs rerunning the full gates.
