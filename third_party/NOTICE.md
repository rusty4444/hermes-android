# Third-party source/build material notices

This inventory scopes separately licensed copied material in the source tree and
in the retained embedded-Library build materials. The complete licence files
below are verbatim upstream texts. Showing these notices in About does not mean
the corresponding source templates or build tools execute in the Android app.
These notices supplement, and do not replace, dependency-generated notices.
Paths below are relative to the complete application source checkout; source-only
copies and their notices are retained in the source/relink ZIP's application
source archive, not installed as executable Android assets.

The application remains under the existing [MIT notice](../LICENSE),
Copyright (c) 2026 Sam Russell and contributors. This inventory does not relicense
third-party material, assign contributors' copyrights, certify originality or
claim legal clearance or F-Droid acceptance.

## Graphify viewer template — source material

Scope: the copied CSS/JavaScript viewer template in `graphify-out/graph.html`,
not the application's original source or the generated graph facts. The viewer
is distributed in source, **not an application runtime asset**. Its template
matches `_html_styles`, `_html_script` and `_hyperedge_script` from
<https://github.com/Graphify-Labs/graphify/blob/b6ffdbb8dd8eeec73f02d939f43e3320db06b461/graphify/export.py>.
That source file has SHA-256
`b1a7a53ee3b21aa1e3d07e4168819c8f577ebc95fdedfd57d3a6ed3a1e281984`.
This identifies a matching MIT-era template, not the generator version installed
by the contributor. The original viewer before the added provenance comment has
SHA-256 `cbc504a7a703007d342f5b878fdf685fef04c5c1284f46bc1d06f336994cf05f`;
no graph data or executable template code was changed by the notice repair.

Copyright (c) 2026 Safi Shamsi. Licence: MIT.
Complete copyright, permission and warranty text: [licenses/graphify-MIT.txt](licenses/graphify-MIT.txt).
Original: <https://github.com/Graphify-Labs/graphify/blob/b6ffdbb8dd8eeec73f02d939f43e3320db06b461/LICENSE>.
Licence SHA-256: `36ecff6bbb97aca1be64e95f42538cf796adde5864edac583e620643c096931a`.
The viewer's existing vis-network 9.1.6 CDN reference is external, not a vendored
library; its independent terms are not replaced by this template notice.

## Hermes Agent message templates — source material

Scope: copied backend template text in
`test/fixtures/internal_background_messages.json`, produced by
`tools/capture_internal_message_fixture.py`. These are test/source materials,
**not application runtime assets**, and this notice does not change the message
payloads, canonical roles or protocol. The fixture records backend commit
`bf0203a794a07aac3ff764972ab9087baa4e4f4e` and has SHA-256
`2fc48814c1cd7b62e9c07fce9356b97163fe63d39ff6de2be04acf7f9411d04a`.
Seven literal/formatted template copies were verified at that snapshot:

- `continuation_prompt_template`
- `continuation_prompt_with_contract_template`
- `continuation_prompt_with_subgoals_template`
- `continuation_prompt_gate_failed_template`
- `compression_continuation_user_content`
- `legacy_compression_continuation_user_content`
- `max_iterations_summary_request`

The standing-goal sources are
<https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/hermes_cli/goals.py>,
SHA-256 `f87f4115d790c0b17183cf3fb72f455b04b4dda6cbafe57efb081dd3d42a0023`.
The compression/iteration sources are
<https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/agent/context_compressor.py>,
SHA-256 `065dc9babbcb811a514c32319ed13a6ddaeefbc3964a109f7bb8e4c9260779d1`.
Keep the corresponding upstream notices when recapturing other backend versions;
this provenance is not a new licence for other authors' copied materials.

Copyright (c) 2025 Nous Research. Licence: MIT.
Complete copyright, permission and warranty text: [licenses/hermes-agent-MIT.txt](licenses/hermes-agent-MIT.txt).
Original: <https://github.com/NousResearch/hermes-agent/blob/bf0203a794a07aac3ff764972ab9087baa4e4f4e/LICENSE>.
Licence SHA-256: `821556e6336796450ab852d375117b48a4887e71d255794fd6318d99982a5ab6`.

## Flutter iOS scaffold — source material

Scope: `ios/Runner/AppDelegate.swift`, a byte-identical copy of Flutter 3.44.0's
scaffold at
<https://github.com/flutter/flutter/blob/559ffa3f75e7402d65a8def9c28389a9b2e6fe42/packages/flutter_tools/templates/app/ios.tmpl/Runner/AppDelegate.swift>.
Source/copy SHA-256:
`451c6d9ba0a2b3ff43092ea349c60fa79a91f1158b915eb29dbdd357cb95d7b8`.
This conservative attribution covers that copied scaffold, not a claim that all
Flutter-generated application code is third-party code. The iOS scaffold is
**not compiled into the Android application**. Flutter framework/dependency
notices remain separate.

