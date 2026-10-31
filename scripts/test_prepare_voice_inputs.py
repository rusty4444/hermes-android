"""Pinned input preparation regressions; no acoustic or Android device claims."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock
import urllib.error

from scripts import prepare_voice_inputs as voice


class PrepareVoiceInputsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = json.loads(voice.MANIFEST.read_text())

    def pin(self, data=b"exact pinned bytes"):
        return {"url": "https://example.invalid/fixed.aar", "github_asset_id": 123,
                "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    def test_fixed_manifest_and_native_asset_hashes_match(self):
        self.assertEqual("2.0.1", self.manifest["runtime_version"])
        self.assertEqual("af2d8d81dbfa61c4cea4c568da78f3982edca005", self.manifest["source_commit"])
        self.assertEqual(678742021, self.manifest["runtime_download"]["github_asset_id"])
        self.assertEqual(166405338, self.manifest["model_download"]["github_asset_id"])
        source = (voice.ROOT / "android/app/src/main/kotlin/com/hermesagent/hermes_android/SherpaWakeDetector.kt").read_text()
        self.assertEqual(5253530, sum(pin["bytes"] for pin in self.manifest["runtime_files"]))
        for pin in self.manifest["runtime_files"]:
            self.assertIn(pin["sha256"], source)
        keyword = self.manifest["keyword"]
        self.assertEqual("▁HE Y ▁HER ME S @Hey_Hermes\n", keyword["utf8_contents"])
        self.assertEqual(keyword["sha256"], hashlib.sha256(keyword["utf8_contents"].encode()).hexdigest())
        self.assertIn(keyword["sha256"], source)

    def test_changed_size_and_same_size_wrong_hash_are_rejected(self):
        path = self.root / "fixed.aar"
        pin = self.pin(b"original")
        for content in (b"short", b"modified"):
            path.write_bytes(content)
            with self.assertRaises(voice.VerificationError):
                voice.verify_file(path, pin)

    def test_corrupt_cache_fails_closed_without_network_or_replacement(self):
        path = self.root / "fixed.aar"
        path.write_bytes(b"corrupt")
        with mock.patch.object(voice.urllib.request, "urlopen") as network:
            with self.assertRaises(voice.VerificationError):
                voice.fetch(self.pin(), self.root, None, False)
            network.assert_not_called()
        self.assertEqual(b"corrupt", path.read_bytes())

    def test_explicit_local_input_must_exist_and_pass_pin(self):
        with mock.patch.object(voice.urllib.request, "urlopen") as network:
            with self.assertRaises(voice.VerificationError):
                voice.fetch(self.pin(), self.root / "cache", self.root, False)
            network.assert_not_called()
        (self.root / "fixed.aar").write_bytes(b"exact pinned bytes")
        self.assertEqual(self.root / "fixed.aar", voice.fetch(self.pin(), self.root / "cache", self.root, True))

    def test_offline_cache_miss_never_fetches(self):
        with mock.patch.object(voice.urllib.request, "urlopen") as network:
            with self.assertRaises(voice.VerificationError):
                voice.fetch(self.pin(), self.root, None, True)
            network.assert_not_called()

    def test_download_fallback_uses_fixed_asset_id_and_verified_bytes(self):
        content = b"exact pinned bytes"
        with mock.patch.object(voice.urllib.request, "urlopen", side_effect=[urllib.error.URLError("blocked"), io.BytesIO(content)]) as network:
            target = voice.fetch(self.pin(content), self.root, None, False)
        self.assertEqual(content, target.read_bytes())
        self.assertEqual("https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/assets/123", network.call_args_list[1].args[0].full_url)
        self.assertEqual("application/octet-stream", network.call_args_list[1].args[0].headers["Accept"])

    def test_bad_download_never_becomes_a_build_input(self):
        with mock.patch.object(voice.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong")):
            with self.assertRaises(voice.VerificationError):
                voice.fetch(self.pin(), self.root, None, False)
        self.assertFalse((self.root / "fixed.aar").exists())
        self.assertEqual([], list(self.root.iterdir()))

    def archive(self, member_type=None):
        path = self.root / "model.tar.bz2"
        data = b"fixture weights for packaging validation, NOT inference"
        name = voice.MODEL_ROOT + "/encoder.onnx"
        pin = self.pin(data) | {"archive_member": name, "apk_asset": "voice/kws-en/encoder.onnx"}
        with tarfile.open(path, "w:bz2") as archive:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            if member_type is not None:
                info.type = member_type
                info.linkname = "/outside"
            archive.addfile(info, io.BytesIO(data) if member_type is None else None)
            readme = b"---\nlicense: Apache License 2.0\n---\noriginal fixture README\n"
            info = tarfile.TarInfo(voice.MODEL_ROOT + "/README.md")
            info.size = len(readme)
            archive.addfile(info, io.BytesIO(readme))
            extra = tarfile.TarInfo("../must-not-be-extracted")
            extra.size = 3
            archive.addfile(extra, io.BytesIO(b"bad"))
        manifest = {"runtime_files": [pin], "keyword": self.manifest["keyword"]}
        return path, manifest

    def test_only_selected_regular_verified_model_files_and_original_readme_are_extracted(self):
        path, manifest = self.archive()
        assets = voice.selected_assets(path, manifest)
        self.assertEqual({"voice/kws-en/encoder.onnx", "voice/kws-en/keywords.txt", "third_party/voice/model-README.md"}, set(assets))
        self.assertIn(b"original fixture README", assets["third_party/voice/model-README.md"])
        self.assertFalse((self.root.parent / "must-not-be-extracted").exists())

    def test_symlink_model_member_is_rejected(self):
        path, manifest = self.archive(tarfile.SYMTYPE)
        with self.assertRaises(voice.VerificationError):
            voice.selected_assets(path, manifest)

    def test_selected_model_and_literal_keyword_tampering_are_rejected(self):
        path, manifest = self.archive()
        manifest["runtime_files"][0]["sha256"] = "0" * 64
        with self.assertRaises(voice.VerificationError):
            voice.selected_assets(path, manifest)
        path, manifest = self.archive()
        manifest["keyword"] = manifest["keyword"] | {"utf8_contents": "wrong\n"}
        with self.assertRaises(voice.VerificationError):
            voice.selected_assets(path, manifest)

    def test_notice_bytes_are_pinned_and_gradle_owns_preparation_dependency(self):
        for name, digest in voice.LICENSE_HASHES.items():
            self.assertEqual(digest, voice.sha256(voice.ROOT / "third_party/voice/licenses" / name))
        gradle = (voice.ROOT / "android/app/build.gradle.kts").read_text()
        self.assertIn('.builtBy(prepareVoiceInputs)', gradle)
        self.assertIn('implementation(voiceAar)', gradle)
        self.assertIn('dependsOn(prepareVoiceInputs)', gradle)
        self.assertIn('outputs.upToDateWhen { false }', gradle)

    @unittest.skipUnless(os.environ.get("HERMES_VOICE_INPUT_DIR"), "Real artifacts are verified by every Gradle native build; optionally supply input directory here")
    def test_real_pinned_artifacts_prepare_reproducibly_without_untracked_models(self):
        output = self.root / "generated"
        receipt = voice.prepare(output, self.root / "cache", Path(os.environ["HERMES_VOICE_INPUT_DIR"]), True)
        second = voice.prepare(output, self.root / "cache", Path(os.environ["HERMES_VOICE_INPUT_DIR"]), True)
        self.assertEqual(receipt, second)
        self.assertEqual(10, len(receipt["packaged_assets"]))
        for name, pin in receipt["packaged_assets"].items():
            voice.verify_file(output / "assets" / name, pin)
        self.assertEqual(self.manifest["runtime_download"]["sha256"], voice.sha256(output / "sherpa-onnx-2.0.1.aar"))


if __name__ == "__main__":
    unittest.main()
