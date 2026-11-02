# Issue #253: API versus Dashboard principal routing

## Evidence and scope

The reporter's [latest capture](https://github.com/rusty4444/hermes-android/issues/253#issuecomment-6585157894)
shows API-server Bearer sends to a Dashboard-owned stored chat failing with
`permission_denied`, while Dashboard password/ticket/WebSocket sends work.
This explains why a successful low-level WebSocket fixture alone cannot validate
which transport the application selects. Thanks to @hnnacgov for the capture
and proposed fork fix direction.

No matching PR existed in the live all-state issue-number, permission-denied and
Dashboard-principal searches. The timeline-linked kvnloo commit
`cc4e83d419fc9d13d14631116b7f520faa6b1fe8` adds stock transport tests, not a
production routing change; it was inspected, not copied. The earlier maintainer
checkout remains clean at `143fa56501a77b1c55820567771f3f7967f15ac0`, with six
low-level stock WebSocket tests. Its ledger correctly stopped short of claiming
a reproduced device fix.

## Current-source result

On main `b7cd9e216b91c5ad9e4f887757b3abb5570e5067`, `ChatScreen.initState`
already attaches the normal application-owned Dashboard session when either:

- a nonempty Desktop Gateway override is configured;
- trusted Dashboard proxy mode is selected; or
- both Dashboard username and password are nonempty.

This guard predates v3.1.7 and is present in that tag too. The API key does not
participate in that decision. `_submitMessage` selects the attached normal
WebSocket transport before the SSE path. Endpoint-digest eligibility uses the
same username/password, proxy and explicit-override conditions.

The new widget tests mount the real `ChatScreen`, with real loopback HTTP/SSE
and WebSocket transports, without injected submit/resume/history callbacks.
They exercise both default and named profiles, and assert:

- dual credentials, without override or proxy mode, select password login,
  cookie-authenticated ticket, stored-ID resume and runtime-ID submission;
- API-key-only connections retain Bearer SSE and surface the captured refusal;
- Dashboard resume/submit refusals do not create another chat, switch to SSE,
  drop the selected profile or resubmit;
- a socket loss after submission does not resend the prompt through SSE or
  create a replacement chat, even if the socket reconnects.

These are controlled principal-specific fixture responses, **not execution of
backend ACLs or a phone/gateway reproduction**. Current production code passes
the reported dual-credential routing case without modification. Consequently no
production fix, credential default, blanket WebSocket routing, permission
workaround, automatic resend, version bump or released-fix changelog is added.

## Validation

- `flutter analyze --no-pub --fatal-infos`: no issues.
- `dart format --output=none --set-exit-if-changed test/chat_principal_routing_test.dart`: unchanged.
- `flutter test --no-pub --reporter expanded`: all 5,189 tests passed,
  including the ten new application-routing cases.
- Mutation check: temporarily require an empty API key in the existing
  Dashboard attach guard. Both dual-credential routing tests fail because they
  observe a Bearer completion POST. Restore the original guard and the full
  suite passes. **This is a synthetic sabotage, not an old-source failure**;
  the unchanged base already passes these routing assertions.

## Remaining blocker

A failing current-source configuration is still needed before changing routing:
confirm that the installed connection reaching `ChatScreen` actually retains both
username and password (presence only; no secrets), proxy/override flags, selected
profile, and any synchronous `ArgumentError` during normal-session attachment.
The reporter's capture states the Dashboard username is configured, so a
password-only connection is a separate unsupported premise, not an established
explanation. Supplying only a password currently does not constitute Dashboard
password authentication in `DashboardClient` either; changing only the chat gate
would not establish an authenticated Dashboard principal.

Do not close the issue or claim a fixed build from this coverage-only change.
