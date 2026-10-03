#!/usr/bin/env python3
"""Validate the local patch registry without requiring a kernel checkout."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATCH_ROOT = ROOT / "patches"
HUNK_RE = re.compile(
    r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:\s.*)?$"
)


def fail(message: str) -> None:
    print(f"[patch-format] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_patch(path: Path) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()

    if any(line == "@@" for line in lines):
        fail(f"bare '@@' hunk header in {path.relative_to(ROOT)}")

    for index, header in enumerate(lines):
        if not header.startswith("@@ "):
            continue

        match = HUNK_RE.match(header)
        if not match:
            fail(f"invalid hunk header in {path.relative_to(ROOT)}: {header}")

        end = index + 1
        while end < len(lines):
            candidate = lines[end]
            if candidate.startswith("@@ ") or candidate.startswith("diff --git "):
                break
            end += 1

        body = lines[index + 1 : end]
        invalid = [line for line in body if line and line[0] not in " +-\\"]
        if invalid:
            fail(
                f"invalid hunk line in {path.relative_to(ROOT)}: "
                f"{invalid[0]!r}"
            )

        expected_old = int(match.group(2) or "1")
        expected_new = int(match.group(4) or "1")
        actual_old = sum(line.startswith((" ", "-")) for line in body)
        actual_new = sum(line.startswith((" ", "+")) for line in body)

        if (actual_old, actual_new) != (expected_old, expected_new):
            fail(
                f"hunk count mismatch in {path.relative_to(ROOT)}: {header}; "
                f"found old/new={actual_old}/{actual_new}, "
                f"expected={expected_old}/{expected_new}"
            )


def validate_series(path: Path) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    for line in lines:
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        patch = Path(entry) if entry.startswith("/") else path.parent / entry
        if not patch.is_file():
            fail(
                f"series {path.relative_to(ROOT)} references missing patch "
                f"{patch.relative_to(ROOT) if patch.is_relative_to(ROOT) else patch}"
            )


def main() -> int:
    patches = sorted(PATCH_ROOT.rglob("*.patch"))
    if not patches:
        fail("no .patch files found")

    series = sorted(PATCH_ROOT.rglob("series.conf"))
    for patch in patches:
        validate_patch(patch)
    for series_file in series:
        validate_series(series_file)

    print(
        f"[patch-format] PASS: {len(patches)} patches, "
        f"{len(series)} series files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
