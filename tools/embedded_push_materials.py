#!/usr/bin/env python3
"""Offline verification, safe extraction and exact-commit source/relink bundles.

Never downloads dependencies, signs an APK or contacts a live Hermes service.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = Path("third_party/sources/embedded-fcm-distributor-3.1.0")
LIBRARY_ROOT = "android-embedded_fcm_distributor"
LIBRARY_SOURCE = f"{LIBRARY_ROOT}/embedded_fcm_distributor/src/main/java/"
LICENCE = Path("third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt")
BUILD_NOTICES = (
    Path("third_party/NOTICE.md"),
    Path("third_party/licenses/Apache-2.0.txt"),
    Path("third_party/licenses/gradle-NOTICE.txt"),
)
BUILD_NOTICE_HASHES = {
    BUILD_NOTICES[1]: "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30",
    BUILD_NOTICES[2]: "d3d569a7f18525b229a7daa4926faf3e0566371f66686b157d62cdf7b3a0b3b3",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tar_bytes(archive: tarfile.TarFile, name: str) -> bytes:
    entry = archive.extractfile(name)
    if entry is None:
        raise ValueError(f"Source archive entry is not a file: {name}")
    return entry.read()


def verify(root: Path, aar: Path | None = None) -> dict:
    source_dir = root / SOURCES
    manifest = json.loads((source_dir / "manifest.json").read_text())
    for name, record in manifest["files"].items():
        if sha256((source_dir / name).read_bytes()) != record["sha256"]:
            raise ValueError(f"Source material hash mismatch: {name}")
    licence = (root / LICENCE).read_bytes()
    if sha256(licence) != manifest["licence_sha256"]:
        raise ValueError("Library licence hash mismatch")
    for relative in BUILD_NOTICES:
        content = (root / relative).read_bytes()
        expected_hash = BUILD_NOTICE_HASHES.get(relative)
        if not content or (expected_hash is not None and sha256(content) != expected_hash):
            raise ValueError(f"Build notice hash mismatch: {relative}")
    archive = source_dir / "embedded-fcm-distributor-3.1.0-upstream.tar.gz"
    source_jar = source_dir / "embedded-fcm-distributor-3.1.0-sources.jar"
    with tarfile.open(archive) as upstream, zipfile.ZipFile(source_jar) as published:
        if tar_bytes(upstream, f"{LIBRARY_ROOT}/LICENSE") != licence:
            raise ValueError("Tagged Library licence does not match retained text")
        names = [name for name in published.namelist() if name.endswith(".kt")]
        tagged = {
            member.name.removeprefix(LIBRARY_SOURCE)
            for member in upstream.getmembers()
            if member.isfile() and member.name.startswith(LIBRARY_SOURCE) and member.name.endswith(".kt")
        }
        if set(names) != tagged or not names:
            raise ValueError("Published/tagged Kotlin source sets differ")
        for name in names:
            if tar_bytes(upstream, LIBRARY_SOURCE + name) != published.read(name):
                raise ValueError(f"Published/tagged Kotlin source differs: {name}")
    result = {"verified_kotlin_files": len(names), "licence_sha256": sha256(licence)}
    if aar is not None:
        digest = sha256(aar.read_bytes())
        if digest != manifest["published_aar"]["sha256"]:
            raise ValueError("Published AAR hash mismatch (a rebuild is not byte-identical by assumption)")
        result["published_aar_sha256"] = digest
    return result


def extract_source(root: Path, output: Path) -> None:
    verify(root)
    output.mkdir(parents=True, exist_ok=True)
    archive = root / SOURCES / "embedded-fcm-distributor-3.1.0-upstream.tar.gz"
    with tarfile.open(archive) as source:
        members = source.getmembers()
        for member in members:
            target = (output / member.name).resolve()
            if not target.is_relative_to(output.resolve()) or not (member.isfile() or member.isdir()):
                raise ValueError(f"Unsafe source archive member: {member.name}")
        for relative in BUILD_NOTICES:
            if not (output / relative).resolve().is_relative_to(output.resolve()):
                raise ValueError(f"Unsafe build notice output: {relative}")
        for member in members:
            target = output / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(tar_bytes(source, member.name))
                target.chmod(member.mode & 0o777)
    # Accompany the unchanged upstream tree; do not alter its root LGPL licence.
    for relative in BUILD_NOTICES:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((root / relative).read_bytes())


def source_bundle(root: Path, ref: str, output: Path, apks: list[Path]) -> dict:
    commit = subprocess.check_output(["git", "rev-parse", "--verify", f"{ref}^{{commit}}"], cwd=root, text=True).strip()
    # git archive excludes ignored/untracked credentials, build state and caches.
    application = subprocess.check_output(["git", "archive", "--format=tar.gz", commit], cwd=root)
    with tarfile.open(fileobj=io.BytesIO(application), mode="r:gz") as archive:
        for required in [
            str(SOURCES / "manifest.json"),
            str(LICENCE),
            *map(str, BUILD_NOTICES),
            "third_party/embedded-push-relink.md",
            "tools/embedded_push_materials.py",
        ]:
            archive.getmember(required)  # fail if this ref predates the materials
    materials = [
        LICENCE,
        *BUILD_NOTICES,
        Path("third_party/embedded-push-notice.md"),
        Path("third_party/embedded-push-relink.md"),
    ]
    materials.extend(path.relative_to(root) for path in sorted((root / SOURCES).iterdir()) if path.is_file())
    committed_materials = {}
    for relative in materials:
        content = subprocess.check_output(["git", "show", f"{commit}:{relative.as_posix()}"], cwd=root)
        if content != (root / relative).read_bytes():
            raise ValueError(f"Source materials differ from the requested commit: {relative}")
        committed_materials[relative.as_posix()] = content
    verify(root)
    report = {
        "application_commit": commit,
        "application_source_sha256": sha256(application),
        "apks": [{"name": apk.name, "sha256": sha256(apk.read_bytes())} for apk in apks],
        "qualification": "Source/relink materials, not legal clearance or a claim that supplied APKs were built from this commit. The distributor must verify that association.",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr("hermes-android-source.tar.gz", application)
        # Duplicate the notices and complete Library source at the top level for
        # recipients without git/Flutter. All are also in the app source archive.
        for relative, content in committed_materials.items():
            bundle.writestr(relative, content)
        bundle.writestr("distribution-manifest.json", json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aar", type=Path, help="Verify the exact published AAR, not a rebuild")
    parser.add_argument("--extract", type=Path, help="Extract verified upstream source/build scripts")
    parser.add_argument("--bundle", type=Path, help="Create a NEW source/relink zip from --ref")
    parser.add_argument("--ref", help="Exact app commit accompanying distributed APKs")
    parser.add_argument("--apk", action="append", type=Path, default=[], help="Record a distributed APK hash (does not sign/copy it)")
    args = parser.parse_args()
    if args.bundle and not args.ref:
        parser.error("--bundle requires --ref")
    print(json.dumps(verify(ROOT, args.aar), indent=2))
    if args.extract:
        extract_source(ROOT, args.extract)
        print(f"Extracted complete upstream source to {args.extract / LIBRARY_ROOT}")
    if args.bundle:
        print(json.dumps(source_bundle(ROOT, args.ref, args.bundle, args.apk), indent=2))


if __name__ == "__main__":
    main()
