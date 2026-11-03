# Exact-host mobile-push compatibility blocker

Reference pair: Android `64991a4ff2054728234a5d8645b176c72f042478`;
archived Hermes host `bf0203a794a07aac3ff764972ab9087baa4e4f4e`.
This is not a green cross-profile integration claim.

## Supported path

The discovered, explicitly enabled **launch-profile, in-process** router works
with the real BasicAuthProvider password-cookie middleware. The compatibility
regression also exercises actual TLS Web Push encryption, independent subscriber
decryption/VAPID verification, lost-ACK revision rotation, stale proof rejection,
confirmation replay rejection, revocation, and unauthenticated/forged-header denial.
It does not establish physical Android delivery or a deployed server.

## Two distinct causes of the legacy fixture failures

1. **Fixture bootstrap is obsolete.** The old mounted fixtures pass a hand-built
   plugin dictionary to `_mount_one_plugin_api`, but do not install a discoverable
   manifest or configure the host's per-profile enabled lists. Their `/scope` and
   `/probe-home` routes directly reuse `_plugin_route_secret_scope` outside
   `/api/plugins/<name>/...`. `_plugin_api_name` returns an empty name for these
   probes. Current runtime discovery/consent checks therefore return 404 `Plugin
   not found`, not a home/enabled payload. They also fail to isolate every imported
   `get_process_hermes_home` binding and the secondary-discovery caches. A mount-time
   enabled set is not a request-time authorisation grant.

   Minimal launch-only harness correction: use the existing `current_host` fixture
   (`test_current_host_default.py`): disposable plugin symlink, actual manifest
   discovery, explicit config enablement, isolated launch-home bindings/caches,
   and real password-cookie authentication. Probe the actual capabilities route,
   not an unrelated path. Do not patch host consent/refusal functions.

2. **Real secondary/hosted compatibility is absent.** Even after correcting
   discovery, `web_server_plugin_profiles.in_process_router_refused` intentionally
   prevents secondary user-plugin code from running in the launch process. The
   supported host routing path forwards it to that profile's plugin child.
   `forward_secondary_plugin_request` strips gateway cookies/Authorization and
   profile/credential query fields. `PluginHost.asgi_request` carries only an
   `authenticated` boolean; `HostRuntime.op_asgi` and `with_hosted_admission` expose
   that as `state.hosted_http_authenticated`, not `state.session`.

   Mobile-push deliberately requires both verified `session.provider` and
   `session.user_id` in `mobile_push.api.principal` to narrow its explicit policy
   ACL. The boolean cannot identify either. Executing the actual child ASGI
   handler with authenticated=True still returns 401 `Verified dashboard session
   required` for capabilities, PUT, confirm, DELETE and events, without database
   effects. This test invokes the actual child handler in-process (no IPC process
   or Channel); it does not pretend a hand-built HTTP response is host evidence.

## Minimal safe resolution boundary

Use a separately launched, explicitly enabled **in-process** dashboard per desired
profile until the host has a verified identity-forwarding contract. This is a
runbook option, not a deployment performed here; a profile selector on a shared
launch dashboard is not equivalent.

Full secondary/hosted support requires a separate host change: carry a bounded,
verified provider/user identity over private request-scoped IPC, established only
by host authentication and scoped to the selected home; stamp vetted child secret
scope; then adapt the companion to that authenticated contract. Retain per-profile
discovery/consent, never forward raw gateway credentials, never derive identity
from headers/body/query, and never equate authenticated=True with owner authority.
Regress absent/malformed/foreign identity, concurrent requests, cached child apps,
all five operations, ACL removal, wrong-profile proofs, physical stores and worker
lifecycle. That host contract is outside this Android-only change's scope.

The historical positive cross-profile tests and every auth/scope negative remain
unchanged and failing against this exact host: no skip/xfail, bundled-source
masquerade, permissive fake host or production security relaxation was introduced.
The new passing diagnostics reproduce the blocker; they do not turn the old
positive integration gate green.
