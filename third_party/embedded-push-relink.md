# Embedded Library source and relinking

This is a technical rebuild/relink path for the LGPL-2.1 embedded FCM distributor,
not legal clearance. Keep the licence and warranty disclaimer in
`licenses/embedded-fcm-distributor-LGPL-2.1.txt`; see `embedded-push-notice.md` for
the POM/source discrepancy and distribution checklist.

## What is supplied

- Exact tag `3.1.0` (`d618c7aceb5c9f139c8c21c2ae6116a7e44e1d2d`), including all
  source, interfaces, manifest, consumer rules, upstream build/wrapper scripts,
  README and licence: `sources/embedded-fcm-distributor-3.1.0/*-upstream.tar.gz`.
- Exact published source JAR and POM, with a hash/origin manifest in the same
  directory. All 13 published Kotlin files match the tagged source bytes.
- Accompanying `NOTICE.md`, `licenses/Apache-2.0.txt` and
  `licenses/gradle-NOTICE.txt` for the separately licensed wrapper/build tools.
  These accompany the unmodified archive and extracted source without changing
  the Library's LGPL licence or the retained upstream bytes.
- Application source, Flutter lockfile, Android Gradle/build scripts and a local
  AAR substitution path. The exact-commit source/relink ZIP is generated below.
- `tools/embedded-push-rebuild/`: a separate build adapter using the app's cached
  AGP 9.0.1 / SDK 36 toolchain, without upstream Dokka/publishing. It does **not**
  modify the Library source. It uses Kotlin language level 2.1, JVM target 1.8,
  coroutines 1.10.2, and the app-aligned Kotlin stdlib 2.3.20. This is not a claim
  of a bit-identical rebuild of Maven's AAR.

## Verify and obtain editable source (offline)

Run from the Hermes Android source root with Python 3.11 or newer:

```sh
python3 tools/embedded_push_materials.py
python3 tools/embedded_push_materials.py --aar /absolute/path/embedded-fcm-distributor-3.1.0.aar
python3 tools/embedded_push_materials.py --extract /absolute/path/editable-source
```

`--aar` checks the exact published AAR hash; a rebuilt/modified AAR is expected to
have a different hash and must not be labelled the original. No command downloads
or installs dependencies, contacts Hermes, or needs credentials.

## Rebuild

The upstream project's own scripts are preserved. Its build requests Gradle 8.13,
AGP 8.13.2, Kotlin 2.3.0, Android SDK 37.0 and Dokka 2.2.0. These tools/dependencies
must already be available or be obtained separately by the person rebuilding.
An offline rebuild in the RC workspace could not resolve Dokka 2.2.0; no package
was installed to conceal that failure.

The alternative build adapter avoids documentation/publishing plugins. With JDK
17, an installed Gradle 9.1.0 and Android SDK 36, the following builds the unchanged
or recipient-edited source using the app's toolchain:

```sh
export JAVA_HOME=/absolute/path/to/jdk17
export ANDROID_HOME=/absolute/path/to/Android/sdk
export TMPDIR=/absolute/path/to/your/build-scratch
# Create TMPDIR first; keep paths absolute. Dependency caches may be required.
gradle --offline --no-daemon -p tools/embedded-push-rebuild \
  -PembeddedPushSource=/absolute/path/editable-source/android-embedded_fcm_distributor \
  assembleRelease
```

The output is `tools/embedded-push-rebuild/build/outputs/aar/hermes-embedded-push-rebuild-release.aar`.
If you modify Library files, preserve upstream notices, mark your modifications
and supply the modified corresponding source under the applicable LGPL terms.
The separate Hermes build adapter is application tooling, not a modification of
the retained upstream archive.

## Relink / build an APK with the rebuilt Library

Use Flutter 3.44.0 / Dart 3.12.0, JDK 17 and the Android SDK specified by the app.
No release keystore is needed for a development build:

```sh
flutter pub get --offline
export ORG_GRADLE_PROJECT_embeddedPushAar=/absolute/path/hermes-embedded-push-rebuild-release.aar
flutter build apk --debug
unset ORG_GRADLE_PROJECT_embeddedPushAar
```

The Gradle property substitutes the local AAR for Maven's Library and explicitly
retains its Kotlin/coroutines runtime dependencies. With no property, the original
Maven coordinate remains the default. The debug app has a separate `.dev` package;
it does not require the production signing certificate and cannot silently
replace the production package. Direct native compilation/relink checks can use
`:app:compileDebugKotlin -PembeddedPushAar=/absolute/path/library.aar` after normal
Flutter project configuration. Direct Gradle calls in a fresh source checkout
must first set Flutter's version extension to the pubspec version (the app rejects
the default low version code); running the Flutter build handles that setup.

## Accompany the exact final RC binaries

After committing the exact source used by the final build, generate a NEW bundle:

```sh
python3 tools/embedded_push_materials.py --ref FULL_COMMIT_SHA \
  --bundle /absolute/path/hermes-android-source-relink.zip \
  --apk /absolute/path/arm64.apk --apk /absolute/path/arm32.apk --apk /absolute/path/x86_64.apk
```

The tool archives only tracked files at that commit, never ignored/untracked
keystores, local settings or caches. It rejects a commit predating these materials
or current source materials that differ from that commit. The bundle contains:

- `hermes-android-source.tar.gz`: exact tracked application and build source;
- a separately accessible Library source/build archive, source JAR, POM, LGPL
  text, scoped notices, complete wrapper Apache text/Gradle NOTICE and rebuild
  instructions;
- `distribution-manifest.json`: full source commit, application archive hash and
  supplied APK hashes. Hashing is not proof that the source produced those APKs;
  the distributor must verify and retain the build's association.

Distribute/retain that ZIP with the corresponding APKs. `assets/third_party/` in
each APK additionally carries the Library source/build archive and notices.
Inside the APK only, the exact archive is named `*-upstream.tar.gz.bin` to stop
Android's asset merger from silently unpacking `.gz` assets. Remove `.bin` after
extracting; the resulting archive has the manifest's original SHA-256.
Check the actual APKs for these assets before distribution. This technical
material does not waive the remaining application/contributor permission review,
LGPL distribution review, or physical-device acceptance gates.
