#!/usr/bin/env python3
"""Prepare #142's content-pinned, build-time-only Android wake inputs (stdlib)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "third_party/voice/manifest.json"
MODEL_ROOT = "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
ABIS = {"arm64-v8a", "armeabi-v7a", "x86", "x86_64"}
LICENSE_HASHES = {
    "sherpa-onnx-Apache-2.0.txt": "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30",
    "onnxruntime-MIT.txt": "2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c",
}


class VerificationError(RuntimeError):
    """An input is absent, changed, or unsafe; do not package it."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_file(path: Path, pin: dict) -> Path:
    if not path.is_file():
        raise VerificationError(f"Missing pinned input: {path.name}")
    if path.stat().st_size != pin["bytes"] or sha256(path) != pin["sha256"]:
        raise VerificationError(f"SHA-256/size mismatch for {path.name}; refusing input")
    return path


def fetch(pin: dict, cache: Path, input_dir: Path | None, offline: bool) -> Path:
    name = pin["url"].rsplit("/", 1)[-1]
    if input_dir is not None:
        # An explicitly supplied wrong/missing input is never silently replaced by a download.
        return verify_file(input_dir / name, pin)
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / name
    if target.exists():
        return verify_file(target, pin)
    if offline:
        raise VerificationError(f"Offline cache lacks {name}")
    urls = [pin["url"], f'https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/assets/{pin["github_asset_id"]}']
    for index, url in enumerate(urls):
        headers = {"User-Agent": "hermes-android-pinned-voice-build/1", "Accept": "application/octet-stream"}
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as response:
                with tempfile.NamedTemporaryFile(dir=cache, prefix=".voice-download-", delete=False) as output:
                    temporary = Path(output.name)
                    try:
                        count = 0
                        while True:
                            block = response.read(1024 * 1024)
                            if not block:
                                break
                            count += len(block)
                            if count > pin["bytes"]:
                                raise VerificationError(f"Oversized download for {name}")
                            output.write(block)
                        output.flush()
                        verify_file(temporary, pin)
                        temporary.replace(target)
                    finally:
                        temporary.unlink(missing_ok=True)
            return target
        except (urllib.error.URLError, TimeoutError):
            if index == len(urls) - 1:
                raise
    raise VerificationError(f"Download failed for {name}")


def archive_bytes(archive: tarfile.TarFile, name: str) -> bytes:
    member = archive.getmember(name)
    if not member.isfile():
        raise VerificationError(f"Expected a regular archive member: {name}")
    source = archive.extractfile(member)
    if source is None:
        raise VerificationError(f"Cannot read archive member: {name}")
    with source:
        return source.read()


def verify_bytes(content: bytes, pin: dict, name: str) -> None:
    if len(content) != pin["bytes"] or hashlib.sha256(content).hexdigest() != pin["sha256"]:
        raise VerificationError(f"SHA-256/size mismatch for selected asset {name}")


def selected_assets(model: Path, manifest: dict) -> dict[str, bytes]:
    selected = {}
    with tarfile.open(model, "r:bz2") as archive:
        for pin in manifest["runtime_files"]:
            data = archive_bytes(archive, pin["archive_member"])
            verify_bytes(data, pin, pin["apk_asset"])
            selected[pin["apk_asset"]] = data
        readme = archive_bytes(archive, MODEL_ROOT + "/README.md")
        if b"license: Apache License 2.0" not in readme:
            raise VerificationError("Exact model README no longer declares its expected license")
        selected["third_party/voice/model-README.md"] = readme
    keyword = manifest["keyword"]
    data = keyword["utf8_contents"].encode("utf-8")
    if hashlib.sha256(data).hexdigest() != keyword["sha256"]:
        raise VerificationError("Literal keyword hash mismatch")
    selected[keyword["file_name"]] = data
    return selected


def write_changed(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_bytes() == data:
        return
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".voice-write-", delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def prepare(output: Path, cache: Path, input_dir: Path | None = None, offline: bool = False) -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    aar = fetch(manifest["runtime_download"], cache, input_dir, offline)
    model = fetch(manifest["model_download"], cache, input_dir, offline)
    with zipfile.ZipFile(aar) as runtime:
        names = set(runtime.namelist())
        if "classes.jar" not in names or any(f"jni/{abi}/libsherpa-onnx-jni.so" not in names for abi in ABIS):
            raise VerificationError("Pinned AAR lacks expected classes/JNI ABIs")
    assets = selected_assets(model, manifest)
    notices = ROOT / "third_party/voice"
    for name, digest in LICENSE_HASHES.items():
        source = notices / "licenses" / name
        if sha256(source) != digest:
            raise VerificationError(f"License text changed: {name}")
        assets["third_party/voice/licenses/" + name] = source.read_bytes()
    for name in ("NOTICE.md", "manifest.json"):
        assets["third_party/voice/" + name] = (notices / name).read_bytes()
    packaged = {name: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                for name, data in sorted(assets.items())}
    receipt = {"schema_version": 1, "source_commit": manifest["source_commit"],
               "runtime": manifest["runtime_download"], "model": manifest["model_download"],
               "packaged_assets": packaged, "runtime_downloads": False}
    assets["third_party/voice/asset-sha256.json"] = (json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "sherpa-onnx-2.0.1.aar"
    if not destination.exists() or sha256(destination) != manifest["runtime_download"]["sha256"]:
        # Copy only bytes that have just passed the fixed full-input checksum.
        write_changed(destination, aar.read_bytes())
    asset_root = output / "assets"
    for name, data in assets.items():
        write_changed(asset_root / name, data)
    # This is a dedicated generated asset root: never leave an older unverified model in the APK.
    if asset_root.exists():
        for existing in asset_root.rglob("*"):
            if existing.is_file() and existing.relative_to(asset_root).as_posix() not in assets:
                existing.unlink()
    write_changed(output / "receipt.json", (json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode())
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/voice-inputs")
    parser.add_argument("--cache-dir", type=Path, default=Path(os.environ.get("HERMES_VOICE_CACHE", Path.home() / ".cache/hermes-voice")))
    parser.add_argument("--input-dir", type=Path, default=os.environ.get("HERMES_VOICE_INPUT_DIR"))
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or output in ROOT.parents or (ROOT / "android/app/src") in output.parents:
        parser.error("--output must be a dedicated generated directory, not source")
    try:
        receipt = prepare(output, args.cache_dir, args.input_dir, args.offline)
    except (VerificationError, OSError, tarfile.TarError, zipfile.BadZipFile, KeyError) as failure:
        parser.exit(1, f"Voice input verification failed: {failure}\n")
    print(f'Verified sherpa-onnx 2.0.1 and {len(receipt["packaged_assets"])} packaged assets; no runtime downloads')


if __name__ == "__main__":
    main()
