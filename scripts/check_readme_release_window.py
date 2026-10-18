"""Keep the README's short release window aligned with the changelog."""

import re
from pathlib import Path


HEADING = re.compile(r"^## (.+)$", re.MULTILINE)
RELEASE_HEADING = re.compile(r".*what['’]s new in v(\d+\.\d+\.\d+)$", re.IGNORECASE)
CHANGELOG_RELEASE = re.compile(r"^## \[(\d+\.\d+\.\d+)\]", re.MULTILINE)


def check_release_window(readme: str, changelog: str) -> list[str]:
    latest = CHANGELOG_RELEASE.findall(changelog)[:3]
    if len(latest) != 3:
        raise ValueError("CHANGELOG.md needs at least three stable release entries")

    headings = [match.group(1) for match in HEADING.finditer(readme)]
    releases = [
        (index, match.group(1))
        for index, heading in enumerate(headings)
        if (match := RELEASE_HEADING.fullmatch(heading))
    ]
    versions = [version for _, version in releases]
    if versions != latest:
        raise ValueError(
            f"README.md must show exactly the three latest changelog releases "
            f"{latest}; found {versions}"
        )

    first = releases[0][0]
    if headings[first + 3 : first + 4] != ["Features"] or [
        index for index, _ in releases
    ] != list(range(first, first + 3)):
        raise ValueError("README release entries must be consecutive and end before Features")
    return latest


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    try:
        versions = check_release_window(
            (root / "README.md").read_text(encoding="utf-8"),
            (root / "CHANGELOG.md").read_text(encoding="utf-8"),
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print(f"README release window: {', '.join(versions)}")


if __name__ == "__main__":
    main()
