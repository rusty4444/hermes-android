import os
import re
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from scripts import verify_play_bundle

ROOT = Path(__file__).resolve().parents[1]


class VerifyPlayBundleTest(unittest.TestCase):
    def setUp(self):
        self.previous = Path.cwd()
        os.chdir(ROOT)
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        match = re.search(
            r"^version:\s*([^\s+]+)\+(\d+)\s*$",
            (ROOT / "pubspec.yaml").read_text(),
            re.M,
        )
        self.assertIsNotNone(match)
        assert match is not None
        self.version, base_text = match.groups()
        self.base = int(base_text)
        self.manifest = self.dir / "AndroidManifest.xml"
        self.bundle = self.dir / "app-release.aab"
        self._manifest()
        with zipfile.ZipFile(self.bundle, "w") as archive:
            archive.writestr("base/manifest/AndroidManifest.xml", b"binary-manifest")
            archive.writestr("base/dex/classes.dex", b"dex")

    def tearDown(self):
        os.chdir(self.previous)
        self.temp.cleanup()

    def _manifest(self, extra=""):
        self.manifest.write_text(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="com.hermesagent.hermes_android" '
            f'android:versionName="{self.version}" '
            f'android:versionCode="{self.base}">'
            '<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/>'
            f'{extra}'
            '<application android:label="Ares"/>'
            '</manifest>'
        )

    def test_unsigned_fixture_verifies_structure_only(self):
        report = verify_play_bundle.verify(
            self.bundle, self.manifest, allow_unsigned=True
        )
        self.assertEqual(report["version_code"], self.base)
        self.assertTrue(report["install_permission_removed"])
        self.assertFalse(report["signed"])

    def test_install_permission_is_rejected(self):
        self._manifest(
            '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>'
        )
        with self.assertRaisesRegex(ValueError, "package installation"):
            verify_play_bundle.verify(self.bundle, self.manifest, allow_unsigned=True)

    def test_update_provider_is_rejected(self):
        self._manifest(
            '<application android:label="Ares"><provider '
            'android:authorities="com.hermesagent.hermes_android.update_provider"/>'
            '</application>'
        )
        with self.assertRaisesRegex(ValueError, "update provider"):
            verify_play_bundle.verify(self.bundle, self.manifest, allow_unsigned=True)

    def test_wrong_base_or_target_is_rejected(self):
        self._manifest()
        text = self.manifest.read_text().replace(
            f'versionCode="{self.base}"', f'versionCode="{self.base * 10 + 2}"'
        )
        self.manifest.write_text(text)
        with self.assertRaisesRegex(ValueError, "un-split"):
            verify_play_bundle.verify(self.bundle, self.manifest, allow_unsigned=True)

    def test_unsigned_bundle_cannot_pass_the_signed_gate(self):
        with self.assertRaisesRegex(ValueError, "unsigned"):
            verify_play_bundle.verify(self.bundle, self.manifest)

    def test_signer_pin_is_checked(self):
        digest = verify_play_bundle.PRODUCTION_CERT_SHA256
        colon = ":".join(digest[i : i + 2] for i in range(0, len(digest), 2))
        with patch.dict(os.environ, {"JAVA_HOME": "/fixture"}), patch.object(
            verify_play_bundle.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                [], 0, stdout=f"SHA256: {colon}\n", stderr=""
            ),
        ):
            verify_play_bundle._verify_signer(self.bundle)
        with patch.dict(os.environ, {"JAVA_HOME": "/fixture"}), patch.object(
            verify_play_bundle.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 0, stdout="SHA256: 00\n"),
        ):
            with self.assertRaisesRegex(ValueError, "signer"):
                verify_play_bundle._verify_signer(self.bundle)


if __name__ == "__main__":
    unittest.main()
