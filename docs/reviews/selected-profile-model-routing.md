# Selected-profile model routing

Contract reference: archived host `bf0203a794a07aac3ff764972ab9087baa4e4f4e`, inspected without modifying its source or live homes.

- `hermes_cli/web_routers/models.py`: info (90–135), options (138–168), auxiliary (219–269) select the GET query `profile`; assignment (376–427) uses `body.profile or profile`.
- `hermes_cli/web_models.py`: `ModelAssignment.profile` is optional; `confirm_expensive_model` defaults false.
- An omitted profile retains the dashboard launch-home behaviour. An unknown selected profile must surface an error, not cause a retry against the launch home.
- API Server inventory still uses the configured gateway path prefix; its profile-path contract is distinct from Dashboard query/body selection. The compatibility model helpers additionally preserve explicit query/body selection when addressing Dashboard-compatible routes.

## Changes

Scope model discovery, info, auxiliary reads and main/auxiliary assignments in service clients. Carry the saved selector into Settings, Desktop Gateway's internal Dashboard client and SavedConnection-based API clients. Leave generic HTTP, authentication, TLS/certificate handling, prefixes, analytics, custom-endpoint exclusion and expensive-model confirmation policy unchanged.

Settings now requires an accepted assignment and matching selected-profile read-back before reporting success. Settings and Auxiliary widgets invalidate departed-client requests, capture the admitted client through read-back and reject late success/error results after replacement/disposal. Settings closes only clients it owns.

## Permanent regressions

`test/selected_profile_model_routing_test.dart` exercises real TCP requests with the production Dashboard/API/Desktop clients against distinct launch/secondary stores, independent-client read-back, encoded selectors, existing prefixes/auth, omitted launch compatibility and unknown-profile no-fallback. Its loopback server implements the inspected host contract; it is not the Python host implementation.

Retained-widget tests cover Auxiliary old-write success/error after replacement; Settings replacement during initial load, write acknowledgement and read-back; injected-client ownership; and the default Settings factory's selector passed to its actual Auxiliary consumer. Existing provider tests retain rejected HTTP-200 confirmation, mismatched read-back, custom endpoint and disposal guards.

## Separate archived-host execution

Scratch evidence `android-rc-profile-fix-evidence/host_model_probe.py` executes the real archived FastAPI model router, profile scopes, assignment and physical config writer against disposable homes. It confirms a secondary auxiliary assignment to `openai/gpt-4.1-mini` via body selector, selected-query read-back, physical secondary YAML values, byte-unchanged launch config and 404s for unknown profiles on info/options/auxiliary. Only environmental home seams and external pricing/context probes are bounded; no host production source is patched. This ASGI probe is separate from the Dart TCP contract test and does not claim live-host deployment or full end-to-end host authentication coverage.

No remote GitHub writes, signing, release, deployment or live-host changes are part of this fix.
