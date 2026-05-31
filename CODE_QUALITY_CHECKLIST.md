# Code Quality Checklist — Pre-release Review Process

This checklist must be completed before every release PR. Mark each item as passed, noted, or not applicable in the release PR description.

## Analysis
- [ ] `flutter analyze` — zero errors, warnings reviewed and noted
- [ ] `flutter pub outdated` — key dependencies checked and update decisions recorded
- [ ] `flutter test` — test suite passes
- [ ] `flutter build apk --release --split-per-abi` — clean release build

## Architecture
- [ ] State management is consistent for each screen or feature (Riverpod / `setState` usage is intentional)
- [ ] No orphaned imports, dead code, or unused assets
- [ ] Network calls have visible error handling paths
- [ ] `StatefulWidget` resources are disposed correctly (`TextEditingController`, `ScrollController`, timers, streams, WebSockets)
- [ ] WebSocket and streaming lifecycles connect, cancel, and dispose cleanly

## UX
- [ ] Error states are visible to the user, not silent failures
- [ ] Loading indicators are shown where network calls or long-running actions happen
- [ ] Layout is responsive on phone and tablet breakpoints
- [ ] Dark mode follows the system setting unless the user explicitly overrides it
- [ ] Forms validate required fields and prevent empty submissions

## Security
- [ ] No API keys, access tokens, or local secrets are committed
- [ ] User-provided hosts and URLs are validated or normalised before use
- [ ] Sensitive values are masked in logs, screenshots, and release notes

## Release
- [ ] Version bumped in `pubspec.yaml`
- [ ] `CHANGELOG.md` updated, or release notes drafted if the changelog is intentionally deferred
- [ ] CI/CD builds a clean APK, or the local build command and output path are recorded
- [ ] Release PR links to this checklist and includes any exceptions

## Manual smoke testing
- [ ] Connect to a Hermes Gateway API Server
- [ ] Browse sessions
- [ ] Send a message and receive a streamed response
- [ ] Open Memory, Cron Jobs, Skills, and Settings drawer screens when dashboard access is configured
- [ ] Verify behaviour on at least one phone-sized layout and one wider/tablet layout
