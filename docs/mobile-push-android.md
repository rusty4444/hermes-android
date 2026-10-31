# Automatic Android background notifications

Background notifications are **off until you enable them** and are separate from
local notifications and active-turn background connection handling. One saved
Hermes connection can be enrolled per Android installation. Starting the app does
not enrol it or silently broaden an existing selected-session subscription.

## Setup on the phone

1. Open the saved connection's Settings and enable **Background notifications**.
2. Accept Android's notification permission prompt if requested.
3. Keep/reopen Hermes until the status is **Active**. No push-server URL, key,
   chat ID, Firebase project or separate distributor app is required on a device
   with functioning Google Play Services. Registration is handled by the app.

The automatic transport uses an existing valid distributor choice when present,
otherwise the built-in Google-backed distributor when available. External
UnifiedPush remains an optional advanced alternative, including for Google-free
phones. If neither transport is available, Hermes reports that limitation; it
cannot provide background push merely by hiding the settings. Installing ntfy or
another compatible distributor remains an option, not a requirement on ordinary
Google-enabled phones. Multiple external distributors without a default may need
an explicit advanced selection.

## Server prerequisite

The operator must install/enable the paired `mobile-push` companion and authorise
your verified dashboard login. The automatic subscription covers current and future
durable chats **only as permitted by that login's live server policy**. For a personal
server, an operator's explicit `owner_all_sessions: true` grant allows new chats
without maintaining IDs. Restricted accounts stay restricted. No wildcard, other
profile or all-users permission is inferred. See [the server runbook](mobile-push-server.md).
A stock, disabled, unauthorised or outdated server is reported as unavailable or
requiring an update, before permission or device registration. This app change does
not install or reconfigure a live server.

The app registers its endpoint using the existing authenticated DashboardClient.
Subscriber `p256dh` and `auth` come from the connector, not the server VAPID key.
The server sends an encrypted challenge; receiving it proves possession of the
subscriber private key. The native service queues the proof even without the
Activity/Flutter engine or before registration PUT returns. Only an authenticated
confirmation for that exact generation activates the installation. **Pending is
not Active.**

