import csv
import hashlib
import subprocess
import re
from pathlib import Path
from datetime import date

REPO = Path(r"C:\Projects\IndianaWorkforceDataArchive")

CSV = "approved/recruitment_daily.csv"
SHA = "approved/recruitment_daily.sha256"

ALLOWED = {CSV, SHA}

HEADERS = [
    "ObservationDate",
    "AdvertisedPostings",
    "NewlyObservedPostings",
    "NoLongerObservedPostings",
    "ReactivatedPostings",
    "CumulativeUniquePostings"
]

def git(*args):
    return subprocess.check_output(
        ["git", "-C", str(REPO), *args],
        text=True
    ).strip()

def main():
    assert git("branch", "--show-current") == "main"

    assert git("remote", "get-url", "origin") == (
        "https://github.com/amuslu87/"
        "indiana-workforce-data-archive.git"
    )

    assert not git("diff", "--cached", "--name-only"), (
        "Unexpected staged files"
    )

    with (REPO / CSV).open(encoding="utf-8") as f:
        reader = csv.reader(f)
        assert next(reader) == HEADERS

        seen = set()

        for row in reader:
            assert len(row) == 6
            day = date.fromisoformat(row[0])
            assert day not in seen
            seen.add(day)

            assert all(
                re.fullmatch(r"[0-9]+", v)
                for v in row[1:]
            )

        assert seen, "Empty archive"

    actual = hashlib.sha256(
        (REPO / CSV).read_bytes()
    ).hexdigest()

    assert (REPO / SHA).read_text().strip() == (
        actual + "  recruitment_daily.csv"
    )

    print("Content validation: PASS")
    print("Checksum validation: PASS")
    print("Repository validation: PASS")

    git("add", "--", CSV, SHA)

    staged = set(
        git("diff", "--cached", "--name-only").splitlines()
    )

    assert staged.issubset(ALLOWED)

    if staged:
        git("commit", "-m", "Update daily recruitment statistics")

    git("fetch", "origin", "main")

    behind, ahead = map(int, git(
        "rev-list", "--left-right", "--count",
        "origin/main...HEAD"
    ).split())

    if behind:
        raise RuntimeError("Remote branch changed; manual review required")

    if not ahead:
        print("Archive unchanged; remote synchronized.")
        return

    for commit in git("rev-list", "origin/main..HEAD").splitlines():
        changed = set(git(
            "diff-tree", "--no-commit-id",
            "--name-only", "-r", commit
        ).splitlines())

        if not changed.issubset(ALLOWED):
            raise RuntimeError("Unapproved files in outgoing commit")

    print(git("push", "origin", "main"))
    print("ARCHIVE SYNCHRONIZATION PASSED")

if __name__ == "__main__":
    main()
