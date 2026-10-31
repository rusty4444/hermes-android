# Embedded push distributor notice

Hermes Android uses the unmodified Library
`org.unifiedpush.android:embedded-fcm-distributor:3.1.0`, maintained by
[UnifiedPush](https://codeberg.org/UnifiedPush/android-embedded_fcm_distributor)
(publisher/developer: S1m, UnifiedPush). It provides the optional Google Play
Services transport. No Firebase or Google Play Services client SDK is bundled by
this dependency. Google infrastructure and a working Play Services runtime are
still required for that transport; external UnifiedPush remains supported.

## Licence basis: LGPL-2.1-or-later, not Apache-only

The exact upstream tag `3.1.0`, commit
`d618c7aceb5c9f139c8c21c2ae6116a7e44e1d2d`, supplies the GNU Lesser General
Public License, version 2.1, with the upstream notice permitting version 2.1
or (at your option) any later version. Copyright (C) 2022 Simon Gougeon.
**Treat that licence as authoritative for RC
packaging and distribution.** The Maven POM's Apache-2.0 declaration conflicts
with that source licence. It is retained as provenance, not treated as a
permissive or dual-licence grant. No upstream clarification, legal clearance or
F-Droid approval has been obtained or is claimed.

The verbatim licence and its warranty disclaimer are in
`licenses/embedded-fcm-distributor-LGPL-2.1.txt`. The Library is supplied without
warranty under those terms. Its exact source, interfaces, manifest, build scripts,
Gradle wrapper, upstream notices and README are retained in
`sources/embedded-fcm-distributor-3.1.0/embedded-fcm-distributor-3.1.0-upstream.tar.gz`.
The published source JAR and POM are retained beside it; `manifest.json` records
their origin and SHA-256 hashes, the licence hash and the published AAR hash.
These materials are copied into the APK's `assets/third_party/` directory too,
so the recipient does not depend on an upstream URL to obtain Library source.
The APK's archive has the additional `.bin` suffix (remove only that suffix
after extracting it); this prevents Android's asset merger from decompressing
the verified `.tar.gz` automatically. Its bytes and SHA-256 remain unchanged.
No Library source files have been modified by Hermes Android.

The retained archive also contains separately Apache-2.0-licensed Gradle wrapper
scripts and a wrapper JAR. Their original copyright headers and archive bytes
remain unchanged. The scoped [NOTICE.md](NOTICE.md), complete
[Apache-2.0 text](licenses/Apache-2.0.txt) and retained
[Gradle NOTICE](licenses/gradle-NOTICE.txt) accompany that archive in the APK,
extracted build materials and the source/relink ZIP. These build-tool terms do
not relicense the Library or turn the conflicting POM into a dual-licence grant.

All 13 Kotlin files in the published source JAR were compared byte-for-byte with
the tagged source archive. The consumed published AAR was hashed and inspected.
That establishes source/package correspondence, not reproducible published
bytecode, upstream licensing intent, or device delivery acceptance.

## Modifying the Library and relinking the application

See [embedded-push-relink.md](embedded-push-relink.md) for exact verification,
extraction, rebuild and local-AAR substitution commands. Both the upstream build
scripts and a separate Hermes toolchain build adapter are supplied. A modified
Library can be relinked using `-PembeddedPushAar=/absolute/path/library.aar`
without editing production dependency declarations or obtaining a vendor project,
Firebase credential or Hermes release-signing key. Development builds use the
separate `.dev` application ID. A recipient's differently signed APK cannot update
the distributor's signed installation in place.

Each RC APK distribution must be accompanied by the **exact application's source
and relink/build materials**, not only a branch URL. Generate the corresponding
source/relink ZIP from the final APK commit with `tools/embedded_push_materials.py`,
retain it with the APKs, and record their hashes. The ZIP includes the complete
tracked application source and Library source/build archive. The distributor must
verify that the chosen commit actually produced those APKs and preserve all
applicable third-party notices and source permissions.

The LGPL's recipient rights, including modification of the Library and reverse
engineering for debugging such modifications, must not be restricted by an EULA
or other distribution terms. This notice does not relicense unrelated application
code or certify that all distribution obligations or application/contributor
permissions have been satisfied. The distributor must review those obligations
before publication. The application's existing README declared MIT before
these materials were added; the root `LICENSE` now records those terms in full.
The earlier absence of a canonical file was not absence of that declaration,
and this Library notice does not create or replace the application grant.
Source/relink materials are provided as a concrete compliance aid, not a legal
approval.
