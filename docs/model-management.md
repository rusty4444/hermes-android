# Model management

Open **More → Agent → Model** to manage the connected Hermes profile's main
model and auxiliary task assignments. These controls have moved out of Settings;
Settings retains appearance, notifications, voice, connection and device options.

## Main model

The profile default card shows the current provider/model and context length.
Choose a provider and model, then tap **Set profile default**. Chats with an
explicit model override keep that override. The app only reports success after
an accepted assignment and an exact provider/model read-back.

## Auxiliary models

The screen lists every task returned by the server's auxiliary-model endpoint,
including task IDs added by newer hosts. Choose a provider/model and save the
individual task. **Automatic / inherit** retains the host's existing inheritance
behavior; opening this screen never changes assignments or runtime defaults.
Unknown current models remain visible rather than being silently replaced by a
catalogue entry. Existing custom/local endpoint routes remain visible read-only:
the catalogue picker cannot safely edit their endpoint and credential settings.
No provider credentials or blank endpoint overrides are sent by these controls.

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
