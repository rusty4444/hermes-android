"""Local-only release identity/material gates; no SDK or network required."""

import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseCandidateMaterialsTest(unittest.TestCase):
    def setUp(self):
        pubspec = (ROOT / "pubspec.yaml").read_text()
        match = re.search(r"^version:\s*([^\s+]+)\+(\d+)\s*$", pubspec, re.M)
        self.assertIsNotNone(match)
        assert match is not None
        self.version, code = match.groups()
        self.base = int(code)

    def test_store_notes_cover_base_and_every_split(self):
        directory = ROOT / "fastlane/metadata/android/en-US/changelogs"
        notes = (directory / f"{self.base}.txt").read_text()
        self.assertTrue(notes.strip())
        self.assertLessEqual(len(notes), 500)
        for abi in (1, 2, 3):
            self.assertEqual(
                (directory / f"{self.base * 10 + abi}.txt").read_text(), notes
            )

    def test_stable_readme_targets_and_full_scope_notes(self):
        self.assertEqual(self.version, "3.2.0")
        self.assertEqual(self.base, 3026)
        readme = (ROOT / "README.md").read_text()
        self.assertIn("# Hermes Android v3.2.0", readme)
        self.assertIn("**3.2.0** (base build **3026**)", readme)
        self.assertIn("Publication pending", readme)
        for abi, digit in (("armeabi-v7a", 1), ("arm64-v8a", 2), ("x86_64", 3)):
            line = next(line for line in readme.splitlines()
                        if f"releases/download/v{self.version}/app-{abi}-release.apk" in line)
            self.assertIn(f"`{self.base * 10 + digit}`", line)
        self.assertIn(f"releases/tag/v{self.version}", readme)
        self.assertIn("For v3.2.0, base `3026` produces codes `30261`/`30262`/`30263`.", readme)
        changelog = (ROOT / "CHANGELOG.md").read_text()
        self.assertEqual(re.findall(r"^## \[3\.2\.0[^]]*\]", changelog, re.M), ["## [3.2.0]"])
        notes = (ROOT / "docs/releases/3.2.0.md").read_text()
        self.assertIn("all changes\nsince the last published stable 3.1.7", notes)
        for surface in ("More → Usage", "Provider sign-in", "More → Agent → Model",
                        "Crons → Edit → Model", "REST run approvals", "LAN repairs"):
            self.assertIn(surface, notes)
        for filename in ("provider-usage.md", "provider-oauth.md", "model-management.md",
                         "cron-model-selection.md"):
            self.assertTrue((ROOT / "docs" / filename).is_file())

    def test_workflow_identity_guards_accept_identity_reject_wrong_base(self):
        for filename in ("release.yml", "pr-quality.yml"):
            with self.subTest(workflow=filename):
                workflow = (ROOT / ".github/workflows" / filename).read_text()
                step = workflow.split(
                    "      - name: Verify release identity and upgrade versionCode\n", 1
                )[1].split("      - name:", 1)[0]
                values = dict(re.findall(r"^\s+(\w+): '([^']*)'$", step, re.M))
                self.assertEqual(values["REQUIRED_BASE_VERSION_CODE"], str(self.base))
                self.assertEqual(values["MINIMUM_INSTALLED_VERSION_CODE"], "2127")
                code = step.split("<<'PY'\n", 1)[1].split("          PY", 1)[0]
                code = "\n".join(line[10:] for line in code.splitlines())
                environment = dict(os.environ)
                environment.update(values)
                environment["ARM64_ABI_CODE"] = "2"
                environment.update(
                    GITHUB_REF_TYPE="tag", GITHUB_REF_NAME=f"v{self.version}"
                )

                def run(overrides):
                    return subprocess.run(
                        [sys.executable, "-c", code], cwd=ROOT,
                        env={**environment, **overrides},
                        capture_output=True, text=True, check=False,
                    )

                valid = run({})
                self.assertEqual(valid.returncode, 0, valid.stderr)
                wrong_base = run({"REQUIRED_BASE_VERSION_CODE": str(self.base - 1)})
                self.assertNotEqual(wrong_base.returncode, 0)
                self.assertIn("does not match required base", wrong_base.stderr)
                if filename == "release.yml":
                    wrong_tag = run({"GITHUB_REF_NAME": "v0.0.0-wrong"})
                    self.assertNotEqual(wrong_tag.returncode, 0)
                    self.assertIn("does not match", wrong_tag.stderr)

    def test_dart_identity_expectations_and_upgrade_floor(self):
        dart = (ROOT / "test/release_identity_test.dart").read_text()
        self.assertIn(f"expect(match!.group(1), '{self.version}')", dart)
        self.assertIn(f"expect(baseCode, {self.base})", dart)
        splits = [self.base * 10 + abi for abi in (1, 2, 3)]
        self.assertIn(str(splits), dart)
        self.assertGreater(min(splits), 30253)
        gradle = (ROOT / "android/app/build.gradle.kts").read_text()
        self.assertIn("minimumInstalledVersionCode = 2127", gradle)
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn(
            "EXPECTED_RELEASE_CERT_SHA256: '"
            "475baf431b16d050c8f658ac838783b273f7c10bba06ed1d16bb0a4239f592fb'",
            release,
        )


if __name__ == "__main__":
    unittest.main()