Copyright 2014 The Flutter Authors. All rights reserved. Licence: BSD-3-Clause.
Complete copyright, conditions and disclaimer: [licenses/flutter-BSD-3-Clause.txt](licenses/flutter-BSD-3-Clause.txt).
Original: <https://github.com/flutter/flutter/blob/559ffa3f75e7402d65a8def9c28389a9b2e6fe42/LICENSE>.
Licence SHA-256: `a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20`.

## Gradle wrapper — Library build material

Scope: `gradlew`, `gradlew.bat` and `gradle/wrapper/gradle-wrapper.jar` inside
`sources/embedded-fcm-distributor-3.1.0/embedded-fcm-distributor-3.1.0-upstream.tar.gz`
(the archive's root is `android-embedded_fcm_distributor/`). They are unmodified
Apache-2.0 build tools, **not executed by the application**. They accompany the
Library's complete source in the APK and the separate source/relink ZIP. The
Library itself remains **LGPL-2.1-or-later** with its existing Simon Gougeon
attribution; this wrapper notice does not resolve the Library POM discrepancy
by relabelling the Library Apache-2.0.

The complete retained Library archive is from upstream commit
`d618c7aceb5c9f139c8c21c2ae6116a7e44e1d2d` and remains byte-unchanged, SHA-256
`e8de0b337b561badf30da4be9ca039fc2fd95b02cd538c9b26024989fab5aef9`.
Original wrapper scripts:
<https://codeberg.org/UnifiedPush/android-embedded_fcm_distributor/src/commit/d618c7aceb5c9f139c8c21c2ae6116a7e44e1d2d/gradlew>
and
<https://codeberg.org/UnifiedPush/android-embedded_fcm_distributor/src/commit/d618c7aceb5c9f139c8c21c2ae6116a7e44e1d2d/gradlew.bat>.
Their existing headers are retained verbatim, including:

- `Copyright © 2015-2021 the original authors.` (`gradlew`, SHA-256 `a3648413b47ef77af21d5ebc36c687c7d103aaef3e17f33de7d4f080a6f300a3`)
- `Copyright 2015 the original author or authors.` (`gradlew.bat`, SHA-256 `57931b17dd228e5c24dac90e815d0bf82477e831a4618dfab4136f5446b42a9f`)

The retained 59,203-byte wrapper JAR has SHA-256
`e996d452d2645e70c01c11143ca2d3742734a28da2bf61f25c82bdc288c9e637`.
It is byte-identical to the older Gradle 7.0.2 repository JAR at
<https://github.com/gradle/gradle/blob/1ef1b260d39daacbf9357f9d8594a8a743e2152e/gradle/wrapper/gradle-wrapper.jar>;
[Gradle's checksum reference](https://gradle.org/release-checksums/) also records
that digest for multiple 6.6–7.0.2/6.9.x releases. The configured download version
8.13 is **not** the wrapper JAR's version. Neither the full downloaded Gradle
distribution nor those runtime dependencies are vendored here.
The matching wrapper's source retains `Copyright 2007 the original author or authors.`:
<https://github.com/gradle/gradle/blob/1ef1b260d39daacbf9357f9d8594a8a743e2152e/subprojects/wrapper/src/main/java/org/gradle/wrapper/GradleWrapperMain.java>.

Complete Apache-2.0 text, including the appendix: [licenses/Apache-2.0.txt](licenses/Apache-2.0.txt),
from <https://www.apache.org/licenses/LICENSE-2.0.txt>.
Licence SHA-256: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.
The original Library archive and its wrapper JAR contain no NOTICE file. For
conservative retention, the matching Gradle snapshot's complete distribution
NOTICE is supplied unchanged as [licenses/gradle-NOTICE.txt](licenses/gradle-NOTICE.txt),
from
<https://github.com/gradle/gradle/blob/1ef1b260d39daacbf9357f9d8594a8a743e2152e/subprojects/distributions-full/src/toplevel/NOTICE>.
NOTICE SHA-256: `d3d569a7f18525b229a7daa4926faf3e0566371f66686b157d62cdf7b3a0b3b3`.
Its references to other software describe the **full Gradle distribution**, not
additional bundled Android libraries or code in this small wrapper JAR.

Keep this inventory, the Apache text and Gradle NOTICE alongside the unchanged
Library archive; `tools/embedded_push_materials.py` also copies them alongside
extracted source and duplicates them in the separately accessible source/relink
ZIP materials. The APK retains the archive's `.tar.gz.bin` alias to preserve the
original compressed bytes; remove only `.bin` after extracting it.

## Existing independent notices

Cinzel remains under the SIL OFL 1.1 in [../assets/fonts/OFL.txt](../assets/fonts/OFL.txt).
The embedded Library remains subject to
[embedded-push-notice.md](embedded-push-notice.md),
[embedded-push-relink.md](embedded-push-relink.md) and
[licenses/embedded-fcm-distributor-LGPL-2.1.txt](licenses/embedded-fcm-distributor-LGPL-2.1.txt).
Those complete existing MIT/OFL/LGPL texts and copyright notices are unchanged.
This inventory is scoped to the identified copied source/build materials; it is
not an exhaustive SBOM or a replacement for other dependencies' licences.
