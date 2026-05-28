# Release Checklist

Run through this before every release PR. Mark each item ✅ or ⚠️.

## Analysis
- [ ] `flutter analyze` — zero errors
- [ ] `flutter pub outdated` — key deps current
- [ ] `flutter build apk --release --split-per-abi` — clean build

## Architecture
- [ ] State management consistency (no orphaned setState vs Riverpod)
- [ ] No orphaned imports
- [ ] Error handling on all network calls
- [ ] `dispose()` on all `StatefulWidget`s with controllers/timers
- [ ] WebSocket lifecycle (connect/dispose)

## UX
- [ ] Error states visible (not silent failures)
- [ ] Loading indicators on network calls
- [ ] Responsive layout (phone + tablet)
- [ ] Dark mode follows system
- [ ] Input validation (no empty submits)

## Security
- [ ] Session token auto-discovery
- [ ] No hardcoded API keys
- [ ] Proper URL scheme validation

## Release
- [ ] Version bumped in `pubspec.yaml`
- [ ] CHANGELOG.md updated
- [ ] CI/CD builds clean APK
- [ ] GitHub Actions workflow passes
- [ ] Tag pushed (`git tag v0.x.y && git push origin main --tags`)

## Testing (Android Emulator / Device)
- [ ] Connect to dashboard
- [ ] Browse sessions
- [ ] Send message → see response
- [ ] Delete session
- [ ] Search sessions
- [ ] Settings → model selection
