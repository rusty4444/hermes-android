# Voice message drafts

Open a chat's actions menu and choose **Record voice message**. Pause the
recording, play it back, or continue recording more parts. Send uses the combined
recording once; it does not send each part as a separate prompt. The existing
microphone control for system dictation remains available.

Recordings are limited to ten minutes and 6 MiB. They are kept in private app
storage per connection and chat. Leaving the chat or backgrounding the app stops
the microphone and retains the draft. Reopen the chat to continue it. Discard
removes the draft; no microphone starts automatically on restore.

## Sending and server compatibility

Send posts the M4A recording to the configured Hermes Dashboard's existing
`POST /api/audio/transcribe` route, using its existing authentication and selected
profile. The request uses `data_url` and `mime_type`; the reply must include
`ok: true` and a nonempty `transcript`. That recognized text becomes one ordinary
user message through the connection's existing chat transport. It remains
visible in the normal transcript; the feature does not archive a playable audio
attachment in chat history.

The authenticated route and profile contract were checked against Hermes
v0.21.7 source. Server STT must already be configured, and the connection must
have access to its configured Dashboard URL. An API-server-only proxy that does
not expose the Dashboard transcription route will show a failure and retain the
recording. The app does not enable endpoints, change server configuration or
fall back to another server.

The raw recording stays on the phone until Send. The configured Hermes server
may use local or cloud STT according to its settings. The app never fetches STT
provider credentials or sends the recording directly to a third-party provider.
Server temporary-file handling is owned by the existing transcription route.

## Failure and draft safety

Transcription, upload and definite prompt failures retain the recording. A
socket write or HTTP headers alone do not discard it. Reply/tool activity,
authoritative recovery acknowledgement or a new canonical user row can establish
acceptance. When delivery is uncertain, check the chat before manually retrying;
there is no automatic prompt resubmission.

An unrelated typed draft and selected attachments are preserved while the voice
message is sent. They are not silently added to its recognized text. Local
continuation fragments are joined on Android's media APIs, with a journal and
hash check so an interrupted join does not silently discard a fragment or send
only the original clip.

## Dependencies and verification

Recording uses pinned `record` 7.1.1 and preview uses `audioplayers` 6.8.1.
The lockfile adds their federated packages without upgrading existing packages.
Android concatenation uses platform `MediaExtractor`/`MediaMuxer`; no FFmpeg,
client model, external service or automatic runtime download is added.

New copy uses AppLocalizations. English strings are provided; other locales use
the generated English fallback until translations are reviewed.

Tests use synthetic recordings and mocked microphone/transcription boundaries.
Android microphone permission, real codec concatenation and preview playback
still require device testing for the contribution build.
