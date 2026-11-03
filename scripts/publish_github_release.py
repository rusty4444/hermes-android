"""Publish an immutable Android release with explicit stable/prerelease flags."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

if __package__:
    from .verify_release_apks import APK_NAMES, verify_release_apks
else:
    from verify_release_apks import APK_NAMES, verify_release_apks


VERSION = re.compile(
    r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def release_flags(tag: str) -> list[str]:
    if not tag.startswith("v") or VERSION.fullmatch(tag[1:]) is None:
        raise ValueError(f"Invalid release tag: {tag}")
    if "-" in tag:
        return ["--prerelease=true", "--latest=false"]
    return ["--prerelease=false", "--latest=true"]


def release_command(
    tag: str, target: str, assets: list[Path], repository: str = ""
) -> list[str]:
    flags = release_flags(tag)
    if re.fullmatch(r"[0-9a-f]{40}", target) is None:
        raise ValueError("Release target must be a full 40-character commit SHA")
    command = [
        "gh",
        "release",
        "create",
        tag,
        "--verify-tag",
        "--target",
        target,
        "--title",
        f"Hermes Android {tag}",
        "--generate-notes",
        "--draft=false",
        *flags,
        *(str(path) for path in assets),
    ]
    if repository:
        command.extend(["--repo", repository])
    return command


def remote_tag_commit(repository: str, tag: str) -> str:
    """Resolve GitHub's exact ref, peeling annotated tags without trusting local tags."""
    release_flags(tag)

    def get_json(endpoint: str) -> dict:
        value = json.loads(subprocess.check_output(["gh", "api", endpoint], text=True))
        if not isinstance(value, dict):
            raise ValueError("GitHub returned an invalid tag response")
        return value

    reference = get_json(f"repos/{repository}/git/ref/tags/{tag}")
    if reference.get("ref") != f"refs/tags/{tag}":
        raise ValueError("GitHub returned a different tag ref")
    obj = reference.get("object")
    seen = set()
    for _ in range(8):
        if not isinstance(obj, dict):
            raise ValueError("Tag has no valid Git object")
        sha = obj.get("sha")
        if not isinstance(sha, str) or re.fullmatch(r"[0-9a-f]{40}", sha) is None:
            raise ValueError("Tag has an invalid object SHA")
        if obj.get("type") == "commit":
            return sha
        if obj.get("type") != "tag" or sha in seen:
            raise ValueError("Tag does not resolve to a commit")
        seen.add(sha)
        annotated = get_json(f"repos/{repository}/git/tags/{sha}")
        if annotated.get("sha") != sha:
            raise ValueError("GitHub returned a different tag object")
        obj = annotated.get("object")
    raise ValueError("Annotated tag chain exceeds the resolution limit")


def release_assets(directory: Path) -> list[Path]:
    assets = [directory / name for name in APK_NAMES]
    actual = {path.name for path in directory.glob("*.apk")}
    if actual != set(APK_NAMES) or not all(path.is_file() for path in assets):
        raise ValueError("Release requires exactly the three signed ABI APKs")
    if any(path.stat().st_size == 0 for path in assets):
        raise ValueError("Release APKs must not be empty")
    lines = []
    for path in assets:
        digest_state = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest_state.update(chunk)
        lines.append(f"{digest_state.hexdigest()}  {path.name}\n")
    checksum = directory / "SHA256SUMS"
    checksum.write_text("".join(lines), encoding="utf-8")
    return [*assets, checksum]


def build_source_bundle(directory: Path, target: str, apks: list[Path]) -> Path:
    """Accompany the APKs with exact tracked app and embedded-Library source."""
    tool = Path("tools/embedded_push_materials.py")
    if not tool.is_file():
        raise SystemExit("Required source/relink material generator is missing")
    bundle = directory / "hermes-android-source-relink.zip"
    if bundle.exists():
        raise SystemExit("Refusing to reuse an existing source/relink bundle")
    command = [sys.executable, str(tool), "--ref", target, "--bundle", str(bundle)]
    for apk in apks:
        command.extend(["--apk", str(apk)])
    subprocess.run(command, check=True)
    if not bundle.is_file() or bundle.stat().st_size == 0:
        raise SystemExit("Source/relink generator did not produce a bundle")
    return bundle


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--assets-dir", required=True, type=Path)
    args = parser.parse_args()
    release_flags(args.tag)
    match = re.search(
        r"^version:\s*([^\s+]+)\+(\d+)\s*$",
        Path("pubspec.yaml").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None or args.tag != f"v{match.group(1)}":
        raise SystemExit("Release tag must exactly match pubspec.yaml versionName")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if args.target != head:
        raise SystemExit("Release target must match the verified checkout HEAD")
    repository = (
        os.environ.get("GITHUB_REPOSITORY")
        or subprocess.check_output(
            ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
            text=True,
        ).strip()
    )
    try:
        tag_commit = remote_tag_commit(repository, args.tag)
    except (ValueError, KeyError, TypeError) as error:
        raise SystemExit(f"Invalid remote release tag: {error}") from error
    if tag_commit != head:
        raise SystemExit("Remote release tag must match the verified checkout HEAD")
    try:
        report = verify_release_apks(args.assets_dir, args.target)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f"APK pre-publication verification failed: {error}") from error
    print(json.dumps(report, indent=2))
    assets = release_assets(args.assets_dir)
    bundle = build_source_bundle(args.assets_dir, args.target, assets[:-1])
    command = release_command(
        args.tag, args.target, [*assets, bundle], repository=repository
    )
    # Create-only: a rerun must not silently overwrite an already published APK.
    subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
