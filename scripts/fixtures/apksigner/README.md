# Captured apksigner output

`run-40062562548-v2.txt` contains the four public certificate lines from the
first APK in the successful **Verify release APKs are signed** step:

- Run: https://github.com/rusty4444/hermes-android/actions/runs/40062562548
- Source commit: `05f69247a5ffd8dc22bc132f5edc6d20f48bafee` (`v3.0.0-rc.1`).
- Capture timestamps: `2026-10-24T04:42:06.7972824Z` through
  `2026-10-24T04:42:06.7974358Z`; raw downloaded run-log lines 5209–5212.
- Only the job/step/timestamp log envelope was removed; certificate text is
  unchanged. The other two splits printed identical certificate records.
- The hosted build-tools revision was **not recorded**; it cannot be inferred
  from this output. Future verifier invocations log their selected paths/revision.

Tests replay this captured output via a mocked SDK subprocess against labelled
ZIP fixtures; they do **not** execute an SDK or verify signed Android binaries.
Negative variants are deliberately synthetic mutations, not captured SDK output.
