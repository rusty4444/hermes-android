# Model management

Open **More → Agent → Model** to manage the connected Hermes profile's main
model and auxiliary task assignments. These controls have moved out of Settings;
Settings retains appearance, notifications, voice, connection and device options.

## Main model

The profile default card shows the current provider/model and context length.
Choose a provider and model, then tap **Set profile default**. Chats with an
explicit model override keep that override. The app only reports success after
an accepted assignment and an exact provider/model read-back.

The host's `/api/model/info` deliberately omits `base_url`. Main-route safety
therefore comes from `/api/providers/custom-endpoints?profile=…`: its `current`
projection supplies provider/model/base_url, and endpoint rows identify active
named custom providers. The client retains only provider/model and an endpoint
presence boolean, not URLs, credential previews or arbitrary configuration.
`/api/config` is not a substitute: it flattens the main model section and does
not preserve its endpoint metadata.

The host persists canonical provider URLs during ordinary model switches
(`model_selection_config_updates`), so a nonempty `base_url` alone is **not** a
custom route. The client compares exact provider/URL pairs against reviewed
backend canonical defaults (`auth.PROVIDER_REGISTRY`, plus the OpenRouter profile).
Only trailing slashes are ignored; hostname similarity, query/fragment removal,
provider aliases and catalogue `api_url` fields cannot prove a standard route.
The host currently provides no canonical-default URL field in model options or
custom-endpoint metadata, so this bounded allowlist is intentionally conservative:
new/unrecognised endpoint pairs remain read-only until reviewed. No backend
changes or live configuration edits are required.

An endpoint override is read-only even with a standard provider slug such as
`openai-api`. Active named endpoint rows take precedence even if their URL equals
a canonical default, and named routes remain read-only without a mirrored main
base URL. The metadata must match the model-info provider/model; unavailable,
malformed or mismatched metadata disables main editing until Refresh succeeds,
without blocking independent auxiliary controls. An explicitly empty endpoint
and no active custom endpoint allow standard assignments, including models not
listed in discovery. Read-back rechecks route metadata with the same canonical
classification before reporting success. Hosts without the metadata route cannot
safely enable the main editor.

## Auxiliary models

The screen lists every task returned by the server's auxiliary-model endpoint,
including task IDs added by newer hosts. Choose a provider/model and save the
individual task. **Automatic / inherit** retains the host's existing inheritance
behavior; opening this screen never changes assignments or runtime defaults.
Unknown current models remain visible rather than being silently replaced by a
catalogue entry. Existing custom/local endpoint routes remain visible read-only:
the catalogue picker cannot safely edit their endpoint and credential settings.
No provider credentials or blank endpoint overrides are sent by these controls.
Both pickers exclude user-defined provider rows and endpoint-bearing catalogue
rows (`api_url` is the host's current catalogue field; `base_url` remains
supported for older hosts).

## Scope and failure behavior

Discovery, mutations and read-back all use the selected connection's Dashboard
client, retaining its origin, reverse-proxy prefix, authentication and mTLS identity.
An explicit selected profile is never retried against the launch profile. Legacy
connections without an explicit profile keep the host's existing launch-profile
behavior. No cron configuration or per-chat override is changed.

A host rejection (`ok: false`) or a read-back mismatch is a failed save, even with
HTTP 200. Retry reloads the host data after a discovery failure. Replacing the
connection/profile or closing the screen fences in-flight responses; injected
clients remain owned by their caller. A missing local mTLS identity produces a
retryable error rather than crashing screen construction.

## Verification

`test/model_management_screen_test.dart` covers changed main and unknown-task
auxiliary assignments, rejection/mismatch, selected-profile payloads, custom route
preservation, disposal, missing-certificate retry, compact large-text layout and
removal of editors/discovery from Settings. Existing selected-profile TCP and
retained-widget tests now exercise the dedicated screen; Dashboard-origin and
Workspace/More tests cover transport identity and navigation.

`tools/capture_main_model_route_fixture.py BACKEND_ROOT` regenerates
`test/fixtures/main_model_routes.json` using the backend interpreter with a
scratch `HERMES_HOME` and network connections refused. It validates every
allowlisted URL against backend provider definitions and executes the actual
`_apply_main_model_assignment` → `apply_model_selection` persistence transform,
`get_model_info` and `_custom_endpoint_response`. Switch credential/network
resolution is bounded at a synthetic `ModelSwitchResult`; this is producer and
persistence-transform coverage, not a full authenticated HTTP model-switch test.
Six providers' backend-produced snapshots cover canonical URLs both before and
after saving, exact selected-profile requests, success/read-back, and refresh.
Additional snapshots protect overrides, unknown/custom routes and active named
endpoints even on a canonical URL. The pure classifier test protects URL suffix,
userinfo, path, scheme, cross-provider and lookalike-host boundaries. Existing
metadata-unavailable/malformed/mismatched and read-back override tests remain.
No fixture capture contacts the gateway or mutates live configuration.

Earlier client fixtures follow the installed host contracts in
`hermes_cli/web_routers/models.py:get_model_info`,
`hermes_cli/web_routers/config_env.py:_custom_endpoint_response`, and
`hermes_cli/model_switch_providers.py:_PickerBuild.add_endpoint_row`:
model info has no endpoint, endpoint metadata is separate, custom catalogue rows
use `api_url`/`is_user_defined`. Tests cover standard-slug overrides, named
endpoints, failed/malformed/mismatched metadata and recovery, endpoint-bearing
read-back, picker exclusion and selected-profile TCP routing. These are local
client fixtures, not live configuration mutations or full host integration.
