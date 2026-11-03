# Existing MIT licence and contribution evidence

## Resolution

Hermes Android's application licence was already MIT before the community
contributions. The historical absence of a standalone `LICENSE` file did not
mean the README contained no licence notice. The complete terms were subsequently
added to the canonical [LICENSE](../../LICENSE), with contributor attribution,
and the confusing [NOTICE](../../NOTICE.md) was corrected.[9]

The evidence below supports continuing the existing MIT distribution without
making fresh confirmation from every historical contributor a prerequisite.
It does not relicense third-party material. Identified copied-template and build
material notices are preserved separately in [the component inventory](../../third_party/NOTICE.md).
No contributor's silence is treated as consent, and no copyright assignment or
claim of exclusive ownership is inferred.

## 1. MIT predates the contributions

The README first declared exactly `## License` / `MIT` in maintainer commit
[`4ad169557182c08446eee129253495efa05ab589`](https://github.com/rusty4444/hermes-android/blob/4ad169557182c08446eee129253495efa05ab589/README.md),
27 May 2026. That commit precedes the audited contributions; it is not a notice
added retrospectively after their submission.[1]

For [PR #88](https://github.com/rusty4444/hermes-android/pull/88):

- Common base: [`aa6b71060a2e4f53616778a2a7117162611dcd97`](https://github.com/rusty4444/hermes-android/blob/aa6b71060a2e4f53616778a2a7117162611dcd97/README.md).
- Source head: [`72f13ad90c1c234b5c2f373f70883164d40917e7`](https://github.com/rusty4444/hermes-android/blob/72f13ad90c1c234b5c2f373f70883164d40917e7/README.md).
- Actual integration parent: `ad6956148d19ccfb6ac556ed5c1fe1ccc111a353`.
- Merge: [`6079f83ebf2d7eaa76b2af915e7def086a830c37`](https://github.com/rusty4444/hermes-android/blob/6079f83ebf2d7eaa76b2af915e7def086a830c37/README.md).

All **56 source commits** retain the identical licence-bearing README blob,
`800877c0e5d590167cc78f9931eeb39f1805a979`. The merge also retains MIT. The
independent `License: MIT` declaration in the historical `fdroiddata.yml` remains
unchanged through that series.[2][3][4] No contrary contributor-specific licence or
separate agreement was identified in the public submission and discussions.
The later unanswered confirmation request is not evidence that these earlier
terms were absent.

The complete PR #88 change set is **142 paths**, not merely the subset for which
the GitHub Files API supplies patches. Full Git-object comparison reconciled
**136,175 additions / 536 deletions**, including the dependency and generated
output files omitted from some API patch/statistic fields.

## 2. Applicable contribution terms

GitHub Terms of Service effective **27 April 2026**, section D.6,
**Contributions Under Repository License**, state:[5][6]

> Whenever you add Content to a repository containing notice of a license, you
> license that Content under the same terms, and you agree that you have the
> right to license that Content under those terms. If you have a separate
> agreement to license that Content under different terms, such as a contributor
> license agreement, that agreement will supersede.[5][6]

Primary sources:

- [27 April publishing-source version](https://github.com/github/docs/blob/301baf10d6e9c8f89460eea6b9ad577b2de6fdb9/content/site-policy/github-terms/github-terms-of-service.md#6-contributions-under-repository-license).
- [24 July publishing-source version](https://github.com/github/docs/blob/de34d5d495d1cd6e7e843075faae2d8f34e8fbb7/content/site-policy/github-terms/github-terms-of-service.md#6-contributions-under-repository-license), with the same effective date and unchanged D.6.
- [GitHub's licence documentation](https://github.com/github/docs/blob/2bbf57a64839909eac94b7c759e27576b81dd1f3/content/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository.md), which recognises README licence declarations and recommends a complete licence file.[7]

The contribution provision concerns a repository **containing notice of a
licence**, not a specifically named file. This is the inbound-under-existing-MIT
basis, distinct from D.5's public viewing/forking permission. It cannot convert
someone else's copied component to MIT or override an actually identified
separate agreement.[5][6]

The policy history was checked against both GitHub's publishing source and its
separately maintained policy mirror. Source commit dates, effective dates and
published-page verification were kept distinct; this is not a claim to possess
an archived HTTP response for every contributor's submission day.

## 3. The inherited NOTICE did not remove MIT

The [original Remote Gateway NOTICE](https://github.com/rusty4444/hermes-android/blob/6d9a8bf730c4ba4d74e0322847e757944470ff4a/NOTICE.md)
says the upstream snapshot lacked a licence **file** and that the fork did not
**add** an upstream grant. Its [README in that same commit](https://github.com/rusty4444/hermes-android/blob/6d9a8bf730c4ba4d74e0322847e757944470ff4a/README.md)
still declares MIT, as does the parent snapshot.[8]

Read together, those statements do not expressly revoke MIT or establish a
superseding agreement for new application contributions. The old wording was
confusing and deserved correction. Commit
[`c3eecfa4d3978cfb00a78d3aa5a77e7fde02fac0`](https://github.com/rusty4444/hermes-android/commit/c3eecfa4d3978cfb00a78d3aa5a77e7fde02fac0)
added the complete MIT file and clarified that existing application terms do not
relicense dependencies or assets.[9] This correction was already present in stable
3.0.3; the historical grant conclusion does not pretend that the full file
existed earlier.

## 4. Whole-contribution coverage

The historical boundary is stable 3.0.3, commit
`b61648bd8b6831997bc0fc8c6abd5471f0dda617`:

- **132 merged PRs**, including **34 externally submitted PRs**.
- **718 stable-reachable commits**, **552 distinct enumerated PR source commits**,
  and **797 distinct stable/source commit snapshots**.
- Every audited PR's common ancestor, enumerated source commits, head and merge
  retain the pre-existing MIT declaration. The 118 distinct README blobs were
  independently checked against their Git identities and saved SHA-256 values.
- The 33 external PRs other than #88 received a separate full changed-body review;
  PR #88's 56-commit series received its own historical-content review. Git author
  metadata and the absence of contrary headers were not treated as proof of
  originality or sole ownership.

[The machine-readable evidence index](contribution-evidence.json) records the
exact PR identities, common bases, integration parents, heads, source commit
lists, merge commits and notice blob identities. It is a fixed historical audit,
not a claim to cover future PRs automatically.

The Remote Gateway import retains its **23 original commits**, including the
15 labelled `Codex <codex@local>`, and their attribution. The
[public fork submission](https://github.com/rusty4444/hermes-android/issues/81) and
[additional original-material confirmation](https://github.com/rusty4444/hermes-android/issues/81#issuecomment-6108110695)
are preserved. That confirmation excludes third-party contributions and is not
expanded into ownership of them.[10] The same pre-existing-notice evidence covers
maebahesioru's localisation/notification contributions; the separate Thaeland and
igitur confirmations are corroboration, not a requirement to obtain a new grant
for every contributor.

## 5. Specific third-party notice corrections

The audit found identifiable grants with notice-retention defects, not an
unidentified author-consent problem:

- **Graphify viewer:** retain Safi Shamsi's historical MIT notice for the matched
  generated HTML template, with a pointer from the viewer. Today's generator
  licence is not used to guess the older copied template's terms.
- **Hermes backend message fixtures:** retain Nous Research's upstream MIT notice
  for copied template text, without changing the recorded message payloads.
- **Gradle wrapper in the embedded Library source archive:** supply the complete
  Apache-2.0 text and scoped attribution alongside the unchanged, hash-bound
  upstream archive. The Library itself remains LGPL-2.1-or-later.
- **Flutter scaffolding:** conservatively retain Flutter's BSD-3-Clause notice
  for the identified template copy, separately from original application code.

See [the component inventory](../../third_party/NOTICE.md) for exact source pins,
applicability and verbatim licences. Cinzel's OFL, the embedded Library's LGPL,
other dependency notices, corresponding source and relink rights remain intact.

## Distribution and review boundary

This resolves the documented historical-contribution and identified-notice
questions using existing grants; it is not a new licence or a blanket warranty of
originality. Undisclosed private agreements, every possible copied input and an
exhaustive native/transitive dependency legal review cannot be established from
public Git history alone. No such unresolved private agreement is alleged here.

Final APK/source correspondence and F-Droid reproducible-build acceptance are
separate executed checks. A successful build does not by itself prove licensing,
and this evidence does not pre-empt a distributor's review. See
[the 3.0.4 release notes](../releases/3.0.4.md) for the distribution containing the
notice corrections.

Hermes Agent assisted with evidence collection, independent audit, notice
corrections and regression tests. Original contributor credits and history are
preserved.

## Sources

[1] https://github.com/rusty4444/hermes-android/blob/4ad169557182c08446eee129253495efa05ab589/README.md
[2] https://github.com/rusty4444/hermes-android/blob/aa6b71060a2e4f53616778a2a7117162611dcd97/README.md
[3] https://github.com/rusty4444/hermes-android/blob/72f13ad90c1c234b5c2f373f70883164d40917e7/README.md
[4] https://github.com/rusty4444/hermes-android/blob/6079f83ebf2d7eaa76b2af915e7def086a830c37/README.md
[5] https://github.com/github/docs/blob/301baf10d6e9c8f89460eea6b9ad577b2de6fdb9/content/site-policy/github-terms/github-terms-of-service.md
[6] https://github.com/github/docs/blob/de34d5d495d1cd6e7e843075faae2d8f34e8fbb7/content/site-policy/github-terms/github-terms-of-service.md
[7] https://github.com/github/docs/blob/2bbf57a64839909eac94b7c759e27576b81dd1f3/content/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository.md
[8] https://github.com/rusty4444/hermes-android/blob/6d9a8bf730c4ba4d74e0322847e757944470ff4a/NOTICE.md
[9] https://github.com/rusty4444/hermes-android/commit/c3eecfa4d3978cfb00a78d3aa5a77e7fde02fac0
[10] https://github.com/rusty4444/hermes-android/issues/81
