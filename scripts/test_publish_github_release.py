"""Regression tests for RC publication; fixture bytes are not actual APKs."""

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.publish_github_release import (
    APK_NAMES,
    build_source_bundle,
    main,
    release_assets,
    release_command,
    release_flags,
)


class PublishReleaseTest(unittest.TestCase):
    def test_rc_is_prerelease_and_not_latest(self):
        self.assertEqual(
            release_flags("v3.0.0-rc.1"),
            ["--prerelease=true", "--latest=false"],
        )

    def test_other_prerelease_is_not_latest(self):
        self.assertEqual(
            release_flags("v3.0.0-beta.2"),
            ["--prerelease=true", "--latest=false"],
        )

    def test_stable_is_explicitly_stable(self):
        self.assertEqual(
            release_flags("v3.0.0"),
            ["--prerelease=false", "--latest=true"],
        )

    def test_invalid_tag_is_rejected(self):
        for tag in ("3.0.0", "v3.0", "v03.0.0", "v3.0.0-", "v3.0.0\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_flags(tag)

    def test_target_requires_full_sha(self):
        with self.assertRaises(ValueError):
            release_command("v3.0.0-rc.1", "abc123", [])

    def test_command_cannot_clobber_an_existing_release(self):
        command = release_command(
            "v3.0.0-rc.1", "a" * 40, [Path("app-arm64-v8a-release.apk")]
        )
        self.assertEqual(command[:4], ["gh", "release", "create", "v3.0.0-rc.1"])
        for flag in (
            "--verify-tag",
            "--draft=false",
            "--prerelease=true",
            "--latest=false",
        ):
            self.assertIn(flag, command)
        self.assertNotIn("--clobber", command)

    def test_exact_three_splits_and_checksums(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            for apk_name in APK_NAMES:
                (directory / apk_name).write_bytes(apk_name.encode())
            assets = release_assets(directory)
            self.assertEqual([path.name for path in assets], [*APK_NAMES, "SHA256SUMS"])
            lines = (directory / "SHA256SUMS").read_text().splitlines()
            self.assertEqual(len(lines), 3)
            for apk_name, line in zip(APK_NAMES, lines):
                self.assertEqual(
                    line, f"{hashlib.sha256(apk_name.encode()).hexdigest()}  {apk_name}"
                )

    def test_missing_split_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            with self.assertRaises(ValueError):
                release_assets(Path(name))

    def test_extra_apk_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            for apk_name in (*APK_NAMES, "unverified.apk"):
                (directory / apk_name).write_bytes(b"test fixture")
            with self.assertRaises(ValueError):
                release_assets(directory)

    def test_empty_split_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            for apk_name in APK_NAMES:
                (directory / apk_name).touch()
            with self.assertRaises(ValueError):
                release_assets(directory)


class PublisherMainTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.previous_directory = Path.cwd()
        os.chdir(self.directory)
        self.addCleanup(os.chdir, self.previous_directory)
        (self.directory / "pubspec.yaml").write_text("version: 3.0.0-rc.1+3000\n")
        for name in APK_NAMES:
            (self.directory / name).write_bytes(b"test fixture, not an APK")
        self.head = "a" * 40
        self.target = self.head
        self.reference = {
            "ref": "refs/tags/v3.0.0-rc.1",
            "object": {"type": "commit", "sha": self.head},
        }
        self.tag_objects = {}

    def read_command(self, command, **kwargs):
        if command[:2] == ["git", "rev-parse"]:
            return self.head + "\n"
        if command[:3] == ["gh", "repo", "view"]:
            return "rusty4444/hermes-android\n"
        if command[:2] == ["gh", "api"]:
            if "/git/ref/tags/" in command[2]:
                return json.dumps(self.reference)
            if "/git/tags/" in command[2]:
                return json.dumps(self.tag_objects[command[2].rsplit("/", 1)[1]])
        raise AssertionError(f"Unexpected command: {command}")

    def invoke(self):
        argv = [
            "publisher",
            "--tag",
            "v3.0.0-rc.1",
            "--target",
            self.target,
            "--assets-dir",
            str(self.directory),
        ]
        with (
            mock.patch("sys.argv", argv),
            mock.patch.dict(
                os.environ, {"GITHUB_REPOSITORY": "rusty4444/hermes-android"}
            ),
            mock.patch(
                "scripts.publish_github_release.subprocess.check_output",
                side_effect=self.read_command,
            ),
            # Explicit verifier seam for the legacy tag/flag tests' non-APK
            # bytes. The real gate is exercised by test_verify_release_apks.
            mock.patch(
                "scripts.publish_github_release.verify_release_apks",
                return_value={"qualification": "labelled legacy verifier fixture"},
            ) as verify_apks,
            mock.patch(
                "scripts.publish_github_release.build_source_bundle",
                return_value=self.directory / "hermes-android-source-relink.zip",
            ) as bundle,
            mock.patch("scripts.publish_github_release.subprocess.run") as publish,
        ):
            main()
            verify_apks.assert_called_once_with(self.directory, self.target)
            bundle.assert_called_once_with(
                self.directory,
                self.target,
                [self.directory / name for name in APK_NAMES],
            )
            return publish

    def test_rejects_remote_tag_at_a_different_commit(self):
        self.reference["object"]["sha"] = "b" * 40
        with self.assertRaisesRegex(SystemExit, "tag.*verified checkout"):
            self.invoke()
        self.assertFalse((self.directory / "SHA256SUMS").exists())

    def test_matching_lightweight_tag_publishes_rc_only(self):
        publish = self.invoke()
        command = publish.call_args.args[0]
        self.assertIn("--prerelease=true", command)
        self.assertIn("--latest=false", command)
        self.assertIn("--repo", command)
        self.assertIn("rusty4444/hermes-android", command)
        self.assertIn(str(self.directory / "hermes-android-source-relink.zip"), command)

    def test_matching_annotated_tag_is_peeled(self):
        tag_sha = "c" * 40
        self.reference["object"] = {"type": "tag", "sha": tag_sha}
        self.tag_objects[tag_sha] = {
            "sha": tag_sha,
            "object": {"type": "commit", "sha": self.head},
        }
        self.invoke().assert_called_once()

    def test_annotated_tag_at_wrong_commit_is_rejected(self):
        tag_sha = "c" * 40
        self.reference["object"] = {"type": "tag", "sha": tag_sha}
        self.tag_objects[tag_sha] = {
            "sha": tag_sha,
            "object": {"type": "commit", "sha": "b" * 40},
        }
        with self.assertRaisesRegex(SystemExit, "tag.*verified checkout"):
            self.invoke()

    def test_unexpected_ref_is_rejected(self):
        self.reference["ref"] = "refs/tags/v3.0.0"
        with self.assertRaises(SystemExit):
            self.invoke()

    def test_invalid_tag_object_fails_closed(self):
        self.reference["object"]["type"] = "tree"
        with self.assertRaises(SystemExit):
            self.invoke()

    def test_cyclic_tag_objects_fail_closed(self):
        tag_sha = "c" * 40
        self.reference["object"] = {"type": "tag", "sha": tag_sha}
        self.tag_objects[tag_sha] = {
            "sha": tag_sha,
            "object": {"type": "tag", "sha": tag_sha},
        }
        with self.assertRaises(SystemExit):
            self.invoke()

    def test_target_cannot_differ_from_checkout(self):
        self.target = "b" * 40
        with self.assertRaisesRegex(SystemExit, "target.*checkout HEAD"):
            self.invoke()


class SourceBundleTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        previous_directory = Path.cwd()
        os.chdir(self.directory)
        self.addCleanup(os.chdir, previous_directory)
        (self.directory / "tools").mkdir()
        (self.directory / "tools/embedded_push_materials.py").write_text(
            "# test-owned fixture\n"
        )
        self.bundle = self.directory / "hermes-android-source-relink.zip"

    def test_generator_receives_exact_commit_and_every_apk(self):
        apks = [self.directory / name for name in APK_NAMES]

        def generate(command, **kwargs):
            self.assertEqual(
                command[2:6], ["--ref", "a" * 40, "--bundle", str(self.bundle)]
            )
            self.assertEqual(
                command[6:], [value for apk in apks for value in ("--apk", str(apk))]
            )
            self.bundle.write_bytes(b"unit-test source-bundle fixture")

        with mock.patch(
            "scripts.publish_github_release.subprocess.run", side_effect=generate
        ):
            self.assertEqual(
                build_source_bundle(self.directory, "a" * 40, apks), self.bundle
            )

    def test_missing_generator_fails_closed(self):
        (self.directory / "tools/embedded_push_materials.py").unlink()
        with self.assertRaisesRegex(SystemExit, "generator is missing"):
            build_source_bundle(self.directory, "a" * 40, [])

    def test_old_source_bundle_cannot_be_reused(self):
        self.bundle.write_bytes(b"old test fixture")
        with self.assertRaisesRegex(SystemExit, "existing source/relink"):
            build_source_bundle(self.directory, "a" * 40, [])

    def test_successful_command_without_a_bundle_is_rejected(self):
        with mock.patch("scripts.publish_github_release.subprocess.run"):
            with self.assertRaisesRegex(SystemExit, "did not produce a bundle"):
                build_source_bundle(self.directory, "a" * 40, [])


if __name__ == "__main__":
    unittest.main()
