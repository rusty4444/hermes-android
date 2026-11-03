"""Offline consistency checks for the fixed historical contribution index."""

import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHA = re.compile(r"[0-9a-f]{40}")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate evidence key: {key}")
        result[key] = value
    return result


class LicenceEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.index = json.loads(
            (ROOT / "docs/licensing/contribution-evidence.json").read_text(),
            object_pairs_hook=unique_object,
        )
        self.prs = self.index["pull_requests"]
        self.scope = self.index["scope"]

    def test_inventory_counts_and_immutable_source_identities(self):
        self.assertEqual(self.index["schema_version"], 1)
        self.assertEqual(len(self.prs), self.scope["merged_prs"])
        self.assertEqual(len({p["pr"] for p in self.prs}), len(self.prs))
        self.assertEqual(
            sum(p["author"] != "rusty4444" for p in self.prs),
            self.scope["external_prs"],
        )
        source_commits = set()
        for pr in self.prs:
            self.assertEqual(len(pr["source_shas"]), pr["source_commits"])
            self.assertEqual(len(set(pr["source_shas"])), pr["source_commits"])
            for sha in [
                pr["common_base"], pr["integration_parent"],
                pr["head"], pr["merge"], *pr["source_shas"],
            ]:
                self.assertRegex(sha, r"^[0-9a-f]{40}$")
            for commit, oid in pr["readme_blobs"].items():
                self.assertIsNotNone(SHA.fullmatch(commit))
                self.assertIsNotNone(SHA.fullmatch(oid))
            self.assertEqual(
                pr["url"],
                f"https://github.com/rusty4444/hermes-android/pull/{pr['pr']}",
            )
            source_commits.update(pr["source_shas"])
        self.assertEqual(len(source_commits), self.scope["unique_pr_source_commits"])

    def test_pr88_boundary_and_readme_identity_are_retained(self):
        pr = next(p for p in self.prs if p["pr"] == 88)
        self.assertEqual(pr["author"], "CarlosReyesPena")
        self.assertEqual(pr["source_commits"], 56)
        self.assertEqual(pr["changed_files_api"], 142)
        self.assertEqual(pr["common_base"], "aa6b71060a2e4f53616778a2a7117162611dcd97")
        self.assertEqual(pr["head"], "72f13ad90c1c234b5c2f373f70883164d40917e7")
        self.assertEqual(pr["merge"], "6079f83ebf2d7eaa76b2af915e7def086a830c37")
        self.assertEqual(
            pr["readme_blobs"][pr["head"]],
            self.scope["pr88_source_readme_blob"],
        )
        self.assertEqual(
            pr["readme_blobs"][pr["common_base"]],
            self.scope["pr88_source_readme_blob"],
        )

    def test_scope_is_historical_not_automatic_future_clearance(self):
        self.assertEqual(
            self.scope["historical_boundary"],
            "b61648bd8b6831997bc0fc8c6abd5471f0dda617",
        )
        self.assertEqual(
            self.scope["mit_declaration_introduced"],
            "4ad169557182c08446eee129253495efa05ab589",
        )
        explanation = (ROOT / "docs/licensing/README.md").read_text()
        self.assertIn("a fixed historical audit", explanation)
        self.assertIn("separate agreement", explanation)
        self.assertIn("third-party", explanation)
        self.assertIn("No contributor's silence is treated as consent", explanation)


if __name__ == "__main__":
    unittest.main()
