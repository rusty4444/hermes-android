import unittest

from scripts.check_readme_release_window import check_release_window


CHANGELOG = """# Changelog
## [2.1.22] - today
## [2.1.21] - yesterday
## [2.1.20] - earlier
## [2.1.19] - older
"""
README = """## Current release
## What's new in v2.1.22
- Change
## Optimisation Release — what's new in v2.1.21
- Change
## What's new in v2.1.20
- Change
## Features
"""


class ReleaseWindowTest(unittest.TestCase):
    def test_accepts_three_latest_releases_with_decorated_heading(self):
        self.assertEqual(
            check_release_window(README, CHANGELOG),
            ["2.1.22", "2.1.21", "2.1.20"],
        )

    def test_rejects_old_entry_left_in_readme(self):
        extra = README.replace(
            "## Features", "## What's new in v2.1.19\n- Change\n## Features"
        )
        with self.assertRaisesRegex(ValueError, "exactly the three latest"):
            check_release_window(extra, CHANGELOG)

    def test_rc_preparation_does_not_rotate_stable_version_window(self):
        changelog = CHANGELOG.replace(
            "# Changelog", "# Changelog\n## [3.2.0-rc.1] - Unreleased"
        )
        readme = README.replace(
            "## Current release",
            "## Current release\n## Release candidate in preparation: 3.2.0-rc.1",
        )
        self.assertEqual(
            check_release_window(readme, changelog),
            ["2.1.22", "2.1.21", "2.1.20"],
        )

    def test_source_only_entries_need_no_download_claims(self):
        readme = README.replace("- Change", "- Source-only; no published APKs.")
        self.assertEqual(
            check_release_window(readme, CHANGELOG),
            ["2.1.22", "2.1.21", "2.1.20"],
        )

    def test_explicit_source_only_versions_are_excluded_without_changing_history(self):
        changelog = """<!-- source-only-releases: 3.1.1, 3.1.2, 3.1.3, 3.1.4, 3.1.5, 3.1.6 -->
## [3.2.0] - Stable promotion pending
## [3.1.7] - published
## [3.1.6] - source preparation
## [3.1.5] - source preparation
## [3.1.4] - source preparation
## [3.1.4] - duplicated historical heading retained
## [3.1.3] - source preparation
## [3.1.2] - source preparation
## [3.1.1] - source preparation
## [3.1.0] - published
## [3.0.6] - published
"""
        readme = """## What's new in v3.2.0
## What's new in v3.1.7
## What's new in v3.1.0
## Features
"""
        self.assertEqual(
            check_release_window(readme, changelog), ["3.2.0", "3.1.7", "3.1.0"]
        )
        # Before promotion the verified published window was 3.1.7/3.1.0/3.0.6.
        self.assertEqual(
            check_release_window(
                readme.replace("## What's new in v3.2.0\n", "").replace(
                    "## Features", "## What's new in v3.0.6\n## Features"
                ),
                changelog.replace("## [3.2.0] - Stable promotion pending\n", ""),
            ),
            ["3.1.7", "3.1.0", "3.0.6"],
        )
        with self.assertRaisesRegex(ValueError, "exactly the three latest"):
            check_release_window(readme.replace("v3.1.0", "v3.1.6"), changelog)

    def test_rejects_new_release_without_rotating_readme(self):
        changed = CHANGELOG.replace("## [2.1.22]", "## [2.1.23]\n## [2.1.22]")
        with self.assertRaisesRegex(ValueError, "exactly the three latest"):
            check_release_window(README, changed)

    def test_rejects_unrelated_heading_in_release_window(self):
        changed = README.replace("## Features", "## Release archive\n## Features")
        with self.assertRaisesRegex(ValueError, "consecutive and end before Features"):
            check_release_window(changed, CHANGELOG)


if __name__ == "__main__":
    unittest.main()
