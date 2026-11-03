# Test fixtures

`client-cert.pem`, `client-key.pem`, `ca-cert.pem`, and `client-test.p12`
are throwaway test certificates generated once with OpenSSL for the mTLS
tests. They are never real secrets and must not be reused outside this
repository. The `.p12` password is `test-password`.

Additional throwaway fixtures:

- `client-key-encrypted.pem` — `client-key.pem` re-encrypted with OpenSSL
  (`-aes256`); passphrase `key-password`. Used to prove an encrypted PEM key
  keeps its password while an unencrypted one does not.
- `mtls-ca-cert.pem`, `mtls-client-cert.pem`, `mtls-client-key.pem`,
  `mtls-server-cert.pem`, `mtls-server-key.pem` — a self-contained CA plus
  client/server certificates (server SAN `IP:127.0.0.1`, `serverAuth`; client
  `clientAuth`) for the real loopback mTLS tests in
  `test/search_mtls_test.dart` and `test/mtls_independent_transports_test.dart`.
  The server validates the client chain and rejects anonymous requests; the
  client trusts this CA explicitly, in a test-only isolated context. The CA
  private key was discarded after signing.
- `mtls-client-key-whitespace.pem` — the same throwaway mTLS client key,
  encrypted as PKCS#8 with the exact passphrase `  key password \t` (two leading
  spaces, one trailing space, then a tab). Used for a real encrypted backup →
  restore → TLS handshake, not just a string-serialization assertion.

The server leaf is valid from **2026-10-22 to 2027-10-22 UTC** (365 days).
Regenerate the CA and both leaf certificates before it expires, keeping the SAN,
key usage and extended key usage above and the server lifetime at 365 days.
A 3,650-day server leaf was rejected by macOS certificate verification even
when its CA was explicitly trusted; reducing the leaf lifetime fixed the
positive handshakes without any `badCertificateCallback`, system trust changes,
or production trust-policy change. Negative tests still reject an untrusted CA
and a hostname that does not match the SAN. These fixtures do not establish
Android user-installed/private-CA acceptance.
