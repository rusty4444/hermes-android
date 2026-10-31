# mTLS RC lane report

## Outcome and ancestry

- Branch: `rc3/mtls`, resumed in its existing worktree without reset or recreation.
- Verified implementation commit: `95cdc6ca8bae2db13336282c664199230ee308a1`.
- Existing merge retained: `38729864826fc3a0ff87586ed5afc76b67e34945`.
- Frozen main ancestor: `6475ee9ee82ad03ed4a89484b77c29241e893f45`.
- Original PR #166 ancestor: `175258a2bc13eb2390ff9adeb523168e53620347`.
- Both ancestors were checked with `git merge-base --is-ancestor` (exit 0).
- This report is committed separately after the implementation. The final lane
  head is recorded in `mtls-final-state.json` beside the release-artifact copy.
- The saved Memory facts screen/model/contracts remain intact. The new Memory
  repository receives the saved TLS identity without changing its facts API.
- Inherited version `2.1.33+2176` and dependency manifests are unchanged. RC
  metadata, signing, packaging and CI remain owned by the parent release lane.

## Fixes

1. **Credential migration:** read the existing physical secure bundle before
   merging a legacy PEM password. Preserve existing API/dashboard/key secrets,
   give current secure fields precedence over stale plaintext, and sanitize
   metadata only after verification. Failures leave retryable legacy metadata.
2. **Exact passphrases:** remove trimming from secure PEM-password persistence
   and backup decoding. A real encrypted PKCS#8 key with leading/trailing spaces
   and a tab survives save, reload, encrypted backup/restore and a TLS handshake.
3. **Independent clients:** carry TLS into stock-owner settled/recovery history,
   the delegated-history HTTP wrapper, the mobile-push default Dashboard client,
   and the Memory repository. Existing list, search, rewrite, REST/SSE, remote
   files and WSS call sites retain their connection-scoped identity. The unrelated
   release-update HTTP client deliberately does not receive gateway credentials.
4. **Retained scopes:** include certificate chain path, key path and exact key
   password in TLS configuration scope. Independently rotate each field, add,
   clear and remove identities; stale stock owners close and unchanged owners
   remain retained. Push authority also detects passphrase changes. Preserve the
   exact existing non-mTLS receipt namespace and push binding to avoid orphaning
   ordinary pending turns or invalidating unrelated notification consent.
5. **Import rollback:** snapshot all affected raw credential bundles before any
   write; restore and verify every attempted entry, including removed or newly
   added IDs, alongside metadata on failure. Cover merge and replace imports,
   prerequisite read, later write, verification and metadata throw/false-ACK
   failures, physical reload, restart and successful retry. Cleanup removes new
   unreferenced PEM files while preserving the old identity.
6. **Rollback outage safety:** if the rollback itself cannot commit, return an
   explicit incomplete-restoration error. Reload physical metadata before key
   cleanup; never delete a replacement still referenced by the committed list,
   or files whose reference state cannot be read safely.

## Real TLS fixture correction

The original 3,650-day server leaf failed macOS native certificate verification
although its CA was explicitly trusted. Controlled standalone probes reproduced
failure with a long-lived leaf and success with a 365-day leaf. The fixture
CA/leaf certificates were reissued with the existing throwaway client/server keys
and a 365-day server leaf, valid **2026-10-22 through 2027-10-22 UTC**. The issuing
private key was not retained.

No `badCertificateCallback`, system trust modification, or weakened production
trust policy was introduced. Test-only isolated contexts trust the fixture CA.
Positive requests now perform real verified HTTPS list, SSE chat, WSS upgrade
and JSON-RPC, server search, AI rewrite, independent stock history, delegated
history, Memory facts and mobile-push capabilities. Negative tests reject missing
client identities after successful server trust, an untrusted server CA and a
hostname outside the server SAN.

## Regression evidence and validation

All final commands ran serially on macOS with Flutter **3.44.0** / Dart **3.12.0**,
using the existing dependency cache, and explicit environment:

```text
TMPDIR=/Users/sam.russell/.hermes/cache/scratch
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
ANDROID_HOME=/Users/sam.russell/Library/Android/sdk
ANDROID_SDK_ROOT=/Users/sam.russell/Library/Android/sdk
```

| Gate | Result | Artifact log |
| --- | --- | --- |
| `flutter pub get --offline` | PASS; manifests unchanged | `mtls-pub-get-offline.log` |
| Format every Dart file changed from frozen base | PASS; 46 files, final check 0 changes | `mtls-format.log`, `mtls-format-check.log` |
| `flutter analyze --no-pub --fatal-infos` | PASS; no issues | `mtls-analyze.log` |
| Focused tests, `--no-pub --concurrency=1 --reporter expanded` | **270 passed** | `mtls-focused.log` |
| Full `flutter test --no-pub --concurrency=1 --reporter expanded` | **1912 passed** | `mtls-full-suite.log` |
| `git diff --check` / staged diff check | PASS | Checked before commit |

The focused command's exact file list is in its log. Initial failing regressions
were retained in `mtls-resume-red-state.log` (six state failures),
`mtls-red-transports.log` (four omitted independent transports),
`mtls-resume-red-search.log` (positive macOS trust failures), and
`mtls-red-rollback-outage.log` (referenced replacement deleted during an outage).
`mtls-red-plain-scope.log` catches the intermediate broad scope change; the final
implementation preserves plain-profile compatibility. Intermediate compile or
fixture-contract errors were corrected, not treated as production defects.

The full suite initially exposed an existing startup fixture that assumed the
first secure read happened after a write. It now separately tests both the new
prerequisite-read failure and the original post-write verification failure,
without dropping recovery/reset assertions. The older multi-profile migration
fault injection still targets the second profile's read-back after the new
prerequisite reads. Cron and Skills screen edits in the implementation commit
are formatter-only changes from formatting the complete PR delta.

## Files and integration boundaries

New regressions: `test/mtls_state_regression_test.dart`,
`test/mtls_independent_transports_test.dart`, `test/support/mtls_fixture.dart`, and
`test/fixtures/mtls-client-key-whitespace.pem`. Existing search, migration,
startup and certificate fixture tests were extended. Implementation changes are
confined to the connection/backup, owner scope and independent transport services.
No remote writes, installs, builds, signing, tags, live-service changes, vault
access or model configuration changes were performed.

## Exact limitations

- Accepted RC scope is **optional imported PEM/P12 identities** in app-private
  files, not Android KeyChain/non-exportable-key support. P12 extraction does not
  retain an unnecessary container password. Do not close #165 as KeyChain work.
- Tests use real loopback TLS with synthetic HTTP/RPC responses and a mocked
  native push boundary. They do not prove a physical Android private-CA trust
  flow, a live reverse-proxy list/chat/WSS deployment, native encrypted storage,
  push delivery, or the full stock backend lifecycle. Keep those acceptance
  checks explicit and separate.
- A persistent storage outage cannot guarantee atomic rollback. That case
  reports incomplete restoration and retains referenced/unknown key files; it
  does not claim the previous configuration was restored.
- Regenerate the short-lived server fixture before **2027-10-22 UTC**.
- No APK was built or installed in this lane. Parent must integrate the other
  lanes and rerun combined validation before packaging or release.
