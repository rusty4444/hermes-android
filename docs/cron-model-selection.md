# Per-cron model selection

Open **Crons**, use a job's overflow menu → **Edit**, and choose its **Model**.
Each option includes the provider. Saving pins that provider/model pair to that
job only; it does not change the profile's main model or other cron jobs.

Choose **Follow default** to clear both stored override fields. At execution
time Hermes resolves the per-job pin first, then `cron.model` /
`cron.model_provider`, then the main model. The Android app does not snapshot
those defaults into the job.

The picker discovers models from the saved connection's selected profile. An
existing custom or retired pair remains visible even when it is not returned
by discovery. Editing another field leaves the original override untouched.
If discovery fails, retry or retain/clear the existing pin; configure additional
custom models on the Hermes host. Script-only jobs keep their stored pin but
cannot change it while script-only mode is enabled.

## API and verification

- Discovery: `GET /api/model/options?profile=<selected>`.
- Job update: `PUT /api/cron/jobs/<id>?profile=<selected>` with
  `{"updates":{"model":"...","provider":"...",...}}`.
- Clearing: explicitly send `model: null` and `provider: null`.
- Unchanged override: omit both fields (do not normalize unknown values).
- Confirmation: `GET /api/cron/jobs/<id>?profile=<selected>`, checking the exact
  job ID and saved pair before displaying success. Rejection, HTTP failure,
  missing/wrong target or mismatching readback never display success.

All operations reuse `DashboardClient.fromConnection` to preserve the dashboard
origin, path prefix, authentication and client certificate configuration. An
explicit selected profile is not retried unscoped. Replacing the connection
invalidates an in-flight edit's notification/readback authority.

Regression coverage: `test/cron_model_selection_test.dart` (widgets, failure
paths, profile replacement and shipped translations) and
`test/cron_model_wire_test.dart` (real loopback HTTP with password-cookie auth,
prefixed origin, selected-profile discovery/update and fresh-client readback).
Fixtures do not mutate a user's cron jobs or configuration.
