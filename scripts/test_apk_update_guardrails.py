"""Regression checks for the GitHub APK updater's static trust boundaries."""

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from scripts.verify_release_apks import PRODUCTION_CERT_SHA256

ROOT = Path(__file__).resolve().parents[1]
ANDROID = "{http://schemas.android.com/apk/res/android}"


class ApkUpdateGuardrailsTest(unittest.TestCase):
    def test_updater_uses_public_release_signer(self):
        source = (
            ROOT / "android/app/src/main/kotlin/com/hermesagent/hermes_android/ApkUpdateInstaller.kt"
        ).read_text()
        match = re.search(r'PRODUCTION_SIGNER_SHA256\s*=\s*"([a-f0-9]{64})"', source)
        self.assertIsNotNone(match)
        if match is None:
            return
        self.assertEqual(match.group(1), PRODUCTION_CERT_SHA256)

    def test_updater_hosts_only_trust_system_cas(self):
        root = ET.parse(ROOT / "android/app/src/main/res/xml/network_security_config.xml").getroot()
        domains = root.findall("domain-config")
        domain_config = next(
            config for config in domains
            if "release-assets.githubusercontent.com" in [entry.text for entry in config.findall("domain")]
        )
        self.assertEqual(
            {entry.text for entry in domain_config.findall("domain")},
            {"api.github.com", "github.com", "release-assets.githubusercontent.com"},
        )
        self.assertEqual(domain_config.get("cleartextTrafficPermitted"), "false")
        self.assertEqual(
            [entry.get("src") for entry in domain_config.findall("./trust-anchors/certificates")],
            ["system"],
        )
        self.assertEqual(
            {entry.get("src") for entry in root.findall("./base-config/trust-anchors/certificates")},
            {"system", "user"},
        )

    def test_installer_provider_is_private_and_narrow(self):
        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml").getroot()
        self.assertIn(
            "android.permission.REQUEST_INSTALL_PACKAGES",
            [item.get(ANDROID + "name") for item in manifest.findall("uses-permission")],
        )
        provider = next(
            item for item in manifest.findall("./application/provider")
            if item.get(ANDROID + "authorities") == "${applicationId}.update_provider"
        )
        self.assertEqual(provider.get(ANDROID + "exported"), "false")
        self.assertEqual(provider.get(ANDROID + "grantUriPermissions"), "true")
        paths = ET.parse(ROOT / "android/app/src/main/res/xml/update_file_paths.xml").getroot()
        self.assertEqual([(item.tag, item.get("path")) for item in paths], [("cache-path", "apk_update/")])


if __name__ == "__main__":
    unittest.main()
