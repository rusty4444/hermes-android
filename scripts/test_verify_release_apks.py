"""Publication-gate tests: ZIP containers and SDK stdout are labelled fixtures.

These are NOT built/signed Android APKs. Git blobs and ZIP comparisons are real;
only public SDK command output, GitHub reads/writes and source generation are
mocked. The release owner's separate SDK run must verify the actual release APKs.
"""

import contextlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest import mock

from scripts import publish_github_release as publisher

ROOT = Path(__file__).resolve().parents[1]
CERTIFICATE = "475baf431b16d050c8f658ac838783b273f7c10bba06ed1d16bb0a4239f592fb"
ABI_CODES = {"armeabi-v7a": 1, "arm64-v8a": 2, "x86_64": 3}
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


class ApkPublicationGateTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="apk-preflight-fixture-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        self.directory = self.root / "apk-fixtures"
        self.directory.mkdir()
        self.previous_directory = Path.cwd()
        os.chdir(self.repository)
        self.addCleanup(os.chdir, self.previous_directory)
        self.real_check_output = subprocess.check_output
        self.real_run = subprocess.run
        self.git("init", "-q")
        for source in set(ASSET_SOURCES.values()):
            target = self.repository / source
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / source).read_bytes())
        self.version_name = "3.0.0-rc.1"
        self.base_code = 3000
        self.commit_identity()
        self.contents = {
            entry: (self.repository / source).read_bytes()
            for entry, source in ASSET_SOURCES.items()
        }
        self.sdk = self.root / "sdk-fixture"
        self.build_tools = self.make_build_tools("36.0.0")
        self.java = self.root / "jdk-fixture/bin/java"
        self.make_executable(self.java)
        self.environment = {
            "PATH": os.defpath,
            "HOME": str(self.root),
            "TMPDIR": str(Path(tempfile.gettempdir())),
            "ANDROID_HOME": str(self.sdk),
            "JAVA_HOME": str(self.java.parent.parent),
            "GITHUB_REPOSITORY": "fixture-owner/fixture-repository",
        }
        self.badging = {}
        self.certificates = {}
        self.tool_errors = set()
        self.events = []
        self.created_releases = []
        self.reset_apks()

    def git(self, *arguments):
        return self.real_check_output(
            ["git", *arguments], cwd=self.repository, text=True
        ).strip()

    def commit_identity(self):
        (self.repository / "pubspec.yaml").write_text(
            f"version: {self.version_name}+{self.base_code}\n", encoding="utf-8"
        )
        self.commit_sources()

    def commit_sources(self):
        self.git("add", ".")
        self.git(
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "user.name=Hermes Agent",
            "-c",
            "user.email=hermes-agent@users.noreply.github.com",
            "commit",
            "--allow-empty",
            "-qm",
            "labelled publication gate fixture",
        )
        self.head = self.git("rev-parse", "HEAD")

    def make_executable(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n# Fixture must never be executed.\nexit 99\n")
        path.chmod(0o755)

    def make_build_tools(self, version, names=("aapt", "apksigner")):
        directory = self.sdk / "build-tools" / version
        for name in names:
            self.make_executable(directory / name)
        return directory

    def reset_apks(self):
        for abi, code in ABI_CODES.items():
            name = f"app-{abi}-release.apk"
            self.write_apk(name)
            self.badging[name] = (
                "package: name='com.hermesagent.hermes_android' "
                f"versionCode='{self.base_code * 10 + code}' "
                f"versionName='{self.version_name}' platformBuildVersionName='16'\n"
                f"native-code: '{abi}'\n"
            )
            self.certificates[name] = (
                "Signer #1 certificate DN: CN=Labelled SDK stdout fixture\n"
                f"Signer #1 certificate SHA-256 digest: {CERTIFICATE}\n"
            )

    def write_apk(self, name, contents=None, duplicate=None):
        contents = self.contents if contents is None else contents
        with (
            warnings.catch_warnings(),
            zipfile.ZipFile(self.directory / name, "w") as apk,
        ):
            warnings.simplefilter("ignore", UserWarning)
            apk.writestr("AndroidManifest.xml", b"labelled fixture; not Android XML")
            for entry, content in contents.items():
                apk.writestr(entry, content)
            if duplicate:
                apk.writestr(duplicate, contents.get(duplicate, b"duplicate fixture"))

    def command_output(self, command, **kwargs):
        if command[0] == "git":
            return self.real_check_output(command, **kwargs)
        if command[:2] == ["gh", "api"]:
            self.assertEqual(
                command[2],
                f"repos/fixture-owner/fixture-repository/git/ref/tags/v{self.version_name}",
            )
            output = json.dumps(
                {
                    "ref": f"refs/tags/v{self.version_name}",
                    "object": {"type": "commit", "sha": self.head},
                }
            )
        elif Path(command[0]).name == "java":
            self.assertEqual(command[1:], ["-version"])
            self.assertIn("build-tools revision:", self.diagnostic_output.getvalue())
            self.events.append(("java", command[0]))
            output = 'openjdk version "17.0.0" (labelled stdout fixture)\n'
        elif Path(command[0]).name == "aapt":
            self.assertEqual(command[1:3], ["dump", "badging"])
            self.events.append(("aapt", Path(command[-1]).name, command[0]))
            output = self.badging[Path(command[-1]).name]
        elif Path(command[0]).name == "apksigner":
            self.assertEqual(command[1:3], ["verify", "--print-certs"])
            self.events.append(("apksigner", Path(command[-1]).name, command[0]))
            output = self.certificates[Path(command[-1]).name]
        else:
            raise AssertionError(f"Unexpected fixture command: {command}")
        if Path(command[0]).name in self.tool_errors:
            raise subprocess.CalledProcessError(1, command, output="labelled failure")
        return output if kwargs.get("text") else output.encode()

    def run_command(self, command, **kwargs):
        if command[0] == "git":
            return self.real_run(command, **kwargs)
        self.assertEqual(command[:3], ["gh", "release", "create"])
        self.events.append(("publish",))
        self.created_releases.append(command)
        return subprocess.CompletedProcess(command, 0)

    def generate_bundle(self, *args):
        self.events.append(("bundle",))
        return self.directory / "hermes-android-source-relink.zip"

    def invoke(self, error=None):
        self.events.clear()
        self.created_releases.clear()
        self.diagnostic_output = io.StringIO()
        argv = [
            "publisher",
            "--tag",
            f"v{self.version_name}",
            "--target",
            self.head,
            "--assets-dir",
            str(self.directory),
        ]
        with (
            mock.patch("sys.argv", argv),
            mock.patch.dict(os.environ, self.environment, clear=True),
            mock.patch.object(
                subprocess, "check_output", side_effect=self.command_output
            ),
            mock.patch.object(subprocess, "run", side_effect=self.run_command),
            # Explicit source-generation fixture; covered separately by real material tests.
            mock.patch.object(
                publisher, "build_source_bundle", side_effect=self.generate_bundle
            ) as bundle,
            mock.patch.object(
                publisher, "release_assets", wraps=publisher.release_assets
            ) as checksums,
            contextlib.redirect_stdout(io.StringIO()) as output,
            contextlib.redirect_stderr(self.diagnostic_output) as diagnostics,
        ):
            if error:
                with self.assertRaisesRegex(SystemExit, error):
                    publisher.main()
                bundle.assert_not_called()
                checksums.assert_not_called()
                self.assertEqual(self.created_releases, [])
                self.assertFalse((self.directory / "SHA256SUMS").exists())
            else:
                publisher.main()
                checksums.assert_called_once_with(self.directory)
                bundle.assert_called_once_with(
                    self.directory,
                    self.head,
                    [self.directory / name for name in publisher.APK_NAMES],
                )
                self.assertEqual(len(self.created_releases), 1)
                report = json.loads(output.getvalue())
                self.assertEqual(report["application_commit"], self.head)
                self.assertEqual(report["version_name"], self.version_name)
                self.assertEqual(report["base_version_code"], self.base_code)
                self.assertEqual(report["signer_sha256"], CERTIFICATE)
                self.assertEqual(
                    {apk["name"] for apk in report["apks"]}, set(publisher.APK_NAMES)
                )
                self.assertEqual(
                    [apk["verified_assets"] for apk in report["apks"]],
                    [len(ASSET_SOURCES)] * 3,
                )

        self.diagnostics = diagnostics.getvalue()

    def test_observed_v2_output_passes_actual_publisher_for_all_splits(self):
        # Captured public output, replayed through a mock; NOT SDK execution.
        observed = (ROOT / "scripts/fixtures/apksigner/run-40062562548-v2.txt").read_text()
        self.certificates = dict.fromkeys(publisher.APK_NAMES, observed)
        self.invoke()
        self.assertEqual(sum(event[0] == "apksigner" for event in self.events), 3)

    def test_legacy_supplementary_metadata_is_not_an_extra_signer(self):
        for name in publisher.APK_NAMES:
            self.certificates[name] += (
                "Number of signers: 1\n"
                "Signer #1 certificate SHA-1 digest: " + "a" * 40 + "\n"
                "Signer #1 certificate MD5 digest: " + "a" * 32 + "\n"
                "Signer #1 key algorithm: RSA\n"
                "Signer #1 key size (bits): 4096\n"
                "Signer #1 public key SHA-256 digest: " + "b" * 64 + "\n"
            )
        self.invoke()

    def test_v2_pinned_stdout_cannot_bypass_cryptographic_command_failure(self):
        observed = (ROOT / "scripts/fixtures/apksigner/run-40062562548-v2.txt").read_text()
        self.certificates = dict.fromkeys(publisher.APK_NAMES, observed)
        self.tool_errors = {"apksigner"}
        self.invoke("apksigner verification command failed")

    def test_v2_invalid_or_ambiguous_records_block_all_publisher_writes(self):
        observed = (ROOT / "scripts/fixtures/apksigner/run-40062562548-v2.txt").read_text()
        legacy = self.certificates[publisher.APK_NAMES[0]]
        sha256 = f"V2 Signer: certificate SHA-256 digest: {CERTIFICATE}\n"
        variants = (
            observed.replace(CERTIFICATE, "b" * 64),
            observed.replace(CERTIFICATE, CERTIFICATE[:-1]),
            observed.replace(CERTIFICATE, CERTIFICATE + "0"),
            observed.replace(CERTIFICATE, "g" + CERTIFICATE[1:]),
            observed.replace(CERTIFICATE, CERTIFICATE + " trailing"),
            observed.replace("V2 Signer:", "V3 Signer:"),
            observed.replace("V2 Signer:", "Source Stamp Signer:"),
            observed.replace("certificate SHA-256", "public key SHA-256"),
            observed.replace("V2 Signer:", "Unrelated:"),
            observed + observed,
            observed + sha256,
            observed + legacy,
            legacy + observed,
            observed + "Signer #2 certificate DN: CN=additional signer\n",
            legacy + "Signer #2 certificate DN: CN=additional signer\n",
            observed + f"Signer #2 certificate SHA-256 digest: {'b' * 64}\n",
            observed + "V2 Signer: certificate SHA-256 digest: malformed\n",
            observed + "V2 Signer: certificate DN: CN=additional signer\n",
            observed + "V3 Signer: certificate SHA-256 digest: malformed\n",
            observed + "Number of signers: 2\n",
            observed + "Number of signers: 1\nNumber of signers: 1\n",
            observed + f"Unrelated certificate SHA-256 digest: {CERTIFICATE}\n",
        )
        for name in publisher.APK_NAMES:
            for index, output in enumerate(variants):
                with self.subTest(apk=name, variant=index):
                    self.reset_apks()
                    self.certificates[name] = output
                    self.invoke("signer")

    def test_selected_sdk_diagnostics_precede_verification_without_fallback(self):
        selected = self.make_build_tools("100.0.0")
        self.environment["UNRELATED_SECRET"] = "must-not-be-logged"
        for tool in ("java", "aapt", "apksigner"):
            with self.subTest(tool=tool):
                self.tool_errors = {tool}
                self.invoke("failed")
                self.assertIn(str((selected / "aapt").resolve()), self.diagnostics)
                self.assertIn(str((selected / "apksigner").resolve()), self.diagnostics)
                self.assertIn("100.0.0", self.diagnostics)
                self.assertNotIn("must-not-be-logged", self.diagnostics)
                for event in self.events:
                    if event[0] in ("aapt", "apksigner"):
                        self.assertEqual(Path(event[2]).parent, selected.resolve())
                self.assertEqual(sum(event[0] == tool for event in self.events), 1)

    def test_valid_labelled_fixtures_verify_all_three_before_source_and_publication(
        self,
    ):
        self.assertEqual(len(ASSET_SOURCES), 22)
        self.invoke()
        for tool in ("aapt", "apksigner"):
            self.assertEqual(
                {event[1] for event in self.events if event[0] == tool},
                set(publisher.APK_NAMES),
            )
            self.assertEqual(sum(event[0] == tool for event in self.events), 3)
        self.assertEqual(
            [event[0] for event in self.events[-2:]], ["bundle", "publish"]
        )
        command = self.created_releases[0]
        self.assertIn("--prerelease=true", command)
        self.assertIn("--latest=false", command)
        self.assertNotIn("--clobber", command)
        expected_assets = {
            *(str(self.directory / name) for name in publisher.APK_NAMES),
            str(self.directory / "SHA256SUMS"),
            str(self.directory / "hermes-android-source-relink.zip"),
        }
        self.assertEqual(
            {
                argument
                for argument in command
                if argument.startswith(str(self.directory))
            },
            expected_assets,
        )

    def test_missing_sdk_blocks_actual_publisher_entrypoint(self):
        self.environment.pop("ANDROID_HOME")
        self.invoke("Android SDK")

    def test_invalid_sdk_directory_fails_closed(self):
        self.environment["ANDROID_HOME"] = str(self.root / "missing-sdk")
        self.invoke("Android SDK")

    def test_sdk_root_is_supported_without_android_home(self):
        self.environment["ANDROID_SDK_ROOT"] = self.environment.pop("ANDROID_HOME")
        self.invoke()

    def test_conflicting_explicit_sdk_roots_fail_closed(self):
        self.environment["ANDROID_SDK_ROOT"] = str(self.root / "other-sdk")
        self.invoke("SDK")

    def test_consistent_explicit_sdk_roots_are_supported(self):
        self.environment["ANDROID_SDK_ROOT"] = str(self.sdk.resolve())
        self.invoke()

    def test_missing_sdk_tools_fail_closed(self):
        for name in ("aapt", "apksigner"):
            with self.subTest(tool=name):
                path = self.build_tools / name
                path.unlink()
                self.invoke("build-tools")
                self.make_executable(path)

    def test_nonexecutable_sdk_tools_fail_closed(self):
        (self.build_tools / "apksigner").chmod(0o644)
        self.invoke("build-tools")

    def test_missing_java_fails_closed(self):
        self.java.unlink()
        self.invoke("Java")

    def test_missing_java_home_and_path_runtime_fail_closed(self):
        self.environment.pop("JAVA_HOME")
        # Labelled missing-runtime discovery fixture; keep Git available.
        with mock.patch("scripts.verify_release_apks.shutil.which", return_value=None):
            self.invoke("Java")

    def test_failed_sdk_or_java_commands_fail_closed(self):
        for tool in ("java", "aapt", "apksigner"):
            with self.subTest(tool=tool):
                self.tool_errors = {tool}
                self.invoke("failed")

    def test_highest_complete_stable_build_tools_pair_selected_numerically(self):
        selected = self.make_build_tools("100.0.0")
        self.make_build_tools("99.0.0")
        self.make_build_tools("101.0.0", names=("aapt",))
        self.make_build_tools("102.0.0-rc1")
        self.invoke()
        for event in self.events:
            if event[0] in ("aapt", "apksigner"):
                self.assertEqual(Path(event[2]).parent, selected.resolve())

    def test_obsolete_build_tools_are_not_a_fallback(self):
        for tool in ("aapt", "apksigner"):
            (self.build_tools / tool).unlink()
        self.make_build_tools("23.0.3")
        self.invoke("build-tools")

    def test_wrong_package_in_each_split_blocks_publication(self):
        for name in publisher.APK_NAMES:
            with self.subTest(apk=name):
                self.reset_apks()
                self.badging[name] = self.badging[name].replace(
                    "com.hermesagent.hermes_android",
                    "com.hermesagent.hermes_android.dev",
                )
                self.invoke("package")

    def test_wrong_version_name_in_each_split_blocks_publication(self):
        for name in publisher.APK_NAMES:
            with self.subTest(apk=name):
                self.reset_apks()
                self.badging[name] = self.badging[name].replace(
                    self.version_name, "3.0.0"
                )
                self.invoke("versionName")

    def test_wrong_effective_code_in_each_split_blocks_publication(self):
        for name in publisher.APK_NAMES:
            with self.subTest(apk=name):
                self.reset_apks()
                self.badging[name] = re.sub(
                    r"versionCode='[0-9]+'", "versionCode='3000'", self.badging[name]
                )
                self.invoke("versionCode")

    def test_each_split_requires_exactly_its_own_abi(self):
        for abi in ABI_CODES:
            name = f"app-{abi}-release.apk"
            for native in ("", "'unknown'", f"'{abi}' 'x86'", f"'{abi}' '{abi}'"):
                with self.subTest(apk=name, native=native):
                    self.reset_apks()
                    self.badging[name] = (
                        self.badging[name].split("native-code:")[0]
                        + f"native-code: {native}\n"
                    )
                    self.invoke("ABI")

    def test_badging_metadata_missing_malformed_or_duplicated_is_rejected(self):
        name = publisher.APK_NAMES[-1]
        original = self.badging[name]
        malformed = (
            "",
            "package: malformed\nnative-code: 'x86_64'\n",
            original + original,
            original.replace("versionCode='30003'", "versionCode='30003x'"),
            original.replace("versionName='3.0.0-rc.1'", "versionName=3.0.0-rc.1"),
            original.replace("package: ", "package: name='duplicate' "),
            original.replace("native-code: 'x86_64'\n", ""),
        )
        for output in malformed:
            with self.subTest(output=output):
                self.badging[name] = output
                self.invoke("metadata|ABI|versionCode")

    def test_wrong_signer_in_each_split_cannot_be_overridden_by_environment(self):
        self.environment["EXPECTED_RELEASE_CERT_SHA256"] = "b" * 64
        for name in publisher.APK_NAMES:
            with self.subTest(apk=name):
                self.reset_apks()
                self.certificates[name] = self.certificates[name].replace(
                    CERTIFICATE, "b" * 64
                )
                self.invoke("signer")

    def test_missing_malformed_duplicate_and_additional_signers_are_rejected(self):
        name = publisher.APK_NAMES[-1]
        original = self.certificates[name]
        for output in (
            "",
            original.replace(CERTIFICATE, CERTIFICATE[:-1]),
            original + original,
            original + original.replace("#1", "#2"),
            original + f"Signer #2 certificate SHA-256 digest: {'b' * 64}\n",
            original + "Signer #2 certificate SHA-256 digest: malformed\n",
        ):
            with self.subTest(output=output):
                self.certificates[name] = output
                self.invoke("signer")

    def test_valid_pinned_signer_does_not_trust_an_environment_override(self):
        self.environment["EXPECTED_RELEASE_CERT_SHA256"] = "b" * 64
        self.invoke()

    def test_future_base_and_version_are_derived_from_the_committed_pubspec(self):
        self.version_name = "3.0.0-rc.2"
        self.base_code = 3017
        self.commit_identity()
        self.reset_apks()
        self.invoke()

    def test_dirty_pubspec_cannot_redefine_publication_identity(self):
        (self.repository / "pubspec.yaml").write_text("version: 3.0.0-rc.1+3017\n")
        self.base_code = 3017
        self.reset_apks()
        self.invoke("pubspec")

    def test_committed_malformed_or_duplicate_pubspec_identity_is_rejected(self):
        for pubspec in (
            "name: fixture\n",
            "version: broken\n",
            "version: 3.0.0-rc.1+3000\n" * 2,
        ):
            with self.subTest(pubspec=pubspec):
                (self.repository / "pubspec.yaml").write_text(pubspec)
                self.commit_sources()
                self.invoke("pubspec")

    def test_every_required_asset_missing_from_each_split_blocks_publication(self):
        for name in publisher.APK_NAMES:
            for entry in ASSET_SOURCES:
                with self.subTest(apk=name, entry=entry):
                    self.reset_apks()
                    contents = dict(self.contents)
                    contents.pop(entry)
                    self.write_apk(name, contents)
                    self.invoke("asset")

    def test_every_required_asset_changed_in_each_split_blocks_publication(self):
        for name in publisher.APK_NAMES:
            for entry in ASSET_SOURCES:
                with self.subTest(apk=name, entry=entry):
                    self.reset_apks()
                    contents = dict(self.contents)
                    content = contents[entry]
                    contents[entry] = bytes([content[0] ^ 1]) + content[1:]
                    self.write_apk(name, contents)
                    self.invoke("asset")

    def test_duplicate_required_zip_entries_in_each_split_block_publication(self):
        for name in publisher.APK_NAMES:
            for entry in ASSET_SOURCES:
                with self.subTest(apk=name, entry=entry):
                    self.reset_apks()
                    self.write_apk(name, duplicate=entry)
                    self.invoke("duplicate")

    def test_duplicate_other_zip_entry_also_blocks_publication(self):
        self.write_apk(publisher.APK_NAMES[-1], duplicate="AndroidManifest.xml")
        self.invoke("duplicate")

    def test_non_zip_container_is_not_an_apk(self):
        (self.directory / publisher.APK_NAMES[-1]).write_bytes(
            b"labelled non-APK fixture"
        )
        self.invoke("ZIP|APK")

    def test_upstream_archive_requires_the_bin_alias_and_exact_compressed_bytes(self):
        name = publisher.APK_NAMES[-1]
        contents = dict(self.contents)
        entry = f"assets/{SOURCE_DIRECTORY}/embedded-fcm-distributor-3.1.0-upstream.tar.gz.bin"
        contents[entry.removesuffix(".bin")] = contents.pop(entry)
        self.write_apk(name, contents)
        self.invoke("asset")

    def test_dirty_local_asset_matching_apk_is_not_the_publication_git_blob(self):
        entry = "assets/flutter_assets/assets/fonts/Cinzel-Variable.ttf"
        source = self.repository / ASSET_SOURCES[entry]
        source.write_bytes(b"uncommitted font fixture")
        contents = dict(self.contents)
        contents[entry] = source.read_bytes()
        self.write_apk(publisher.APK_NAMES[-1], contents)
        self.invoke("asset")

    def test_malformed_committed_material_manifest_cannot_pass_by_matching_apk(self):
        manifest = self.repository / SOURCE_DIRECTORY / "manifest.json"
        original = manifest.read_text()
        variants = (
            "not JSON",
            "[]",
            original.replace(
                '"coordinate":', '"coordinate": "duplicate", "coordinate":'
            ),
            original.replace('"files": {', '"files": null, "ignored": {'),
            original.replace('"licence_sha256": "620e', '"licence_sha256": "bad620e'),
        )
        for text in variants:
            with self.subTest(manifest=text[:80]):
                manifest.write_text(text)
                self.commit_sources()
                self.contents[f"assets/{SOURCE_DIRECTORY}/manifest.json"] = (
                    text.encode()
                )
                self.reset_apks()
                self.invoke("manifest|metadata")

    def test_non_rfc_json_constants_block_publication_before_outputs(self):
        manifest = self.repository / SOURCE_DIRECTORY / "manifest.json"
        original = manifest.read_text()
        for constant in ("NaN", "Infinity", "-Infinity"):
            for value in (constant, f'{{"nested": [{constant}]}}'):
                with self.subTest(constant=constant, value=value):
                    text = re.sub(
                        r'"coordinate":\s*"[^"]+"',
                        f'"coordinate": {value}',
                        original,
                        count=1,
                    )
                    self.assertNotEqual(text, original)
                    manifest.write_text(text, encoding="utf-8")
                    self.commit_sources()
                    self.contents[f"assets/{SOURCE_DIRECTORY}/manifest.json"] = (
                        text.encode()
                    )
                    self.reset_apks()
                    self.invoke(
                        "Malformed material manifest: Non-RFC JSON constant: "
                        + re.escape(constant)
                    )

    def test_standalone_verifier_checks_exact_apk_set(self):
        from scripts.verify_release_apks import verify_release_apks

        for removed, extra in ((publisher.APK_NAMES[0], None), (None, "extra.apk")):
            with self.subTest(removed=removed, extra=extra):
                self.reset_apks()
                if removed:
                    (self.directory / removed).unlink()
                if extra:
                    (self.directory / extra).write_bytes(b"extra fixture")
                with self.assertRaisesRegex(ValueError, "exactly"):
                    verify_release_apks(self.directory, self.head)
                if extra:
                    (self.directory / extra).unlink()

    def test_cli_import_and_help_do_not_require_an_sdk(self):
        for script in ("publish_github_release.py", "verify_release_apks.py"):
            with self.subTest(script=script):
                result = self.real_run(
                    [sys.executable, str(ROOT / "scripts" / script), "--help"],
                    cwd=self.repository,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("--assets-dir", result.stdout)


if __name__ == "__main__":
    unittest.main()
