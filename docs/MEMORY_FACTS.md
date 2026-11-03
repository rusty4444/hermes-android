# Saved memory facts

Open **More → Memory** to inspect the built-in facts saved by the connected
Hermes profile:

- **About you** opens first and shows entries from `memories/USER.md`: identity,
  preferences and other user facts Hermes has chosen to retain.
- **Agent notes** shows entries from `memories/MEMORY.md`: environment facts and
  the agent’s other durable notes. These are kept separate rather than inferred
  to be personal facts about the user.

Each fact is selectable text. Use Refresh or pull down to fetch a new snapshot.
A long fact may initially be shortened by the server; **Read full fact** fetches
its complete text. Full reads require a fingerprinted memory ID from a current
Hermes gateway; older positional IDs keep their labelled preview and show an
update notice, because entries can shift even when their previews are identical.
If a fingerprinted entry changed or disappeared in the meantime, the labelled
preview remains visible with an error and a suggestion to refresh.

This screen is read-only. It never changes memory settings or edits/deletes a
fact. You can ask Hermes in chat to correct or forget a fact. This view covers
only the two built-in stores, **not** external-provider recall, MemPalace drawers,
conversation history or skills. It does not create an AI-generated summary or
save another copy of the facts in device preferences.

## Connection and compatibility

The screen uses the configured dashboard origin, including its HTTPS scheme,
port, path prefix, password-cookie or trusted-proxy authentication, and a distinct
Desktop Gateway origin when configured. Every facts/detail request includes the
connection’s selected `gatewayProfile` as `?profile=...`; a blank profile retains
the server’s existing default-profile behaviour.

The Hermes dashboard must provide:

- `GET /api/learning/graph`: the `memory` card array, with corresponding memory
  identities from `nodes` (not skill nodes). Sources are `profile` and `memory`.
- `GET /api/learning/node?id=...`: complete saved content for a long fact, using
  the exact node identity returned by the graph.

`GET /api/memory` provides **provider status**, not facts. The `memory` section
of `GET /api/config` contains **settings**, not saved memories. Neither is a
fallback. An unsupported endpoint, unknown profile, malformed response or failed
connection displays an error and Retry; only an explicit empty graph produces an
empty-state message. An older server may need a Hermes update.

## Development checks

```sh
flutter gen-l10n
flutter analyze --no-pub --fatal-infos
flutter test --no-pub test/memory_repository_test.dart test/memory_screen_test.dart test/memory_backend_contract_test.dart
```

The tests cover dashboard routing/authentication/profile scope, facts versus
settings, full-text identity checks, empty/error/retry states, refresh ownership,
late success/error after profile replacement or disposal, and narrow layouts at
large text scale across the shipped locales. API fixtures under
`test/fixtures/memory/` are produced by a disposable real Hermes backend; their
provenance documents the scope. No real user memory is used by the tests.

Hermes Agent assisted with implementation and regression testing. Local widget
and build checks do not constitute physical-device validation.
