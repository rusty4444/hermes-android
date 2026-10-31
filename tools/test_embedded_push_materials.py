#!/usr/bin/env python3
"""Offline regression tests for the embedded Library's source/relink materials."""
import io
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
import zipfile

import embedded_push_materials as materials

BUILD_NOTICES = (
    Path("third_party/NOTICE.md"),
    Path("third_party/licenses/Apache-2.0.txt"),
    Path("third_party/licenses/gradle-NOTICE.txt"),
)


class EmbeddedPushMaterialsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="embedded-push-materials-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for relative in [
            materials.SOURCES,
            materials.LICENCE,
            *BUILD_NOTICES,
            Path("third_party/embedded-push-notice.md"),
            Path("third_party/embedded-push-relink.md"),
            Path("tools/embedded_push_materials.py"),
        ]:
            source = materials.ROOT / relative
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir():
                shutil.copytree(source, target)
            else:
                shutil.copyfile(source, target)

    def test_retained_sources_and_tagged_licence_match(self):
        self.assertEqual(materials.verify(self.root)["verified_kotlin_files"], 13)
        output = self.root / "extracted"
        materials.extract_source(self.root, output)
        self.assertTrue((output / materials.LIBRARY_ROOT / "gradlew").is_file())
        self.assertEqual((output / materials.LIBRARY_ROOT / "LICENSE").read_bytes(), (self.root / materials.LICENCE).read_bytes())
        for relative in BUILD_NOTICES:
            self.assertEqual((output / relative).read_bytes(), (self.root / relative).read_bytes())

    def test_wrapper_notice_hashes_and_unchanged_upstream_archive(self):
        hashes = {
            "embedded-fcm-distributor-3.1.0-upstream.tar.gz": "e8de0b337b561badf30da4be9ca039fc2fd95b02cd538c9b26024989fab5aef9",
            "embedded-fcm-distributor-3.1.0-sources.jar": "5b483568a352ccd89c31c8ab1e4f981897db5b2661f27635651c0f8bc5ba9e8f",
            "embedded-fcm-distributor-3.1.0.pom": "5e8df76984675050ddf921bbfc6db8edc3dcdc74501020711fa82d4ea095f803",
            "manifest.json": "73bec2da88f3e2f1699ae198059fa708a1c8ba31b13a9ee1736c9d451f9fb992",
        }
        for name, digest in hashes.items():
            self.assertEqual(materials.sha256((self.root / materials.SOURCES / name).read_bytes()), digest, name)
        with tarfile.open(self.root / materials.SOURCES / "embedded-fcm-distributor-3.1.0-upstream.tar.gz") as archive:
            for name, digest in {
                "gradlew": "a3648413b47ef77af21d5ebc36c687c7d103aaef3e17f33de7d4f080a6f300a3",
                "gradlew.bat": "57931b17dd228e5c24dac90e815d0bf82477e831a4618dfab4136f5446b42a9f",
                "gradle/wrapper/gradle-wrapper.jar": "e996d452d2645e70c01c11143ca2d3742734a28da2bf61f25c82bdc288c9e637",
            }.items():
                self.assertEqual(materials.sha256(materials.tar_bytes(archive, f"{materials.LIBRARY_ROOT}/{name}")), digest, name)

    def test_missing_or_altered_wrapper_notices_are_rejected(self):
        for relative in ("third_party/licenses/Apache-2.0.txt", "third_party/licenses/gradle-NOTICE.txt"):
            path = self.root / relative
            original = path.read_bytes()
            path.write_bytes(original + b"fixture tamper")
            with self.assertRaisesRegex(ValueError, "Build notice hash mismatch"):
                materials.verify(self.root)
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                materials.verify(self.root)
            path.write_bytes(original)

    def test_tampered_published_source_is_rejected(self):
        path = self.root / materials.SOURCES / "embedded-fcm-distributor-3.1.0-sources.jar"
        path.write_bytes(path.read_bytes() + b"fixture tamper")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            materials.verify(self.root)

    def test_missing_or_empty_scope_inventory_is_rejected(self):
        path = self.root / "third_party/NOTICE.md"
        path.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "Build notice hash mismatch"):
            materials.verify(self.root)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            materials.verify(self.root)

    def test_tampered_licence_and_nonpublished_aar_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "AAR hash mismatch"):
            materials.verify(self.root, self.root / materials.LICENCE)
        (self.root / materials.LICENCE).write_text("fixture tamper")
        with self.assertRaisesRegex(ValueError, "licence hash mismatch"):
            materials.verify(self.root)

    def test_extraction_rejects_path_traversal_before_writes(self):
        archive = self.root / materials.SOURCES / "embedded-fcm-distributor-3.1.0-upstream.tar.gz"
        with tarfile.open(archive, "w:gz") as fixture:
            member = tarfile.TarInfo("../outside")
            member.size = 3
            fixture.addfile(member, io.BytesIO(b"bad"))
        with patch.object(materials, "verify"), self.assertRaisesRegex(ValueError, "Unsafe"):
            materials.extract_source(self.root, self.root / "extracted")
        self.assertFalse((self.root / "outside").exists())

    def test_extraction_rejects_notice_symlinks_before_writes(self):
        output = self.root / "extracted"
        outside = self.root / "outside"
        output.mkdir()
        outside.mkdir()
        (output / "third_party").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Unsafe build notice output"):
            materials.extract_source(self.root, output)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse((output / materials.LIBRARY_ROOT).exists())

    def test_bundle_is_exact_commit_and_excludes_untracked_material(self):
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()
        git("init", "-q")
        git("add", "third_party", "tools")
        git("-c", "user.name=Hermes Agent", "-c", "user.email=hermes-agent@users.noreply.github.com", "commit", "-qm", "fixture source materials")
        commit = git("rev-parse", "HEAD")
        (self.root / "untracked-secret").write_text("test-only sentinel")
        output = self.root / "bundle.zip"
        report = materials.source_bundle(self.root, commit, output, [])
        self.assertEqual(report["application_commit"], commit)
        with zipfile.ZipFile(output) as bundle:
            for relative in BUILD_NOTICES:
                self.assertEqual(bundle.read(relative.as_posix()), (self.root / relative).read_bytes())
            manifest = json.loads(bundle.read("distribution-manifest.json"))
            application = bundle.read("hermes-android-source.tar.gz")
            self.assertEqual(manifest["application_source_sha256"], materials.sha256(application))
            with tarfile.open(fileobj=io.BytesIO(application), mode="r:gz") as source:
                self.assertNotIn("untracked-secret", source.getnames())
                self.assertIn(str(materials.LICENCE), source.getnames())
                self.assertIn("third_party/licenses/Apache-2.0.txt", source.getnames())
        for relative in (*BUILD_NOTICES, Path("third_party/embedded-push-notice.md")):
            path = self.root / relative
            original = path.read_bytes()
            path.write_bytes(original + b"uncommitted fixture")
            with self.subTest(material=relative), self.assertRaisesRegex(ValueError, "differ from the requested commit"):
                materials.source_bundle(self.root, commit, self.root / "rejected.zip", [])
            self.assertFalse((self.root / "rejected.zip").exists())
            path.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
