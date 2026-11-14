"""Verify the Play AAB's package, identity, merged manifest and upload signer."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

if __package__:
    from .verify_release_apks import PRODUCTION_CERT_SHA256
else:
    from verify_release_apks import PRODUCTION_CERT_SHA256

ANDROID = "{http://schemas.android.com/apk/res/android}"


def _sha256(path: Path) -> str:
    state = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            state.update(chunk)
    return state.hexdigest()


def _manifest(path: Path, version: str, base: int) -> None:
    root = ET.parse(path).getroot()
    if root.get("package") != "com.hermesagent.hermes_android":
        raise ValueError("Play manifest has the wrong package")
    if root.get(ANDROID + "versionName") != version:
        raise ValueError("Play manifest has the wrong versionName")
    if root.get(ANDROID + "versionCode") != str(base):
        raise ValueError("Play AAB must use the un-split base versionCode")
    uses_sdk = root.find("uses-sdk")
    if uses_sdk is None or uses_sdk.get(ANDROID + "targetSdkVersion") != "36":
        raise ValueError("Play manifest must target API 36")
    if any(
        item.get(ANDROID + "name") == "android.permission.REQUEST_INSTALL_PACKAGES"
        for item in root.findall("uses-permission")
    ):
        raise ValueError("Play manifest still requests package installation")
    if any(
        (item.get(ANDROID + "authorities") or "").endswith(".update_provider")
        for item in root.findall("./application/provider")
    ):
        raise ValueError("Play manifest still contains the APK update provider")
    application = root.find("application")
    if application is None or application.get(ANDROID + "label") != "Ares":
        raise ValueError("Play application label must be Ares")


def _bundle(path: Path, allow_unsigned: bool) -> None:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Play AAB contains duplicate ZIP entries")
        if "base/manifest/AndroidManifest.xml" not in names:
            raise ValueError("Play AAB has no base manifest")
        if not any(name.startswith("base/dex/") for name in names):
            raise ValueError("Play AAB has no application DEX")
        signed = any(
            name.startswith("META-INF/") and name.endswith((".RSA", ".DSA", ".EC"))
            for name in names
        )
    if not allow_unsigned and not signed:
        raise ValueError("Play AAB is unsigned")


def _verify_signer(path: Path) -> None:
    java_home = os.environ.get("JAVA_HOME")
    if not java_home:
        raise ValueError("JAVA_HOME is required for Play AAB signer verification")
    keytool = Path(java_home) / "bin" / "keytool"
    result = subprocess.run(
        [str(keytool), "-printcert", "-jarfile", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError("keytool could not read the Play AAB signer")
    fingerprints = []
    for match in re.finditer(r"(?im)^\s*SHA-?256:\s*([0-9A-Fa-f:]+)\s*$", result.stdout):
        fingerprints.append(match.group(1).replace(":", "").lower())
    if fingerprints != [PRODUCTION_CERT_SHA256]:
        raise ValueError("Play AAB signer does not match the production certificate")


def verify(bundle: Path, manifest: Path, allow_unsigned: bool = False) -> dict:
    match = re.search(
        r"^version:\s*([^\s+]+)\+(\d+)\s*$",
        Path("pubspec.yaml").read_text(),
        re.M,
    )
    if match is None:
        raise ValueError("pubspec.yaml must declare versionName+versionCode")
    version, base_text = match.groups()
    base = int(base_text)
    _manifest(manifest, version, base)
    _bundle(bundle, allow_unsigned)
    if not allow_unsigned:
        _verify_signer(bundle)
    return {
        "bundle": bundle.name,
        "version_name": version,
        "version_code": base,
        "package": "com.hermesagent.hermes_android",
        "target_api": 36,
        "install_permission_removed": True,
        "update_provider_removed": True,
        "signed": not allow_unsigned,
        "sha256": _sha256(bundle),
        "size": bundle.stat().st_size,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--merged-manifest", required=True, type=Path)
    parser.add_argument("--allow-unsigned", action="store_true")
    args = parser.parse_args()
    try:
        report = verify(args.bundle, args.merged_manifest, args.allow_unsigned)
    except (OSError, ValueError, ET.ParseError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Play AAB verification failed: {error}") from error
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