Before each registration PUT and confirmation POST,
Hermes writes an attempt journal into the native encrypted store. If the server
commits but its response (or the local generation/activation write) is lost, the
next foreground reconciliation—including after process restart—atomically rotates
the native nonce/revision, clears old proof/tap/activation authority, and registers
the **same already-consented** endpoint, account and session scope again. It must
receive a fresh encrypted proof and authenticated confirmation of that exact
new generation. This recovery does not request permission, enable a new binding,
or contact the distributor. A waiting registration also has a durable five-minute
local wait ceiling (not a claim about the server's configured proof TTL); an
expired proof or elapsed ceiling renews on the next foreground reconciliation.
A missing proof therefore cannot leave a nonzero generation permanently Pending.
Network failures wait for the next resume/manual retry, rather than continuously
rotating registrations from queued challenge callbacks.

The paired server must advertise `registration_fence:1`. Every PUT includes the
native durable `revision` as `registration_revision` (1–9007199254740991). The server
checks that it strictly exceeds the previous value **inside the same SQLite write
transaction** that changes authority; UUID nonces are random equality tokens, not
ordered revisions. An older authenticated handler held before commit cannot overwrite
a recovered active registration, even if its client or TCP connection has gone away.
The registration response must echo the exact revision before native generation is
accepted. This is paired with the server migration described in
[the companion runbook](mobile-push-server.md#registration-fence-upgrade).

Revisions never reset on the same installation during recovery, renewal or restart.
Disabling/re-enabling (including changing sessions/distributor) creates a **new random
installation ID**, so valid new consent starts at revision 1 without stalling behind
an old high-water mark. Revocation is terminal for the old installation. If the server
revokes an expired subscription (404/410), explicitly disable and enable again; retry
cannot reactivate it. Legacy native consent is migrated once to a fresh nonce and
incremented revision, with activation/proofs/taps cleared before use. Legacy hints
are rejected headlessly even before foreground migration.

`Reconcile / retry` also refreshes the authenticated event feed,
retries distributor registration when it failed, and retries failed server
revocations. Delivery is best-effort, not a guarantee. A changed endpoint
immediately clears local generation/active authority and queued old taps; the
next foreground reconciliation registers and confirms it again. Editing,
removing or importing a bound saved connection revokes native authority before
changing its credentials/metadata; opt in again afterwards.

Disable revokes local consent, queued hints, taps, subscription material, and
visible transport notifications **before** distributor IPC or authenticated
server DELETE. Failed server revocations remain recorded for foreground retry.
They are never sent using another connection or changed credentials. If the
original login/origin is no longer available, revoke the stale installation
server-side. Local authority remains off regardless.

## Privacy and lifecycle

* The official native connector `org.unifiedpush.android:connector:3.3.5` receives
  through its manifest receiver and our non-exported `MobilePushService`. It does
  not require an Activity, Flutter UI, foreground socket, or background startup
  screen. Only `PushMessage.decrypted == true` is accepted; plaintext fallback
  messages from the connector are discarded.
* The connector manages subscription key generation and encrypted private-key
  storage. Hermes stores its endpoint/auth material, consent, installation nonce,
  generation, explicit allowlist or authorised scope, pending challenge/revocation/tap queues and a
  bounded 256-event dedup window in an AES-GCM envelope, using a non-exportable
  Android Keystore key. SharedPreferences contains ciphertext only. Backups are
  disabled in the app manifest. Neither endpoints, auth secrets, proofs nor
  payloads are logged or exported by configuration backup.
* Hints contain only schema/event ID/kind/generation/nonce/expiry and an optional
  challenge. Unknown kinds, wrong installation/nonce/generation, expired hints,
  disabled consent, and unconfirmed notifications are rejected natively.
* Native notifications are generic (no session ID/title/text/approval token).
  Notification taps carry a locally issued event/installation/nonce/revision,
  are revalidated against durable authority and expiry, and resolve session IDs
  **only** from the authenticated plugin event feed. No arbitrary URL, automatic
  approval, or prompt resubmission is implemented.
* Current master/per-kind notification preferences are synchronized into native
  encrypted state. Suppression cancels already-visible transport notifications.
  These preferences suppress delivery, not consent; use Disable to unsubscribe.
  Android notification permission is never requested from the headless service.
* Background delivery is not the same as Android **Force stop**: force-stopped
  applications generally cannot receive broadcasts until opened again. OEM
  battery/distributor restrictions can also prevent delivery.

## Root integration API (app owner)

`HermesAppState` in `main.dart` installs the startup, serial validated-tap routing
and teardown hooks after credential hydration and the first frame. Settings reuses
the same app-lifetime service. The hooks below document that lifecycle contract
for app owners integrating the feature into another root; they are already
installed in this app:

```dart
final mobilePush = MobilePushService.shared;

// After normal ConnectionManager credential hydration, after the first frame.
// Do not await this before runApp / first frame. Startup never requests consent.
unawaited(mobilePush.initialize(widget.connManager));
mobilePush.addListener(onMobilePushChanged);

// onMobilePushChanged hands off to the root's existing serialized intent owner.
// Do not add another direct tap -> fetch -> push dispatcher. The production root
// retains taps while paused, snapshots push proof and mutation epoch at ingress,
// and passes both fences to every page of the real authenticated lookup:
// client.getSessionById(id, canContinue: current, isCurrent: currentSync).
// currentSync checks mounted/closing, lifecycle, generation, complete saved
// binding AND ConnectionMutationBarrier.isCurrent(id, capturedEpoch).
// current rechecks currentSync AFTER awaiting native push authority too.

// When current NotificationPrefs change, await parity before reporting saved:
await mobilePush.syncPreferences(notificationPrefs.value);
// This listener is also installed automatically by initialize().

// Explicit consent revocation; local native invalidation precedes HTTP DELETE:
await mobilePush.disable();

// On root teardown: remove its listener. The app-lifetime singleton owns its
// lifecycle observer; it automatically reconciles on resumed. Do not dispose it
// from a Settings screen. Tests may dispose their injected service instance.
mobilePush.removeListener(onMobilePushChanged);
```

`takePendingNotificationRoute()` consumes a single pending native tap and returns
`MobilePushRoute(connection, sessionId, eventId, authority)` or null. There are no
approval fields. Recheck `isRouteCurrent(route)` after **every** async boundary
before navigation. Both methods recheck current saved connection credentials,
consent, installation/nonce/revision, preferences and event expiry. The service
also rechecks ownership after registration, confirmation and each event page.
The root should serialize its own route-open requests to avoid two simultaneous
listeners navigating twice. It can call `refresh()` explicitly after recovering
network or changing account metadata; ConnectionManager already invalidates native
authority before saved-account edits/import/removal.

### Engine-owned mutation recovery

`MobilePushPlugin` owns each native channel and mutation lease for the lifetime of
its Flutter engine, not its Activity. Activity/configuration detach does not end a
live transaction. Engine destruction rejects queued old IPC, removes only that
engine's unused enable tickets, and retires only its own orphan leases. A genuinely
live sibling's BEGIN is never released by another engine's destruction or END.
Durable consent revoked at BEGIN remains off; recovery never restores it.

Clearing the singleton map at detach is insufficient: secure-storage 10.3.1 calls
`quitSafely()` and can finish already-dispatched writes later, and the legacy
SharedPreferences API executes on a background queue. The installed
`EngineScopedSecureStoragePlugin` and `EngineScopedPreferencesPlugin` retain native
completion ownership around the actual existing storage implementations. Old
queued metadata writes fail before effects. Executing writes drain before orphan
leases are released, even if their Dart reply is lost. New consent is blocked
while an orphan drains or a metadata commit is executing. A full-list write also
durably revokes a bound row it removes/changes before commit, even if the writer's
original ID set omitted that row.

Replacement consent refreshes physical metadata when no live local list owner
exists, without waiting behind or reloading over an unrelated live transaction.
The native engine-bound enable additionally compares the submitted non-secret
metadata with the actual saved row. A fresh ticket alone cannot lend authority to
a replacement isolate's stale cached host/profile. Native AES-GCM lifecycle tests
hold a real metadata commit through detach/reattach, preserve live siblings, reject
old headless hints, and prove fresh consent works without knowing the abandoned
token. Their binding/messenger, AES-key acquisition and distributor IPC are fixture
seams, not running-JNI-engine or physical-device evidence.

The Settings widget can also be embedded directly:
`MobilePushSettings(connection: selected, connectionManager: manager)`.
It exposes one opt-in switch, Pending/Active/Error, retry/revoke and optional
advanced transport controls. No manual chat IDs are needed. It remains
accessible in the Settings fallback when model settings fail to load.

## Frozen server API

Paths are relative to DashboardClient's authenticated origin and dashboard path
prefix, never the Gateway chat/API key origin. Every operation forwards the saved
`gatewayProfile` as `?profile=<name>`, alongside cursor parameters where applicable.
The server's vetted profile dependency selects that home's policy/state, not the
dashboard's launch home. The operator must separately enable the lifecycle
hooks/worker in that profile; API selection cannot start them.

* `GET /api/plugins/mobile-push/capabilities` → schema 1, registration_fence 1, enabled, transports
  containing `webpush`, VAPID public key and `session_scope_modes` containing `authorized`.
* `PUT /api/plugins/mobile-push/registrations/{installation_id}` → endpoint,
  keys `{p256dh, auth}`, registration_nonce, registration_revision and explicit event_kinds.
  Automatic enrolment sends `session_scope: authorized` and omits `session_ids`;
  legacy explicit enrolment retains its validated `session_ids`;
  response `{generation, status: pending, registration_nonce, registration_revision}`.
* `POST .../registrations/{id}/confirm` → `{generation, challenge}`;
  response must contain `status: active` and the exact `generation` before local activation.
* `DELETE .../registrations/{id}` revokes.
* Automatic mode uses `GET .../events?installation_id=<id>&generation=<generation>&after=<cursor>&limit=100`
  → events, next_cursor, has_more and matching installation/generation/scope.
  Cursor pages are read to exhaustion (safety cap fails honestly rather than
  returning partial reconciliation). Every page is bound to current consent;
  only unexpired, currently authorised events route. Legacy explicit mode also
  retains its local allowlist. An old explicit subscription never becomes broad
  automatically: disable it and opt in again to select authorised scope.

## Dependency/build compatibility and verification

Version 3.3.5 and its `PushService`, `PushEndpoint.pubKeySet` and
`PublicKeySet.pubKey/auth` APIs were verified against the published Maven source
JAR and AAR. The Flutter wrapper is not used (avoids transitive AGP drift). The
connector publishes the JVM `tink` artifact, whereas flutter_secure_storage
already depends on `tink-android`: bundling both creates duplicate classes.
The app excludes connector's `tink` and explicitly uses the published
`tink-android:1.23.0`. This cryptographic library is not Firebase messaging.

The optional built-in transport adds `embedded-fcm-distributor:3.1.0`, which uses
device Play Services IPC without a bundled Firebase/GMS SDK or Google credentials.
Its published POM and tagged source disagree on licensing. See the
[retained licence, source and rebuild notice](../third_party/embedded-push-notice.md).
RC packaging treats the exact tagged LGPL-2.1 licence as authoritative. The APK
carries its notice, licence and complete Library source/build archive. An
exact-application source/relink ZIP and tested local-AAR substitution path are
provided; see the notice for the remaining distribution/application-permission
review. This is not legal clearance, F-Droid acceptance or physical Google delivery.

Run from the repository (Flutter 3.44 / Dart 3.12):

```sh
export TMPDIR=/Users/sam.russell/.hermes/cache/scratch
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
flutter pub get
flutter analyze lib/core/services/mobile_push_api.dart \
  lib/core/services/mobile_push_service.dart lib/core/widgets/mobile_push_settings.dart \
  lib/core/services/connection_manager.dart test/mobile_push_service_test.dart \
  test/mobile_push_recovery_test.dart test/mobile_push_settings_scope_test.dart
flutter test test/mobile_push_service_test.dart test/mobile_push_recovery_test.dart \
  test/mobile_push_settings_scope_test.dart
flutter build apk --debug
(cd android && ./gradlew :app:testDebugUnitTest --tests '*MobilePush*Test')
```

Dart tests use controlled native MethodChannel callbacks and an authenticated
HTTP fixture for opt-in, permissions, unavailable/forbidden servers, challenge
race, stale generations, renewal/disable races, durable failed revoke retry,
per-kind preferences, event cursor paging and authenticated routing. The recovery
suite uses a consuming-nonce/one-use-proof HTTP fixture (not an idempotent success
stub), lost responses and held acknowledgements after server commit, replacement
production controllers, failed local commits, persisted expiry/missing-proof
waits, retry single-flight, renewal handoff, and 128-ID/200-character ASCII scope
boundaries. It also holds an old PUT before commit across controller replacement,
activates recovery/endpoint revision, then releases the old handler and rechecks
retry/restart authority. Legacy explicit-scope service tests retain exact
count/length/ASCII validation; the automatic Settings flow needs no ID entry. Native JVM
Robolectric tests exercise the real headless service/bridge with the connector's
decrypted flag controlled, durable encrypted storage with a test-injected AES
key (not AndroidKeystore acquisition), generic notifications, bounded dedup,
renewal, disable, preferences and corrupt ciphertext. Test fixture subscription
material is never used by production code. They are not evidence of physical
killed-process delivery. No connected-device/distributor end-to-end test has
been performed; that remains required before claiming device delivery works.
