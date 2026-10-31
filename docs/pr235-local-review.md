# PR235 local repair — backend contracts

Base integrated locally: `81e99b2098cf07ca459452efd5adc3573453373c` (3.1.7+3020).
Original review ancestry: `1db1887b` → inherited-edits checkpoint `df166c94` → main merge `78249309` → repair commit.

## Backend source inspected (read only)

Hermes source checkout `/Users/sam.russell/.hermes/hermes-agent`, commit `bf0203a794a07aac3ff764972ab9087baa4e4f4e`:

- `hermes_cli/web_routers/status.py:749–793`: `/api/portal` returns flat `logged_in`, `free_tier`, `account_tier`, `provider`, `features: [{label,state}]`. No nested auth/subscription/tool_gateway, balances or credits. Free-tier tokens are not signed-in accounts.
- `hermes_cli/web_routers/analytics.py:80–155`: usage has `period_days` and totals `total_sessions`, `total_input`, `total_output`, `total_estimated_cost`, `total_actual_cost`.
- `hermes_cli/web_routers/analytics.py:304–417`: models are recorded provider-qualified rows, with `estimated_cost`, `actual_cost`; not the available-model catalogue or model prices. Do not deduplicate by model name, inject unused catalogue models, equate missing with zero, or label recorded zero as Free.

## Repairs

- Removed unused plaintext Nous key entry, its reads/writes, controller leak and unsupported success messages. Connection initialization deletes only the obsolete preference without reading its value. Rejected/thrown deletion fails initialization honestly; unconditional retry handles the plugin's optimistic cache eviction.
- Screen is read-only; only three dashboard GETs. Existing dashboard authentication, prefix, selected profile and client-certificate settings are retained. No config, authentication, model selection, or routing writes.
- Independent section failures preserve available data; refresh clears old snapshots, errors use safe translated copy; generations reject old connection/disposed completions. Free-tier is distinct from sign-in; absent values remain unknown.
- More and screen copy localized across every shipped ARB; generated localizations regenerated. Current theme inherited, no literal presentation colors. Regression tests cover every palette at both brightnesses, live palette changes without refetching, German 2x text on a narrow viewport.
- Restored `chat_display_items.dart` byte-for-byte to integrated main; PR marker matching hid real user prompts and assistant references. Added tests for exact known suffix decoding, retry identity and literal marker preservation. Kept inherited stale test fixes for typed activity groups/collapsed reasoning, which match main.
- Repaired stale More section expectation and PR's extra notice tap (it closed the already-open notice). Tests assert both opening selectable content and second-tap collapse.

## Verification

Flutter 3.44.0 / Dart 3.12.0. Logs under `/Users/sam.russell/.hermes/cache/scratch/pr235-evidence/`.

- `flutter analyze --no-pub --fatal-infos`: exit 0, no issues (`analyze-final2.log`).
- Focused six-file suite: exit 0, 209 passed (`focused-final2.log`).
- First complete full suite: exit 1, 4866 passed, 1 failed: stale extra-tap notice test, then corrected. Isolated reproduction exit 1 confirms it was deterministic, not an assumed pre-existing failure.
- A combined command subsequently exceeded the tool's 420-second hard limit and its full-suite run was interrupted; `full-suite-final.log` is incomplete and NOT passing evidence. Final rerun is tracked separately in `full-suite-verified.log` and `.exit`.

No GitHub writes, pushes, remote merges, tags, releases, or live backend requests were performed. Backend fixtures in widget tests are explicitly synthetic contract fixtures, not claimed server responses. No device/APK smoke test was performed.
