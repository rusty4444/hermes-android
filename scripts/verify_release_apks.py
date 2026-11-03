"""Offline, fail-closed checks of the actual APKs before release creation.

Uses an explicitly configured, already installed Android SDK and Java runtime.
Packaged assets are compared with Git blobs at the full publication commit, not
with potentially dirty working files. No build, signing, download or remote write.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

PACKAGE_NAME = "com.hermesagent.hermes_android"
# Public production identity, not an environment-configurable trust anchor.
PRODUCTION_CERT_SHA256 = (
    "475baf431b16d050c8f658ac838783b273f7c10bba06ed1d16bb0a4239f592fb"
)
ABI_CODES = {"armeabi-v7a": 1, "arm64-v8a": 2, "x86_64": 3}
APK_NAMES = tuple(f"app-{abi}-release.apk" for abi in ABI_CODES)
SOURCE_DIRECTORY = "third_party/sources/embedded-fcm-distributor-3.1.0"
NATIVE_SOURCES = (
    "third_party/embedded-push-notice.md",
    "third_party/embedded-push-relink.md",
    "third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt",
    f"{SOURCE_DIRECTORY}/embedded-fcm-distributor-3.1.0-sources.jar",
    f"{SOURCE_DIRECTORY}/embedded-fcm-distributor-3.1.0-upstream.tar.gz",
    f"{SOURCE_DIRECTORY}/embedded-fcm-distributor-3.1.0.pom",
    f"{SOURCE_DIRECTORY}/manifest.json",
    "third_party/NOTICE.md",
    "third_party/licenses/Apache-2.0.txt",
    "third_party/licenses/gradle-NOTICE.txt",
)
FLUTTER_SOURCES = (
    "LICENSE",
    "assets/fonts/OFL.txt",
    "assets/fonts/Cinzel-Variable.ttf",
    *NATIVE_SOURCES[:3],
    "third_party/NOTICE.md",
    "third_party/licenses/graphify-MIT.txt",
    "third_party/licenses/hermes-agent-MIT.txt",
    "third_party/licenses/flutter-BSD-3-Clause.txt",
    "third_party/licenses/Apache-2.0.txt",
    "third_party/licenses/gradle-NOTICE.txt",
)
ASSET_SOURCES = {
    **{
        f"assets/{source}" + (".bin" if source.endswith(".tar.gz") else ""): source
        for source in NATIVE_SOURCES
    },
    **{f"assets/flutter_assets/{source}": source for source in FLUTTER_SOURCES},
}


def git_blob(root: Path, target: str, source: str) -> bytes:
    return subprocess.check_output(
        ["git", "cat-file", "blob", f"{target}:{source}"], cwd=root, timeout=30
    )


def committed_identity(root: Path, target: str) -> tuple[str, int]:
    pubspec = git_blob(root, target, "pubspec.yaml")
    if pubspec != (root / "pubspec.yaml").read_bytes():
        raise ValueError("pubspec.yaml differs from the publication commit")
    declarations = re.findall(r"^version:.*$", pubspec.decode("utf-8"), re.MULTILINE)
    match = re.fullmatch(
        r"version:[ \t]+([0-9]+\.[0-9]+\.[0-9]+"
        r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)\+([1-9][0-9]*)[ \t]*",
        declarations[0] if len(declarations) == 1 else "",
    )
    if match is None:
        raise ValueError("Committed pubspec.yaml needs one versionName+versionCode")
    return match.group(1), int(match.group(2))


def executable(path: Path) -> bool:
    return path.is_file() and os.access(path, os.X_OK)


def sdk_tools() -> tuple[Path, Path]:
    roots = {
        Path(value).expanduser().resolve()
        for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT")
        if (value := os.environ.get(name))
    }
    if len(roots) != 1 or not next(iter(roots)).is_dir():
        raise ValueError(
            "Android SDK requires one consistent ANDROID_HOME/ANDROID_SDK_ROOT"
        )
    sdk = next(iter(roots))
    candidates = []
    for directory in (sdk / "build-tools").glob("*"):
        if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", directory.name) is None:
            continue
        version = tuple(int(part) for part in directory.name.split("."))
        # apksigner first shipped in 24.0.3. Do not mix tools from different
        # revisions, use previews, or fall back after a selected tool fails.
        if version >= (24, 0, 3) and all(
            executable(directory / tool) for tool in ("aapt", "apksigner")
        ):
            candidates.append((version, directory))
    if not candidates:
        raise ValueError(
            "Android SDK has no compatible executable aapt/apksigner build-tools pair"
        )
    _, selected = max(candidates)
    print(
        f"Android SDK: {sdk}; build-tools revision: {selected.name}; "
        f"aapt: {selected / 'aapt'}; apksigner: {selected / 'apksigner'}",
        file=sys.stderr,
        flush=True,
    )
    return selected / "aapt", selected / "apksigner"


def tool_output(command: list[str]) -> str:
    try:
        return subprocess.check_output(
            command, text=True, stderr=subprocess.STDOUT, timeout=60
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError(
            f"{Path(command[0]).name} verification command failed"
        ) from error


def verify_java() -> None:
    home = os.environ.get("JAVA_HOME")
    java = Path(home) / "bin/java" if home else Path(shutil.which("java") or "")
    if not executable(java):
        raise ValueError("Java runtime is missing or not executable")
    tool_output([str(java), "-version"])


def unique_json_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate material manifest key: {key}")
        result[key] = value
    return result


def reject_json_constant(value: str) -> None:
    raise ValueError(f"Non-RFC JSON constant: {value}")


def committed_assets(root: Path, target: str) -> dict[str, bytes]:
    sources = {
        source: git_blob(root, target, source)
        for source in sorted(set(ASSET_SOURCES.values()))
    }
    try:
        manifest = json.loads(
            sources[f"{SOURCE_DIRECTORY}/manifest.json"],
            object_pairs_hook=unique_json_object,
            parse_constant=reject_json_constant,
        )
    except ValueError as error:
        raise ValueError(f"Malformed material manifest: {error}") from error
    file_sources = NATIVE_SOURCES[3:6]
    if not isinstance(manifest, dict) or not isinstance(manifest.get("files"), dict):
        # Invalid serialized content, not an incorrectly typed Python argument.
        raise ValueError("Malformed material manifest files metadata")  # noqa: TRY004
    if set(manifest["files"]) != {Path(source).name for source in file_sources}:
        raise ValueError("Material manifest must describe all retained source files")
    for source in file_sources:
        record = manifest["files"][Path(source).name]
        if (
            not isinstance(record, dict)
            or record.get("sha256") != hashlib.sha256(sources[source]).hexdigest()
        ):
            raise ValueError(f"Material manifest hash mismatch: {source}")
    if (
        manifest.get("licence_sha256")
        != hashlib.sha256(sources[NATIVE_SOURCES[2]]).hexdigest()
    ):
        raise ValueError("Material manifest licence hash mismatch")
    return {entry: sources[source] for entry, source in ASSET_SOURCES.items()}


def verify_badging(output: str, abi: str, version_name: str, version_code: int) -> None:
    package_lines = [
        line for line in output.splitlines() if line.startswith("package:")
    ]
    if (
        len(package_lines) != 1
        or re.fullmatch(
            r"package: (?:[A-Za-z][A-Za-z0-9]*='[^'\r\n]*'[ \t]*)+", package_lines[0]
        )
        is None
    ):
        raise ValueError("Malformed or duplicate APK package metadata")
    pairs = re.findall(r"([A-Za-z][A-Za-z0-9]*)='([^']*)'", package_lines[0])
    attributes = dict(pairs)
    if len(attributes) != len(pairs):
        raise ValueError("Duplicate APK package metadata field")
    for field, expected in (
        ("name", PACKAGE_NAME),
        ("versionName", version_name),
        ("versionCode", str(version_code)),
    ):
        if attributes.get(field) != expected:
            label = "package" if field == "name" else field
            raise ValueError(
                f"APK {label} mismatch: expected {expected!r}, found {attributes.get(field)!r}"
            )
    native_lines = [
        line for line in output.splitlines() if line.startswith("native-code:")
    ]
    if native_lines != [f"native-code: '{abi}'"]:
        raise ValueError(f"APK ABI must be exactly {abi!r}; found {native_lines!r}")


def verify_signer(output: str) -> None:
    error = (
        "APK signer must be the single pinned production SHA-256 certificate"
    )
    # These are the two observed current-signer record formats. Do not search
    # arbitrary certificate/public-key/source-stamp text for the pinned digest.
    fields = {
        "certificate DN": r".+",
        "certificate SHA-256 digest": r"[0-9a-fA-F]{64}",
        "certificate SHA-1 digest": r"[0-9a-fA-F]{40}",
        "certificate MD5 digest": r"[0-9a-fA-F]{32}",
        "key algorithm": r"[A-Za-z0-9-]+",
        "key size (bits)": r"[1-9][0-9]*",
        "public key SHA-256 digest": r"[0-9a-fA-F]{64}",
        "public key SHA-1 digest": r"[0-9a-fA-F]{40}",
        "public key MD5 digest": r"[0-9a-fA-F]{32}",
    }
    records = {}
    prefix = None
    signer_count_seen = False
    for line in output.splitlines():
        if line.startswith("Number of signers:"):
            if signer_count_seen or line != "Number of signers: 1":
                raise ValueError(error)
            signer_count_seen = True
            continue
        match = re.fullmatch(
            r"(Signer #1 |V2 Signer: )([^:]+):[ \t]*(.*)", line
        )
        if match is None:
            if re.search(r"signer|certificate|public key", line, re.IGNORECASE):
                raise ValueError(error)
            continue
        current_prefix, field, value = match.groups()
        if (
            (prefix is not None and current_prefix != prefix)
            or field in records
            or field not in fields
            or re.fullmatch(fields[field], value) is None
        ):
            raise ValueError(error)
        prefix = current_prefix
        # Count records, not unique digests: duplicate identical signers are
        # ambiguous too, including a second DN without its SHA-256 line.
        records[field] = value
    if records.get("certificate SHA-256 digest", "").lower() != PRODUCTION_CERT_SHA256:
        raise ValueError(error)


def verify_packaged_assets(apk: Path, expected: dict[str, bytes]) -> None:
    try:
        with zipfile.ZipFile(apk) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise ValueError(f"APK {apk.name} contains duplicate ZIP entries")
            for entry, content in expected.items():
                if entry not in names:
                    raise ValueError(
                        f"APK {apk.name} is missing required asset: {entry}"
                    )
                if (
                    archive.getinfo(entry).file_size != len(content)
                    or archive.read(entry) != content
                ):
                    raise ValueError(
                        f"APK {apk.name} asset differs from publication Git blob: {entry}"
                    )
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        raise ValueError(f"APK {apk.name} is not a readable, valid ZIP") from error


def verify_release_apks(directory: Path, target: str, root: Path = Path(".")) -> dict:
    """Verify all three actual splits, or raise before publication is possible."""
    if re.fullmatch(r"[0-9a-f]{40}", target) is None:
        raise ValueError("APK verification requires the full publication commit SHA")
    apks = [directory / name for name in APK_NAMES]
    if {path.name for path in directory.glob("*.apk")} != set(APK_NAMES) or not all(
        path.is_file() and path.stat().st_size > 0 for path in apks
    ):
        raise ValueError(
            "APK verification requires exactly the three nonempty release ABI APKs"
        )
    version_name, base_code = committed_identity(root, target)
    expected = committed_assets(root, target)
    aapt, apksigner = sdk_tools()
    verify_java()
    verified = []
    for apk, (abi, offset) in zip(apks, ABI_CODES.items()):
        effective_code = base_code * 10 + offset
        try:
            verify_badging(
                tool_output([str(aapt), "dump", "badging", str(apk)]),
                abi,
                version_name,
                effective_code,
            )
            verify_signer(
                tool_output([str(apksigner), "verify", "--print-certs", str(apk)])
            )
            verify_packaged_assets(apk, expected)
        except ValueError as error:
            raise ValueError(f"{apk.name}: {error}") from error
        verified.append(
            {
                "name": apk.name,
                "abi": abi,
                "version_code": effective_code,
                "verified_assets": len(expected),
            }
        )
    return {
        "application_commit": target,
        "version_name": version_name,
        "base_version_code": base_code,
        "signer_sha256": PRODUCTION_CERT_SHA256,
        "apks": verified,
        "qualification": "Identity and packaged Git-blob checks only; not legal clearance, proof of build provenance or bit-identical builds.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True, help="Full publication commit SHA")
    parser.add_argument("--assets-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        report = verify_release_apks(args.assets_dir, args.target)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f"APK pre-publication verification failed: {error}") from error
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
