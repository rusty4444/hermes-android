"""Exercise the actual native CI configuration script in a disposable checkout."""

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeCiConfigurationTest(unittest.TestCase):
    def run_configuration(self, pubspec):
        workflow = (ROOT / ".github/workflows/native-server.yml").read_text()
        script = textwrap.dedent(
            workflow.split("          python3 - <<'PY'\n", 1)[1].split(
                "          PY\n", 1
            )[0]
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "android").mkdir()
            (root / "pubspec.yaml").write_text(pubspec)
            result = subprocess.run(
                [sys.executable, "-c", script],
                cwd=root,
                env={
                    **os.environ,
                    "FLUTTER_ROOT": "/fixture/flutter",
                    "ANDROID_HOME": "/fixture/android",
                },
                capture_output=True,
                text=True,
            )
            properties = root / "android/local.properties"
            return result, properties.read_text() if properties.exists() else None

    def test_native_gradle_receives_the_real_rc_identity(self):
        result, text = self.run_configuration("version: 3.0.0-rc.1+3000\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        assert text is not None
        properties = dict(line.split("=", 1) for line in text.splitlines())
        self.assertEqual(properties["flutter.versionCode"], "3000")
        self.assertEqual(properties["flutter.versionName"], "3.0.0-rc.1")
        self.assertEqual(properties["flutter.buildMode"], "debug")
        self.assertEqual(properties["flutter.sdk"], "/fixture/flutter")
        self.assertEqual(properties["sdk.dir"], "/fixture/android")

    def test_native_job_supplies_the_pinned_gradle_without_an_ignored_wrapper(self):
        workflow = (ROOT / ".github/workflows/native-server.yml").read_text()
        wrapper = (ROOT / "android/gradle/wrapper/gradle-wrapper.properties").read_text()
        self.assertIn("gradle-9.1.0-all.zip", wrapper)
        self.assertIn("gradle/actions/setup-gradle@v4", workflow)
        self.assertIn("gradle-version: '9.1.0'", workflow)
        self.assertIn("run: gradle :app:testDebugUnitTest", workflow)
        self.assertNotIn("run: ./gradlew", workflow)

    def test_ci_runs_tts_correlation_and_retains_both_native_reports(self):
        workflow = (ROOT / ".github/workflows/native-server.yml").read_text()
        self.assertIn(
            "run: gradle :app:testDebugUnitTest :flutter_tts:testDebugUnitTest",
            workflow,
        )
        self.assertIn(
            "python3 -m unittest scripts.test_prepare_voice_inputs scripts.test_native_ci_config",
            workflow,
        )
        for module in ("app", "flutter_tts"):
            self.assertIn(f"build/{module}/reports/tests/testDebugUnitTest", workflow)
            self.assertIn(f"build/{module}/test-results/testDebugUnitTest", workflow)

    def test_missing_pubspec_identity_fails_before_writing_properties(self):
        result, text = self.run_configuration("name: hermes_android\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(text)


if __name__ == "__main__":
    unittest.main()
