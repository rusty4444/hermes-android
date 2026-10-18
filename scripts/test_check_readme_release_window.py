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
