# Automatic Android push: implementation contract

## User acceptance

On a Google-enabled Android device, the user enables Background notifications and accepts the Android notification permission. They never enter URLs, keys, chat IDs or distributor package names, and need no separate app. The existing saved Hermes connection supplies authentication. Keep external UnifiedPush as an optional advanced alternative. No startup enrolment or silently expanded legacy consent. Do not merge, release, modify the live Hermes installation or update GitLab.

## Frozen shared wire contract

- Retain schema 1 and existing fenced registration/revocation/challenge protocol. Capabilities additionally advertise `session_scope_modes: ["explicit", "authorized"]`.
- Legacy registrations omit `session_scope` (default `explicit`) and require 1–128 exact validated `session_ids`.
- New automatic registrations send `session_scope: "authorized"` and OMIT `session_ids`. Reject conflicting fields, null lists, unknown modes and malformed values. Include existing monotonic `registration_revision`, nonce, keys, endpoint and event kinds unchanged.
- `authorized` means current AND future durable sessions permitted by the authenticated principal's live operator ACL in the selected profile. It is NOT an ownership grant. Existing operator `owner_all_sessions` is required for owner-wide future sessions. A restricted principal remains restricted. Allow enrolling before the first chat exists.
- Persist `session_scope` explicitly server-side and in sealed native consent. Missing/legacy scope remains explicit. New modes require new explicit consent; never broaden an existing installation on migration.
- New clients using authorized mode fetch `/events?installation_id=ID&generation=N&after=CURSOR&limit=100`. The server verifies current active generation/ownership and applies live ACL, durability, registration scope and event-kind filtering. Response echoes `installation_id`, integer `generation`, and `session_scope`; the client must validate all three on EVERY page. Legacy unscoped event queries remain compatible, but cannot act as dynamic scope authority.
- Confirmation, observer enqueue/admission and every send recheck live authorization; ordinary send additionally checks current durability and registration scope. No literal wildcard, no identity/header/token fallback, no cross-profile or lineage inference. Maintain revisions, tombstones and encrypted challenge verification.

## Client/native boundary

- Add published `org.unifiedpush.android:embedded-fcm-distributor:3.1.0`, no Firebase/GMS SDK, google-services.json, Gradle plugin or vendor credentials.
- Connector 3.3.5 recognises app package as embedded distributor; availability is `context.packageName in UnifiedPush.getDistributors(context)`. Prefer a valid existing explicit/saved choice, then built-in, then valid default/lone external. Multiple externals without a default need an actionable advanced choice; never silently pick an arbitrary package. A missing/disabled GMS runtime or failed endpoint registration must not be presented as active.
- `MobilePushService.enableAutomatic(connection, {String? distributor})` shares existing enable fences and lifecycle; native `enable` receives `session_scope: authorized`, `sessions: []` and distributor `automatic` unless explicitly overridden. Native resolves transport and validates scope before persisting consent or registration. Legacy `enable(connection, distributor, sessions)` stays explicit for compatibility/tests.
- Native scope persists across endpoint renewal/recovery/restart, revoked before account changes. Dart enables authorized event acceptance ONLY from its sealed authorized consent plus correctly bound authenticated event responses. Legacy explicit lists stay enforced.
- Settings: one Background notifications switch, status and readable failure guidance, retry/revoke controls. No required ID text field or package dropdown. Optional advanced transport settings may reveal readable built-in/external choices. Explain Google-backed encrypted hint delivery and no chat content. Server plugin unavailability/update required is explicit, not an optimistic success. Permission/native registration only after capabilities negotiation succeeds. Disabling remains available during a pending enable.

## Verification and distribution boundaries

Test automatic UI, capability refusal before effects, dynamic empty/new/restricted sessions, migration, ACL revocation, wrong principal/profile/generation, field conflicts, expired/revoked generation, recovery and native sealed scope persistence. Run full Flutter suite, server suite, native Robolectric tests and actual APK build. Add a consuming-client/server contract check where practical. Physical Google/Doze/killed-process delivery is a separate acceptance test and must not be claimed from fixtures.

Upstream embedded 3.1.0 licensing is inconsistent: POM Apache-2.0 vs tagged LICENSE LGPL-2.1. Conservatively retain LGPL notice/text/source location and document replacement/relinking/rebuild path. Do not claim unambiguous Apache licensing or F-Droid approval. No release before licensing/device acceptance review.
